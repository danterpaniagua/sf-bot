# Job Description — Ingeniero/a de Infraestructura, Operaciones y Confiabilidad (Operations, SRE & DevOps)

> Origen: ticket `GITIN-1820` (título original "SRE Job Description"). Documentos hermanos: `job_description_operations.md` (versión enfocada solo en Operations), `job_description_sre.md` (versión enfocada solo en SRE) y `job_description_devops.md` (versión enfocada solo en DevOps). Este documento existe porque, en la práctica diaria del equipo, Operations, SRE y DevOps no son tres búsquedas distintas — ver nota abajo.

## Nota para Dirección: ¿por qué un solo documento?

"Operations", "SRE" (Site Reliability Engineering) y "DevOps" suelen confundirse porque comparten el mismo stack técnico y, muchas veces, la misma persona. La diferencia real es de **énfasis**, no de herramientas:

| | Operations | SRE | DevOps |
|---|---|---|---|
| **Enfoque principal** | Mantenimiento continuo y operación diaria de la plataforma | Confiabilidad, causa raíz y prevención de incidentes | Automatizar cómo se construye, prueba y despliega el software, y cómo se provisiona la infraestructura |
| **Trabajo típico** | Renovación de certificados, rotación de credenciales, mantenimiento de pipelines de CI/CD, configuración de monitoreo, actualizaciones coordinadas de flota | Investigación de incidentes de producción, análisis cruzado aplicación/DB/infra, automatización para reducir trabajo manual repetitivo | Pipelines de CI/CD, Terraform/IaC, entornos locales/test reproducibles vía Docker Compose, gates de calidad de código, gestión de configuración y secretos por ambiente |
| **Disparador del trabajo** | Programado (renovaciones, mantenimientos, altas de ambientes) | Reactivo a un problema + proactivo en prevenirlo (postmortems, hardening) | Un cambio de código o de infraestructura que necesita llegar a un ambiente de forma repetible |
| **Resultado esperado** | El sistema sigue funcionando y actualizado | El sistema falla menos y, cuando falla, se explica y se corrige la causa, no el síntoma | Cualquier cambio (app o infra) se construye, prueba y despliega de la misma forma, sin pasos manuales |

En la evidencia de trabajo real de los últimos meses, **los tres roles fueron ejercidos por el mismo perfil técnico**, sobre el mismo stack. Este documento describe el conjunto completo de responsabilidades y tecnologías para una posición que cubra los tres frentes — recomendado como el perfil a publicar, salvo que Dirección decida dividir explícitamente el equipo en posiciones separadas (ver `job_description_operations.md`, `job_description_sre.md` y `job_description_devops.md` para las versiones acotadas).

## Resumen del puesto

Responsable de mantener en funcionamiento, seguros y confiables los sistemas de infraestructura que soportan la plataforma SmartFran (SmartLoyalty, SmartFran Cloud, SmartPedidos): un ecosistema multi-tenant sobre Azure y AWS que da servicio a una red de franquicias en Argentina, Paraguay y otros países de Latinoamérica.

El rol combina trabajo de **operación y mantenimiento programado** (certificados, credenciales, actualizaciones, monitoreo) con trabajo de **ingeniería de confiabilidad** (investigación de incidentes, causa raíz, automatización, capacity planning). Incluye acceso y responsabilidad directa sobre bases de datos de producción, redes, identidad y sistemas de mensajería.

## Responsabilidades principales

### Operación y mantenimiento

- Ejecutar y documentar procedimientos coordinados de mantenimiento sobre flotas de servidores (ej. rotación de credenciales compartidas sin causar bloqueos ni cortes de servicio).
- Automatizar la renovación de certificados SSL/TLS (ACME, DNS-01, integración con Key Vault y Application Gateway) para eliminar cargas manuales recurrentes.
- Administrar y mantener pipelines de CI/CD (GitHub Actions; Jenkins con Jenkinsfiles leídos desde SCM, librería Groovy compartida y versionada por proyecto/stack, y ejecución condicional de stages según los paths modificados) y herramientas de calidad de código (SonarQube) y de seguridad de imágenes de contenedor (Trivy — vulnerabilidades CRITICAL/HIGH).
- Integrar herramientas de IA generativa como stage automatizado dentro del pipeline de CI/CD (ej. CLI de un modelo de lenguaje invocada por Jenkins sobre el diff de cada PR) para reporte automatizado de bugs/vulnerabilidades y generación de changelog, gestionando el prompt y el template de salida como artefactos versionados del pipeline.
- Diseñar — no solo configurar — soluciones de monitoreo y telemetría a medida para servicios críticos sin healthcheck nativo (ej. integraciones de facturación electrónica): arquitectura completa de script custom (Bash/Python) → UserParameter/items dependientes en Zabbix → triggers con macros → ruteo de alertas, para dependencias externas o de cumplimiento normativo donde un fallo silencioso tiene impacto de negocio directo.
- Gestionar y resolver problemas de red en ambos clouds: en Azure, DNS, redes virtuales (VNet), reglas de NSG (auditoría periódica y limpieza) y Application Gateway; en AWS, Security Groups de EC2 y ruteo/reglas de listener de ALB/NLB; balanceadores de carga self-hosted (nginx como reverse proxy/terminación SSL/balanceo). Incluye diagnóstico activo — no solo configuración — de conectividad rota, reglas conflictivas y capacidad de distinguir timeout de backend vs. indisponibilidad de backend vs. bloqueo genuino a nivel de red/WAF.
- Operar stacks self-hosted en Docker Compose, incluyendo servicios stateful en cluster (bases de datos con replicación primary/replica, aplicaciones con cache distribuido).
- Analizar y optimizar costos de infraestructura cloud (sizing de VMs, reserva de instancias, retención de datos) a partir de billing real, no de estimaciones de lista de precios.
- Mantener actualizada la documentación de infraestructura (inventario de servidores, topología de red, cuentas de servicio) a medida que cambia.

### Confiabilidad e incidentes (SRE)

- Investigar y resolver incidentes de producción de alta severidad: picos de CPU/memoria, timeouts, colas de mensajería bloqueadas, pérdida de logs, caídas de disponibilidad.
- Diagnosticar incidentes de red multi-cloud como causa raíz — no solo confirmar que "la red está bien": errores de Application Gateway/WAF (502/504/403) en Azure, reglas de NSG conflictivas o mal priorizadas, y en AWS problemas de ruteo o reglas de listener de ALB/NLB y Security Groups — distinguiendo explícitamente timeout de backend, backend caído, y bloqueo genuino a nivel de red.
- Determinar causa raíz cruzando aplicación (.NET/C#, Node.js), base de datos (SQL Server, MongoDB, CosmosDB) e infraestructura cloud.
- Actuar como DBA sobre los tres motores productivos de la plataforma — SQL Server, MongoDB Atlas y CosmosDB: investigar eventos a partir de una ventana temporal reportada (en SQL Server, identificando la query/proceso responsable vía delta de CPU por SPID entre snapshots consecutivos, sin depender de que el evento se repita), proponer mejoras/optimización de queries (tuning de T-SQL e índices, rediseño de aggregation pipelines en Mongo, ajuste de particionamiento y consumo de RU/throughput en CosmosDB) a partir de evidencia real de uso, y mantener el mantenimiento periódico de índices (reconstrucción/reorganización según fragmentación en SQL Server, revisión de índices en Mongo Atlas y CosmosDB) como tarea programada, no solo reactiva a un incidente.
- Diseñar y mantener el stack de observabilidad end-to-end (Graylog/OpenSearch, Zabbix, Azure Monitor/Application Insights, AWS CloudWatch).
- Definir mejoras de capacidad y auto-scaling a partir de datos reales de uso (ECS Fargate, App Service Plans, pools elásticos de base de datos).
- Escribir infraestructura como código (Terraform) para cambios reproducibles y auditable.
- Producir runbooks, postmortems y documentación de causa raíz con evidencia verificable.
- Coordinar con desarrollo cuando un problema excede el alcance de infraestructura (ej. limitaciones de la plataforma cloud, cambios de arquitectura de logging) — no solo escalar el límite, sino proponer la recomendación arquitectónica concreta (qué patrón, qué componente, qué trade-off) en lugar de dejar el diseño de la solución enteramente del lado de desarrollo.
- Evaluar e implementar componentes de identidad self-hosted (ej. Keycloak, con clustering y base de datos replicada) como alternativa o complemento a proveedores de identidad SaaS (Auth0).
- Ejecutar análisis estático de seguridad y calidad sobre código de aplicación en producción (Node.js/Express): detección de credenciales/tokens expuestos en logs, violaciones de Single Responsibility Principle y duplicación de código, con hallazgos priorizados por severidad y trazados a un log de deuda técnica (referencia por archivo/línea, estado y prioridad).
- Diseñar, documentar e implementar un estándar de logging estructurado propio (niveles, campos obligatorios, reglas de qué nunca debe loguearse) — generalizado a un conjunto de axiomas *stack-agnostic* aplicado tanto a servicios Node.js como .NET, y escribir parches acotados de compliance directamente sobre código productivo sin alterar reglas de negocio.
- Administrar y diagnosticar PostgreSQL (tuning, capacity planning, troubleshooting operativo) en un segundo producto sobre stack Django, y proponer logging de observabilidad en ese código con el mismo criterio de "sin ruido, con propósito operativo claro" que en el resto de la plataforma.
- Aplicar una metodología formal de control de alcance para cambios de infraestructura y de código: análisis de requerimientos, definición y versionado de scope antes de implementar, y validación posterior de que lo implementado coincide con lo aprobado (detección de scope creep, cambios fuera de alcance, incumplimiento de reglas del repositorio) — sin comprometerse nunca a que una prueba pasó sin haberla ejecutado.

## Stack tecnológico

| Categoría | Tecnologías |
|---|---|
| **Cloud** | Microsoft Azure (App Services Windows/Linux, Application Gateway/WAF, VNet, NSG — incl. auditoría y limpieza periódica de reglas, Key Vault, App Configuration, Service Bus, Event Hubs, Azure Functions, Azure Container Instances, CosmosDB, Azure SQL Database, Redis, SignalR, Azure DNS, Azure Monitor / Log Analytics Workspace, Azure AD Domain Services); AWS (IAM, S3, Lambda, API Gateway, Secrets Manager, SQS FIFO/DLQ, EC2 incl. Security Groups, ECS Fargate, ALB/NLB — target groups, listener rules, ruteo, CloudWatch) |
| **Bases de datos** | DBA multi-motor: SQL Server (T-SQL, tuning, blocking, mantenimiento de índices, SQL Agent, investigación de eventos vía captura de CPU delta por SPID); MongoDB / MongoDB Atlas (aggregation pipeline, Atlas Admin API, sizing de clusters, optimización de queries); CosmosDB (SQL API, particionamiento, ajuste de RU/throughput); PostgreSQL (administración completa: tuning, capacity planning, replicación streaming primary/replica, troubleshooting operativo); Azure SQL Database (pools elásticos multi-tenant) |
| **Lenguajes / Scripting** | PowerShell (avanzado); Bash (avanzado); Python (intermedio — `pymongo`, `boto3`, `pandas`, `Flask`, `redis`, análisis ad-hoc en Jupyter; lectura de código Django para observabilidad); SQL (avanzado); lectura y **escritura de parches acotados** en C#/.NET y Node.js/Express (Mongoose, Axios, node-cron) — diagnóstico de causa raíz, refactors SRP/DRY y compliance de logging sin alterar reglas de negocio |
| **Sistemas operativos** | Windows Server (IIS, Active Directory / Azure AD DS, Kerberos, PowerShell remoting); Linux (Ubuntu, administración de servidores y contenedores Docker) |
| **CI/CD e IaC** | GitHub Actions (pipeline principal, despliegues a Azure App Service); Jenkins (infraestructura legacy vigente — Jenkinsfiles desde SCM, librería Groovy compartida `customScripts`, ejecución condicional por paths modificados, agentes Windows Server 2019 y Ubuntu); Terraform / OpenTofu multi-cloud (proveedor `azurerm` — VMs, redes, discos, Event Hubs; proveedor `aws` — SQS, IAM, API Gateway, Lambda, Secrets Manager); SonarQube y Trivy (gates de calidad y seguridad de imágenes de contenedor); integración de IA generativa como stage de pipeline (análisis automatizado de PR, generación de changelog) |
| **Observabilidad / Monitoreo** | Graylog + OpenSearch + Mongo (múltiples stacks Docker autogestionados, incluye troubleshooting de cluster e índices); Logstash (pipelines de ingesta/transformación, plugin Azure Event Hubs); Zabbix (v4, v5 y 6, diseño de integraciones custom vía UserParameter/items dependientes con JSONPath preprocessing, scripting Bash/Python de healthchecks para servicios sin monitoreo nativo — ej. integraciones de facturación electrónica); Azure Application Insights; AWS CloudWatch; Grafana |
| **Seguridad / Identidad** | Azure AD Domain Services; Auth0 (multi-tenant SaaS); Keycloak (IAM self-hosted, clustering, federación custom); Key Vault y Managed Identities; Service Principals; gestión de secretos (Azure Key Vault, AWS Secrets Manager); automatización ACME/DNS-01, win-acme, Let's Encrypt/certbot; revisión de políticas IAM |
| **Mensajería / Integración** | AWS SQS (FIFO, dead-letter queues); Azure Service Bus; Azure Event Hubs; relays SMTP (hMailServer, SendGrid) |
| **Servidores web / Balanceo** | IIS (Windows); nginx (reverse proxy, terminación SSL, balanceo de carga) |
| **Contenedores** | Docker / Docker Compose (stacks self-hosted: Graylog, OpenSearch, Zabbix, clusters de aplicaciones con cache distribuido) |

### División de foco por rol

El stack de arriba es compartido — lo que cambia por rol es **qué parte de ese stack se usa y con qué propósito**. Esta tabla existe para que Dirección pueda ver, categoría por categoría, dónde pondría el foco cada búsqueda si se dividiera el equipo:

| Categoría | Operations | SRE | DevOps |
|---|---|---|---|
| **Cloud** | Provisión, mantenimiento y auditoría periódica de recursos ya desplegados (NSG, DNS, Key Vault, Application Gateway) | Diagnóstico cruzado sobre recursos en producción para causa raíz, incluyendo capa de red (NSG/WAF en Azure, Security Groups/ALB-NLB en AWS) además de Azure Monitor/CloudWatch/Application Insights | Provisión reproducible vía IaC (Terraform `azurerm`/`aws`) y gestión de configuración por ambiente |
| **Bases de datos** | Mantenimiento operativo (backups, actualizaciones, altas de instancia) | DBA multi-motor: investigación de causa raíz y optimización de queries (SQL Server, MongoDB Atlas, CosmosDB) | Provisión de instancias/pools elásticos — no administración de datos en sí |
| **Lenguajes / Scripting** | PowerShell/Bash para automatización de tareas programadas | Python/SQL para análisis de causa raíz; lectura de código de aplicación para diagnóstico | Escritura de parches acotados en código de aplicación (compliance de logging, SRP/DRY); scripting de pipeline |
| **CI/CD e IaC** | Mantenimiento de pipelines ya existentes | Automatización puntual (Terraform) para reducir trabajo manual repetitivo en incidentes recurrentes | Diseño y ownership de los pipelines (GitHub Actions/Jenkins, incl. gates de seguridad/calidad e integración de IA en el pipeline) y de la IaC multi-cloud |
| **Observabilidad / Monitoreo** | Diseño de integraciones de monitoreo a medida para servicios sin healthcheck nativo (script Bash/Python → Zabbix) | Diseño end-to-end del stack de observabilidad y su uso activo para causa raíz | Observabilidad como código — definición versionada de chequeos, pipelines de ingesta (Logstash) |
| **Contenedores** | Operación día a día de stacks self-hosted en producción | Troubleshooting de cluster cuando algo falla (índices, replicación, memoria) | Diseño de stacks multi-servicio y de entornos locales/test reproducibles para desarrollo |
| **Seguridad / Identidad** | Rotación coordinada de credenciales, renovación de certificados como tarea programada | Revisión de políticas IAM como parte de la causa raíz de un incidente de seguridad | Gestión de secretos/configuración por ambiente; automatización del ciclo de vida de certificados |

## Requisitos excluyentes

- Experiencia operando y troubleshooteando infraestructura de producción en un entorno de alta disponibilidad.
- Azure nivel avanzado (App Services, redes/VNet/NSG, Key Vault, Azure Monitor) y AWS nivel intermedio/avanzado (IAM, S3, Lambda, SQS, EC2/Security Groups, ECS, ALB/NLB, CloudWatch) — en ambos casos, capacidad de diagnosticar problemas de red, no solo de administrar recursos ya funcionando.
- PowerShell y Bash avanzado; Python intermedio; SQL avanzado sobre SQL Server.
- Administración de Windows Server + IIS y de Linux con Docker.
- Experiencia con al menos una herramienta de observabilidad tipo Graylog/ELK/OpenSearch y con un sistema de monitoreo tipo Zabbix.
- Experiencia con al menos una herramienta de CI/CD (GitHub Actions o Jenkins) y con Terraform u otra IaC.
- Capacidad de leer código de aplicación (C#/.NET o Node.js) para diagnóstico, sin necesidad de desarrollo activo.
- Criterio de seguridad operativa: manejo de credenciales y secretos sin exponerlos, coordinación de cambios sensibles con ventanas de mantenimiento.
- Experiencia real como DBA sobre más de un motor (SQL Server y al menos uno entre MongoDB Atlas / CosmosDB) — investigación de eventos, optimización de queries y mantenimiento periódico de índices, no solo consultas puntuales.

## Requisitos deseables

- Experiencia con arquitecturas SaaS multi-tenant.
- CosmosDB y sistemas de identidad multi-tenant (Auth0, Keycloak o similar).
- Kerberos / Active Directory / Azure AD Domain Services.
- SonarQube y prácticas de calidad de código, incluyendo escaneo de vulnerabilidades de imágenes de contenedor (Trivy).
- Experiencia integrando herramientas de IA generativa como stage automatizado dentro de un pipeline de CI/CD (ej. análisis de PR, generación de changelog), no solo como asistente de desarrollo.
- Experiencia operando PostgreSQL con replicación, o administrando servicios basados en JVM (Graylog, OpenSearch, Keycloak).
- Experiencia aplicando principios de diseño de software (SRP, DRY) para proponer y ejecutar refactors incrementales en código productivo, y criterio para escribir cambios acotados (ej. compliance de logging) sin afectar lógica de negocio.
- Certificaciones: Azure (AZ-104, AZ-400) o AWS (SysOps Administrator, DevOps Engineer).

## Seniority sugerido

Semi-senior a Senior. El rol requiere autonomía tanto para ejecutar mantenimiento programado sin errores como para investigar incidentes sin supervisión directa, y buen criterio para escalar a desarrollo cuando un problema excede el alcance de infraestructura. El núcleo real del perfil es un SRE con profundidad de DBA (SQL Server, MongoDB Atlas, CosmosDB) — la causa raíz de un incidente frecuentemente se resuelve dentro de la base de datos, no solo en infraestructura — con Operations y DevOps como frentes adicionales cubiertos por el mismo perfil, no como el foco principal.
