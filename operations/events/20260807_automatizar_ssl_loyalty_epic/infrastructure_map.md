# Mapa de infraestructura — Automatización SSL (GITIN-1768)

Topología técnica real de los dos tramos ya implementados (`GITIN-1774` MobileAppService, `GITIN-1770` ClubSite AR) — complementa a `epic_map.md` (que muestra estado por ticket, no la infraestructura).

```mermaid
flowchart TB
    subgraph GoDaddy["GoDaddy DNS — clubgrido.com.ar"]
        NS1["Registro NS:<br/>_acme-challenge.mobileservice"]
        NS2["Registro NS:<br/>_acme-challenge.www"]
    end

    subgraph AzureDNS["Azure DNS — zonas delegadas"]
        Z1["_acme-challenge.mobileservice.<br/>clubgrido.com.ar"]
        Z2["_acme-challenge.www.<br/>clubgrido.com.ar"]
    end

    NS1 -.delega.-> Z1
    NS2 -.delega.-> Z2

    subgraph Identity["Identidad y permisos"]
        SP["Service Principal<br/>winacme-mobileservice-dns<br/>(appId 3cca7e2a...)"]
        MI["Managed Identity<br/>waf-apps-kv-identity"]
    end

    SP -->|DNS Zone Contributor| Z1
    SP -->|DNS Zone Contributor| Z2
    SP -->|Key Vault Certificates Officer| KV
    MI -->|Key Vault Secrets User| KV

    LE["Let's Encrypt<br/>(ACME CA, validación DNS-01)"]

    subgraph MobiHosts["SFCG-MOBI-01 / 02 (win-acme)"]
        M1["SFCG-MOBI-01<br/>cert propio, clave propia"]
        M2["SFCG-MOBI-02<br/>cert propio, clave propia"]
    end

    subgraph ClubHosts["SFCG-CLUB-01 / 02 (win-acme)"]
        C1["SFCG-CLUB-01<br/>cert público → Key Vault<br/>+ cert backend → IIS local"]
        C2["SFCG-CLUB-02<br/>cert backend → IIS local<br/>(independiente, clave propia)"]
    end

    Z1 -.valida DNS-01.-> M1
    Z1 -.valida DNS-01.-> M2
    Z2 -.valida DNS-01.-> C1
    Z2 -.valida DNS-01.-> C2
    LE -->|emite certificado| M1
    LE -->|emite certificado| M2
    LE -->|emite certificado| C1
    LE -->|emite certificado| C2

    KV["Key Vault<br/>sfcg-waf-apps-kv<br/>(secret sin versión)"]
    C1 -->|store| KV

    subgraph Gateway["Application Gateway WAF_APPs"]
        Listener["Listener_ClubSite_HTTPS<br/>(TLS público)"]
        Backend["Backend_ClubSite HTTP settings<br/>trustedRootCertificates:<br/>clubsite_CA + letsencrypt-isrg-root-x1"]
    end

    KV -->|cert sin versión, auto-pickup ~4h| Listener
    MI -.identidad de lectura.-> Listener

    subgraph BackPool["Back_ClubSite (backend pool)"]
        B1["SFCG-CLUB-01<br/>192.168.50.121"]
        B2["SFCG-CLUB-02<br/>192.168.50.122"]
    end

    C1 -.instala cert local.-> B1
    C2 -.instala cert local.-> B2

    Listener --> Backend
    Backend -->|re-encripta, valida cadena| B1
    Backend -->|re-encripta, valida cadena| B2

    subgraph MobiLB["SFCG-MOBI-LB (L4, sin WAF)"]
        LB["TCP passthrough :8043"]
    end

    M1 -.instala cert local.-> LB
    M2 -.instala cert local.-> LB

    Internet(["Internet"])
    Internet -->|HTTPS 443| Listener
    Internet -->|TCP 8043| LB
    LB --> M1
    LB --> M2

    classDef done fill:#c8e6c9,stroke:#2e7d32,color:#1b5e20;
    class M1,M2,C1,C2,KV,Listener,Backend,B1,B2,LB done;
```

**Notas:**
- `SFCG-MOBI-01`/`02` no pasan por re-encriptación de gateway (LB de capa 4) — cada VM sirve su propio certificado directo al cliente.
- `SFCG-CLUB-01`/`02` sí tienen dos TLS independientes: público (Cliente↔Gateway, vía Key Vault) y backend (Gateway↔Backend, cert local en cada VM) — ver hallazgo crítico en `operations/events/20260806_automatizar_clubsite_ar/investigation.md`.
- `letsencrypt-isrg-root-x1` es el único certificado de cadena cargado en el gateway — los intermedios (`YR1`/`YR2`) los sirve cada VM backend directamente, no van en `trustedRootCertificates`.

**Última actualización:** 2026-08-07.
