#!/usr/bin/env bash
# Event: 20261007_gitin1715-keyvault-aws-ohio-stg

# === TERRAFORM (a ejecutar por el usuario; salidas en data/) ===
# C1 — aws sts get-caller-identity → data/aws-caller-identity.txt
# C2 — terraform init + validate en /home/dpaniagua/Documentos/git/sf-devops/infrestructure/smartpedidos → data/tf-validate.txt
# C3 — terraform plan → data/tf-plan.txt
# ⚠️ C4 — terraform apply (modifica AWS)

# === COMANDOS POSTERIORES (2026-10-08; salidas en data/, comandos entregados como bloques en la sesion) ===
# C5 — terraform state list → data/tf-state-list.txt
# C6 — terraform plan (alcance Platform) → data/tf-plan-2.txt, tf-plan-3.txt
# ⚠️ C7 — terraform state mv x7 (cambia solo el state local) → data/tf-state-mv.txt
# ⚠️ C8 — terraform apply -auto-approve (3 add, 7 change, 13 destroy) → data/tf-apply.txt (cancelado), data/tf-apply-2.txt
# C9 — terraform show del plan guardado (refactor por ambiente) → data/tf-plan-4.txt
# ⚠️ C10 — terraform apply tfplan.plan (8 add tst) → data/tf-apply-3.txt
# ⚠️ C11 — scripts/load_secrets.sh ENV=tst (dry run y APPLY=1) → data/tst-loader-dry-run.txt, data/tst-loader-apply.txt
