# Runbook — `itservices` account password rotation (shared SmartLoyalty IIS identity)

> Source: event `20260723_itservices_bloqueo_password`. See also `20260610_kerberos_rc4_aadds` (AADDS123) for why this account is a critical single point of dependency.

## 1. Goal

Rotate safely the password of the Azure AD DS account `itservices` (UPN `grupo.servicesit@smartfran.com`, object `CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure`) without the account being locked out for exceeding `badPwdCount`.

## 2. Why this is not a single-server rotation

`itservices` is the IIS App Pool identity **shared** by the 12 SmartLoyalty production servers:

| Server | Service |
|---|---|
| SFCG-WEBS-01, 02, 03 | SmartLoyalty WebService |
| SFCG-WSV2-01, 02 | SmartLoyalty WebServiceV2 |
| SFCG-WSIT-01 | SmartLoyalty Website |
| SFCG-MOBI-01, 02 | Mobile service |
| SFCG-WSCG-01 | CG web service |
| SFCG-CLUB-01, 02 | Club Grido website |
| SFCG-TO-01 | TaskOperatorService |

If the password is updated on one server only, the rest keep authenticating with the old credential. Each failed attempt increments `badPwdCount` **locally on the DC that serves it** (not replicated between replicas), but once the domain lockout threshold is exceeded `lockoutTime` **is** replicated at once to all replicas, locking the account for the **whole** fleet, including servers already updated correctly.

**Golden rule: never update `itservices` on a single server without a maintenance window to finish the rest in the same interval.**

## 3. Prerequisites

- A coordinated maintenance window: update the 12 servers in the same interval, minimising how long different passwords coexist.
- An account with delegated permissions over `smartit.azure` (`AAD DC Administrators` group in Entra ID) to unlock/query the object over LDAP from any fleet server.
- RDP/PowerShell access to each of the 12 servers.
- AADDS domain controller IPs: `192.168.40.4`, `192.168.40.5` (subnet `192.168.40.0/24`, RG `DefaultGroup01`, subscription Smart IT - Grido `0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`).
- **IIS stopped on each VM before updating the identity** (`iisreset /stop` or the `W3SVC` service) on all 12 servers before touching the App Pool. This stops a pool from starting or recycling mid-update with a half-configured credential, which would add a failed logon to the `badPwdCount`.

## 4. Procedure

### 4.1 Password reset in Entra ID

Change the password once, in Entra ID (portal or `az ad user update`), and record the exact value in the secrets manager before touching any server. Do not retype the password on each server from memory: always copy it from the recorded secret.

### 4.2 Check hash sync to AADDS

From any domain-joined server, confirm `pwdLastSet` shows the recent change **on both replicas** before continuing:

```powershell
foreach ($dc in "192.168.40.4","192.168.40.5") {
    $root = New-Object DirectoryServices.DirectoryEntry("LDAP://$dc/CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure")
    $searcher = New-Object DirectoryServices.DirectorySearcher($root)
    $searcher.SearchScope = "Base"
    $searcher.PropertiesToLoad.AddRange(@("pwdLastSet"))
    $result = $searcher.FindOne()
    $pwdLastSet = [Int64]$result.Properties["pwdlastset"][0]
    "$dc -> PwdLastSet: " + [DateTime]::FromFileTime($pwdLastSet)
}
```

If the two DCs do not show the same recent timestamp, wait a few minutes and repeat before moving on: sync to AADDS is asynchronous.

### 4.3 Coordinated rollout

Update the App Pool identity on the 12 servers within the same window, in whatever order is simplest (no order dependency). On each server:

1. IIS Manager → Application Pools → select the pool → Advanced Settings → Identity → Custom account → enter `smartit\itservices` (or `grupo.servicesit@smartfran.com`) and the new password (copied from the recorded secret, not retyped).
2. Recycle the App Pool to validate the new logon immediately.
3. Confirm the site responds (not left "stopped" by a logon failure).

### 4.4 Final check

Repeat the `badPwdCount` / `lockoutTime` check on both DCs after the rollout: it must stay stable (no increments) once all servers are aligned (script in 5.2).

Complement with the Zabbix map of fleet service state, http://sf-monitoreo.smartfran.com:8080/zabbix.php?action=map.view&sysmapid=2: confirm all 12 IIS services are green before closing the rollout.

## 5. Diagnostics — reusable scripts

All run on any server joined to the `smartit.azure` domain, without the RSAT `ActiveDirectory` module (they use `System.DirectoryServices` directly).

### 5.1 Locate the object by UPN/mail (when sAMAccountName does not match the UPN)

```powershell
$searcher = New-Object DirectoryServices.DirectorySearcher
$searcher.Filter = "(|(userPrincipalName=grupo.servicesit@smartfran.com)(mail=grupo.servicesit@smartfran.com)(proxyAddresses=smtp:grupo.servicesit@smartfran.com)(proxyAddresses=SMTP:grupo.servicesit@smartfran.com))"
$searcher.PropertiesToLoad.AddRange(@("distinguishedName","objectClass","sAMAccountName","userPrincipalName","pwdLastSet","whenChanged"))
$searcher.FindAll() | ForEach-Object {
    "DN: "   + $_.Properties["distinguishedname"]
    "Class: "+ $_.Properties["objectclass"]
    "sAM: "  + $_.Properties["samaccountname"]
    "UPN: "  + $_.Properties["userprincipalname"]
}
```

> Do not use an ANR search (`anr=<term>`) as a first attempt: ANR indexes only `displayName`, `sAMAccountName`, `sn`, `givenName`, `legacyExchangeDN` and `proxyAddresses`; if the term is in none of them the search returns empty with no error, falsely suggesting the object does not exist.

### 5.2 Check lockout and `badPwdCount` per DC

```powershell
foreach ($dc in "192.168.40.4","192.168.40.5") {
    $root = New-Object DirectoryServices.DirectoryEntry("LDAP://$dc/CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure")
    $searcher = New-Object DirectoryServices.DirectorySearcher($root)
    $searcher.SearchScope = "Base"
    $searcher.PropertiesToLoad.AddRange(@("lockoutTime","badPwdCount"))
    $result = $searcher.FindOne()
    $lockoutTime = if ($result.Properties["lockouttime"].Count -gt 0) { [Int64]$result.Properties["lockouttime"][0] } else { 0 }
    "$dc -> badPwdCount: " + $result.Properties["badpwdcount"][0]
    if ($lockoutTime -ne 0) {
        "$dc -> LOCKED since: " + [DateTime]::FromFileTime($lockoutTime)
    } else {
        "$dc -> not locked"
    }
}
```

> **Do not read `lockoutTime` with `[ADSI]"LDAP://..."` directly.** Through `DirectoryEntry`/`[ADSI]` the attribute is an `IADsLargeInteger` (COM object) and `[Int64]$de.Properties["lockoutTime"].Value` fails with `Cannot convert the "System.__ComObject" value...`. `DirectorySearcher` marshals it to a native integer: always use it for 64-bit attributes.

### 5.3 Unlock the account

```powershell
try {
    $de = New-Object DirectoryServices.DirectoryEntry("LDAP://192.168.40.4/CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure")
    $de.Properties["lockoutTime"].Value = 0
    $de.CommitChanges()
    "Unlock succeeded"
} catch {
    "Unlock FAILED: " + $_.Exception.Message
}
```

Needs delegated write permission on the object (`AAD DC Administrators`). An error here usually means missing that permission, not a script problem.

### 5.4 Test the credential in isolation (without touching IIS)

Before changing anything in IIS Manager, validate the credential on its own. This avoids spending logon attempts (and so `badPwdCount`) reconfiguring and reloading pools repeatedly:

```powershell
Start-Process cmd -Credential (Get-Credential smartit\itservices)
```

Type the password once, by hand (do not paste): rules out keyboard-layout problems with special characters. Avoid `runas` for this test: if a cached credential for the account exists in Credential Manager (`cmdkey /list`), `runas` silently reuses it without asking for a password, which can lead to wrong conclusions about whether the new password is right.

## 6. Known errors and their correct reading

| Symptom | Real cause | How to confirm |
|---|---|---|
| IIS: "The specified password is invalid" | Often **account locked**, not a wrong password; IIS does not clearly tell them apart | Section 5.2; `Start-Process -Credential` (5.4) returns an explicit "account is currently locked out" |
| `runas` does not ask for a password | Cached Credential Manager credential silently reused | `cmdkey /list` / use `Start-Process -Credential` instead |
| `net user <account> /domain` → "user name could not be found" | `net user` needs the exact `sAMAccountName`; it does not accept a UPN or a wrong guess | Section 5.1 to confirm the real `sAMAccountName` |
| `badPwdCount` differs between the two DCs | Expected: the attribute is not replicated between replicas | Not a finding by itself; look at `lockoutTime` (replicated) |
| Account locks again minutes after unlocking | Another fleet server still authenticates with the old password | Confirm all 12 servers of section 2 are aligned before calling the rollout complete |

## 6bis. Open items (event `20260723_itservices_bloqueo_password`)

- No alert exists on `badPwdCount` / lockout of `itservices` (Zabbix or Azure Monitor); proposed after the July 2026 event, not implemented. Until then the first sign of a lockout is IIS failing across the fleet.
- The first (non-fleet) password change that caused that event was never traced to a server; the fleet rollout of 2026-07-23 was confirmed by the user (all App Pools running, Zabbix map green) without a direct AADDS-side recheck, so use section 4.4 after every rotation.

## 7. References

- `operations/events/20260723_itservices_bloqueo_password/`: event that originated this runbook.
- `operations/events/20260610_kerberos_rc4_aadds/`: AADDS123, critical dependency of `itservices` on Kerberos encryption.
- `operations/events/20260710_sfdev_acceso_dc_azure/`: AADDS DC IPs and topology.
- Zabbix map, state of all services: http://sf-monitoreo.smartfran.com:8080/zabbix.php?action=map.view&sysmapid=2
