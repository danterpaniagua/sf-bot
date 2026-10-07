#!/bin/bash
# npm registry packument fetch — 35 unique direct (production) dependencies
# concentradorService + platformsService, union, for Compat.Dockerfile check (Node major 20)
# One full packument per package (all published versions + their engines.node fields) —
# avoids one-call-per-version round trips, per sp-npm-compliance skill guidance.
# Run and paste back confirmation (or any errors) — files land directly in data/.
set -e

curl -s https://registry.npmjs.org/@aws-sdk/client-sqs -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_aws-sdk__client-sqs.json
curl -s https://registry.npmjs.org/@aws-sdk/client-ssm -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_aws-sdk__client-ssm.json
curl -s https://registry.npmjs.org/@babel/core -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_babel__core.json
curl -s https://registry.npmjs.org/@babel/node -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_babel__node.json
curl -s https://registry.npmjs.org/@babel/runtime -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_babel__runtime.json
curl -s https://registry.npmjs.org/@meanie/mongoose-to-json -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_meanie__mongoose-to-json.json
curl -s https://registry.npmjs.org/@sendgrid/mail -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_sendgrid__mail.json
curl -s https://registry.npmjs.org/@types/form-data -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_types__form-data.json
curl -s https://registry.npmjs.org/axios -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_axios.json
curl -s https://registry.npmjs.org/body-parser -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_body-parser.json
curl -s https://registry.npmjs.org/cookie-parser -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_cookie-parser.json
curl -s https://registry.npmjs.org/core-js -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_core-js.json
curl -s https://registry.npmjs.org/cors -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_cors.json
curl -s https://registry.npmjs.org/cross-env -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_cross-env.json
curl -s https://registry.npmjs.org/crypto-js -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_crypto-js.json
curl -s https://registry.npmjs.org/env-var -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_env-var.json
curl -s https://registry.npmjs.org/express -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_express.json
curl -s https://registry.npmjs.org/express-jwt -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_express-jwt.json
curl -s https://registry.npmjs.org/form-data -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_form-data.json
curl -s https://registry.npmjs.org/jsonwebtoken -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_jsonwebtoken.json
curl -s https://registry.npmjs.org/lodash -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_lodash.json
curl -s https://registry.npmjs.org/moment -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_moment.json
curl -s https://registry.npmjs.org/mongoose -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_mongoose.json
curl -s https://registry.npmjs.org/mongoose-unique-validator -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_mongoose-unique-validator.json
curl -s https://registry.npmjs.org/morgan -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_morgan.json
curl -s https://registry.npmjs.org/node-cron -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_node-cron.json
curl -s https://registry.npmjs.org/node-schedule -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_node-schedule.json
curl -s https://registry.npmjs.org/nodemon -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_nodemon.json
curl -s https://registry.npmjs.org/regenerator-runtime -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_regenerator-runtime.json
curl -s https://registry.npmjs.org/sqs-consumer -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_sqs-consumer.json
curl -s https://registry.npmjs.org/swagger-jsdoc -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_swagger-jsdoc.json
curl -s https://registry.npmjs.org/swagger-ui-express -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_swagger-ui-express.json
curl -s https://registry.npmjs.org/uuid -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_uuid.json
curl -s https://registry.npmjs.org/winston -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_winston.json
curl -s https://registry.npmjs.org/winston-mongodb -o /home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260925_npm-compat-node20-boundary/data/registry_winston-mongodb.json

echo "Done — 35 files written to data/registry_*.json"
