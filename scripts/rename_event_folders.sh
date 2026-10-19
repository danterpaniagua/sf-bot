#!/usr/bin/env bash
# Renombra una carpeta de evento para incluir el ticket (regla del usuario, 2026-10-16: "rename folder when i give ticket").
# Uso:  rename_event_folders.sh dry|apply <proyecto> <nombre-viejo> <ticket>
#       rename_event_folders.sh rollback <manifiesto>
#   <proyecto>: loyalty | smartpedidos | operations | cloud
#   <nombre-viejo>: YYYYMMDD_descripcion        <ticket>: gitinXXXX (minusculas)
#   El nombre nuevo es YYYYMMDD_<ticket>-descripcion.
# Pasos de "apply": (1) mv de la carpeta; (2) reemplaza el nombre viejo por el nuevo en los archivos de texto de loyalty/events, smartpedidos/events, operations/events y cloud/events
# EXCEPTO en las carpetas data/ (son evidencia: no se reescriben); (3) crea un enlace simbolico con el nombre viejo apuntando al nuevo (para que sigan funcionando los comandos de rollback de los logs de data/,
# que llevan la ruta vieja); el usuario puede quitarlo despues con rm (es un enlace: no borra datos).
# Modos: dry (SOLO LECTURA) | apply (CAMBIA ESTADO) | rollback <manifiesto> (CAMBIA ESTADO). No toca git.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
ROOT="/home/dpaniagua/Documentos/git/bots"
MODE="${1:-}"
SCOPE=("$ROOT/loyalty/events" "$ROOT/smartpedidos/events" "$ROOT/operations/events" "$ROOT/cloud/events")
TS=$(date -u +%Y%m%dT%H%M%SZ)
hits() { grep -rIl --exclude-dir=data --exclude-dir=.git --exclude-dir=node_modules -F -- "$1" "${SCOPE[@]}" 2>/dev/null || true; }

if [ "$MODE" = "rollback" ]; then
  MAN="${2:-}"; [ -f "$MAN" ] || { echo "uso: $0 rollback <manifiesto rename-events-manifest-...tsv>"; exit 1; }
  # manifiesto: "PAIR<TAB>base<TAB>old<TAB>new" y "FILE<TAB>ruta<TAB>old<TAB>new"
  while IFS=$'\t' read -r kind a b c; do
    [ "$kind" = "FILE" ] || continue
    sed -i "s#${c}#${b}#g" "$a"; echo "revertido $a"
  done < "$MAN"
  while IFS=$'\t' read -r kind base old new; do
    [ "$kind" = "PAIR" ] || continue
    [ -L "$base/$old" ] && rm "$base/$old" && echo "enlace $old quitado"
    [ -d "$base/$new" ] && mv "$base/$new" "$base/$old" && echo "carpeta $new -> $old"
  done < "$MAN"
  echo "rollback hecho"; exit 0
fi

case "$MODE" in dry|apply) ;; *) echo "uso: $0 dry|apply <proyecto> <nombre-viejo> <ticket> | rollback <manifiesto>"; exit 1;; esac
PROJ="${2:-}"; OLD="${3:-}"; TICKET="${4:-}"
case "$PROJ" in loyalty|smartpedidos|operations|cloud) ;; *) echo "proyecto invalido: '$PROJ'"; exit 1;; esac
[[ "$OLD" =~ ^[0-9]{8}_[a-z0-9_-]+$ ]] || { echo "nombre viejo invalido: '$OLD' (esperado YYYYMMDD_descripcion)"; exit 1; }
[[ "$TICKET" =~ ^gitin[0-9]+$ ]] || { echo "ticket invalido: '$TICKET' (esperado gitinXXXX en minusculas)"; exit 1; }
[[ "$OLD" != *"_${TICKET}-"* ]] || { echo "GUARDA: el nombre ya contiene el ticket"; exit 1; }
NEW="${OLD%%_*}_${TICKET}-${OLD#*_}"
BASE="$ROOT/$PROJ/events"
[ -d "$BASE/$OLD" ] && [ ! -L "$BASE/$OLD" ] || { echo "GUARDA: $BASE/$OLD no existe como carpeta real"; exit 1; }
[ ! -e "$BASE/$NEW" ] || { echo "GUARDA: $BASE/$NEW ya existe"; exit 1; }
echo "modo=$MODE | $TS"
echo "== $PROJ: $OLD -> $NEW"
echo "   archivos de texto (fuera de data/) que se reescriben: $(hits "$OLD" | wc -l)"
hits "$OLD" | sed "s#^$ROOT/#     #"
echo "   archivos en data/ con el nombre viejo (NO se tocan): $(grep -rIl -F -- "$OLD" "${SCOPE[@]}" 2>/dev/null | grep -c '/data/' || true)"
if [ "$MODE" != "apply" ]; then echo "DRY: no se cambio nada. Para aplicar: $0 apply $PROJ $OLD $TICKET"; exit 0; fi

MANF="$ROOT/scripts/rename-events-manifest-$TS.tsv"; : > "$MANF"
mv "$BASE/$OLD" "$BASE/$NEW"
mapfile -t FILES < <(hits "$OLD")
for f in "${FILES[@]}"; do sed -i "s#${OLD}#${NEW}#g" "$f"; printf 'FILE\t%s\t%s\t%s\n' "$f" "$OLD" "$NEW" >> "$MANF"; done
ln -s "$NEW" "$BASE/$OLD"
printf 'PAIR\t%s\t%s\t%s\n' "$BASE" "$OLD" "$NEW" >> "$MANF"
echo "hecho: $OLD -> $NEW (${#FILES[@]} archivos reescritos, enlace con el nombre viejo)"
echo "== comprobacion: referencias al nombre viejo fuera de data/: $(hits "$OLD" | wc -l); enlace: $(readlink "$BASE/$OLD")"
echo "aplicado. Rollback: $0 rollback $MANF"
