#!/usr/bin/env bash
# GITIN-2249 — Reproduce localmente (sin red, sin tocar el servidor) lo que imprime get_enddate.sh cuando openssl no obtiene certificado.
# Las lineas 6-8 son las del script del servidor (data/server-get-enddate-script-2026-10-18.txt); aqui la cadena openssl se reemplaza por una cadena vacia.
echo "date: $(date --version | head -1)"; echo "TZ=${TZ:-<sin definir>}"
echo "-- fallo de conexion: openssl x509 no imprime nada --"
enddate=$(date -d "$(printf '' | sed "s/.*=\(.*\)/\1/")" +%s)
today=$(date +%s)
echo "enddate=$enddate (epoch) today=$today"
echo -n "salida del script: "; date -ud "@$enddate" +"$(( $enddate/3600/24 - $today/3600/24 ))"
echo "-- certificado valido con 17 dias (referencia) --"
enddate=$(date -d "$(date -ud '+17 days' '+%b %d %T %Y GMT')" +%s)
echo -n "salida del script: "; date -ud "@$enddate" +"$(( $enddate/3600/24 - $today/3600/24 ))"
