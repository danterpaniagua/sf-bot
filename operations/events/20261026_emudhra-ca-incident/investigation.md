# eMudhra CA key compromise: exposure check (2026-10-26)

Status: open. No Jira ticket yet (folder has no ticket id; rename with `scripts/rename_event_folders.sh` when one exists).

## Context
- Public incident: eight eMudhra intermediate CA keys were recoverable from the public certificates. Reported 2026-10-17; Chrome/Firefox blocked the same day, Apple 10-19, Microsoft 10-20. eMudhra says roots were not affected and announced on 10-22 it is leaving the global TLS business. Root cause analysis was still in progress per its last statement.
- Sources (web search, 2026-10-26): Help Net Security, Cloudflare blog, Google Security blog, eMudhra statement, SecurityWeek.

## Exposure (user-reported, not verified)
- SmartLoyalty: mostly Let's Encrypt, the rest GoDaddy.
- SmartPedidos: AWS default certificates.
- SmartCloud: Azure default certificates.
- No real chain was inspected for any endpoint. No third-party (customer or provider) certificate was inspected.

## Related
- The Node.js security release of 2026-10-21 also updates the CA certificates bundled in Node for this incident (listed under dependency updates in the Node advisory). Node exposure of SmartPedidos: `operations/events/20261026_gitin2310-nodejs-security-release-oct2026/`. That update concerns the trust store inside Node, not our own certificates.

## Open items
- Collect issuer and root of every public endpoint per platform (`openssl s_client`, read-only), saved under `data/`.
- Check whether any third-party integration uses an eMudhra certificate.
- One source says Sectigo revoked certificates in this incident; detail not found. Check whether any of our domains has a Sectigo certificate.
- Operational rule proposed in the email: on a customer/provider TLS error, check the certificate issuer first.

## Deliverable
- `email_ops.md` (Spanish): drafted, not sent.
