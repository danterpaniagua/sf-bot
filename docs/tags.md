# Jira Tags Reference

**Rule for new tickets:** always add exactly one of the 5 project tags below — `Operaciones`, `SmartLoyalty`, `SmartCloud`, `SmartPedidos`, `SmartAnalitics`. Time is tracked by time-in-"In Progress", segmented by this tag. Other tags (tech, env, tool) are supplementary — they never substitute for the project tag, even when they imply a project on their own (e.g. `Concentrador` still needs `SmartPedidos` added alongside it).

## Project tags (primary — one required per ticket)

| Tag | Description |
|---|---|
| `Operaciones` | Operations Related issue |
| `SmartLoyalty` | SmartLoyalty Project |
| `SmartCloud` | SmartCloud Project |
| `SmartPedidos` | SmartPedidos Project |
| `SmartAnalitics` | SmartAnalitics project |

## Project-specific tags (imply a project — add the project tag too)

| Tag | Description | Project |
|---|---|---|
| `ClubSite` | SmartLoyalty ClubSite related issue | SmartLoyalty |
| `Fraude` | PuntosCG, SML-Puntos, queries in SQLServer, SMLDB | SmartLoyalty |
| `MobileAppService` | MobileAppService related issue | SmartLoyalty |
| `PuntosCG` | Related with Club Grido Points Assignment | SmartLoyalty |
| `Redis` | CG Redis Component | SmartLoyalty |
| `SML-Puntos` | Related with Club Grido Points Assignment | SmartLoyalty |
| `SMLDB` | Related with SmartLoyalty BD | SmartLoyalty |
| `SQLServer` | Related with SmartLoyalty BD | SmartLoyalty |
| `Sonarqube` | Sonarqube SmartLoyalty service | SmartLoyalty |
| `TaskOperator` | SmartLoyalty TaskOperator Project | SmartLoyalty |
| `WebSite` | SmartLoyalty WebSite project | SmartLoyalty |
| `WebserviceCG` | SmartLoyalty WebserviceCG Project | SmartLoyalty |
| `PUSH` | ClubGrido PUSH campaign | SmartLoyalty |
| `CloudPOS` | SmartCloud CloudPOS project related issue | SmartCloud |
| `Concentrador` | SmartPedidos Concentrador project related issue | SmartPedidos |
| `MongoDB` | SmartPedidos MongoDB related issue | SmartPedidos |
| `Platform` | SmartPedidos Platform service | SmartPedidos |

## Cross-cutting tags (span multiple projects — never sufficient alone)

| Tag | Description |
|---|---|
| `AWS` | AWS Cloud related issue |
| `Azure` | Azure Cloud related issue |
| `DEPLOY` | When on a deployment |
| `Graylog` | SmartPedidos, SmartLoyalty, SmartCloud Graylog related issue |
| `INFRADEVOPS` | Main label used to filter Infra DevOps board |
| `Jenkins` | Jenkins related issue — SmartLoyalty, SmartPedidos, SmartCloud pipelines/automations |
| `Obserbavilidad` | Observability — Graylog, Grafana, Zabbix, Azure Insights, AWS CloudWatch |
| `Performance` | Performance related issue |
| `SEGURIDAD` | Security related tag |
| `SRE` | SRE tasks |
| `Terraform` | Terraform automated solutions |

## Environment tags (never a substitute for the project tag)

| Tag | Description |
|---|---|
| `PREPRO` | SmartLoyalty PREPRO / Stg env related issue |
| `PROD` | PROD env related issue |
| `TEST02` | SmartLoyalty Test02 / QA environment |
