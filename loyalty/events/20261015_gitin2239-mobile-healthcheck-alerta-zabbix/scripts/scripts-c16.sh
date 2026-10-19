#!/usr/bin/env bash
# Event: 20261015_gitin2239-mobile-healthcheck-alerta-zabbix (GITIN-2239)
# C16 - Azure CLI (suscripcion Smart IT - Grido, 0190fa7d-4ccf-4e3d-beb1-323b5780bfc8). Decision del usuario (2026-10-16): "webs02 -> 01": dejar en SFCG-WEBS-01 el mismo healthcheck.ashx que tienen SFCG-WEBS-02/03.
#      Efecto (ya conversado): WEBS-01 pasa de la version de enero de 2026 (comprueba base de datos y Redis, siempre responde 200) a la de noviembre de 2025 (mide CPU/memoria y responde 400 por encima del 80 %).
#      Copia EXACTA por bytes: 1) lee en WEBS-02 el archivo (solo lectura) y lo trae como base64; comprueba en local que su MD5 es 93AB20070B9D825FBDD421854FE82352 (el medido en C15);
#      2) en WEBS-01: comprueba que el archivo actual sigue siendo el de C15 (MD5 C4AF003536E75FF5F8C9895F9B7C00A5; si cambio, ABORTA), lo respalda FUERA de la carpeta web (C:\SmartFran\backup\), escribe los bytes sobre el archivo
#      existente (conserva sus permisos) y comprueba que el MD5 final es el esperado. No toca healthcheckv2.ashx ni ningun otro archivo, ni reinicia IIS (ASP.NET recompila el handler al detectar el cambio).
#      Modos: dry (por defecto, SOLO LECTURA: lista las VMs y el plan) | apply (CAMBIA ESTADO en WEBS-01) | rollback <carpeta c16-run-...> (CAMBIA ESTADO en WEBS-01: restaura el respaldo)
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
MODE="${1:-dry}"; SNAP="${2:-}"
SUB="0190fa7d-4ccf-4e3d-beb1-323b5780bfc8"
DIR="/home/dpaniagua/Documentos/git/bots/loyalty/events/20261015_gitin2239-mobile-healthcheck-alerta-zabbix"
SRC_MD5="93AB20070B9D825FBDD421854FE82352"; DST_OLD_MD5="C4AF003536E75FF5F8C9895F9B7C00A5"
SRC_VM="SFCG-WEBS-02"; DST_VM="SFCG-WEBS-01"; RG="DEFAULTGROUP01"
FILE='C:\SmartFran\SmartLoyalty.WebService\healthcheck.ashx'
rc() { az vm run-command invoke --subscription "$SUB" -g "$RG" -n "$1" --command-id RunPowerShellScript --scripts @"$2" -o json | jq -r '.value[]|.message'; }
if [ "$MODE" = "rollback" ]; then
  [ -f "$SNAP/backup-path.txt" ] || { echo "uso: $0 rollback <carpeta c16-run-...> (falta backup-path.txt)"; exit 1; }
  BAK=$(cat "$SNAP/backup-path.txt")
  cat > "$SNAP/restore.ps1" <<EOF
\$ErrorActionPreference='Stop'
"HOST: \$env:COMPUTERNAME"
\$md5=[Security.Cryptography.MD5]::Create(); function H(\$b){(\$md5.ComputeHash(\$b)|ForEach-Object{\$_.ToString('X2')}) -join ''}
\$bak='$BAK'; \$f='$FILE'
if(-not (Test-Path -LiteralPath \$bak)){ "ABORTA: no existe el respaldo \$bak"; return }
"ANTES MD5=" + (H([IO.File]::ReadAllBytes(\$f)))
[IO.File]::WriteAllBytes(\$f,[IO.File]::ReadAllBytes(\$bak))
"DESPUES MD5=" + (H([IO.File]::ReadAllBytes(\$f)))
EOF
  rc "$DST_VM" "$SNAP/restore.ps1" | tee "$SNAP/restore-out.txt"; echo "rollback ejecutado (comprobar que DESPUES MD5 = $DST_OLD_MD5)"; exit 0
fi
TS=$(date -u +%Y%m%dT%H%M%SZ); RUN="$DIR/data/c16-run-$TS"; mkdir -p "$RUN"
echo "run $TS | $SRC_VM -> $DST_VM | $FILE"
for v in "$SRC_VM" "$DST_VM"; do echo "$v | $RG | $(az vm get-instance-view --subscription "$SUB" -g "$RG" -n "$v" --query "instanceView.statuses[?starts_with(code,'PowerState')].displayStatus | [0]" -o tsv)"; done
echo "plan: leer el archivo de $SRC_VM (MD5 esperado $SRC_MD5), comprobar que el de $DST_VM sigue con MD5 $DST_OLD_MD5, respaldarlo en C:\\SmartFran\\backup\\, escribir los bytes y comprobar el MD5 final"
if [ "$MODE" != "apply" ]; then echo "DRY: no se ejecuto nada en las VMs. Para aplicar: $0 apply"; exit 0; fi
# 1) leer en WEBS-02 (solo lectura)
cat > "$RUN/read.ps1" <<EOF
\$f='$FILE'
"HOST: \$env:COMPUTERNAME"
\$b=[IO.File]::ReadAllBytes(\$f)
\$md5=[Security.Cryptography.MD5]::Create()
"MD5=" + ((\$md5.ComputeHash(\$b)|ForEach-Object{\$_.ToString('X2')}) -join '')
"BYTES=" + \$b.Length
"B64=" + [Convert]::ToBase64String(\$b)
EOF
rc "$SRC_VM" "$RUN/read.ps1" > "$RUN/read-out.txt"
B64=$(grep '^B64=' "$RUN/read-out.txt" | head -1 | tr -d '\r' | cut -d= -f2-)
[ -n "$B64" ] || { echo "ABORTA: no se obtuvo el contenido de $SRC_VM"; exit 1; }
LOCAL_MD5=$(printf '%s' "$B64" | base64 -d | md5sum | cut -d' ' -f1 | tr a-f A-F)
echo "MD5 de lo leido en $SRC_VM (calculado en local): $LOCAL_MD5 | bytes: $(printf '%s' "$B64" | base64 -d | wc -c)"
[ "$LOCAL_MD5" = "$SRC_MD5" ] || { echo "ABORTA: el MD5 no es el esperado ($SRC_MD5); no se toca $DST_VM"; exit 1; }
# 2) respaldar y escribir en WEBS-01
BAK="C:\\SmartFran\\backup\\healthcheck.ashx.$DST_VM.$TS"
printf '%s' "$BAK" > "$RUN/backup-path.txt"
cat > "$RUN/write.ps1" <<EOF
\$ErrorActionPreference='Stop'
"HOST: \$env:COMPUTERNAME"
\$md5=[Security.Cryptography.MD5]::Create(); function H(\$b){(\$md5.ComputeHash(\$b)|ForEach-Object{\$_.ToString('X2')}) -join ''}
\$f='$FILE'; \$bak='$BAK'
\$cur=H([IO.File]::ReadAllBytes(\$f)); "ANTES MD5=\$cur"
if(\$cur -ne '$DST_OLD_MD5'){ "ABORTA: el archivo actual no es el esperado (cambio desde C15); no se toca nada"; return }
\$new=[Convert]::FromBase64String('$B64')
if((H \$new) -ne '$SRC_MD5'){ "ABORTA: el contenido recibido no coincide; no se toca nada"; return }
New-Item -ItemType Directory -Force -Path (Split-Path \$bak) | Out-Null
Copy-Item -LiteralPath \$f -Destination \$bak
"respaldo: \$bak MD5=" + (H([IO.File]::ReadAllBytes(\$bak)))
[IO.File]::WriteAllBytes(\$f,\$new)
\$after=H([IO.File]::ReadAllBytes(\$f)); "DESPUES MD5=\$after"
if(\$after -eq '$SRC_MD5'){ "OK: copia exacta" } else { "ERROR: el MD5 final no coincide; restaurar con el rollback" }
EOF
rc "$DST_VM" "$RUN/write.ps1" | tee "$RUN/write-out.txt"
echo "aplicado. Rollback: $0 rollback $RUN"
