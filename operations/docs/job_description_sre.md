# Job Description — Site Reliability Engineer (SRE)

> Origen: ticket `GITIN-1820`. Documentos hermanos: `job_description_completa.md` (versión combinada Operations + SRE + DevOps, con nota explicativa comparando los tres roles), `job_description_operations.md` (versión acotada a Operations) y `job_description_devops.md` (versión acotada a DevOps).

## Resumen del puesto

Buscamos un/a **Site Reliability Engineer (SRE)** para la plataforma SmartFran (SmartLoyalty, SmartFran Cloud y SmartPedidos): un ecosistema multi-tenant sobre Azure y AWS que da servicio a una red de franquicias en Argentina, Paraguay y otros países de Latinoamérica.

La persona en este rol es responsable de la **confiabilidad, performance y observabilidad** de los servicios en producción: investiga causas raíz de incidentes, diseña y mantiene el stack de monitoreo/logging, automatiza infraestructura como código, y actúa como puente técnico entre los equipos de desarrollo e infraestructura cuando un problema de plataforma excede lo que se resuelve con configuración.

No es un rol de soporte reactivo puro: implica diagnóstico profundo cruzando aplicación, base de datos, red y nube, y la capacidad de traducir ese diagnóstico en un runbook, una automatización o una recomendación técnica accionable.

## Responsabilidades principales

- Investigar y resolver incidentes de producción de alta severidad: picos de CPU/memoria en bases de datos y servicios, timeouts, colas de mensajería bloqueadas, pérdida o degradación de logs, caídas de disponibilidad.
- Diagnosticar incidentes de red multi-cloud como causa raíz — no solo confirmar que "la red está bien": errores de Application Gateway/WAF (502/504/403) en Azure, reglas de NSG conflictivas o mal priorizadas, y en AWS problemas de ruteo o reglas de listener de ALB/NLB y Security Groups — distinguiendo explícitamente timeout de backend, backend caído, y bloqueo genuino a nivel de red.
- Determinar causa raíz cruzando múltiples capas: código de aplicación (.NET/C#, Node.js), base de datos (SQL Server, MongoDB, CosmosDB), infraestructura cloud (Azure/AWS) y red.
- Actuar como DBA sobre los tres motores productivos — SQL Server, MongoDB Atlas y CosmosDB: investigar eventos a partir de una ventana temporal reportada (en SQL Server, vía captura de CPU delta por SPID entre snapshots), optimizar queries (tuning T-SQL/índices, aggregation pipelines en Mongo, particionamiento y RU/throughput en CosmosDB), y mantener el mantenimiento periódico de índices como tarea programada, no solo reactiva a un incidente.
- Diseñar, mantener y resolver problemas del stack de observabilidad: agregación de logs (Graylog/OpenSearch), monitoreo de infraestructura (Zabbix), telemetría cloud-nativa (Azure Monitor, Application Insights, AWS CloudWatch).
- Diseñar — no solo configurar — soluciones de monitoreo y telemetría a medida para servicios críticos sin healthcheck nativo (ej. integraciones de facturación electrónica): arquitectura completa de script custom (Bash/Python) → UserParameter/items dependientes en Zabbix → triggers con macros → ruteo de alertas, para dependencias externas o de cumplimiento normativo donde un fallo silencioso tiene impacto de negocio directo.
- Automatizar infraestructura como código (Terraform) e integrarse con pipelines de CI/CD (GitHub Actions) para cambios de infraestructura relacionados a observabilidad y confiabilidad.
- Definir mejoras de capacidad y auto-scaling (ECS Fargate, App Service Plans, pools elásticos de base de datos) a partir de datos reales de uso, no de estimaciones.
- Participar en hardening de seguridad operativa: rotación coordinada de credenciales sin causar cortes de servicio, gestión de secretos, revisión de políticas IAM, automatización de renovación de certificados SSL/TLS.
- Documentar cada investigación con evidencia verificable (comandos, queries, outputs) y producir runbooks reutilizables para incidentes recurrentes.
- Coordinar con desarrollo cuando la causa raíz está en el código o en una limitación de la plataforma (ej. una plataforma cloud que no soporta cierto tipo de logging para una tecnología específica) — reconocer el límite entre "esto se resuelve con configuración de infraestructura" y "esto requiere una decisión de arquitectura de software".
- Analizar y optimizar costos de infraestructura cloud (sizing de VMs, reserva de instancias, retención de datos) a partir de billing real y APIs de pricing, no de estimaciones de lista de precios.
- Evaluar e implementar componentes de identidad self-hosted (ej. Keycloak) como alternativa o complemento a proveedores de identidad SaaS.

## Stack tecnológico

| Categoría | Tecnologías |
|---|---|
| **Cloud** | Microsoft Azure (App Services, Application Gateway/WAF, VNet, NSG — incl. auditoría y limpieza periódica de reglas, Key Vault, App Configuration, Service Bus, Event Hubs, Azure Monitor / Log Analytics Workspace, Azure Functions, Azure Container Instances, CosmosDB, Azure SQL Database, Redis, SignalR); AWS (IAM, S3, Lambda, API Gateway, Secrets Manager, SQS incl. FIFO/DLQ, EC2 incl. Security Groups, ECS Fargate, ALB/NLB — target groups, listener rules, ruteo, CloudWatch) |
| **Bases de datos** | DBA multi-motor: SQL Server (T-SQL, tuning, blocking, mantenimiento de índices, investigación de eventos vía CPU delta por SPID); MongoDB / MongoDB Atlas (aggregation pipeline, Atlas Admin API, mantenimiento de índices); CosmosDB (SQL API, particionamiento, RU/throughput); PostgreSQL (incl. replicación streaming primary/replica); Azure SQL Database (pools elásticos multi-tenant) |
| **Lenguajes / Scripting** | PowerShell (avanzado); Bash (avanzado); Python (intermedio, automatización); SQL (avanzado); lectura de código C#/.NET y/o Node.js para trazabilidad de causa raíz (no requiere desarrollo activo) |
| **Sistemas operativos** | Windows Server (IIS, Active Directory / Azure AD Domain Services, Kerberos); Linux (Ubuntu, contenedores Docker) |
| **CI/CD e IaC** | GitHub Actions (despliegues a Azure App Service); Terraform / OpenTofu multi-cloud (proveedor `azurerm` — VMs, redes, discos, Event Hubs; proveedor `aws` — SQS, IAM, API Gateway, Lambda, Secrets Manager); familiaridad con Jenkins (infraestructura legacy aún en uso) |
| **Observabilidad / Monitoreo** | Graylog + OpenSearch (stacks Docker autogestionados, incluye instancias dedicadas por producto); Logstash (pipelines de transformación e ingesta de eventos, plugin Azure Event Hubs); Zabbix (diseño de integraciones custom vía UserParameter/items dependientes con JSONPath preprocessing, scripting Bash/Python de healthchecks para servicios sin monitoreo nativo — ej. integraciones de facturación electrónica); Azure Application Insights; AWS CloudWatch; Grafana |
| **Seguridad / Identidad** | Azure AD Domain Services; Auth0 (identidad multi-tenant SaaS); Keycloak (IAM self-hosted, clustering); Key Vault y Managed Identities; automatización de certificados (ACME / DNS-01, win-acme, Let's Encrypt/certbot) |
| **Mensajería / Integración** | AWS SQS (FIFO, dead-letter queues); Azure Service Bus; Azure Event Hubs |
| **Servidores web / Balanceo** | IIS (Windows); nginx (reverse proxy, terminación SSL, balanceo de carga) |
| **Contenedores** | Docker / Docker Compose (orquestación multi-contenedor, clustering de aplicaciones stateful) |

## Requisitos excluyentes

- Experiencia comprobada troubleshooteando sistemas distribuidos en producción (no solo en ambientes de desarrollo/QA).
- Azure nivel avanzado: App Services, redes (NSG/Application Gateway), Key Vault, Azure Monitor.
- AWS nivel intermedio/avanzado: IAM, S3, Lambda, SQS, EC2/Security Groups, ECS/Fargate, ALB/NLB, CloudWatch.
- Capacidad de diagnosticar problemas de red en ambos clouds (NSG/WAF en Azure, Security Groups/ALB-NLB en AWS) como parte de causa raíz, no solo de administrar recursos de red ya funcionando.
- PowerShell y Bash avanzado; Python intermedio.
- SQL avanzado sobre SQL Server; valorable experiencia con MongoDB.
- Administración de Windows Server + IIS y de Linux sobre contenedores Docker.
- Experiencia con al menos una herramienta de observabilidad tipo Graylog/ELK/OpenSearch o equivalente, y con Zabbix o un sistema de monitoreo de infraestructura similar.
- Terraform u otra herramienta de infraestructura como código.
- Capacidad de leer (no necesariamente escribir) código de aplicación para diagnóstico de causa raíz.
- Experiencia real como DBA sobre más de un motor (SQL Server y al menos uno entre MongoDB Atlas / CosmosDB) — investigación de eventos, optimización de queries y mantenimiento periódico de índices, no solo consultas puntuales.

## Requisitos deseables

- Experiencia con arquitecturas SaaS multi-tenant.
- CosmosDB y sistemas de identidad multi-tenant (Auth0, Keycloak o similar).
- Kerberos / Active Directory / Azure AD Domain Services.
- GitHub Actions y SonarQube.
- Experiencia operando PostgreSQL con replicación, o administrando servicios basados en JVM (Graylog, OpenSearch, Keycloak).
- Certificaciones: Azure (AZ-104, AZ-400) o AWS (SysOps Administrator, DevOps Engineer).

## Seniority sugerido

Semi-senior a Senior — el rol requiere autonomía para investigar sin supervisión directa y buen criterio para escalar a desarrollo cuando corresponde. Es un perfil de SRE con profundidad real de DBA (no un DBA puro ni un generalista superficial): la investigación de causa raíz frecuentemente termina dentro de la base de datos (SQL Server, MongoDB Atlas, CosmosDB), no solo en la capa de infraestructura o aplicación.
