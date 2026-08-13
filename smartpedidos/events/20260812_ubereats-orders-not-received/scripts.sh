# Comandos y consultas usadas en la investigación — 20260812_ubereats-orders-not-received

# C1 — MongoDB: descartar db.logerrors como fuente confiable (platforms-service no escribe ahí)
db.logerrors.find({
  service: 'platforms-service',
  createdAt: { $gte: new Date(Date.now() - 6*60*60*1000) }
}, { message: 1, createdAt: 1 }).sort({ createdAt: -1 }).limit(20)

# C2 — Graylog (stream SP_Platform): actividad UberEats en la ventana del incidente
service:platforms-service AND UberEats

# C3 — Graylog (stream SP_Platform): confirmar que otras plataformas no fueron afectadas
NOT message:UberEats AND NOT message:heartbeat

# C4 — git: ubicar el commit que introdujo el bug de scoping
git log --oneline -- api/src/controllers/uberEats.js
git blame -L 159,159 --date=short -- api/src/controllers/uberEats.js
git log -p -L 155,161:api/src/controllers/uberEats.js

# C5 — AWS ECS: historial de eventos del servicio (despliegue original y rollback)
aws ecs describe-services --cluster smartfran-pedidos-production \
  --services platform-service-production-service \
  --region us-east-1 --profile <profile> \
  --query 'services[].events[0:100][].{t:createdAt,m:message}'
