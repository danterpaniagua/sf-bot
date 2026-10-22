# Guía para QA y responsables de despliegue: escenarios web de Zabbix

Qué comprueba Zabbix de forma automática después de un despliegue, qué escenario mirar según lo que se desplegó y qué queda fuera y hay que verificar a mano.

**Fuente:** configuración leída de Zabbix el 2026-10-19 a las 10:16 (UTC-3): 16 escenarios, 37 pasos. Los escenarios cambian (entre el 2026-10-15 y el 2026-10-19 cambiaron al menos dos), así que conviene volver a leerlos antes de apoyarse en el número de pasos.

## Cómo usarlo después de un despliegue

1. Terminar el despliegue y esperar al menos un intervalo completo: **1 minuto**, o **30 segundos** en MobileApp. Una falla registrada mientras el servicio se reiniciaba es esperable y se borra en la corrida siguiente.
2. En Zabbix, abrir el escenario del componente desplegado (tabla de abajo) y verificar que esté en verde.
3. Si falla, anotar **en qué paso** falla (columna `#` de cada tabla) y el texto del error. El paso indica la capa:
   - Falla el primer paso (página o healthcheck): el servicio no responde.
   - Falla un paso posterior con el primero en verde: responde, pero falla la aplicación o lo que ella consulta.
4. Cada paso espera como máximo **15 segundos**; un "timed out" significa que no llegó respuesta en ese tiempo.

**Qué considera "correcto" Zabbix:** respuesta HTTP 200 en todos los pasos y, en 7 de los 37 pasos, además un texto que debe aparecer en la respuesta. Nada más.

**Limitaciones que conviene tener presentes**
- **No se valida el certificado SSL** en ninguno de los 16 escenarios. Un certificado vencido, equivocado o no confiable no hace fallar estas pruebas; el vencimiento de certificados tiene alertas propias.
- **Casi todo es solo "está vivo"** (código 200 sin comprobar el contenido). Un 200 no demuestra que el contenido sea el correcto.
- **El healthcheck del WebService devuelve 400 cuando el servidor está muy cargado** (una muestra de CPU o de memoria comprometida por encima de 80). Un 400 justo después de un despliegue puede ser carga y no el despliegue; ver [GITIN-2250](https://smartit-ar.atlassian.net/browse/GITIN-2250). El último error del escenario `API POS / Gestion` fue un 400.
- Los escenarios usan el **nombre público** de cada servicio, por lo que no indican cuál de los servidores respondió.

## Qué escenario mirar según lo desplegado

| Se desplegó | Escenario | Qué comprueba | Qué NO comprueba (verificar a mano) |
|---|---|---|---|
| Servicio Mobile | `[PROD] MobileApp` | healthcheck, inicio de sesión de la cuenta de monitoreo y una consulta de información adicional que debe devolver `Ok` | otros endpoints y otras cuentas; no distingue entre los servidores Mobile |
| Sitio de gestión (Website) | `[PROD] Website` | que la página de inicio de sesión responda 200 | que alguien pueda iniciar sesión (el único paso no envía credenciales) |
| Clubsite Argentina | `[PROD] Clubsite AR` | la página de inicio y la consulta de beneficios (el texto `Promotion` debe aparecer) | inicio de sesión y canjes |
| Clubsite Paraguay | `[PROD] Clubsite PY` | igual que Argentina | inicio de sesión y canjes |
| WebService (API del POS y gestión) | `[PROD] API POS / Gestion` | healthcheck y que la descripción del servicio (`?wsdl`) responda 200 | una llamada real al servicio; el contenido de la descripción no se verifica |
| WebServiceV2 | `[PROD] WebServiceV2` | healthcheck | cualquier llamada a la API |
| Facturasend | `[PROD ] Facturasend APP` | página de autenticación, una llamada autenticada a la API que devuelve `FacturaSend Funciona.` y que el inicio de sesión sea el de Keycloak | que se pueda emitir una factura |
| Test02 (todo el ambiente) | `Loyalty Test02` | 7 páginas responden 200 (ver abajo) | contenido y llamadas reales |
| PreProd (todo el ambiente) | `Loyalty PreProd` | 8 páginas responden 200 (ver abajo) | contenido y llamadas reales |
| SonarQube | `Sonarqube` (dos escenarios) | página de inicio de sesión; en el otro escenario, la página de inicio con el texto `SonarQube` y el envío del inicio de sesión | que el inicio de sesión funcione (ese paso no tiene código esperado) |
| Jenkins | `Jenkins` | página de inicio de sesión | inicio de sesión |

Los escenarios `[PROD] Clubsite AR Local` y `PY Local` piden la misma dirección pública desde cada servidor del Clubsite (CLUB-01 y CLUB-02): sirven para ver si cada servidor ve el sitio público.

## Detalle de pasos de los escenarios de producción

**`[PROD] MobileApp`** (cada 30 s)

| # | Paso | Resultado esperado |
|---|---|---|
| 1 | healthcheck | 200 |
| 2 | Inicio de sesión de la cuenta de monitoreo | 200 y el texto propio de esa cuenta en la respuesta |
| 3 | Consulta de información adicional | 200 y el texto `Ok` |

Es la prueba más completa de las de producción: un fallo en el paso 2 o 3 con el 1 en verde apunta a la aplicación o a sus datos, no a que el servicio esté caído.

**`[PROD] Website`**: 1. Página de inicio de sesión, 200.

**`[PROD] Clubsite AR` y `PY`**

| # | Paso | Resultado esperado |
|---|---|---|
| 1 | Página de inicio | 200 |
| 2 | Consulta de beneficios | 200 y el texto `Promotion` |

Los dos escenarios no son idénticos (Argentina sigue redirecciones en el paso 2 y usa el puerto 443 explícito; Paraguay no). No se comprobó si la diferencia es intencional.

**`[PROD] API POS / Gestion`**: 1. Healthcheck, 200. 2. Descripción del servicio (`?wsdl`), 200.

**`[PROD] WebServiceV2`**: 1. Healthcheck, 200.

**`[PROD ] Facturasend APP`** (el nombre tiene un espacio antes del corchete)

| # | Paso | Resultado esperado |
|---|---|---|
| 1 | Página de autenticación | 200 |
| 2 | Llamada autenticada a la API | 200 y `FacturaSend Funciona.` |
| 3 | Inicio de sesión | 200 y el texto `Keycloak` |

Los pasos se ejecutan en el orden de la columna `#`, no en el orden en que Zabbix los lista.

## Ambientes de prueba: qué páginas se piden

Todas esperan solo HTTP 200 (no se verifica contenido).

| Componente | Test02 | PreProd |
|---|---|---|
| Clubsite AR y PY | puerto 9443 | puerto por defecto |
| Website | página de inicio de sesión, 9443 | página principal, 4430 |
| Mobile (`/Help`, http) | 803 | 8081 |
| WebService (`/service/saleprovider.svc`, http) | 804 | 8080 |
| WebServiceV2 (página de Swagger) | 802 | 8082 |
| WebServiceCG (página de Swagger) | 805 | no está en el escenario |
| WebServiceV2 nodo 1 / nodo 2 | no está en el escenario | 8181 / 8182 |

Las direcciones de Swagger llevan un fragmento (`#!`) que el navegador conserva y la petición no envía: esos pasos solo piden la página de Swagger, no llaman a ninguna API.

## Qué falta cubrir (para QA)

- Inicio de sesión real en el sitio de gestión (Website).
- Llamadas reales al WebService y al WebServiceV2 (hoy solo healthcheck y descripción del servicio).
- Emisión de una factura de prueba en Facturasend.
- En Test02 y PreProd, todo lo que no sea que la página responda.
- Cualquier cambio de certificados, porque Zabbix no lo ve aquí.

Esta lista sale de lo que la configuración no comprueba; no es un procedimiento de prueba aprobado.
