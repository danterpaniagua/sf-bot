#!/usr/bin/env bash
# Event: 20260825_wholesale-service-infra-proposal
# Commands are grouped by phase: Investigation / Audit / Remediation
# ⚠️ ACTION commands are clearly marked

# === INVESTIGATION ===

# C1 — Confirmar disponibilidad de pandoc/mermaid-cli para exportar dev-guide.md a PDF/LaTeX con diagramas renderizados
which pandoc mmdc
pandoc --version | head -1
mmdc --version
