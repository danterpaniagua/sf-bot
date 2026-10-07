# Investigation — 20260908_gitin2011-ope-jenkins-scope

**Status:** converged — ticket written and closed (`ops.md`). Webhook token, PR-event confirmation, and git commit remain as follow-up, not blocking closure.

**Jira:** [GITIN-2011](https://smartit-ar.atlassian.net/browse/GITIN-2011), parent [GITIN-1857](https://smartit-ar.atlassian.net/browse/GITIN-1857) — same parent epic as the Jenkins subtasks (GITIN-1858/1859/1957) reconciled in `smartpedidos/events/20260904_gitin1857-jenkins-status-review/`. That prior ticket covered the `develop`-scope Concentrador/Platform Jenkinsfiles; this one is a new, separate `ope` scope, not a continuation of that work.

## Purpose

Creation of a new `ope`-scoped Jenkins pipeline directory for SF-PEDIDOS, in the separate `sf-devops` repo (not part of this `bots/` monorepo):

```
/home/dpaniagua/Documentos/git/sf-devops/jenkins/SF-PEDIDOS/jenkinsfiles/ope/
```

Per the user: this scope currently only has Trivy (container vulnerability scanning) wired up.

## Confirmed facts

- **Location confirmed:** `sf-devops/jenkins/SF-PEDIDOS/jenkinsfiles/` has three scope directories: `develop` (existing, full pipeline), `stg` (existing, empty — no jenkinsfiles inside), and `ope` (new, created 2026-09-08).
- **`ope/` contents (both untracked in git, confirmed via `git status` in `sf-devops`):**
  - `dev-src-pedidos-concentrador.jenkinsfile`
  - `dev-src-pedidos-platform.jenkinsfile`
  - Both files are near-identical in structure (differ in `REPO_FOLDER_NAME`/`DOCKER_TAG`/agent label for `agent none` vs `agent any` at the pipeline level). Both already reference `GITIN-2011` in an inline comment on the `triggers` block.
- **Stages implemented in `ope/` (3 total):** Cloning Repo → Docker Build → Test with Trivy. Matches the user's "only has Trivy for now" description.
- **Stages implemented in `develop/`'s equivalent files (8 total, for comparison):** Cloning Repo, Bugs Report, Changelog, NPM install, Sonarqube Analisys, Docker Build, Quality Gate, Test with Trivy. `ope` is missing Bugs Report, Changelog, NPM install, Sonarqube Analisys, and Quality Gate relative to `develop`.
- **Trigger mechanism:** `GenericTrigger` matching either a direct push to the `ope` branch or a PR (opened/synchronize/reopened) targeting `ope`. Inline comment notes the GitHub webhook for the underlying repo must have both "push" and "Pull requests" events enabled, or the PR half of this trigger will never fire.
- **Webhook token resolved, 2026-09-28, both services confirmed** — both the concentrador and platform jenkinsfiles (pasted by the user this session, current content) now have a real generated token each (distinct values) in place of the `REPLACE_WITH_NEW_GENERIC_WEBHOOK_TOKEN` placeholder. **Values themselves not recorded here or anywhere in this repo** — real secrets, per root `CLAUDE.md`'s rule; referenced by name/purpose only ("the `ope` GenericTrigger webhook token" per service). The inline comment ("generate a dedicated token... before enabling") is now stale/misleading on both files now that a token is actually in place — worth a cleanup pass on that comment in `sf-devops`, not blocking.
- **Fixed, 2026-09-28 — platform's missing `docker rmi` cleanup.** Platform's `Test with Trivy` stage was missing the `post { always { docker rmi ... } } }` cleanup block that concentrador's has (concentrador's file explains why: scan-only image, never deployed, PR runs get a unique `pr-<number>` tag per run that would otherwise accumulate indefinitely on `sonarqube-srv`). User applied the same `always { sh "docker rmi -f $DOCKER_TAG:${env.IMAGE_TAG} || true" }` block to platform's file — confirmed present in the pasted current content, functionally identical to concentrador's (without the explanatory comment, not required for the fix itself). Both `ope` jenkinsfiles are now consistent on this point.
- **Credentials referenced:** `CRED_URL_GOOGLE-CHAT_OPE` (Google Chat webhook credential) — assumed to already exist in Jenkins credentials store, not verified from this repo (Jenkins credential existence isn't something a local file clone can confirm).
- **Real build log obtained, 2026-09-28 — `SF-Pedidos/ope/dev-src-pedidos-concentrador` build #2** (`data/jenkins_build2_concentrador_ope_manual_trigger_trivy_sigbus_20260928.txt`). Confirms two things directly:
  - **Trigger was manual, not webhook.** `Started by user jenkinsadministrator` — matches the theory in the (now superseded) open question below; the earlier successful test runs the user described were very likely manual "Build Now" runs too, same as this one, not GitHub-webhook-triggered.
  - **Build result: FAILURE — a Trivy crash, not an application or config bug.** Trivy's vulnerability DB downloaded successfully (117.78 MiB, `[vulndb] Artifact successfully downloaded`), then crashed immediately with `fatal error: fault, signal SIGBUS` inside `go.etcd.io/bbolt` (Trivy's embedded DB engine) while reading the just-downloaded DB file. A SIGBUS on a memory-mapped read like this points to the DB file being corrupted/truncated on disk, or a filesystem/mmap issue on the `sonarqube-srv` agent — not a defect in the commit being tested (`fix(GITIN-2000): agrega overrides de tar y axios en package.json`, the same `overrides.axios: "$axios"` change already understood from `smartpedidos/events/20260925_gitin2116-platform-npm-update/`). Worth a retry to see if it's transient (disk space, one-off download corruption) or a recurring `sonarqube-srv`-specific problem.

## Current working theory — resolved

Trivy-only is the **intentional, sufficient scope** for `ope`, not a partial/WIP state needing `develop`-level parity. Confirmed by the user: both jenkinsfiles were deployed to Jenkins and tested, and both successfully produced Trivy vulnerability-scan reports against the **post-upgrade `package.json`** — this ties `ope` directly to the dependency-upgrade work in `smartpedidos/events/20260908_gitin2000-axios-tar-upgrade/` and `20260908_gitin2002-platform-axios-tar-upgrade/` (GITIN-2000/GITIN-2002, axios/tar remediation). `ope`'s purpose is to give that upgrade work a real vulnerability-scan verification gate, not to replicate the full `develop` build/test/deploy pipeline.

## Ruled out

- **`ope` needing NPM install/Sonarqube/Quality Gate/Changelog/Bugs Report stages to reach `develop` parity** — ruled out. Confirmed intentional scope is Trivy-only; adding those stages isn't part of GITIN-2011.

## Open questions / next steps

1. ~~Scope clarification~~ — resolved, Trivy-only is intentional and already confirmed working end-to-end for its actual purpose (post-upgrade vulnerability verification).
2. ~~Webhook token still a placeholder~~ — resolved for both concentrador and platform, 2026-09-28 (see "Confirmed facts" above).
3. Confirm the GitHub webhook config for both `dev-src-smartPedidos-concentradorService` and `dev-scr-smartPedidos-platformsService` repos has "Pull requests" events enabled (not just "push") — required for the PR half of the trigger to ever fire. Token being in place now makes this the actual remaining blocker to the webhook going fully live (vs. manual-trigger-only, confirmed still the case as of build #2).
4. `stg/` scope directory exists but is empty — tangential, not part of this ticket's scope, noted only because it's a sibling directory in the same location.
5. This ticket's artifacts (`ops.md`, `ops-events.md`) are being written under `operations/events/` per the user's explicit placement, even though the underlying services are SmartPedidos-owned and the precedent (`GITIN-1858/1859/1957`) was tracked under `smartpedidos/events/` instead.
6. **New, 2026-09-28 — build #2's Trivy SIGBUS crash needs a retry to classify as transient vs. recurring.** If a rerun of the same commit succeeds cleanly, treat as a one-off (disk/download hiccup on `sonarqube-srv`); if it recurs, this becomes its own finding about the `ope` pipeline's reliability, separate from the webhook/token work above.
7. **⚠️ TEMPORARY CHANGE STILL PENDING REVERT, as of 2026-09-29.** `sh "docker rmi -f $DOCKER_TAG:${env.IMAGE_TAG} || true"` in `platform`'s `Test with Trivy` `post.always` block remains commented out (`echo "Allways"` placeholder in its place). **The capture it was blocking on is done** — GITIN-2116's `investigation.md` confirms the diagnostic `package-lock.json` pull succeeded and that whole line of investigation (stale `tar`) is closed. **But the revert itself was never confirmed applied** — not verified in this session, no confirmation from the user that the `docker rmi` line was restored. Still an open item: leaving this disabled long-term reintroduces the image-accumulation problem the cleanup exists to prevent.
