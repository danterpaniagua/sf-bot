# Alta de backOffice en el pipeline Jenkins SF-Pedidos

**Tags:** SmartPedidos, Jenkins

## Resumen

Se incorpora `dev-src-smartPedidos-backOffice` a la estructura de Jenkins de SF-Pedidos, siguiendo el patrón de Concentrador y Platform (`sf-devops/jenkins/SF-PEDIDOS/`), con las adaptaciones necesarias dado que backOffice es una SPA Angular que despliega a S3/CloudFront y no a ECS/Fargate: sin etapa de Docker Build, y con Trivy operando como escaneo de filesystem (`trivy fs`) en lugar de escaneo de imagen.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2023 |
| Sistema | Jenkins — carpeta SF-Pedidos |
| Servicio | backOffice |
| Rama | develop |
| Agente | sonarqube-srv |
| Estado | Reportado como funcionando (Jenkinsfile, Sonar, Trivy); sin log de build exitoso capturado como evidencia |

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El `Jenkinsfile` propio del repositorio (raíz, rama `develop`) tiene marcadores de conflicto de merge sin resolver comprometidos (`<<<<<<< HEAD` / `>>>>>>> master`) | Medio |
| H2 | El primer intento de ejecución en Jenkins corría un borrador con rutas `api/` inexistentes en backOffice y `SONAR_CRED_ID` apuntando al project key en lugar del credential ID — build falló en la etapa NPM install | Alto |
| H3 | El log de build muestra la carga de la librería compartida `customScripts` desde la carpeta SF-LOYALTY en lugar de SF-PEDIDOS — pendiente confirmar si el override a nivel de carpeta está correctamente configurado | Bajo |

## Acciones realizadas

1. (SRE) Creación de `jenkins/SF-PEDIDOS/jenkinsfiles/develop/dev-src-pedidos-backoffice.jenkinsfile`, basado en la plantilla de Concentrador, sin etapa de Docker Build, con rutas apuntando a `app/`.
2. (SRE) Generación de un token de `GenericTrigger` propio y único para el webhook de backOffice.
3. (SRE) Ajuste de la etapa Trivy a `trivy fs` contra `./app` (scanners `vuln,secret`, severidad CRITICAL/HIGH), dado que no se construye imagen Docker.
4. (SRE) Corrección de la configuración del job en Jenkins para apuntar al archivo correcto, tras el fallo del primer intento (H2).

## Acciones propuestas

1. (SRE) Configurar el token de `GenericTrigger` generado como secreto del webhook de GitHub en `dev-src-smartPedidos-backOffice`.
2. (SRE) Confirmar si el override de la librería compartida a nivel de carpeta SF-PEDIDOS está correctamente aplicado (H3).
3. (SRE) Capturar un log de build exitoso como evidencia del estado reportado como funcionando.

## Hallazgos secundarios

- `app/Dockerfile` fija `node:10-alpine`, incompatible con Angular ~21.2.7 (requiere Node ~20.19+/22.12+). No bloqueante para este pipeline (no se construye imagen), pero a corregir si el Dockerfile se reutiliza en el futuro.
