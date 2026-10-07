#!/usr/bin/env bash
# GITIN-2129: what can the AWS credentials hardcoded in the concentrador's api/src/config/env/staging.js do?
# Usage: bash scripts_staging_credential_permissions.sh <admin-aws-cli-profile>
#
# Read-only against AWS (STS identity + IAM get/list/generate-last-accessed). Writes only masked JSON under data/.
# - The credential values are read from staging.js into shell variables and are NEVER printed or written to a file.
#   Access key IDs in outputs are masked (AKIA************XXXX). Secrets never appear in any API response.
# - Exactly one call uses the hardcoded credential itself: `sts get-caller-identity` (needed to learn which IAM principal it is).
#   That call is recorded in CloudTrail as that principal. Everything else uses the admin profile you pass in.
# - staging.js lines read: AWS_ID / AWS_SECRET pairs at lines 52/53 (block 1) and 59/60 (block 2) on the `ope` branch (tree == develop).
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260930_gitin2129-credentials-in-code/data
F=/home/dpaniagua/Documentos/git/bots/smartpedidos/repo/dev-src-smartPedidos-concentradorService/api/src/config/env/staging.js
ADMIN="${1:?usage: $0 <admin-aws-cli-profile>}"
REGION=us-east-1
mkdir -p "$E"

mask() { sed -E 's/(AKIA|ASIA)[A-Z0-9]{12}([A-Z0-9]{4})/\1************\2/g'; }
val()  { sed -n "${1}p" "$F" | grep -oE "['\"][A-Za-z0-9+/=_-]{16,}['\"]" | head -1 | tr -d "'\""; }
adm()  { aws --profile "$ADMIN" --region "$REGION" "$@"; }

# Key names at the expected lines (no values) — sanity check that line numbers still match
for n in 52 53 59 60; do printf '%s: %s\n' "$n" "$(sed -n "${n}p" "$F" | grep -oE '^[[:space:]]*[A-Za-z_]+' | tr -d ' ')"; done > "$E/staging_cred_lines_check.txt"
grep -q 'AWS_ID'     <(sed -n '52p;59p' "$F") || { echo "line layout changed (AWS_ID) — abort"; exit 1; }
grep -q 'AWS_SECRET' <(sed -n '53p;60p' "$F") || { echo "line layout changed (AWS_SECRET) — abort"; exit 1; }

for N in 1 2; do
  if [ "$N" = 1 ]; then IDL=52; SL=53; else IDL=59; SL=60; fi
  P="$E/staging_cred${N}"
  KID=$(val "$IDL"); KSEC=$(val "$SL")
  [[ "$KID" =~ ^(AKIA|ASIA)[A-Z0-9]{16}$ ]] || { echo "block $N: key id not in expected format — skipped" | tee "${P}_skipped.txt"; continue; }
  [ -n "$KSEC" ] || { echo "block $N: secret not found — skipped" | tee "${P}_skipped.txt"; continue; }

  # 1) Which principal is it? (the only call made with the hardcoded credential)
  ( export AWS_ACCESS_KEY_ID="$KID" AWS_SECRET_ACCESS_KEY="$KSEC"; unset AWS_PROFILE AWS_SESSION_TOKEN
    aws --region "$REGION" sts get-caller-identity --output json ) 2>&1 | mask > "${P}_sts_identity.json" || true
  ARN=$(jq -r '.Arn // empty' "${P}_sts_identity.json" 2>/dev/null || true)
  if [ -z "$ARN" ]; then echo "block $N: sts failed (see ${P}_sts_identity.json) — credential may be invalid/inactive"; unset KSEC; continue; fi
  unset KSEC
  USERNAME="${ARN##*/}"
  echo "block $N principal: $(echo "$ARN" | mask)"

  # 2) Everything else with the admin profile (read-only)
  adm iam get-user --user-name "$USERNAME" --output json 2>&1 | mask > "${P}_iam_get_user.json" || true
  adm iam list-access-keys --user-name "$USERNAME" --output json 2>&1 | mask > "${P}_iam_access_keys.json" || true
  adm iam get-access-key-last-used --access-key-id "$KID" --output json 2>&1 | mask > "${P}_iam_key_last_used.json" || true
  adm iam list-attached-user-policies --user-name "$USERNAME" --output json 2>&1 | mask > "${P}_iam_attached_user_policies.json" || true
  adm iam list-user-policies --user-name "$USERNAME" --output json 2>&1 | mask > "${P}_iam_inline_user_policies.json" || true
  adm iam list-groups-for-user --user-name "$USERNAME" --output json 2>&1 | mask > "${P}_iam_groups.json" || true

  # Policy documents: attached (user + groups) and inline
  for PA in $(jq -r '.AttachedPolicies[]?.PolicyArn' "${P}_iam_attached_user_policies.json" 2>/dev/null); do
    V=$(adm iam get-policy --policy-arn "$PA" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || true)
    [ -n "$V" ] && adm iam get-policy-version --policy-arn "$PA" --version-id "$V" --output json 2>&1 | mask > "${P}_policy_$(basename "$PA").json" || true
  done
  for PN in $(jq -r '.PolicyNames[]?' "${P}_iam_inline_user_policies.json" 2>/dev/null); do
    adm iam get-user-policy --user-name "$USERNAME" --policy-name "$PN" --output json 2>&1 | mask > "${P}_inline_${PN}.json" || true
  done
  for G in $(jq -r '.Groups[]?.GroupName' "${P}_iam_groups.json" 2>/dev/null); do
    adm iam list-attached-group-policies --group-name "$G" --output json 2>&1 | mask > "${P}_group_${G}_attached.json" || true
    adm iam list-group-policies --group-name "$G" --output json 2>&1 | mask > "${P}_group_${G}_inline.json" || true
    for PA in $(jq -r '.AttachedPolicies[]?.PolicyArn' "${P}_group_${G}_attached.json" 2>/dev/null); do
      V=$(adm iam get-policy --policy-arn "$PA" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || true)
      [ -n "$V" ] && adm iam get-policy-version --policy-arn "$PA" --version-id "$V" --output json 2>&1 | mask > "${P}_policy_$(basename "$PA").json" || true
    done
  done

  # 3) Which services has this principal actually used (IAM service last accessed, ~400-day window)
  JOB=$(adm iam generate-service-last-accessed-details --arn "$ARN" --query JobId --output text 2>/dev/null || true)
  if [ -n "$JOB" ]; then
    for i in 1 2 3 4 5 6; do
      S=$(adm iam get-service-last-accessed-details --job-id "$JOB" --query JobStatus --output text 2>/dev/null || true)
      [ "$S" = COMPLETED ] && break; sleep 5
    done
    adm iam get-service-last-accessed-details --job-id "$JOB" --output json 2>&1 | mask > "${P}_service_last_accessed.json" || true
  fi
  unset KID
done
echo "done: files in $E (staging_cred1_*, staging_cred2_*)"
