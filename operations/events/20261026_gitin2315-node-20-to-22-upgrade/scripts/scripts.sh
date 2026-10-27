#!/usr/bin/env bash
# Event: 20261026_gitin2315-node-20-to-22-upgrade
# Local test build of platformsService on Node 22.23.4 (branch `ope`, uncommitted Dockerfile change).
# Build only, local image; nothing is pushed.

# === INVESTIGATION ===
# C1 — build the image without cache and with a fresh base image (the build needs network:
#      npm registry and bot-security.smartfran.com:443 for the certificate chain)
docker build --pull --no-cache --progress=plain -t platforms-service:node22-test /home/dpaniagua/Documentos/git/bots/smartpedidos/repo/dev-scr-smartPedidos-platformsService/api > /home/dpaniagua/Documentos/git/bots/operations/events/20261026_gitin2315-node-20-to-22-upgrade/data/docker-build-platforms-node22-20261026.txt 2>&1

# C2 — Node and npm versions inside the final image
docker run --rm --entrypoint sh platforms-service:node22-test -c 'node --version && npm --version' > /home/dpaniagua/Documentos/git/bots/operations/events/20261026_gitin2315-node-20-to-22-upgrade/data/docker-node-version-platforms-20261026.txt 2>&1

# C3 — Trivy scan of the local image (OS packages and npm packages; the Node runtime itself is not covered, see C2)
trivy image --scanners vuln --severity HIGH,CRITICAL --format table platforms-service:node22-test > /home/dpaniagua/Documentos/git/bots/operations/events/20261026_gitin2315-node-20-to-22-upgrade/data/trivy-platforms-node22-20261026.txt 2>&1

# C4 — ⚠️ start the service from the local image with the staging config for 90 s (port 3087).
#      It connects to the STAGING MongoDB cluster and the staging SQS queues (us-east-2) and may consume messages
#      and run its schedules there. `timeout` sends SIGTERM to the docker client, which forwards it to the container.
timeout 90 docker run --rm --name platforms-stg-test -p 3087:3087 platforms-service:node22-test serve:stg > /home/dpaniagua/Documentos/git/bots/operations/events/20261026_gitin2315-node-20-to-22-upgrade/data/docker-run-serve-stg-platforms-20261026.txt 2>&1

# C5 — ⚠️ same as C4 but with AWS credentials from a named profile of the user's ~/.aws (read-only mount), not from staging.js.
#      With credentials the SQS consumer WILL receive and process messages from the staging queue. Use a staging-only profile.
#      Mask the output file before reading it (error stacks can include request bodies).
timeout 90 docker run --rm --name platforms-stg-test -p 3087:3087 -v /home/dpaniagua/.aws:/root/.aws:ro -e AWS_PROFILE=sp-staging platforms-service:node22-test serve:stg > /home/dpaniagua/Documentos/git/bots/operations/events/20261026_gitin2315-node-20-to-22-upgrade/data/docker-run-serve-stg-aws-platforms-20261026.txt 2>&1

# C6 — rebuild the image with the aws.js change (static credentials read from the staging config)
docker build --pull --progress=plain -t platforms-service:node22-test /home/dpaniagua/Documentos/git/bots/smartpedidos/repo/dev-scr-smartPedidos-platformsService/api > /home/dpaniagua/Documentos/git/bots/operations/events/20261026_gitin2315-node-20-to-22-upgrade/data/docker-build-platforms-aws-js-20261026.txt 2>&1

# C7 — ⚠️ run `serve:stg` for 90 s with the credentials from staging.js (no profile mount). The SQS consumer will process staging messages.
timeout 90 docker run --rm --name platforms-stg-test -p 3087:3087 platforms-service:node22-test serve:stg > /home/dpaniagua/Documentos/git/bots/operations/events/20261026_gitin2315-node-20-to-22-upgrade/data/docker-run-serve-stg-config-creds-platforms-20261026.txt 2>&1


# C9 — read-only: list the packages installed inside the local image before it is removed
docker run --rm -i --entrypoint sh platforms-service:node22-test -s < /home/dpaniagua/Documentos/git/bots/operations/events/20261026_gitin2315-node-20-to-22-upgrade/scripts/inspect-image-packages.sh > /home/dpaniagua/Documentos/git/bots/operations/events/20261026_gitin2315-node-20-to-22-upgrade/data/docker-image-packages-platforms-20261026.txt 2>&1
