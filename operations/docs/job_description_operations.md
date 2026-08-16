# Job Description — Operations Engineer

> Origen: ticket `GITIN-1820`. Documentos hermanos: `job_description_completa.md` (versión combinada Operations + SRE + DevOps, con nota explicativa comparando los tres roles), `job_description_sre.md` (versión acotada a SRE) y `job_description_devops.md` (versión acotada a DevOps). Este documento aísla la parte del trabajo real que es específicamente **Operations** — mantenimiento programado y operación diaria de la plataforma ya desplegada — separada de la investigación de incidentes y del diseño de pipelines/IaC.

## Resumen del puesto

Responsable de que los sistemas de infraestructura que soportan la plataforma SmartFran (SmartLoyalty, SmartFran Cloud, SmartPedidos) sigan funcionando, actualizados y seguros día a día: renovación de certificados, rotación coordinada de credenciales, mantenimiento de pipelines ya existentes, configuración de monitoreo, y administración de la capa de red en Azure y AWS.

El disparador del trabajo es mayormente programado (renovaciones, mantenimientos, altas de ambiente), no reactivo a un incidente — aunque el rol incluye diagnóstico activo cuando algo programado falla (ej. una regla de red rota, un chequeo custom que deja de reportar).

## Responsabilidades principales

- Ejecutar y documentar procedimientos coordinados de mantenimiento sobre flotas de servidores (ej. rotación de credenciales compartidas sin causar bloqueos ni cortes de servicio).
- Automatizar la renovación de certificados SSL/TLS (ACME, DNS-01, integración con Key Vault y Application Gateway) para eliminar cargas manuales recurrentes.
- Administrar y mantener pipelines de CI/CD (GitHub Actions, Jenkins) y herramientas de calidad de código (SonarQube).
- Diseñar — no solo configurar — soluciones de monitoreo y telemetría a medida para servicios críticos sin healthcheck nativo (ej. integraciones de facturación electrónica): arquitectura completa de script custom (Bash/Python) → UserParameter/items dependientes en Zabbix → triggers con macros → ruteo de alertas, para dependencias externas o de cumplimiento normativo donde un fallo silencioso tiene impacto de negocio directo.
- Gestionar y resolver problemas de red en ambos clouds: en Azure, DNS, redes virtuales (VNet), reglas de NSG (auditoría periódica y limpieza) y Application Gateway; en AWS, Security Groups de EC2 y ruteo/reglas de listener de ALB/NLB; balanceadores de carga self-hosted (nginx como reverse proxy/terminación SSL/balanceo). Incluye diagnóstico activo — no solo configuración — de conectividad rota y reglas conflictivas.
- Operar stacks self-hosted en Docker Compose, incluyendo servicios stateful en cluster (bases de datos con replicación primary/replica, aplicaciones con cache distribuido).
- Analizar y optimizar costos de infraestructura cloud (sizing de VMs, reserva de instancias, retención de datos) a partir de billing real, no de estimaciones de lista de precios.
- Mantener actualizada la documentación de infraestructura (inventario de servidores, topología de red, cuentas de servicio) a medida que cambia.

## Stack tecnológico

| Categoría | Tecnologías |
|---|---|
| **Cloud** | Microsoft Azure (App Services Windows/Linux, Application Gateway/WAF, VNet, NSG — incl. auditoría y limpieza periódica de reglas, Key Vault, App Configuration, Azure DNS); AWS (EC2 incl. Security Groups, ALB/NLB — target groups, listener rules, ruteo, S3, CloudWatch) |
| **Bases de datos** | Mantenimiento operativo: backups, actualizaciones de versión, altas de instancia (SQL Server, MongoDB Atlas, CosmosDB, PostgreSQL) — no investigación de causa raíz ni tuning activo |
| **Lenguajes / Scripting** | PowerShell (avanzado); Bash (avanzado); Python (intermedio, automatización de tareas programadas y healthchecks custom) |
| **Sistemas operativos** | Windows Server (IIS, Active Directory / Azure AD DS, Kerberos, PowerShell remoting); Linux (Ubuntu, administración de servidores y contenedores Docker) |
| **CI/CD** | GitHub Actions, Jenkins (mantenimiento de pipelines ya existentes, no diseño desde cero); SonarQube |
| **Observabilidad / Monitoreo** | Zabbix (v4, v5 y 6 — diseño de integraciones custom vía UserParameter/items dependientes con JSONPath preprocessing, scripting Bash/Python de healthchecks para servicios sin monitoreo nativo); configuración de chequeos y alertas sobre el stack de observabilidad ya diseñado (Graylog, Azure Monitor, CloudWatch) |
| **Seguridad / Identidad** | Rotación coordinada de credenciales; automatización de certificados (ACME/DNS-01, win-acme, Let's Encrypt/certbot); Key Vault y Managed Identities; Service Principals |
| **Servidores web / Balanceo** | IIS (Windows); nginx (reverse proxy, terminación SSL, balanceo de carga) |
| **Contenedores** | Docker / Docker Compose (operación día a día de stacks self-hosted: Graylog, OpenSearch, Zabbix, clusters de aplicaciones con cache distribuido) |

## Requisitos excluyentes

- Experiencia operando infraestructura de producción en un entorno de alta disponibilidad, con foco en mantenimiento programado sin errores (no solo investigación de incidentes).
- Azure nivel avanzado (App Services, redes/VNet/NSG, Key Vault) y AWS nivel intermedio (EC2/Security Groups, ALB/NLB, S3, CloudWatch).
- PowerShell y Bash avanzado; Python intermedio.
- Administración de Windows Server + IIS y de Linux con Docker.
- Experiencia diseñando integraciones custom de monitoreo (Zabbix UserParameter o equivalente) para servicios sin healthcheck nativo, no solo consumiendo templates ya armados.
- Criterio de seguridad operativa: manejo de credenciales y secretos sin exponerlos, coordinación de cambios sensibles con ventanas de mantenimiento.

## Requisitos deseables

- Experiencia con al menos una herramienta de CI/CD (GitHub Actions o Jenkins).
- Kerberos / Active Directory / Azure AD Domain Services.
- SonarQube y prácticas de calidad de código.
- Certificaciones: Azure (AZ-104) o AWS (SysOps Administrator).

## Seniority sugerido

Semi-senior. El rol requiere autonomía para ejecutar mantenimiento programado sin errores en producción y buen criterio para escalar cuando algo excede el alcance de una tarea programada — no requiere el nivel de investigación de causa raíz cruzada que sí exige el perfil SRE.
