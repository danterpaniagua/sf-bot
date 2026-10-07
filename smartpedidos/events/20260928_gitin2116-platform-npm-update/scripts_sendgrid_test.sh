#!/usr/bin/env bash
# GITIN-2116: compare @sendgrid/mail behaviour on axios 0.26.1 (develop image) vs axios 1.20.0 (override, Option 1 image).
# Step 1 (needs the 3 SENDGRID_TEST_* variables exported): SANDBOX send — SendGrid validates the request and
#   returns a result but does NOT deliver the email.
# Step 2 (always): send with a deliberately INVALID API key — checks the rejection shape the code logs (error.response.body).
# Writes JSON lines to data/. Never prints or stores the API key. Do NOT use the keys committed in the repo; use a test key.
#   export SENDGRID_TEST_API_KEY=...   (a test key with "Mail Send" permission)
#   export SENDGRID_TEST_FROM=...      (a sender verified in that SendGrid account)
#   export SENDGRID_TEST_TO=...        (any mailbox you control; nothing is delivered in sandbox mode)
set -eu
E=/home/dpaniagua/Documentos/git/bots/smartpedidos/events/20260928_gitin2116-platform-npm-update/data
J=$(mktemp); trap 'rm -f "$J"' EXIT
cat > "$J" <<'JS'
const base = '/usr/src/app/node_modules';
const path = require('path');
const sg = require(base + '/@sendgrid/mail');
const info = (o) => console.log(JSON.stringify(o));
const clientPath = require.resolve(base + '/@sendgrid/client');
const axiosPkg = require(require.resolve('axios/package.json', { paths: [path.dirname(clientPath)] }));
info({ step: 'versions', sendgridMail: require(base + '/@sendgrid/mail/package.json').version,
       sendgridClient: require(base + '/@sendgrid/client/package.json').version, axiosUsedBySendgridClient: axiosPkg.version, node: process.version });
const shape = (e) => ({ ok: false, code: e.code, name: e.name, message: String(e.message).slice(0, 120),
  status: e.response && e.response.statusCode, bodyType: e.response && typeof e.response.body,
  bodyKeys: e.response && e.response.body && typeof e.response.body === 'object' ? Object.keys(e.response.body) : null });
(async () => {
  const to = process.env.SENDGRID_TEST_TO, from = process.env.SENDGRID_TEST_FROM, key = process.env.SENDGRID_TEST_API_KEY;
  if (key && to && from) {
    sg.setApiKey(key);
    try { const [res] = await sg.send({ to, from, subject: 'axios compat test (sandbox)', text: 'sandbox', mailSettings: { sandboxMode: { enable: true } } });
      info({ step: 'sandbox_send', ok: true, statusCode: res.statusCode, bodyType: typeof res.body, headerKeys: Object.keys(res.headers || {}).length });
    } catch (e) { info(Object.assign({ step: 'sandbox_send' }, shape(e))); }
  } else { info({ step: 'sandbox_send', skipped: 'SENDGRID_TEST_* variables not set' }); }
  sg.setApiKey('SG.invalid.invalid');
  try { await sg.send({ to: 'nobody@example.com', from: 'nobody@example.com', subject: 'invalid key test', text: 'x', mailSettings: { sandboxMode: { enable: true } } });
    info({ step: 'invalid_key', ok: true, note: 'unexpectedly accepted' });
  } catch (e) { info(Object.assign({ step: 'invalid_key' }, shape(e))); }
})();
JS

for IMG in platform-service:develop-current platform-n20:opt1; do
  TAG=$(echo "$IMG" | tr ':/' '__')
  docker run --rm -e SENDGRID_TEST_API_KEY -e SENDGRID_TEST_FROM -e SENDGRID_TEST_TO -v "$J":/tmp/sg_test.js:ro --entrypoint node "$IMG" /tmp/sg_test.js \
    > "$E/sendgrid_test_${TAG}_20260930.jsonl" 2>&1 || true
done
echo "done: $E/sendgrid_test_*_20260930.jsonl"
