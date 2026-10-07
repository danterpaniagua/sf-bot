#!/usr/bin/env bash
# Read-only. Usage: DB=<database> bash run_mongo_orders.sh   (needs $MONGO_URI in the environment)
set -u
: "${MONGO_URI:?MONGO_URI not set}"
: "${DB:?DB not set}"
EV=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20261002_5713-no-new-orders-sqs
mkdir -p "$EV/data"
mongosh "$MONGO_URI/$DB" --quiet --file "$EV/mongo_orders_5713.js" \
  > "$EV/data/mongo_orders_5713.json" \
  2> "$EV/data/mongo_orders_5713.err"
echo "exit=$? out_bytes=$(wc -c < "$EV/data/mongo_orders_5713.json") err_bytes=$(wc -c < "$EV/data/mongo_orders_5713.err")"
