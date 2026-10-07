# Investigation — 20260919_search-knowledgebase

**Status:** in progress — design proposal, not yet implemented

## Goal

The `bots/` monorepo has grown too large to rely on manual grep/read across `events/` markdown files when checking for precedent during a new investigation. User wants a local, Claude-usable search/knowledge-base layer over `investigation.md` files and their evidence, to cut down on wasted full-file reads during the discovery/triage phase of a new ticket. Framed explicitly as tooling for Claude's own consumption, not a human-facing search UI.

## Confirmed facts

- SQLite FTS5 is available in the local Python (`sqlite3` stdlib module compiles with FTS5 support) — confirmed via `python3 -c "import sqlite3; ... CREATE VIRTUAL TABLE ... USING fts5(x)"`.
- Corpus size (as of 2026-09-19): 87 `investigation.md` files across all four sub-projects (`loyalty/`, `cloud/`, `smartpedidos/`, `operations/`), out of 400 total `.md` files under `events/` (the rest being `ops.md`/`ops-events.md`/tickets — explicitly out of scope for this index per user's "Investigation and raw evidences" scoping).
- Evidence volume (`events/*/data/`) totals ~5.4GB. Breakdown by extension: 1329 `.json`, 929 `.gz`, 151 `.txt`, 34 `.csv`, plus smaller counts of `.html`/`.conf`/`.zip`/`.xml`/`.js`.
- The 929 `.gz` files are almost entirely **not real evidence** — they're a stray `venv/lib/python3.12/site-packages/botocore/data/**/*.json.gz` (AWS SDK service definitions) accidentally left inside `smartpedidos/events/20260901_s3-history-utc3-normalization/data/`. Total size of all `.gz` combined is only 16MB. Flagged for cleanup as an unrelated finding — not acted on here, out of this investigation's scope.
- The real driver of the 5.4GB is a handful of `.csv` files: raw HTTP-log exports (`httplogs_raw_export.csv` and variants) ranging 100MB–825MB each, concentrated in `cloud/events/` (`20260915_gitin2042-waf-cost-estimate`, `20260913_pos-net-http-timeout`, `20260915_sales-appservice-perf-report`, `20260917_smartpedidos-peru-orders-pending`, `20260918_sales-cpu-live-metrics-discrepancy`). These are repetitive per-request log rows — low marginal full-text search value per byte, high storage/indexing cost if indexed whole.
- Raw evidence files under `events/*/data/` are already gitignored (root `.gitignore`: `**.json`, `**.csv`, `**.tsv`, `**.tbl`, `**.table`, `**.cer`, `**.svclog`, `**.txt` — "local-only, never in git history"). Consistent with keeping the proposed search DB itself local-only too.
- `investigation.md` is not append-only — it's rewritten in place as understanding evolves (confirmed both in root `CLAUDE.md` and in the `ope-sre-output` skill template). This means:
  - A conclusion's supporting evidence (a specific quoted line/value) survives indefinitely as long as the conclusion itself stands, because decisive evidence is typically quoted directly into the prose (e.g. "confirmed via `data/svclog_trace.txt` line 42: `<Data>...</Data>`"), not just referenced by pointer.
  - Evidence tied to a *disproven* theory can disappear from the narrative entirely on rewrite, even though the underlying `data/` file is still on disk — this is the one real gap that indexing `investigation.md` text alone would miss.
- Sampled a real large investigation (`operations/events/20260905_sonarqube_upgrade/investigation.md`) as a structural reference — confirms the `ope-sre-output` template is followed in practice (evolving sections, confirmed facts with evidence references, open questions at the end), and shows decisive evidence is generally cited by both file reference and quoted value/result, not by pointer alone.

## Current working theory

Build a local, gitignored SQLite FTS5 database (no server, single file, BM25 ranking built in) as a triage layer, not a source of truth:

1. **`investigation.md` (87 files):** full-text indexed, always — this is where decisive/confirmed content already lives in prose.
2. **Evidence files (`events/*/data/**`):** metadata-only by default (path, project, event, extension, size, mtime) — covers two things full-text indexing `investigation.md` alone would miss: (a) dead-end evidence whose citation got rewritten away, (b) "don't repeat this pull" awareness (avoid re-running a query whose output already exists for this event), even for evidence that was never decisive enough to get quoted. Full-content indexing is reserved for small text-based files only (rough cutoff still open, see below) — the large raw httplog CSVs are excluded from content indexing, metadata only.
3. **Two content roles within `investigation.md`:** `analysis` (working theories, dead ends, general narrative) vs `conclusion` (the confirmed root cause / resolution). Still needs a concrete tagging mechanism — either a fixed heading convention the indexer greps for (e.g. a `## Root Cause (CONFIRMED)`-style heading, to be reconciled against whatever the `ope-sre-output`/`loyalty-sre-output`/`sp-sre-output`/`cloud-sre-output` skills' actual templates already use, if anything), or a new explicit marker introduced going forward. Not yet decided — see open questions.
4. **Consumption model:** a small query CLI (e.g. `search.py "query" --type conclusion --project cloud`) returning compact structured hits (path, project, Jira ref, date, one-line summary/conclusion text) — not raw file dumps. Wrapped in a new cross-project skill, tentatively named `historic-search`, invoked via the `Skill` tool at Claude's discretion (judgment-triggered, like the existing "read investigation.md first" rule — not run reflexively on every message).
5. **DB hits are leads, not facts.** Same discipline as the existing "verify local event-folder references before citing them as fact" rule — a search hit tells Claude which 2-3 of ~90 files are worth opening; the live file is still read and verified before anything from it is cited in a ticket. This also means the index doesn't need real-time freshness — stale-but-mostly-right is acceptable for triage as long as re-verification happens before citation.

## Ruled out

- **Elasticsearch** — ruled out as over-engineered for this corpus/use case. Its value (distributed indexing, relevance ML, multi-user concurrency, long-running service) doesn't apply to a single-user local tool over ~90 small prose files plus a few thousand small evidence files. A JVM service would be pure overhead with no upside over SQLite FTS5, which needs no server, is a single gitignored file, and gives BM25 ranking natively.
- **Semantic/embedding-based search** — deferred, not ruled out permanently. Would add real complexity (embedding model, vector store, re-indexing on schema change) that isn't justified until keyword/exact-match search (SQLite FTS5) proves insufficient in practice.
- **Full-content indexing of all evidence regardless of size** — ruled out for the handful of 100MB–825MB raw httplog CSVs specifically; metadata + header/schema line only for those. Full content indexing remains in scope for genuinely small evidence files.

## Open questions / next steps

- **Analysis/conclusion tagging mechanism**: check whether `loyalty-sre-output` / `sp-sre-output` / `cloud-sre-output` / `ope-sre-output` skills already have a distinguishable "confirmed root cause" heading in their `investigation.md` templates that could be reused as-is, before inventing a new convention. (`ope-sre-output`'s template, checked here, uses `## Confirmed facts` / `## Current working theory` / `## Ruled out` — none of these map cleanly to a single "conclusion" heading; the closest signal is the `Status: converged` field plus prose density, not a dedicated section.)
- **Size cutoff for full-content indexing of evidence files** (proposed ~200KB–2MB, not yet fixed).
- **`historic-search` skill's trigger conditions** — needs explicit spec (e.g.: any new event-folder creation, or only on "has this happened before"-shaped user asks, or both).
- **Indexer script location and invocation** — not yet designed (e.g. `bots/tools/search/build_index.py` + `bots/tools/search/search.py`, DB at a gitignored `bots/.search_index.db`). No code written yet.
- **Jira ticket** — not yet created/provided for this initiative. Needs a URL per root `CLAUDE.md`'s "External References" rule before any external-facing output (ticket/email) is written; not needed to continue design work in `investigation.md`.
- Cleanup of the stray `venv/` inside `smartpedidos/events/20260901_s3-history-utc3-normalization/data/` — noted as a tangential finding, not part of this investigation's scope.
