# Investigation — 20261001_github-actions-ubuntu-24-04

**Jira:** none yet (ask the user for the ticket URL when one exists).

**Status (2026-10-02):** in progress — decision taken, patch prepared, not applied anywhere. A Google Chat message for Operations was drafted twice (first as a proposal, then as an advisory with sections for origin, impact and required fix, which is the version to use); no ticket exists yet and nothing has been announced or changed in any repository.

## Trigger

GitHub notice (pasted by the user, 2026-10-01): the `ubuntu-latest` runner label will migrate to the Ubuntu 26 image, rolled out gradually between **2026-10-19 and 2026-11-19**; once a workflow is migrated it no longer runs on Ubuntu 24; the Ubuntu 26 image may ship different tools. Scope given by the user: the Cloud repo. **Decision (user, 2026-10-01): change `ubuntu-latest` to `ubuntu-24.04`.**

## Confirmed facts — repo `SmartFran.Cloud`, branch `main`, HEAD `d969856fa` (2026-09-30), working tree clean at the time of reading

- 75 workflow files in `.github/workflows/`; **161 jobs use `runs-on: ubuntu-latest`** (in **69 files**), 31 use `windows-latest` (not part of the notice), none uses another label or an expression/matrix for `runs-on`; the 161 are plain `runs-on: ubuntu-latest` lines.
- 11 PRO workflows have Ubuntu jobs: Business, Admin, Catalog, CodeGen, TicketProcessAsync, Orders, ScheduledJobs, Platform, Person (all Ubuntu) and Sales/POS (Windows build + Ubuntu deploy job).
- Actions used by the Ubuntu jobs: `upload/download-artifact@v4`, `actions/checkout@v4` (54) plus `@v3` (7) and `@v2` (6), `azure/webapps-deploy@v3` (48) and `@v2` (8), `actions/setup-dotnet@v4` (43) and `@v3` (8), `Azure/functions-action@v1` (17), `peter-evans/repository-dispatch@v4`/`@v3`, `kolpav/purge-artifacts-action@v1`, `actions/cache@v2` (1). Every `dotnet restore/build/test/publish` job (51 each) has a matching `setup-dotnet` step, so it does not rely on the image's preinstalled SDK. Other commands are basic shell (`rm`, `echo`, `ls`, `mv`, `sleep`, `cat`).
- The only image-dependent steps found: `Poc_v1.yml` and `MergeDeploy.DEVtoTEST_v3.yml` install the GitHub CLI with `sudo apt` (key import, `software-properties-common`).
- 17 workflow files use older actions (`checkout@v2/@v3`, `setup-dotnet@v3`, `cache@v2`, `webapps-deploy@v2`); whether they still run today was not checked.

## The change

`ubuntu-24.04.patch` (this folder): unified diff, **69 files, 161 lines**, each `runs-on: ubuntu-latest` → `runs-on: ubuntu-24.04`; verified with `git apply --check` against `main` `d969856fa` (check only — nothing was modified in the repo clone, which is read-only reference material). The `windows-latest` jobs are untouched. Apply from the repo root of a working clone: `git apply <path>/ubuntu-24.04.patch`.

## Not known / to decide

- Which branches carry workflows that must be patched: this patch was generated from `main`; `dev`, `test` and `stg` branches (and the other SmartFran repos with workflows, e.g. the platform service) were not read. The team's promotion flow (DEV → TEST → STG → PRO) decides where to apply it first to avoid merge conflicts.
- Whether `ubuntu-24.04` remains available as a label for the whole transition period and beyond (GitHub runner image lifecycle was not checked) — confirm in GitHub's runner-image documentation.
- Behaviour of the two `apt` workflows and the old actions on any newer image — not tested.
- The two follow-ups (testing the Ubuntu 26 image on DEV/TEST; updating the old actions and `apt` steps) are proposals, not decided.
