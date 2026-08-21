# Investigation — messages with source:unknown-service (GITIN-1908)

**Status:** in progress, scoping. Waiting on live rule source for the two candidate rules.

## Objective

New bug report: some Graylog messages show `source: "unknown-service"`. Distinct symptom from GITIN-1905 (Default Stream duplication), but suspected same root cause family — a field-name drift between `Properties_Service`/`Properties_Environment` (what the local reference file `cloud-graylog/docs/sales-direct-gelf-clef-format.rule` has documented) and `Service`/`Environment` (what GITIN-1905 confirmed is actually live on at least one rule in this same pipeline, modified 2026-08-18).

## Relevant prior context (GITIN-1905, same session, same file)

The local `.rule` file documents two related rules in this same pipeline:

```
rule "GITIN-1835: CLEF source from Properties.Service"
when
  has_field("MessageTemplate") AND has_field("Properties_Service")
then
  set_field("source", $message.Properties_Service);
end

rule "GITIN-1835: CLEF source fallback"
when
  has_field("MessageTemplate") AND NOT has_field("Properties_Service")
then
  set_field("source", "unknown-service");
end
```

GITIN-1905 confirmed (via live query against a *different* rule in the same file, "CLEF Azure resource fields for Sales PRO") that the live pipeline had already been changed to use bare `$message.Service` instead of `$message.Properties_Service`, as of 2026-08-18 — but the local reference file wasn't updated to match at the time (fixed as part of GITIN-1905's cleanup, but only for that one rule).

**Working theory, not yet confirmed:** if these two "CLEF source" rules were *not* updated the same way live (or if they were, but the local file is still stale here too), then `has_field("Properties_Service")` never matches real messages (since the real field is bare `Service`), which means the primary rule never fires and the fallback rule fires on every single direct-GELF CLEF message — explaining `source: "unknown-service"` appearing broadly, not just on messages genuinely missing a service name.

## Not yet done

- Live source for both "CLEF source from Properties.Service" and "CLEF source fallback" rules not yet pulled — requested from the user, response pending.
- No message count/sample confirming how widespread `source: "unknown-service"` actually is, or which app(s)/message shapes it affects.

## Next steps

1. Pull live source for both rules (`GET /api/system/pipelines/rule`, filter title contains "CLEF source").
2. If confirmed still using `Properties_Service`: same class of fix as GITIN-1905 — update both rules to use bare `Service`, applied live + mirrored in the local reference file.
3. Quantify: how many/which messages currently show `source: "unknown-service"`, and confirm the fix resolves it against real post-fix traffic (same validation standard as GITIN-1905 — not just source diff).

Jira: `https://smartit-ar.atlassian.net/browse/GITIN-1908` (per user; parent not specified).
