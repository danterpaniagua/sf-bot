# Investigation — 20260805_waf_services_cert_automation_feasibility

**Status:** in progress

## Context
Follow-on from `GITIN-1786` (`operations/events/20260804_mobileappservice_ssl_cert_renewal/`), which automated Let's Encrypt cert renewal for `MobileAppService` (`SFCG-MOBI-01/02`, plain L4 load balancer, no WAF). This investigation is a **separate scope**: whether the same win-acme-based approach can be extended to the services sitting behind Application Gateway `WAF_APPs`, which have a fundamentally different TLS topology.

## Confirmed facts
- **Correction (2026-08-06):** `GITIN-1768` is the epic (SSL certificate renewal automation), not a specific work ticket. The three services in this investigation each have their own subtask: `GITIN-1769` (ClubSite PY), `GITIN-1770` (ClubSite AR), `GITIN-1771` (WebSite). This file remains the shared technical context (`WAF_APPs` topology, Key Vault finding, cert sprawl) — each subtask has or will have its own event/ticket for that hostname's specific work.
- Subscription: Smart IT - Grido (`0190fa7d-4ccf-4e3d-beb1-323b5780bfc8`), resource group `DefaultGroup01`.
- Application Gateway `WAF_APPs` (WAF_v2 tier) fronts at least three hostnames (per `loyalty-azure-waf` skill, confirmed 2026-07-21, needs re-verification before trusting):

  | Listener | Host | Frontend port | Backend pool | Servers |
  |---|---|---|---|---|
  | `Listener_ClubSite_HTTPS` | `www.clubgrido.com.ar` | 443 | `Back_ClubSite` | `192.168.50.121`, `.122` |
  | `Listener_ClubSite_HTTPS_PY` | `www.clubgrido.com.py` | 443 | `Back_ClubSite_PY` | `192.168.50.121`, `.122` (same servers) |
  | `Listener_WebSite_HTTPS` | `gestion.clubgrido.com.ar` | 4430 | `Back_WebSite` | `192.168.50.131` (single server, no redundancy) |

- **Key topology difference from MobileAppService:** a WAF must decrypt traffic to inspect it, so TLS terminates **at the Application Gateway**, not per-backend-VM. This means one cert per listener (3 total, or fewer if consolidated via SANs), not one per VM — potentially simpler to automate than the MobileAppService per-VM pattern, *if* the cert is Key Vault-referenced (Application Gateway v2 auto-picks up new Key Vault secret versions with no redeploy).
- `www.clubgrido.com.ar` and `gestion.clubgrido.com.ar` are subdomains of `clubgrido.com.ar`, same GoDaddy-managed zone already confirmed **API-access-denied** for Domains API (`GITIN-1786` finding, 2026-08-04) — the NS-delegation-to-Azure-DNS workaround from that ticket should carry over directly for these two.
- `www.clubgrido.com.py` is a different TLD/registrar, not yet confirmed — DNS provider unknown.
- **Key Vault question resolved (2026-08-05): none of it.** `az network application-gateway show` → `.sslCertificates[]` shows **9 certificate objects, all `keyVaultSecretId: null` / `hasDirectData: true`** — every cert on `WAF_APPs` is a directly-uploaded PFX, no Key Vault integration anywhere. No auto-pickup mechanism exists; extending automation here needs either a one-time migration to Key Vault-referenced listeners (then renewals become a secret-version push, gateway auto-picks up within ~4h) or a scripted direct PFX re-upload per renewal (touches live gateway config every cycle, needs an Azure credential on whatever host runs win-acme).
- **Secondary finding — certificate sprawl, now resolved with certainty (2026-08-06).** Listener→cert mapping confirmed via `az network application-gateway show` → `.httpListeners[].sslCertificate`: the 3 actually-live certs are `clubgrido.2023.2024` (`Listener_ClubSite_HTTPS`, AR), `www.clubgrido.com.py_2026_v2` (`Listener_ClubSite_HTTPS_PY`), `website_2024` (`Listener_WebSite_HTTPS`). **Correction:** `clubgrido.2023.2024` was initially guessed as an orphan candidate by name pattern alone — it's actually live, name pattern was not a reliable signal. The other 6 objects (`WebSite_PK`, `clubsite_pk`, `www.com.py_pk`, `website_2023`, `clubgrido.py_2024`, `clubgrido.com.py2026`) are confirmed orphaned — not referenced by any listener.
- **HTTP-01 ruled out for AR and PY (2026-08-06).** Both hostnames have an HTTP (port 80) listener (`Listener_ClubSite_HTTP_AR`/`_PY`), but their routing rules have `redirectConfig` set and `backendPool: null` — pure HTTP→HTTPS redirects, no real backend. An ACME HTTP-01 challenge would be redirected to HTTPS before reaching anything that could serve it. DNS-01 remains the only viable validation method for both — see per-ticket investigations (`GITIN-1770`/`operations/events/20260806_automatizar_clubsite_ar/`, `GITIN-1769`/`operations/events/20260806_automatizar_clubsite_py/` — the latter additionally blocked on DNS access).

## Ruled out
- Reusing MobileAppService's per-VM win-acme + IIS-binding pattern as-is — doesn't apply here, since the cert lives on the gateway, not the backend VMs.

## Open questions / next steps
- **Listener → certificate mapping** — which of the 9 cert objects are actually attached to `Listener_ClubSite_HTTPS`, `Listener_ClubSite_HTTPS_PY`, `Listener_WebSite_HTTPS` right now:
  ```bash
  az network application-gateway show --name WAF_APPs --resource-group DefaultGroup01 \
    --subscription 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8 -o json \
    | jq '.httpListeners[] | {name, hostName, sslCertificate: .sslCertificate.id}'
  ```
- **DNS provider for `clubgrido.com.py`** — determines whether the GoDaddy-blocked / Azure-DNS-delegation workaround applies directly or needs a different path:
  ```bash
  dig NS clubgrido.com.py
  ```
