# Investigation — 20260806_automatizar_clubsite_py

**Status:** blocked — paused, see "Blocker" below

## Blocker (2026-08-06)
**No administrative access to the `clubgrido.com.py` domain.** This directly rules out the DNS-01 validation mechanism via NS delegation (the one that worked for `GITIN-1774`) — it's not possible to add the delegation NS record without DNS panel access, regardless of which provider manages it. Didn't investigate the actual DNS provider further since access is the real blocker, not the specific provider.

**HTTP-01 alternative ruled out (2026-08-06):** an HTTP listener exists for this host (`Listener_ClubSite_HTTP_PY`), but its rule (`Rule_ClubSite_HTTP_PY`) has `redirectConfig` set and `backendPool: null` — a pure HTTP→HTTPS redirect, not routed to any real backend. An HTTP-01 validation request would be redirected to HTTPS before reaching anything that could serve the challenge file. Without a path-based routing rule (`urlPathMaps`), which doesn't exist on this gateway today, HTTP-01 isn't viable this way either.

**Status: no viable automation path identified.** DNS-01 blocked by lack of domain access; HTTP-01 blocked by the backend-less redirect. Paused in favor of `GITIN-1770` (ClubSite AR), which doesn't have the DNS access blocker. Possible future paths, not explored: (a) get DNS access to `clubgrido.com.py` from whoever administers it, (b) add a path-based routing rule on the gateway that sends specifically `/.well-known/acme-challenge/*` to a real backend without affecting the rest of the traffic (redirect would stay for everything else).

## Context
Jira ticket: `GITIN-1769` — Automate ClubSite PY (`www.clubgrido.com.py`). Subtask of the epic `GITIN-1768` — SSL certificate renewal automation. Shares technical context with `GITIN-1770`/`1771` (ClubSite AR, WebSite — same Application Gateway/WAF), see `operations/events/20260805_waf_services_cert_automation_feasibility/` (not re-derived here). Reuses the DNS-01 validation mechanism via Azure DNS already implemented and verified in `GITIN-1774` (MobileAppService) — see `operations/events/20260806_acme_challenge_migration/`.

## Confirmed facts (carried over, not re-derived)
- Listener: `Listener_ClubSite_HTTPS_PY`, host `www.clubgrido.com.py`, frontend port 443, backend pool `Back_ClubSite_PY` (servers `192.168.50.121`/`.122`, shared with ClubSite AR) — not re-verified since 2026-07-21, confirm before assuming still current.
- **None of the 9 current certificates on `WAF_APPs` are integrated with Azure Key Vault** — all are directly-uploaded PFX. This is a blocker separate from the DNS validation mechanism: even with DNS-01 working, there's no way for the gateway to automatically pick up a renewed certificate without either (a) migrating the listener to a Key Vault reference, or (b) scripting a direct PFX upload to the gateway on every renewal.
- The DNS-01 validation mechanism via Azure DNS (delegated zone + Service Principal + win-acme plugin) is already proven end-to-end in `GITIN-1774` — a direct candidate to reuse here for domain proof, independent of whichever certificate delivery mechanism gets chosen.
- No dedicated VM exists for ClubSite PY the way `SFCG-MOBI-01/02` did for MobileAppService — win-acme would need to run from some host with permissions on the Key Vault/gateway, which one still to be defined.

## Ruled out
- Reusing `GITIN-1774`'s same Service Principal without evaluating — that SP has `DNS Zone Contributor` scoped specifically to the `_acme-challenge.mobileservice.clubgrido.com.ar` zone; this zone (`_acme-challenge.www.clubgrido.com.py` or whatever gets decided) needs, at minimum, a new role assignment on the new zone — reusing the same scope isn't enough.

## Open questions / next steps
- **DNS provider for `clubgrido.com.py`** — still unconfirmed, blocks knowing whether the same NS-delegation trick applies directly or a different path needs evaluating:
  ```bash
  dig NS clubgrido.com.py
  ```
- **Listener → certificate mapping** — which of the 9 certificate objects on `WAF_APPs` is actually assigned to `Listener_ClubSite_HTTPS_PY` today:
  ```bash
  az network application-gateway show --name WAF_APPs --resource-group DefaultGroup01 \
    --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json \
    | jq '.httpListeners[] | {name, hostName, sslCertificate: .sslCertificate.id}'
  ```
- **Certificate delivery decision:** migrate to Key Vault (recommended — enables real renewal without re-touching the gateway every time) vs. scripting a direct PFX upload. Affects the whole downstream design.
- **Where win-acme runs from for this certificate** — no dedicated VM like MobileAppService had.
- None of this has been executed yet — no Azure resources created for this specific ticket.
