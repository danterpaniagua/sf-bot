# Alta del proyecto SonarQube para backOffice

**Tags:** SmartPedidos, SonarQube

## Resumen

Se crea el proyecto SonarQube `DEVELOP.SmartPedidos.BackOffice` (tipo JS/TS & Web) para habilitar el análisis estático de calidad de `dev-src-smartPedidos-backOffice` dentro del pipeline de Jenkins (GITIN-2023), reutilizando la credencial compartida `Sonarqube.TEST.Pedidos` ya usada por Concentrador y Platform.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | GITIN-2024 |
| Sistema | SonarQube |
| Proyecto | `DEVELOP.SmartPedidos.BackOffice` |
| Tipo de proyecto | JS/TS & Web |
| Credencial Jenkins | `Sonarqube.TEST.Pedidos` (compartida) |
| Estado | Reportado como funcionando (Quality Gate en verde); sin log de build exitoso capturado como evidencia |

## Acciones realizadas

1. Creación del proyecto SonarQube `DEVELOP.SmartPedidos.BackOffice`, tipo JS/TS & Web.
2. Verificación de que el project key coincide con la variable `SONAR_POJECT_NAME` del jenkinsfile de GITIN-2023.

## Acciones propuestas

1. (SRE) Capturar un log de build exitoso como evidencia del estado del Quality Gate reportado.

Ver GITIN-2023 para el detalle completo del pipeline de Jenkins que consume este proyecto.
