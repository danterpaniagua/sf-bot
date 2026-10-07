# Investigation — 20260827_jenkins-bugreport-toggle-branch-filter

**Status:** converged — applied by user

## Confirmed facts
- Repo `sf-devops` (separate repo, not in `bots/`) holds `jenkins/SF-PEDIDOS/jenkinsfiles/develop/dev-src-pedidos-concentrador.jenkinsfile` and `dev-src-pedidos-platform.jenkinsfile`, mirrored copies of the live Jenkins job pipeline scripts.
- The working tree for both files, as pasted back from live Jenkins at the start of this ticket, reflected the actual running configuration — a `staged` (git index) version in the same repo was a stale WIP that migrated `prAnalyzer`/`changelogAnalyzer` into a shared Groovy library (`gitSPAnalizer.groovy`); that migration was never applied to Jenkins and is unrelated to this ticket's scope.
- Both jobs use `GenericTrigger` (Generic Webhook Trigger plugin) bound to a per-service GitHub webhook token, with no `genericVariables`/filter configured — the trigger fired a build on every push to the repo, regardless of branch.
- The `Bugs Report` stage (Claude Code-based PR analysis via `prAnalyzer`) ran unconditionally on every triggered build in both pipelines — no way to skip it.
- Platform's `LOCAL_GIT_BRANCH` was set to a stale feature branch (`mejorasLogsTestTokenHeaders`) rather than `develop`, unlike Concentrador (already `develop`).

## Actions taken
- Added a `RUN_BUGS_REPORT` boolean parameter (default `false`) to both Jenkinsfiles' `parameters {}` block, and gated the `Bugs Report` stage with `when { expression { return params.RUN_BUGS_REPORT } } }`. Webhook-triggered builds use the parameter default (`false`), so the stage is now skipped by default; a manual "Build with Parameters" run can still opt in.
- Hoisted the target branch into a single Groovy variable (`def TARGET_BRANCH`) declared above the `pipeline {}` block in both files, referenced by both `environment { LOCAL_GIT_BRANCH = "${TARGET_BRANCH}" }` and the trigger filter, so the two can't drift out of sync.
- Added `genericVariables: [[key: 'ref', value: '$.ref']]` plus `regexpFilterText: '$ref'` / `regexpFilterExpression: "^refs/heads/${TARGET_BRANCH}\$"` to each `GenericTrigger`, so the webhook only starts a build when the GitHub push `ref` matches `refs/heads/<TARGET_BRANCH>`.
- Set `TARGET_BRANCH = "develop"` for Platform (confirmed by user), aligning it with Concentrador and fixing the stale `mejorasLogsTestTokenHeaders` branch reference as a side effect.
- User pasted both updated Jenkinsfiles into their respective Jenkins job configurations and confirmed the changes are live.

## Ruled out
- N/A — no dead ends; both changes worked as designed on first pass.

## Open questions / next steps
- The `sf-devops` git repo's index still holds the stale, unapplied library-migration WIP for these two files, unrelated to this ticket — out of scope here, flagged separately to the user during the session.
