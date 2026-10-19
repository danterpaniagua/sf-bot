// GITIN-2252 — SOLO LECTURA. Estado actual de MongoDB de SmartPedidos (cluster PedidosSmartfran, base smartfran). Imprime explicitamente (mongosh no interactivo no auto-imprime).
// Uso: mongosh "$MONGO_URI" --quiet mongo-health-snapshot.js > data/mongo-health-snapshot-<HHMM>.json
// No imprime texto de consultas ni documentos: solo contadores, estados y nombres de namespace.
const out = { ahora: new Date().toISOString() };
const ss = db.getSiblingDB('admin').serverStatus();
out.host = ss.host; out.version = ss.version; out.uptime_segundos = ss.uptime; out.localTime = ss.localTime;
out.connections = ss.connections;
out.opcounters = ss.opcounters;
out.asserts = ss.asserts;
out.globalLock_currentQueue = ss.globalLock && ss.globalLock.currentQueue;
out.network = ss.network && { bytesIn: ss.network.bytesIn, bytesOut: ss.network.bytesOut, numRequests: ss.network.numRequests };
try {
  const rs = db.getSiblingDB('admin').runCommand({ replSetGetStatus: 1 });
  const prim = rs.members.find(m => m.stateStr === 'PRIMARY');
  out.replicaSet = { set: rs.set, myState: rs.myState, members: rs.members.map(m => ({
    name: m.name, state: m.stateStr, health: m.health, uptime_segundos: m.uptime,
    lag_vs_primary_segundos: (prim && m.optimeDate) ? (prim.optimeDate - m.optimeDate) / 1000 : null,
    pingMs: m.pingMs, ultimoCambioDeEstado: m.lastHeartbeatMessage || null, electionDate: m.electionDate || null })) };
} catch (e) { out.replicaSet = { error: String(e) }; }
try {
  const ops = db.getSiblingDB('admin').aggregate([{ $currentOp: { allUsers: true, idleConnections: false } }, { $match: { active: true, secs_running: { $gte: 5 } } },
    { $project: { _id: 0, ns: 1, op: 1, secs_running: 1, planSummary: 1 } }, { $limit: 20 }]).toArray();
  out.operaciones_activas_5s_o_mas = ops;
} catch (e) { out.operaciones_activas_5s_o_mas = { error: String(e) }; }
const st = db.getSiblingDB('smartfran').stats();
out.smartfran = { collections: st.collections, objects: st.objects, dataSize: st.dataSize, storageSize: st.storageSize, indexes: st.indexes, indexSize: st.indexSize };
printjson(out);
