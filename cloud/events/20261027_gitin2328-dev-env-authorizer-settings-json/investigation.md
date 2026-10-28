# Investigation — 20261027_gitin2328-dev-env-authorizer-settings-json

**Jira:** [GITIN-2328](https://smartit-ar.atlassian.net/browse/GITIN-2328) (OPE, a developer cannot use their environment).

**Status:** converged; ops.md written 2026-10-27. Solved per the user (2026-10-27): the copy of the authorizer keys into the dev's store had lost its quotes (C1 vs C3); the key(s) were re-copied. Post-fix check (C1 again, `data/authorizer-keys-check-after-fix.txt`, 2026-10-27 15:52): all 5 keys `VALID JSON`. That the developer's API now starts is his statement, not observed.

## Report

A developer cannot connect to their own environment while working on branch `feature/GSFC-1084-eliminar-lista-de-precios`. The error is `Newtonsoft.Json.JsonReaderException: 'Unexpected character encountered while parsing value: S. Path 'Platform', line 1, position 11.'`.

## Confirmed facts (source read-only, `cloud/repo/SmartFran.Cloud`, branch `main`, HEAD `e00e8c467`, 2026-10-14; the feature branch is **not** in the local clone, so its diff was not read)

- The only config model with a root property `Platform` that goes through `JsonConvert.DeserializeObject` is `AuthorizerSettings` (`Source/Common/Providers/SmartFran.Cloud.Provider.Authorization.AzureAppConfiguration/AuthorizerSettings.cs`: `Platform, ModuleName, Domain, ClientId, ClientSecret, Audience, TokenName, BusinessRules, BusinessActions[]`). `GenericSettingCached` also has a `Platform` property but is a cache model.
- `AzureAppConfigurationRelationsService.GetAuthorizerSettings` (same folder, ~line 55) reads the Azure App Configuration key `SmartFran.Cloud.<ModuleName>.Authorization.<providerName>` from `_configuration` and calls `JsonConvert.DeserializeObject<AuthorizerSettings>(settingValue)`. A **missing** key gives `null` (no exception); only a **malformed value** produces this exception.
- It is wired by `Add<Module>Settings` extensions in Business, Catalog, Orders, Person and Sales APIs when `SmartFran_Cloud_Providers:Auth<Module>SettingsProvider` is enabled with provider `SmartFran_Cloud_Providers_Authorization_AzureAppConfiguration`; the store comes from `AzureAppConfigurationAuthorizationSettings.Connection`.
- The message fits a text that begins `{"Platform":S...`: `{"Platform"` is 11 characters, so the parser fails right after the colon, on a value starting with `S` that is not a quoted string (an unquoted word, or a stray character before the opening quote).

## Confirmed in the dev's App Configuration store (C1, `--auth-mode key`, read-only, no values printed; `data/authorizer-keys-check.txt`)

- All 5 `SmartFran.Cloud.*.Authorization.*` keys (`Business`, `Catalog`, `Person`, `Sales`, `Site`, each `.Auth0`, no label) hold values that are **not valid JSON**: every one starts with `{Platform:SmartFran.Cloud,Modu...` — every property name **and value is unquoted** (lengths 5718, 5152, 1089, 2139, 4619 characters).
- That matches the error exactly: `{Platform:` is 10 characters, Newtonsoft's reader tolerates the unquoted property name, then fails at position 11 on the first character of the unquoted value, `S` of `SmartFran.Cloud` ("Unexpected character encountered while parsing value: S. Path 'Platform'"). The first key the application reads fails first, so the other keys would fail the same way.
- So the failure is in the data of this store, not in the code of `main`, and it is independent of the branch name. The pattern (all double quotes missing, in every key) is what a JSON value passed through a shell or script without escaping the inner quotes looks like (typical in PowerShell/cmd, or an import script that strips them); how the store was seeded is not known.
- My `jq` check is stricter than Newtonsoft (it also rejects unquoted property names); here both agree because the values are unquoted too.

## Previous working theory (superseded by the above)

The App Configuration value of one `SmartFran.Cloud.*.Authorization.*` key in that dev's environment store is not valid JSON: the `Platform` value is unquoted or has a stray character, probably from a hand edit made while adding or removing permissions/`BusinessActions` for the price-list removal. The error is not in the application code of `main`. Whether the branch changed the authorizer settings model or the expected keys is **not known** (branch not read).

## To confirm

1. Run `scripts/scripts.sh <app-configuration-name> <subscription-id>` against the dev's store (read-only, prints no values): every `SmartFran.Cloud.*.Authorization.*` key reported `VALID JSON` or `INVALID JSON` with the first 30 characters. The key reported invalid is the culprit; fix its value in the store (valid JSON, strings in double quotes).
2. If all values are valid, the failing text is read from somewhere else: fetch the branch (`git fetch origin` in the clone) and look for other `DeserializeObject` calls on a type with a `Platform` property in the branch diff against `dev`; also ask for the full stack trace (the first frames name the caller).
3. Ask which of the APIs fails at startup and whether the same store works for another developer on `dev`.

## Attempts

- `scripts/scripts.sh` with `--auth-mode login` against the dev's App Configuration store returned `ERROR: Operation returned an invalid status 'Forbidden'` (user's paste, not saved as a file): the SRE account has no data-plane role (App Configuration Data Reader) on that store, so the key values could not be read. Next: the same script with the third argument `key` (works only with listKeys permission on the store), or the developer runs it himself (his environment already reads the store). A role grant was not requested.
- With the third argument `key` the same script returned `ERROR: Operation returned an invalid status 'Bad Request'`: caused by the script itself, since an App Configuration key filter accepts `*` only at the end (`SmartFran.Cloud.*.Authorization.*` is invalid). Fixed: the script lists `SmartFran.Cloud.*` and filters `.Authorization.` with `jq`. Whether `key` mode is permitted for this account is still untested.

## Timeline: the user reports it worked until yesterday

- Code side (read-only, `cloud/repo/SmartFran.Cloud` `main` @ `e00e8c467`): `JsonConvert.DeserializeObject<AuthorizerSettings>` in `AzureAppConfigurationRelationsService` is unchanged since 2023-11-01; the provider folder's last commit is 2026-10-08 (Azure SDK package bump for net10). So nothing in `main` changed yesterday; the branch was not read.
- Store side: the values are invalid now, so either they changed yesterday (re-seeded, re-imported or edited) or they were always unquoted and a code path that tolerated them changed. The store's revision history decides: `scripts/scripts-revisions.sh` (C2, read-only) prints per revision the date, content type, length, valid/invalid and the first 14 characters of each of the 5 keys. Revision retention depends on the pricing tier (this store is Developer tier), so older revisions may be gone.
- Also ask what the developer did yesterday: pulled/merged the branch, ran a seeding or import script, recreated the store, or edited keys in the Portal.

## Source of the copy (user, 2026-10-27)

The developer's store is a copy of the shared DEV store `SmartFran-Cloud-Settings-DEV` (resource group `smartfran.cloud`, same subscription, Developer tier; `data/appconfig-shared-dev-overview.txt`). So the known-good values should be there. Next: run `scripts/scripts.sh` against the shared store (C3). If its 5 keys are valid JSON, the copy mechanism stripped the quotes (the dev's store lengths are 5718, 5152, 1089, 2139 and 4619; valid copies should be longer by two characters per quoted name/value); if they are invalid there too, the shared store broke (and other users would be failing). The method used to copy (Portal import/export, `az appconfig kv import/export`, `kv copy`, a script) is not known.

## Confirmed: the shared DEV store is fine, the copy lost the quotes (C3, `--auth-mode key`, `data/authorizer-keys-check-shared-dev.txt`)

All 5 `SmartFran.Cloud.{Business,Catalog,Person,Sales,Site}.Authorization.Auth0` keys of `SmartFran-Cloud-Settings-DEV` are `VALID JSON`, each with the same top-level properties (`Audience, BusinessActions, BusinessRules, ClientId, ClientSecret, Domain, ModuleName, Platform, TokenName`). The same 5 keys in the developer's store are unquoted (C1). So the shared store is not the problem (other users are not affected by this), and the quotes were lost while copying to the developer's store. When it happened (before or yesterday) is not known: the revisions check (C2, `data/authorizer-revisions.txt`) has not been run.

## Outcome (user-stated, not seen in a file)

- Before copying, a read of the dev store's `Person.Authorization.Auth0` value returned `Forbidden` again (`data/az-appconfig-kv-show-forbidden-20261027.txt`); the user then updated the managed role (permissions on the store; which role and scope are not recorded here) and the read worked.
- The user ran the re-copy from the shared DEV store and reports the key fixed and the problem solved. The re-check shows all 5 keys valid after the fix, so all 5 were corrected (no output of the copy itself was saved). That the developer's environment starts is his statement.

## Fix (applied by the user)

The 5 values must be valid JSON (all property names and string values in double quotes; `BusinessActions` as an array of objects with `Permissions` and `Callers` string arrays), keeping the `Platform`, `ModuleName`, `Domain`, `ClientId`, `ClientSecret`, `Audience`, `TokenName`, `BusinessRules` and `BusinessActions` fields. The correct content has to come from a known-good store (the shared DEV one) with the dev environment's own Auth0 `Domain`/`ClientId`/`ClientSecret`/`Audience`; do not write secrets in any file here. Write the new values from a file (`az appconfig kv set --value` takes the text as is; passing JSON inline from a shell is how the quotes get lost) or in the Portal. Validate afterwards by rerunning `scripts/scripts.sh` (all keys `VALID JSON`).

## Open questions

- The name of the dev's App Configuration store and its subscription.
- Full stack trace, and whether the failure happens at startup or on the first authorized request.
- What the branch changed (the clone has no `feature/GSFC-1084-eliminar-lista-de-precios` ref); it is probably irrelevant to this error.
- How the store was seeded (script, import, manual) and why the values lost their quotes; other keys of the store may have the same problem (only the `Authorization` keys were checked).
- Whether the developer's environment should use the shared DEV store's Auth0 values as they are (the store was copied from it) or its own.

## Scripts index (outputs in `data/`)

| # | Script | Purpose |
|---|---|---|
| C1 | `scripts/scripts.sh` | Authorizer keys of the dev store: VALID/INVALID JSON, first 30 characters (read-only) -> `authorizer-keys-check.txt`, `authorizer-keys-check-after-fix.txt` |
| C2 | `scripts/scripts-revisions.sh` | Per-revision check of the 5 keys (read-only); never run |
| C3 | `scripts/scripts.sh` against the shared DEV store | Same check on `SmartFran-Cloud-Settings-DEV` -> `authorizer-keys-check-shared-dev.txt` |
| C4 | user paste, saved | `az appconfig kv show` on the dev store returned Forbidden -> `az-appconfig-kv-show-forbidden-20261027.txt` |
