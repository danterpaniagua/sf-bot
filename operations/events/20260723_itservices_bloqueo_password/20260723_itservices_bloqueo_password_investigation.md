# Investigation — 20260723_itservices_bloqueo_password

**Status:** converged — ready for ticket

## Confirmed facts

- `itservices` (UPN `grupo.servicesit@smartfran.com`, object `CN=appaccess,OU=AADDC Users,DC=smartit,DC=azure`) is the shared IIS App Pool identity across all 12 SmartLoyalty production web servers (established in `20260610_kerberos_rc4_aadds`, AADDS123).
- The new password's hash had already synced into AADDS before the "invalid password" error was investigated — `pwdLastSet` showed `2026-07-23 10:42:29` (C2 in scripts file), ruling out sync lag as the cause.
- IIS's "The specified password is invalid" was a generic error masking an actual account lockout, not a wrong password (C6: `Start-Process -Credential` returned an explicit "account is currently locked out" error, a clearer signal than IIS gave).
- `lockoutTime` replicates immediately/consistently across both AADDS DC replicas (`192.168.40.4`, `192.168.40.5`) once the lockout threshold is hit — confirmed both replicas agreed on the same lockout timestamp (C8).
- `badPwdCount` does **not** replicate between DC replicas (expected AD behavior, not a finding) — each DC counts failed attempts locally; only the resulting `lockoutTime` propagates domain-wide.
- After unlocking, `badPwdCount` climbed again within minutes with no further manual attempts on our end (C10) — proof of an external, automated source of failed logons.
- Root cause: only the server under test had been updated to the new password; the other 11 fleet servers were still configured with the old one and kept retrying, repeatedly re-tripping the lockout threshold.
- Resolution: password rotation executed across all 12 fleet servers; user subsequently confirmed all IIS App Pools operational under the new credential, cross-checked against the Zabbix services map (sysmapid=2).

## Current working theory

None outstanding — root cause and fix both confirmed above.

## Ruled out

- **AADDS hash-sync lag** — plausible initial theory given the account had just had its password changed, but `pwdLastSet` already showed the sync had completed before lockout was even discovered (C2). Not the cause.
- **`runas` reusing a cached credential silently** — checked via `cmdkey /list` (C5); no entry existed for `itservices`. Not the cause of `runas` not prompting (that behavior was never fully explained, but became moot once `Start-Process -Credential` gave a clear lockout error instead).
- **Wrong password entered by the user** — the account was never actually rejecting a *correct* password at any point; every failure after the initial diagnosis traced back to lockout state, not credential mismatch.

## Open questions / next steps

- The specific server where the initial (isolated, non-fleet-wide) password change was made was never identified in this session — worth confirming for the record, though no longer operationally important since the fleet-wide rollout is complete.
- No formal LDAP-level `badPwdCount`/`lockoutTime` recheck was performed after the fleet-wide rollout — closure relies on operational confirmation (all App Pools running, Zabbix map green) rather than a direct AADDS-side check. Low priority given the operational signal is strong, but worth doing if this recurs.
