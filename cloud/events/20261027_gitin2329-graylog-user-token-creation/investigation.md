# Investigation — 20261027_gitin2329-graylog-user-token-creation

**Status:** converged; ops.md written 2026-10-27. Cause found for the SmartCloud instance: the global setting `restrict_access_token_to_admins: true` (`org.graylog2.users.UserConfiguration`) limits token creation to admins; consistent with users A and B lacking `users:tokencreate`; two changes applied (see "Applied"); effect on the users' Tokens page not yet checked

**Jira:** [GITIN-2329](https://smartit-ar.atlassian.net/browse/GITIN-2329) (OPE, Graylog: Problemas cont Token Creation).

## Report

A Graylog user (user A) cannot use the API: the option to create a token is not offered to them. Which Graylog instance is not stated (SmartCloud `sfcloud-monitoreo`, Graylog 7.1.3, or the SmartPedidos/SmartLoyalty stack `sf-monitoreo`, 5.2.12).

## Candidate causes (from Graylog's permission model as remembered, unverified; none checked)

1. **Missing token permissions.** Creating a personal access token needs the permission `users:tokencreate:<username>` (listing and removing need `users:tokenlist:` / `users:tokenremove:`). A user whose roles are custom or limited and do not include them (or who lacks the built-in `Reader` role) will not see the option. Check: the user's roles and effective permissions versus a user who can create tokens.
2. **Account type.** An external/SSO/LDAP-synchronized user, a read-only account or a service account may have the page restricted or token management handled elsewhere.
3. **Instance setting.** Newer Graylog versions have user/token configuration (token creation restrictions, lifetime). The 7.1.3 docs searched for the MCP proposal (`cloud/events/20261021_gitin2272-mcp-email-propuesta/`) named no such setting; whether one exists was left open there. Check the instance's cluster configuration.
4. **Wrong place.** Tokens are created under the user's own profile (*Edit profile → Tokens*) or by an admin under *System → Users and Teams → Tokens*; an admin can create one for another user if the user cannot.

## Confirmed (C1, `data/user-a-token-check.txt`, SmartCloud Graylog 7.1.3+c34604d)

- Authentication needed fixing first: the first runs returned HTTP 401 with an empty body on `/api/system` and `/api/users/user-a` (the token in the shell was not accepted; the user replaced it). My script also split the role name `Dashboard Creator` into two words and then failed on `GET /api/roles/Dashboard` -> 404 (script bug, fixed in the file; not an instance fault).
- The user is a local account (`external: false`), not read-only (`read_only: false`), not a service account, with roles `Reader` and `Dashboard Creator`.
- His effective token-related permissions are `users:tokenlist:user-a` and `users:tokenremove:user-a` (and the same for his user id); **there is no `users:tokencreate:user-a`**. The built-in `Reader` role has 17 permissions and none about tokens (`token_permissions: []`); the `Dashboard Creator` role was not read (script bug above). So the "create token" option is missing because he lacks the create permission; he can only list and remove tokens.
- Not checked: a user who *can* create tokens (to see what carries `users:tokencreate`), `Dashboard Creator`'s permissions, and whether 7.1.3 has an instance setting that withholds `users:tokencreate` from new users by default (the cluster-config part of the output was not seen).

## Second user and role findings (2026-10-27)

- A second account (user B) has the same problem. The Roles page (`data/roles-page-paste-20261027.txt`, user paste) shows both accounts hold `API Browser Reader` ("Allows viewing the API browser page", **not** marked built-in, so probably custom and editable), `Dashboard Creator` (built-in) and `Reader` ("Grants basic permissions for every user", built-in). So the missing `users:tokencreate` is the default state of ordinary users on this instance, not one account's problem. User B's own permissions were not read.
- `Reader` is built-in and read-only (`read_only: true` in C1): it cannot be edited in the UI or the API. A role-wide `users:tokencreate:*` would also let every holder create tokens for any user, which is acting as that user; so editing Reader is not an option even in principle.
- `API Browser Reader` only allows viewing the API browser; it does not give token creation (from the role description; its permission list was not read).

## Is it a Graylog configuration-file feature? (checked 2026-10-27)

- The `cloud-graylog` repo (separate repository, `main` @ `68678cf`) was searched: Terraform covers Azure resources only (VM, disks, network, Event Hub, App Services, Function Apps); `server.conf` (`/etc/graylog/server/server.conf` on the VM) is not versioned there and is only touched by the install script of the VM build (`password_secret`, `root_password_sha2`, `http_external_uri`, bind address). Nothing in the repo sets token, permission or default-role behavior; its README lists the server configuration still pending as timezone, e-mail relay and GeoIP.
- Not checked yet: the live `server.conf` key names and the instance's cluster-config classes (the two read-only commands given to the user: `data/cluster-config-classes.txt`, `data/server-conf-keys.txt`; neither file exists yet). Until they exist, whether a global setting for token creation exists in 7.1.3 is unknown.

## Global setting found (C4/C5, 2026-10-27, `data/cluster-config-classes.txt`, `data/usercfg-mcpcfg-roles.txt`)

- `GET system/cluster_config/org.graylog2.users.UserConfiguration` (raw JSON, no transformation): `restrict_access_token_to_admins: true`, `allow_access_token_for_external_user: false`, `default_ttl_for_new_tokens: PT720H`, `enable_global_session_timeout: false`, `global_session_timeout_interval: PT8H`.
- This matches the symptom: ordinary users keep `tokenlist`/`tokenremove` on themselves but are not offered `tokencreate`. That the flag is what withholds the option is inferred from its name and the symptom; not tested by changing it or by creating a token as a non-admin.
- C2 (`data/roles-all.txt`): 16 roles, all built-in/read-only; the only one with `users:tokencreate` is `Sidecar Manager`, and only for `graylog-sidecar`. `Dashboard Creator` = `dashboards:create`; `API Browser Reader` = `api_browser:read`; `MCP Server Access` = `mcp_server:access`.
- `org.graylog.mcp.config.McpConfiguration`: `enable_remote_access: false`, `enable_output_schema: true`. Relevant to the MCP proposal of `cloud/events/20261021_gitin2272-mcp-email-propuesta/`: remote MCP access is currently off.
- Consequence for option 2 (per-user `users:tokencreate`): unknown whether the grant overrides the admin restriction; do not assume it does.

## Proposed approach for the AI integration (not applied, not decided)

- A dedicated local user for the integration (not a person's account), with the least roles that cover what it reads (start with `Reader`; stream-level access is a separate decision), and an admin creates its token. The `restrict_access_token_to_admins` setting stays `true`.
- `default_ttl_for_new_tokens` is `PT720H` (30 days): whether it applies to a token an admin creates for another user was not verified; if it does, the token needs a rotation routine.
- The token value goes to a secrets manager, never into `events/`.

## Options (nothing applied)

1. An admin creates the token for each user (UI: System → Users and Teams → user → Tokens). No permission change.
2. Grant `users:tokencreate:<user>` per user through the API: `scripts/scripts-grant-token-create.sh` (dry run by default; `--apply` writes; it backs up the current permission list first because the PUT replaces it). Whether `PUT /api/users/{username}/permissions` is available in 7.1.3 was not verified.
3. A custom role with `users:tokencreate:*`: not recommended (privilege escalation).
4. Set `restrict_access_token_to_admins` to `false` via `PUT system/cluster_config/org.graylog2.users.UserConfiguration` (resend the whole object): instance-wide, lets every user create tokens that act as that user; needs a decision on whether that is acceptable. Preferred narrow path stays option 1.

Scripts index (output files in `data/`):

| # | Script | Purpose |
|---|---|---|
| C1 | `scripts/scripts.sh` | User, roles and token-related permissions (read-only) -> `user-a-token-check.txt`, `jacquelinem-token-check*.txt` |
| C2 | `scripts/scripts-roles.sh` | All roles, read-only flag, token permissions (read-only) -> `roles-all.txt` |
| C3 | `scripts/scripts-grant-token-create.sh` | Per-user `users:tokencreate` grant; written, never run |
| C4 | `scripts/scripts-cluster-config.sh` | Cluster-config classes (read-only) -> `cluster-config-classes.txt` |
| C5 | inline | `UserConfiguration`, `McpConfiguration`, three roles (read-only) -> `usercfg-mcpcfg-roles.txt`; streams and `Reader` permissions -> `streams-and-reader-perms.txt`; user roles/stream permissions -> `jacquelinem-roles-streamperms*.txt`; streams visible to a user token -> `jacquelinem-visible-streams.txt` |
| C6 | `scripts/scripts-create-ai-role.sh` | WARNING state-changing: creates role `AI Integration Streams` -> `create-ai-role-*.txt` |
| C7 | `scripts/scripts-unrestrict-tokens.sh` | WARNING state-changing: `restrict_access_token_to_admins` = false -> `unrestrict-tokens-apply.txt`, backup `user-configuration-backup.json` |
| C8 | `scripts/scripts-create-stream-role.sh` | WARNING state-changing: creates the DEV and HTTP roles -> `create-stream-roles-*.txt` |
| C9 | `scripts/scripts-delete-ai-roles.sh` | WARNING state-changing: deletes the three custom roles -> `delete-ai-roles-*.txt`, backups in `role-backups/` |

## To confirm

`scripts/scripts.sh <username> <base-url> <token-env-var>` (read-only; prints the user's roles, flags and token-related permissions only, the token permissions per role, and the cluster-config classes that look user/token related). Run it for user A and for a user who can create tokens, then compare.

## Open questions

- Whether the per-user grant (option 2) works while the restriction is on.
- Use case (stated 2026-10-27): token for an AI integration through the REST API; MCP is not in scope for now (`enable_remote_access` stays `false`). This points to option 1 with a dedicated account instead of a person's account (below). Not decided yet: which AI tool, which streams it must read, the account name.
- Whether the goal is the user's own token or API access in general (an admin can create a token for them).

## Applied (2026-10-27)

- C6 `scripts/scripts-create-ai-role.sh --apply` (`data/create-ai-role-apply.txt`): custom role `AI Integration Streams` = `streams:read:<id>` for the 12 `PROD-*-AppServicePlan` / `PROD-*-FunctionApp` streams (no HTTP, DEV or system streams). The user `jacquelinem` holds it (reported by the user).
- C7 `scripts/scripts-unrestrict-tokens.sh --apply` (`data/unrestrict-tokens-apply.txt`): `restrict_access_token_to_admins` set from `true` to `false`; readback shows the other four keys unchanged. Original object in `data/user-configuration-backup.json`; rollback is the PUT of that file.
- Not verified: whether the flag alone makes the create-token option appear for non-admins (users A and B had no `users:tokencreate`, and `jacquelinem`'s permissions were not read: `data/jacquelinem-token-check.txt` does not exist).
- Recheck of `jacquelinem` (`data/jacquelinem-token-check.txt`, `-2.txt`): after C7 she has `users:tokencreate|tokenlist|tokenremove:jacquelinem` (user A had no `tokencreate` before C7; his permissions were not re-read, so the flag as the cause is consistent but not isolated). First check showed roles `Reader`, `Dashboard Creator` only; after the role was assigned: `AI Integration Streams`, `Reader`, `Dashboard Creator`.
- C8 `scripts/scripts-create-stream-role.sh --apply` (`data/create-stream-roles-apply.txt`): custom roles `AI Integration Streams DEV` (1 stream: `DEV`) and `AI Integration Streams HTTP` (the 8 `PROD-*-AppServiceHTTPLogs` streams). Assigned to nobody. HTTP logs are Ops-only for now, so the HTTP role should go only to an Ops-approved account.
- The token value pasted by the user in chat on 2026-10-27 was not used or stored; the user said it will be deleted after tests.
- Streams visible to `jacquelinem`'s own token (`data/jacquelinem-visible-streams.txt`, `GET /api/streams`, 14 rows): `Default Stream`, `DEV`, and the 12 `PROD-*-AppServicePlan` / `PROD-*-FunctionApp` streams. None of the 8 `*-AppServiceHTTPLogs`, none of `All events` / `All system events` / `DEV-AppServiceHTTPLogs`. The 12 + `DEV` match the roles `AI Integration Streams` and `AI Integration Streams DEV` exactly; the absence of the HTTP streams is consistent with the HTTP role not being assigned (her roles were not re-read after the C8 roles were created). Where `Default Stream` visibility comes from was not determined. No before-state was captured, so that the roles (and not an earlier grant) provide the access is consistent but not isolated.
- This test is the list of streams only; that a search on them returns messages was not tested.
- `jacquelinem` now (`data/jacquelinem-roles-streamperms.txt`): roles `Reader`, `Dashboard Creator` only (the custom `AI Integration Streams*` roles are not on her; the user said "no roles"). She holds 10 **direct** `streams:read:<id>` permissions on her user: `Default Stream`, `DEV` and the 8 `PROD-*-AppServicePlan` streams, identical to the 10 rows her token lists (`data/jacquelinem-visible-streams.txt`, overwritten by the re-run; the earlier 14-row result is the bullet above). So her access to those 10 does not come from the roles; the 4 `PROD-*-FunctionApp` streams she saw earlier came only from `AI Integration Streams`. When and by whom the direct permissions were added is unknown. Entity shares were not checked and are not needed to explain the 10.
- C9 `scripts/scripts-delete-ai-roles.sh --apply` (`data/delete-ai-roles-apply.txt`, dry run `data/delete-ai-roles-dryrun.txt`): the three custom roles `AI Integration Streams`, `... DEV`, `... HTTP` were deleted (none had members); role JSON backups in `data/role-backups/` (recreate with `POST /api/roles`). Recheck of `jacquelinem` after the deletion (`data/jacquelinem-roles-streamperms-2.txt`): roles `Reader`, `Dashboard Creator`; the same 10 direct `streams:read` permissions; `users:tokencreate|tokenlist|tokenremove:jacquelinem` present. Unchanged by the deletion.
- Standing change from this event: `restrict_access_token_to_admins` is `false` on the SmartCloud instance (C7), so every user can create tokens that act as them. Rollback: PUT `data/user-configuration-backup.json`.
- Decision (user, 2026-10-27): leave `restrict_access_token_to_admins` at `false`; any user may create API tokens on the SmartCloud instance (confirmed 2026-10-28). No rollback planned.
- User-stated (2026-10-28): the tokens pasted in chat were deleted; `ops.md` was pasted into Jira; decision on the setting: keep `restrict_access_token_to_admins` at `false` (any user can create tokens), no longer "for now".
