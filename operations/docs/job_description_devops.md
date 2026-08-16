# Job Description — DevOps Engineer

> Origen: ticket `GITIN-1820`. Documentos hermanos: `job_description_completa.md` (versión combinada Operations + SRE + DevOps, con nota explicativa comparando los tres roles), `job_description_operations.md` (versión acotada a Operations) y `job_description_sre.md` (versión acotada a SRE). Este documento aísla la parte del trabajo real que es específicamente **DevOps** — pipelines, infraestructura como código, contenedores y entornos — separada de la operación diaria y de la investigación de incidentes.

## Resumen del puesto

Responsable de cómo el código y la infraestructura de la plataforma SmartFran (SmartLoyalty, SmartFran Cloud, SmartPedidos) — y de proyectos adicionales con stack propio — llegan a producción de forma repetible, auditable y sin intervención manual: pipelines de CI/CD, infraestructura como código, contenedores, entornos de desarrollo/test reproducibles, y gates de calidad automatizados.

El rol no es de desarrollo activo de features, pero sí implica escribir y mantener automatización (Terraform, scripts de pipeline, Docker Compose) y, cuando corresponde, parches acotados sobre código de aplicación (ej. compliance de un estándar de logging) sin alterar reglas de negocio.

## Responsabilidades principales

- Diseñar, mantener y operar pipelines de CI/CD (GitHub Actions como principal; Jenkins como infraestructura legacy vigente, con Jenkinsfiles leídos directamente desde SCM, librería Groovy compartida y versionada por proyecto/stack — helpers PowerShell para .NET/Windows, `sh` para Node.js/Linux — y ejecución condicional de stages según los paths modificados) para despliegues a Azure App Service, AWS ECS Fargate y otros targets.
- Escribir y mantener infraestructura como código multi-cloud (Terraform / OpenTofu) — proveedor `azurerm` (VMs, redes, discos, Event Hubs) y proveedor `aws` (SQS, IAM, API Gateway, Lambda, Secrets Manager) — priorizando cambios reproducibles y auditables sobre configuración manual por consola.
- Definir y mantener entornos reproducibles de desarrollo/test vía Docker Compose para servicios internos (ej. levantar `platforms-service`/`concentrador-service` en local con variables de entorno y puertos consistentes con producción).
- Operar stacks self-hosted en contenedores, incluyendo servicios stateful en cluster (bases de datos con replicación primary/replica, aplicaciones con cache distribuido) y su ciclo de vida (upgrade, backup, troubleshooting de cluster).
- Integrar y mantener gates de calidad de código (SonarQube) y de seguridad de imágenes de contenedor (Trivy — vulnerabilidades CRITICAL/HIGH) en el pipeline, y estándares de logging estructurado con detección automatizable de violaciones (greps/reglas por axioma, no solo revisión manual).
- Integrar herramientas de IA generativa como stage automatizado dentro del pipeline de CI/CD (ej. CLI de un modelo de lenguaje invocada por Jenkins sobre el diff de cada PR) para reporte automatizado de bugs/vulnerabilidades y generación de changelog, gestionando el prompt y el template de salida como artefactos versionados del pipeline, no como uso manual ad-hoc.
- Gestionar configuración y secretos por ambiente (Azure Key Vault, App Configuration, AWS Secrets Manager, variables `.env` para entornos locales) evitando credenciales hardcodeadas o compartidas entre ambientes.
- Automatizar la renovación de certificados SSL/TLS (ACME, DNS-01, integración con Key Vault y Application Gateway) como parte del ciclo de vida de infraestructura, no como tarea manual recurrente.
- Definir y versionar el alcance de cambios de infraestructura/aplicación antes de implementarlos (control de scope, changelog por versión), para que cada cambio sea trazable a una necesidad concreta y no a un ajuste ad-hoc.
- Colaborar con desarrollo para que cambios de arquitectura (ej. separación de logging, particionado de datos) puedan expresarse como infraestructura/pipeline, no solo como código de aplicación — proponiendo la recomendación arquitectónica del lado de infraestructura/pipeline, no solo adaptándose a lo que desarrollo ya decidió.

## Stack tecnológico

| Categoría | Tecnologías |
|---|---|
| **CI/CD** | GitHub Actions (pipeline principal, despliegues a Azure App Service); Jenkins (infraestructura legacy vigente — Jenkinsfiles desde SCM, librería Groovy compartida `customScripts`, ejecución condicional por paths modificados, agentes Windows Server 2019 y Ubuntu); SonarQube y Trivy (gates de calidad y seguridad de imágenes de contenedor); integración de IA generativa como stage de pipeline (análisis automatizado de PR, generación de changelog) |
| **IaC** | Terraform / OpenTofu multi-cloud — proveedor `azurerm` (VMs, redes, discos, Event Hubs); proveedor `aws` (SQS, IAM, API Gateway, Lambda, Secrets Manager) |
| **Contenedores** | Docker / Docker Compose — stacks self-hosted en producción (Graylog, OpenSearch, Zabbix, clusters de aplicaciones con cache distribuido) y entornos locales de desarrollo/test para servicios Node.js/Express |
| **Cloud** | Microsoft Azure (App Services Windows/Linux, Application Gateway/WAF, NSG, Key Vault, App Configuration, Service Bus, Event Hubs, Azure Functions, Azure Container Instances, CosmosDB, Azure SQL Database, Azure DNS, Azure AD Domain Services); AWS (IAM, S3, Lambda, API Gateway, Secrets Manager, SQS FIFO/DLQ, ECS Fargate, ALB, CloudWatch) |
| **Gestión de configuración/secretos** | Azure Key Vault, App Configuration, Managed Identities, Service Principals; AWS Secrets Manager; variables de entorno `.env` para réplica local de configuración productiva |
| **Bases de datos (operación, no desarrollo)** | SQL Server; MongoDB / MongoDB Atlas; PostgreSQL (replicación streaming primary/replica); Azure SQL Database (pools elásticos); CosmosDB |
| **Lenguajes / Scripting** | PowerShell (avanzado); Bash (avanzado); Python (intermedio — `pymongo`, `boto3`, `pandas`); lectura y escritura de parches acotados en Node.js/Express y C#/.NET (compliance de logging, sin alterar reglas de negocio) |
| **Observabilidad como código** | Definición/integración de chequeos custom en Zabbix (UserParameters, triggers, macros); pipelines de ingesta Logstash (plugin Azure Event Hubs); provisión de dashboards/paneles (Grafana) |

## Requisitos excluyentes

- Experiencia manteniendo pipelines de CI/CD en producción (GitHub Actions o Jenkins), no solo consumiéndolos.
- Terraform u otra IaC con experiencia real en al menos dos proveedores cloud.
- Docker y Docker Compose — construcción de stacks multi-servicio, no solo ejecución de contenedores individuales.
- Azure nivel avanzado y AWS nivel intermedio/avanzado (los mismos servicios que Operations/SRE, con foco en cómo se provisionan, no solo cómo se operan).
- PowerShell y Bash avanzado; Python intermedio.
- Capacidad de leer y escribir cambios acotados en código de aplicación (Node.js o C#/.NET) sin necesidad de desarrollo activo de features.
- Criterio de seguridad operativa: gestión de secretos/configuración por ambiente sin exponerlos ni mezclarlos entre entornos.

## Requisitos deseables

- Experiencia integrando gates de calidad y seguridad de código en pipelines (SonarQube, escaneo de vulnerabilidades de imágenes de contenedor tipo Trivy).
- Experiencia integrando herramientas de IA generativa como stage automatizado dentro de un pipeline de CI/CD (ej. análisis de PR, generación de changelog), no solo como asistente de desarrollo.
- Experiencia definiendo estándares (logging, testing, scope de cambios) de forma que sean verificables automáticamente, no solo documentados.
- Experiencia con arquitecturas SaaS multi-tenant y sus implicancias de aislamiento por ambiente/tenant.
- Certificaciones: Azure (AZ-104, AZ-400) o AWS (SysOps Administrator, DevOps Engineer).

## Seniority sugerido

Semi-senior a Senior. El rol requiere autonomía para diseñar pipelines e infraestructura como código sin supervisión directa, y criterio para decidir qué automatizar primero según impacto y riesgo.
