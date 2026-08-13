# Job Description — Infrastructure Operations Engineer

> Origen: ticket `GITIN-1820`. Documentos hermanos: `job_description_completa.md` (versión combinada Operations + SRE + DevOps, con nota explicativa comparando los tres roles), `job_description_sre.md` (versión acotada a SRE) y `job_description_devops.md` (versión acotada a DevOps). Este documento aísla la parte del trabajo real que es específicamente **Operations** — mantenimiento programado, operación diaria de la plataforma y monitoreo — separada de la investigación de causa raíz y del diseño de pipelines/IaC.

## Resumen del puesto

Responsable de que la infraestructura que soporta la plataforma SmartFran (SmartLoyalty, SmartFran Cloud, SmartPedidos) — un ecosistema multi-tenant sobre Azure y AWS que da servicio a una red de franquicias en Argentina, Paraguay y otros países de Latinoamérica — siga funcionando, actualizada y segura día a día.

El rol combina mantenimiento programado (renovación de certificados, rotación de credenciales, actualizaciones coordinadas de flota) con operación continua de servicios self-hosted, monitoreo y pipelines de CI/CD ya existentes. No es un rol de investigación de causa raíz ni de diseño de infraestructura como código desde cero — cuando un problema excede mantenimiento/configuración, se escala a SRE o a desarrollo.

## Responsabilidades principales

- Ejecutar y documentar procedimientos coordinados de mantenimiento sobre flotas de servidores (ej. rotación de credenciales compartidas sin causar bloqueos ni cortes de servicio).
- Automatizar la renovación de certificados SSL/TLS (ACME, DNS-01, integración con Key Vault y Application Gateway) para eliminar cargas manuales recurrentes.
- Administrar y mantener pipelines de CI/CD (GitHub Actions, Jenkins) y herramientas de calidad de código (SonarQube) ya existentes.
- Diseñar soluciones de monitoreo y telemetría a medida para servicios críticos sin healthcheck nativo (ej. integraciones de facturación electrónica): script custom (Bash/Python) → UserParameter/items dependientes en Zabbix → triggers con macros → ruteo de alertas, para dependencias externas o de cumplimiento normativo donde un fallo silencioso tiene impacto de negocio directo.
- Gestionar recursos de red en ambos clouds: en Azure, DNS, VNet, reglas de NSG (auditoría periódica y limpieza) y Application Gateway; en AWS, Security Groups de EC2 y ruteo/reglas de listener de ALB/NLB; balanceadores de carga self-hosted (nginx como reverse proxy/terminación SSL/balanceo).
- Operar stacks self-hosted en Docker Compose, incluyendo servicios stateful en cluster (bases de datos con replicación primary/replica, aplicaciones con cache distribuido).
- Analizar y optimizar costos de infraestructura cloud (sizing de VMs, reserva de instancias, retención de datos) a partir de billing real, no de estimaciones de lista de precios.
- Mantener actualizada la documentación de infraestructura (inventario de servidores, topología de red, cuentas de servicio) a medida que cambia.

## Stack tecnológico

| Categoría | Tecnologías |
|---|---|
| **Cloud** | Microsoft Azure (App Services Windows/Linux, VNet, NSG — auditoría y limpieza periódica de reglas, Application Gateway, Key Vault, App Configuration, Azure DNS, Service Bus, Event Hubs, Azure AD Domain Services); AWS (EC2 incl. Security Groups, ALB/NLB, IAM, S3, Secrets Manager, SQS) |
| **Bases de datos (mantenimiento operativo)** | SQL Server (backups, mantenimiento programado de índices, SQL Agent); MongoDB / MongoDB Atlas (altas de instancia, mantenimiento); Azure SQL Database (pools elásticos multi-tenant); CosmosDB; PostgreSQL |
| **Lenguajes / Scripting** | PowerShell (avanzado); Bash (avanzado); Python (intermedio — automatización de tareas programadas); SQL básico/intermedio para mantenimiento operativo |
| **Sistemas operativos** | Windows Server (IIS, Active Directory / Azure AD Domain Services, Kerberos, PowerShell remoting); Linux (Ubuntu, administración de servidores y contenedores Docker) |
| **CI/CD** | GitHub Actions y Jenkins (mantenimiento de pipelines ya existentes); SonarQube |
| **Observabilidad / Monitoreo** | Zabbix (v4, v5 y 6 — diseño de integraciones custom vía UserParameter/items dependientes con JSONPath preprocessing, scripting Bash/Python de healthchecks para servicios sin monitoreo nativo); Graylog + OpenSearch (operación día a día del stack Docker autogestionado); Azure Monitor; AWS CloudWatch |
| **Seguridad / Identidad** | Azure AD Domain Services; Key Vault y Managed Identities; Service Principals; gestión de secretos (Azure Key Vault, AWS Secrets Manager); automatización ACME/DNS-01, win-acme, Let's Encrypt/certbot; rotación coordinada de credenciales compartidas |
| **Servidores web / Balanceo** | IIS (Windows); nginx (reverse proxy, terminación SSL, balanceo de carga) |
| **Contenedores** | Docker / Docker Compose — operación día a día de stacks self-hosted en producción (Graylog, OpenSearch, Zabbix, clusters de aplicaciones con cache distribuido) |

## Requisitos excluyentes

- Experiencia operando infraestructura de producción en alta disponibilidad, ejecutando mantenimientos programados sin generar cortes de servicio.
- Azure nivel avanzado (App Services, VNet/NSG, Key Vault, Application Gateway) y AWS nivel intermedio (EC2/Security Groups, ALB/NLB, IAM) — foco en administración y auditoría de recursos ya desplegados, no en diagnóstico de causa raíz.
- PowerShell y Bash avanzado; Python intermedio para automatización de tareas repetitivas.
- Administración de Windows Server + IIS y de Linux con Docker.
- Experiencia manteniendo pipelines de CI/CD ya existentes (GitHub Actions o Jenkins).
- Experiencia diseñando integraciones de monitoreo a medida para servicios sin healthcheck nativo (Zabbix + scripting Bash/Python).
- Criterio de seguridad operativa: rotación coordinada de credenciales y renovación de certificados sin exponer secretos ni causar bloqueos.
- Mantenimiento operativo de al menos un motor de base de datos productivo (backups, altas de instancia, actualizaciones, mantenimiento programado de índices).

## Requisitos deseables

- Experiencia con arquitecturas SaaS multi-tenant.
- Kerberos / Active Directory / Azure AD Domain Services.
- Análisis de costos de infraestructura cloud a partir de billing real.
- Certificaciones: Azure (AZ-104) o AWS (SysOps Administrator).

## Seniority sugerido

Semi-senior. El rol requiere autonomía para ejecutar mantenimiento programado sin errores sobre sistemas productivos, y buen criterio para escalar a SRE o desarrollo cuando un problema excede el alcance de operación y mantenimiento (causa raíz de un incidente, cambios de arquitectura, diseño de infraestructura como código desde cero).
