#!/usr/bin/env bash
# Event: 20261017_gitin2248-platform-contenedores-caidos-20261016
# C6 - SOLO LECTURA contra AWS (cuenta 382381053403, us-east-1). Historial de revisiones de la definicion de tarea platform-service-production-task, para ubicar en el tiempo
#      el primer build que incluye el commit b56d403 (2026-10-08 14:42 -03:00; entro a develop por el pull request #135 el 2026-10-09).
#      (1) ECS: revisiones de la familia (mas nuevas primero) con su fecha de registro (hora local -03:00 como la imprime la CLI de AWS), estado e imagen.
#      (2) ECR: fecha de publicacion (imagePushedAt) de cada imagen distinta de esas revisiones. Un tag que se reutiliza (por ejemplo latest) muestra la ultima publicacion, no la de la revision.
#      No se imprime configuracion de contenedores, variables de entorno, secretos ni ARNs de roles: solo revision, fecha, estado e imagen. Salidas en data/c6/.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
R="us-east-1"; FAM="platform-service-production-task"
OUT="/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261017_gitin2248-platform-contenedores-caidos-20261016/data/c6"; mkdir -p "$OUT"
ACCT=$(aws sts get-caller-identity --query Account --output text --region $R)
[ "$ACCT" = "382381053403" ] || { echo "GUARDA: la cuenta no es 382381053403"; exit 1; }
echo "run $(date -u +%FT%TZ) | cuenta $ACCT"

echo "== (1) revisiones de la familia $FAM (mas nuevas primero)"
aws ecs list-task-definitions --region $R --family-prefix "$FAM" --sort DESC --max-items 60 --query 'taskDefinitionArns' --output json > "$OUT/arns.json"
: > "$OUT/taskdefs.tsv"
for arn in $(jq -r --arg f "task-definition/$FAM:" '.[]|select(contains($f))' "$OUT/arns.json"); do
  aws ecs describe-task-definition --region $R --task-definition "$arn" \
    --query 'taskDefinition.{r:revision,t:registeredAt,s:status,i:containerDefinitions[].image}' --output json \
    | jq -r '[.r,(.t|tostring|.[0:19]),.s,(.i|join(","))]|@tsv' >> "$OUT/taskdefs.tsv"
done
echo "revisiones leidas: $(wc -l < "$OUT/taskdefs.tsv")"
echo "-- revision, registrada (hora local -03:00), estado, imagen"
sort -t$'\t' -k1,1nr "$OUT/taskdefs.tsv"

echo; echo "== (2) ECR: fecha de publicacion de cada imagen distinta"
: > "$OUT/ecr-images.tsv"
cut -f4 "$OUT/taskdefs.tsv" | tr ',' '\n' | sort -u | while read -r img; do
  [ -n "$img" ] || continue
  case "$img" in
    *.dkr.ecr.*) ;;
    *) printf '%s\t%s\n' "$img" "no es una imagen de ECR" | tee -a "$OUT/ecr-images.tsv" >/dev/null; continue ;;
  esac
  repo="${img#*/}"; repo="${repo%%[:@]*}"
  if [[ "$img" == *@* ]]; then sel="imageDigest=${img##*@}"; else sel="imageTag=${img##*:}"; fi
  rg=$(echo "$img" | sed -E 's#^[0-9]+\.dkr\.ecr\.([a-z0-9-]+)\..*#\1#')   # el repositorio de ECR puede estar en otra region que el servicio (run del 2026-10-19: us-east-2)
  res=$(aws ecr describe-images --region "$rg" --repository-name "$repo" --image-ids "$sel" --query 'imageDetails[0].imagePushedAt' --output text 2>&1 | head -c 80) || res="no se pudo leer"
  printf '%s\t%s\n' "$img" "$res" >> "$OUT/ecr-images.tsv"
done
cat "$OUT/ecr-images.tsv"
echo listo
