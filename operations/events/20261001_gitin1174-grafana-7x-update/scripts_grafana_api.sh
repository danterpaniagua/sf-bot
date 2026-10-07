#!/usr/bin/env bash
# GITIN-1174: read-only inventory of the live Grafana through its HTTP API (GET requests only).
# Needs: GRAFANA_API_KEY exported (a temporary key with the Admin role; delete it afterwards) and GRAFANA_URL.
# Recommended: open an ssh tunnel so the key never crosses the network in clear text (the public name only serves plain HTTP):
#     ssh -N -L 3300:localhost:3000 "$GRAFANA_HOST"        # leave it running in another terminal
#     export GRAFANA_URL=http://localhost:3300
# Output goes to data/. Fields that can carry secrets or personal data are dropped (datasource passwords, e-mail addresses,
# notification-channel settings, API key values).
set -eu
: "${GRAFANA_API_KEY:?export GRAFANA_API_KEY first}"
: "${GRAFANA_URL:?export GRAFANA_URL first (e.g. http://localhost:3300)}"
E=/home/dpaniagua/Documentos/git/bots/operations/events/20261001_gitin1174-grafana-7x-update/data
mkdir -p "$E"
get() { curl -s --max-time 30 -H "Authorization: Bearer $GRAFANA_API_KEY" "$GRAFANA_URL$1"; }

# 1. Version / health (no key needed)
curl -s --max-time 10 "$GRAFANA_URL/api/health" > "$E/gf_01_health_20261001.json"

# 2. Instance counters (dashboards, datasources, users, alerts, ...)
get /api/admin/stats > "$E/gf_02_admin_stats_20261001.json"

# 3. Datasources (no passwords / secure fields)
get /api/datasources | jq '[.[]|{id,name,type,url,access,isDefault,basicAuth,database}]' > "$E/gf_03_datasources_20261001.json"

# 4. Installed plugins (id, type, version, signature)
get /api/plugins | jq '[.[]|{id,name,type,version:.info.version,author:.info.author.name,signature,enabled}]' > "$E/gf_04_plugins_20261001.json"

# 5. Folders and dashboards (titles, folders, tags)
get /api/folders | jq '[.[]|{id,uid,title}]' > "$E/gf_05_folders_20261001.json"
get '/api/search?type=dash-db&limit=5000' > "$E/gf_06_dashboards_raw_20261001.json"
jq '[.[]|{uid,title,folderTitle,tags,url}]' "$E/gf_06_dashboards_raw_20261001.json" > "$E/gf_06_dashboards_20261001.json"

# 6. Per-dashboard summary: panel types, datasource names, legacy alerts, schema version, last update
: > "$E/gf_07_dashboard_summaries_20261001.jsonl"
for uid in $(jq -r '.[].uid' "$E/gf_06_dashboards_raw_20261001.json"); do
  get "/api/dashboards/uid/$uid" | jq -c '
    . as $d
    | ([.dashboard.panels[]?, .dashboard.panels[]?.panels[]?, .dashboard.rows[]?.panels[]?]) as $p
    | {uid:$d.dashboard.uid, title:$d.dashboard.title, folder:$d.meta.folderTitle, updated:$d.meta.updated,
       schemaVersion:$d.dashboard.schemaVersion, panels:($p|length),
       panelTypes:($p|map(.type)|group_by(.)|map({(.[0]):length})|add),
       datasources:($p|map(.datasource|select(.!=null))|unique),
       legacyAlerts:($p|map(select(.alert!=null))|length)}' >> "$E/gf_07_dashboard_summaries_20261001.jsonl"
done

# 7. Legacy alerts and notification channels (names/types only)
get /api/alerts | jq '[.[]|{id,dashboardUid,name,state}]' > "$E/gf_08_alerts_20261001.json"
get /api/alert-notifications | jq '[.[]|{id,name,type,isDefault}]' > "$E/gf_09_alert_notifiers_20261001.json"

# 8. Orgs, users (no e-mail addresses) and API keys (names/roles/expiry only)
get /api/orgs > "$E/gf_10_orgs_20261001.json"
get /api/org/users | jq '[.[]|{userId,login,role,lastSeenAtAge}]' > "$E/gf_11_org_users_20261001.json"   # org users (works with an Admin-role API key; e-mail dropped)
get /api/auth/keys | jq '[.[]|{id,name,role,expiration}]' > "$E/gf_12_api_keys_20261001.json"

echo "done: $E/gf_*_20261001.*"
