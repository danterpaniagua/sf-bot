#!/usr/bin/env bash
# Event: 20261013_gitin2221-normalizar-http-paths
# Despliegue de NormalizedPath en el Logstash de la VM de Graylog de SmartCloud. CAMBIA ESTADO (archivos en /etc/logstash y reinicio).
# Lo ejecuta el usuario; este archivo no se ejecuta desde Claude.
# Modos:  stage     sube archivos a /tmp, instala la tabla de rutas (archivo nuevo que nadie lee todavia) y prueba el config PARCHEADO
#                   en una copia en /tmp con 'logstash -t'. No toca el config vivo ni reinicia.
#         apply     respalda el config vivo (azure-eventhub-to-graylog.conf.bak-GITIN-2221: NO termina en .conf, pipelines.yml carga conf.d/*.conf),
#                   aplica el patch, prueba el config vivo; si la prueba falla restaura el respaldo y NO reinicia; si pasa, reinicia logstash.
#         test      corre un Logstash APARTE (stdin->solo el filtro nuevo->stdout, heap de 512 MB) con la tabla real y los paths observados; no toca el config vivo ni reinicia.
#         update    segunda pasada (tabla ampliada + regla de estaticos): prueba -t del patch en una copia, instala la tabla nueva, prueba el filtro en un Logstash aparte
#                   contra data/test-expected, y recien entonces parchea el config vivo, prueba y reinicia; si algo falla restaura todo y NO reinicia.
#         fix       tercera pasada: ElapsedMillisecondsOpe para Sales (string -> numero); ElapsedMilliseconds no se toca. Guarda patch --dry-run, -t en una copia, prueba del bloque en un Logstash aparte, y recien entonces aplica y reinicia.
#         rollback-fix deshace 'fix'.   rollback-update  deshace 'update' (config y tabla) y reinicia.   rollback  vuelve al config original de antes de 'apply' y reinicia.
# Guarda: el config vivo debe tener el sha256 visto en C2 (728bb77c...), si no, aborta. Salidas redactadas (sed) antes de guardarse.
set -euo pipefail
trap 'echo "FALLO en linea $LINENO: $BASH_COMMAND" >&2' ERR
MODE="${1:?uso: deploy.sh stage|apply|test|update|fix|rollback-fix|rollback-update|rollback}"
D="/home/dpaniagua/Documentos/git/bots/operations/events/20261013_gitin2221-normalizar-http-paths"
VM() { ssh -p 5689 -i ~/.ssh/sfcloud_monitoreo gadmin@sfcloud-monitoreo.smartfran.com "$1"; }
RED() { sed -E 's/((connection|conn|secret|password|passwd|key|token|sas)[A-Za-z_]*[[:space:]]*[=:>]+[[:space:]]*).*/\1"REDACTED"/I; s/(SharedAccessKey=|AccountKey=)[^"; ]*/\1REDACTED/g'; }
LIVE=/etc/logstash/conf.d/azure-eventhub-to-graylog.conf; BAK=$LIVE.bak-GITIN-2221; TBL=/etc/logstash/normalized-paths.json
EXPECT=728bb77c357293006166f7fdf30be3bd4f9b6495243e63400414c087d91bc56a
LS="/usr/share/logstash/bin/logstash --path.settings /etc/logstash"
guard() { got=$(VM "sudo sha256sum $LIVE" | cut -d' ' -f1); [ "$got" = "$EXPECT" ] || { echo "GUARDA: el config vivo cambio (sha $got); correr C2 de nuevo"; exit 1; }; echo "guarda: el config vivo tiene el sha esperado"; }

case "$MODE" in
stage)
  guard
  VM "mkdir -p /tmp/gitin2221 && chmod 755 /tmp/gitin2221 && sudo install -d -o logstash -g logstash -m 755 /tmp/gitin2221/data"
  VM "cat > /tmp/gitin2221/normalizedpath.patch" < "$D/scripts/logstash/normalizedpath.patch"
  VM "cat > /tmp/gitin2221/normalized-paths.json" < "$D/scripts/logstash/normalized-paths.json"
  VM "sudo install -o root -g logstash -m 640 /tmp/gitin2221/normalized-paths.json $TBL && sudo ls -l $TBL"
  VM "sudo cp $LIVE /tmp/gitin2221/test.conf && sudo chmod 644 /tmp/gitin2221/test.conf && sudo patch /tmp/gitin2221/test.conf < /tmp/gitin2221/normalizedpath.patch"
  echo "== logstash -t sobre la copia parcheada (usuario logstash, data dir aparte)"
  VM "sudo -u logstash $LS --path.data /tmp/gitin2221/data -f /tmp/gitin2221/test.conf -t 2>&1 | tail -15" | RED
  ;;
apply)
  guard
  VM "sudo test -f $TBL" || { echo "GUARDA: falta $TBL; correr stage antes"; exit 1; }
  VM "sudo cp -p $LIVE $BAK && sudo patch $LIVE < /tmp/gitin2221/normalizedpath.patch"
  echo "== logstash -t sobre el config vivo"
  if VM "sudo -u logstash $LS --path.data /tmp/gitin2221/data -f $LIVE -t 2>&1 | tail -8" | RED > "$D/data/.apply-test.tmp" && cat "$D/data/.apply-test.tmp" && grep -q "Configuration OK" "$D/data/.apply-test.tmp"; then
    echo "prueba OK: reiniciando logstash"; VM "sudo systemctl restart logstash"; sleep 45
    echo "estado: $(VM 'systemctl is-active logstash')"
    VM "sudo journalctl -u logstash --since '-2min' --no-pager | grep -i -E 'error|exception|fatal' | cut -c1-220 | head -10" | RED || true
  else
    echo "prueba FALLO: restaurando respaldo, sin reiniciar"; VM "sudo cp -p $BAK $LIVE && sudo sha256sum $LIVE"; exit 1
  fi
  ;;
test)
  VM "mkdir -p /tmp/gitin2221 && sudo install -d -o logstash -g logstash -m 755 /tmp/gitin2221/data-test"
  VM "cat > /tmp/gitin2221/test-pipeline.conf" < "$D/scripts/logstash/test-pipeline.conf"
  VM "cat > /tmp/gitin2221/test-events.jsonl" < "$D/scripts/logstash/test-events.jsonl"
  VM "sudo chmod 644 /tmp/gitin2221/test-pipeline.conf /tmp/gitin2221/test-events.jsonl"
  echo "== logstash aparte: stdin -> filtro NormalizedPath -> stdout"
  VM "sudo -u logstash env LS_JAVA_OPTS='-Xms256m -Xmx512m' $LS --path.data /tmp/gitin2221/data-test -f /tmp/gitin2221/test-pipeline.conf < /tmp/gitin2221/test-events.jsonl 2>&1 | grep -E '^\{|ERROR|FATAL|Exception' | cut -c1-1500"
  ;;
update)
  # Segunda pasada: tabla ampliada (paginas Razor, hubs, framework) + regla de archivos estaticos. Parte del config ya parcheado por 'apply'.
  EXPECT2=d2fe3152354e2af22fa9f0a8f37a1ecba4dc33800107936f18681a093fcce3c3; BAK2=$LIVE.bak-GITIN-2221-update; TBLBAK=$TBL.bak-GITIN-2221
  got=$(VM "sudo sha256sum $LIVE" | cut -d' ' -f1); [ "$got" = "$EXPECT2" ] || { echo "GUARDA: el config vivo no es el de despues de 'apply' (sha $got)"; exit 1; }
  echo "guarda: el config vivo tiene el sha de despues de apply"
  VM "mkdir -p /tmp/gitin2221 && sudo install -d -o logstash -g logstash -m 755 /tmp/gitin2221/data-update"
  VM "cat > /tmp/gitin2221/normalizedpath-update.patch" < "$D/scripts/logstash/normalizedpath-update.patch"
  VM "cat > /tmp/gitin2221/normalized-paths.v2.json" < "$D/scripts/logstash/normalized-paths.json"
  VM "cat > /tmp/gitin2221/test-pipeline.conf" < "$D/scripts/logstash/test-pipeline.conf"
  VM "cat > /tmp/gitin2221/test-events.jsonl" < "$D/scripts/logstash/test-events.jsonl"
  VM "sudo chmod 644 /tmp/gitin2221/test-pipeline.conf /tmp/gitin2221/test-events.jsonl /tmp/gitin2221/normalizedpath-update.patch"
  echo "== 1) el patch sobre una copia del config vivo y logstash -t"
  VM "sudo cp $LIVE /tmp/gitin2221/update-test.conf && sudo chmod 644 /tmp/gitin2221/update-test.conf && sudo patch /tmp/gitin2221/update-test.conf < /tmp/gitin2221/normalizedpath-update.patch"
  VM "sudo -u logstash $LS --path.data /tmp/gitin2221/data-update -f /tmp/gitin2221/update-test.conf -t 2>&1 | tail -6" | RED > "$D/data/.update-t.tmp"; cat "$D/data/.update-t.tmp"
  grep -q "Configuration OK" "$D/data/.update-t.tmp" || { echo "prueba -t FALLO: no se cambio nada"; exit 1; }
  echo "== 2) tabla nueva (respaldo de la anterior) y prueba del filtro en un Logstash aparte"
  VM "sudo cp -p $TBL $TBLBAK && sudo install -o root -g logstash -m 640 /tmp/gitin2221/normalized-paths.v2.json $TBL && sudo ls -l $TBL $TBLBAK"
  VM "sudo -u logstash env LS_JAVA_OPTS='-Xms256m -Xmx512m' $LS --path.data /tmp/gitin2221/data-update -f /tmp/gitin2221/test-pipeline.conf < /tmp/gitin2221/test-events.jsonl 2>&1 | grep -E '^\{|ERROR|FATAL|Exception'" > "$D/data/.update-test.tmp" || true
  if ! python3 - "$D/data/.update-test.tmp" "$D/scripts/logstash/test-expected.json" <<'PY'
import json, sys
exp = json.load(open(sys.argv[2])); got = {}; bad = []; nopath = 0
for l in open(sys.argv[1]):
    l = l.strip()
    if not l.startswith("{"): bad.append(l[:150]); continue
    e = json.loads(l); p = e.get("Path")
    if not p:
        nopath += 1
        if "NormalizedPath" in e: bad.append("evento sin Path con NormalizedPath: %r" % e)
        continue
    got[p] = e.get("NormalizedPath")
diff = [(p, exp[p], got.get(p)) for p in exp if got.get(p) != exp[p]]
print("eventos: %d con Path (esperados %d), %d sin Path | diferencias: %d | lineas raras: %d" % (len(got), len(exp), nopath, len(diff), len(bad)))
for x in diff[:10]: print("  DIF", x)
for x in bad[:5]: print("  RARO", x)
sys.exit(0 if not diff and not bad and len(got) == len(exp) else 1)
PY
  then echo "prueba del filtro FALLO: restaurando la tabla anterior, sin reiniciar"; VM "sudo cp -p $TBLBAK $TBL && sudo ls -l $TBL"; exit 1; fi
  echo "== 3) aplicar al config vivo, probar, reiniciar"
  VM "sudo cp -p $LIVE $BAK2 && sudo patch $LIVE < /tmp/gitin2221/normalizedpath-update.patch"
  VM "sudo -u logstash $LS --path.data /tmp/gitin2221/data-update -f $LIVE -t 2>&1 | tail -6" | RED > "$D/data/.update-t2.tmp"; cat "$D/data/.update-t2.tmp"
  if grep -q "Configuration OK" "$D/data/.update-t2.tmp"; then
    echo "prueba OK: reiniciando logstash"; VM "sudo systemctl restart logstash"; sleep 45
    echo "estado: $(VM 'systemctl is-active logstash')"
    VM "sudo journalctl -u logstash --since '-2min' --no-pager | grep -E '\]\[(ERROR|FATAL)\]' | cut -c1-220 | head -10" | RED || true
  else
    echo "prueba FALLO: restaurando config y tabla, sin reiniciar"; VM "sudo cp -p $BAK2 $LIVE && sudo cp -p $TBLBAK $TBL && sudo sha256sum $LIVE"; exit 1
  fi
  ;;
fix)
  # Tercera pasada: ElapsedMillisecondsOpe para Sales (el valor llega como string "0.453886e2"; el campo ElapsedMilliseconds NO se toca).
  # No hay sha esperado: la guarda es 'patch --dry-run' sobre el config vivo (el contexto de las lineas debe coincidir).
  BAK3=$LIVE.bak-GITIN-2221-fix
  VM "mkdir -p /tmp/gitin2221 && sudo install -d -o logstash -g logstash -m 755 /tmp/gitin2221/data-fix"
  VM "cat > /tmp/gitin2221/elapsed-fix.patch" < "$D/scripts/logstash/elapsed-fix.patch"
  VM "cat > /tmp/gitin2221/test-sales-pipeline.conf" < "$D/scripts/logstash/test-sales-pipeline.conf"
  VM "cat > /tmp/gitin2221/test-sales-events.jsonl" < "$D/scripts/logstash/test-sales-events.jsonl"
  VM "sudo chmod 644 /tmp/gitin2221/elapsed-fix.patch /tmp/gitin2221/test-sales-pipeline.conf /tmp/gitin2221/test-sales-events.jsonl"
  echo "== 1) guarda: el patch debe aplicar sobre el config vivo"
  VM "sudo patch --dry-run $LIVE < /tmp/gitin2221/elapsed-fix.patch" || { echo "GUARDA: el patch no aplica sobre el config vivo; no se cambio nada"; exit 1; }
  echo "== 2) el patch sobre una copia y logstash -t"
  VM "sudo cp $LIVE /tmp/gitin2221/fix-test.conf && sudo chmod 644 /tmp/gitin2221/fix-test.conf && sudo patch /tmp/gitin2221/fix-test.conf < /tmp/gitin2221/elapsed-fix.patch"
  VM "sudo -u logstash $LS --path.data /tmp/gitin2221/data-fix -f /tmp/gitin2221/fix-test.conf -t 2>&1 | tail -6" | RED > "$D/data/.fix-t.tmp"; cat "$D/data/.fix-t.tmp"
  grep -q "Configuration OK" "$D/data/.fix-t.tmp" || { echo "prueba -t FALLO: no se cambio nada"; exit 1; }
  echo "== 3) el bloque de Sales parcheado en un Logstash aparte, contra los valores esperados"
  VM "sudo -u logstash env LS_JAVA_OPTS='-Xms256m -Xmx512m' $LS --path.data /tmp/gitin2221/data-fix -f /tmp/gitin2221/test-sales-pipeline.conf < /tmp/gitin2221/test-sales-events.jsonl 2>&1 | grep -E '^\{|ERROR|FATAL|Exception'" > "$D/data/.fix-test.tmp" || true
  python3 - "$D/data/.fix-test.tmp" "$D/scripts/logstash/test-sales-expected.json" <<'PY' || { echo "prueba del filtro FALLO: no se cambio nada"; exit 1; }
import json, sys
exp = json.load(open(sys.argv[2])); n = 0; bad = []
for l in open(sys.argv[1]):
    l = l.strip()
    if not l.startswith("{"): bad.append("linea rara: " + l[:150]); continue
    e = json.loads(l); n += 1; want = exp[str(e["id"])]
    try: raw = json.loads(e["Properties"]).get("ElapsedMilliseconds") if "Properties" in e else None
    except Exception: raw = None
    want_old = raw if isinstance(raw, (int, float)) and not isinstance(raw, bool) else None
    ope, old = e.get("ElapsedMillisecondsOpe"), e.get("ElapsedMilliseconds")
    ok_ope = (ope is None) if want is None else (isinstance(ope, (int, float)) and abs(ope - want) < 1e-9)
    ok_old = (old is None) if want_old is None else (isinstance(old, (int, float)) and abs(old - want_old) < 1e-9)
    if not (ok_ope and ok_old): bad.append("id %s: Ope=%r (esperado %r), original=%r (esperado %r)" % (e["id"], ope, want, old, want_old))
print("eventos: %d (esperados %d) | diferencias: %d" % (n, len(exp), len(bad)))
for b in bad[:10]: print("  ", b)
sys.exit(0 if not bad and n == len(exp) else 1)
PY
  echo "== 4) aplicar al config vivo, probar, reiniciar"
  VM "sudo cp -p $LIVE $BAK3 && sudo patch $LIVE < /tmp/gitin2221/elapsed-fix.patch"
  VM "sudo -u logstash $LS --path.data /tmp/gitin2221/data-fix -f $LIVE -t 2>&1 | tail -6" | RED > "$D/data/.fix-t2.tmp"; cat "$D/data/.fix-t2.tmp"
  if grep -q "Configuration OK" "$D/data/.fix-t2.tmp"; then
    echo "prueba OK: reiniciando logstash"; VM "sudo systemctl restart logstash"; sleep 45
    echo "estado: $(VM 'systemctl is-active logstash')"
    VM "sudo journalctl -u logstash --since '-2min' --no-pager | grep -E '\]\[(ERROR|FATAL)\]' | cut -c1-220 | head -10" | RED || true
  else
    echo "prueba FALLO: restaurando el config, sin reiniciar"; VM "sudo cp -p $BAK3 $LIVE && sudo sha256sum $LIVE"; exit 1
  fi
  ;;
rollback-fix)
  VM "sudo cp -p $LIVE.bak-GITIN-2221-fix $LIVE && sudo sha256sum $LIVE && sudo systemctl restart logstash"; sleep 45
  echo "estado: $(VM 'systemctl is-active logstash')"
  ;;
rollback-update)
  VM "sudo cp -p $LIVE.bak-GITIN-2221-update $LIVE && sudo cp -p $TBL.bak-GITIN-2221 $TBL && sudo sha256sum $LIVE && sudo systemctl restart logstash"; sleep 45
  echo "estado: $(VM 'systemctl is-active logstash')"
  ;;
rollback)
  VM "sudo cp -p $BAK $LIVE && sudo sha256sum $LIVE && sudo systemctl restart logstash"; sleep 45
  echo "estado: $(VM 'systemctl is-active logstash')"
  ;;
*) echo "modo desconocido: $MODE"; exit 1;;
esac
echo listo
