# [GITIN-2328](https://smartit-ar.atlassian.net/browse/GITIN-2328) — Entorno de desarrollo no inicia: valores del autorizador en App Configuration sin comillas

**Tags:** SmartCloud, Azure

## Qué pasó

- Un desarrollador no podía usar su entorno mientras trabajaba en la rama `feature/GSFC-1084-eliminar-lista-de-precios`.
- El error era `Newtonsoft.Json.JsonReaderException: 'Unexpected character encountered while parsing value: S. Path 'Platform', line 1, position 11.'`.
- El desarrollador indicó que el entorno funcionaba hasta el día anterior.

## Resumen

El entorno de desarrollo de un desarrollador no podía leer la configuración del autorizador porque los valores de las 5 claves `SmartFran.Cloud.<Módulo>.Authorization.Auth0` (Business, Catalog, Person, Sales y Site) de su App Configuration no eran JSON válido: habían perdido todas las comillas. Se detectó el 2026-10-27. Se comparó con el App Configuration compartido de DEV (`SmartFran-Cloud-Settings-DEV`), cuyas 5 claves son JSON válido, y se volvieron a copiar los valores desde ahí. Tras la corrección las 5 claves validan como JSON.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2328](https://smartit-ar.atlassian.net/browse/GITIN-2328) |
| ID alerta | NA |
| Sistema | SmartFran.Cloud, App Configuration del entorno de un desarrollador (copia de `SmartFran-Cloud-Settings-DEV`) |
| Severidad | Baja |
| Detectado | 2026-10-27 |
| Resuelto | 2026-10-27 (claves corregidas y validadas; que el entorno inicia lo informó el desarrollador, no se observó) |
| Responsable | SRE |

## Causa raíz

Los valores de las 5 claves de autorización del App Configuration del desarrollador tenían todos los nombres de propiedad y valores de texto sin comillas (empiezan con `{Platform:SmartFran.Cloud,Modu...`). El código lee la clave con `JsonConvert.DeserializeObject<AuthorizerSettings>`: Newtonsoft tolera el nombre de propiedad sin comillas, pero falla en el primer valor sin comillas (`S` de `SmartFran.Cloud`, posición 11), lo que coincide exactamente con el error reportado. El App Configuration compartido de DEV tiene las mismas 5 claves con JSON válido, por lo que las comillas se perdieron al copiar los valores al store del desarrollador. No se conoce el método de copia usado ni cuándo ocurrió (no se ejecutó la comparación de revisiones). No se identificaron ocurrencias anteriores del mismo síntoma.

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Las 5 claves `SmartFran.Cloud.{Business,Catalog,Person,Sales,Site}.Authorization.Auth0` del store del desarrollador no eran JSON válido (todas sin comillas; 5718, 5152, 1089, 2139 y 4619 caracteres) | Medio |
| H2 | Las mismas 5 claves del App Configuration compartido de DEV son JSON válido: el problema no afecta a otros usuarios de DEV | Bajo |
| H3 | La falla no está en el código de `main`: `AzureAppConfigurationRelationsService` no cambió desde 2023-11-01; la rama del desarrollador no estaba en el clon local y no se leyó | Bajo |
| H4 | La cuenta de SRE no tenía rol de datos sobre el store (`Forbidden`) y la lectura de claves con `--auth-mode key` falló inicialmente por un filtro de claves inválido en el script (el comodín `*` solo se acepta al final) | Bajo |
| H5 | Solo se revisaron las claves `Authorization`; otras claves del store podrían tener el mismo problema | Bajo |

## Acciones Tomadas

| # | Hora (UTC) | Acción |
|---|---|---|
| 1 | 2026-10-27 18:04 | Revisadas las claves de autorización del store del desarrollador (solo lectura, sin imprimir valores): las 5 inválidas |
| 2 | 2026-10-27 18:08 | Revisadas las mismas claves en el App Configuration compartido de DEV: las 5 válidas |
| 3 | 2026-10-27 | Actualizado el rol gestionado con permisos sobre el store y copiados de nuevo los valores desde el App Configuration compartido de DEV |
| 4 | 2026-10-27 18:52 | Revisadas de nuevo las 5 claves del store del desarrollador: las 5 válidas |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| App Configuration del entorno de un desarrollador | Copia de `SmartFran-Cloud-Settings-DEV`; 5 claves `Authorization.Auth0` corregidas |
| `SmartFran-Cloud-Settings-DEV` | Origen de la copia; sin cambios (solo lectura) |

## Acciones propuestas

| # | Responsable | Acción | Estado |
|---|---|---|---|
| 1 | SRE | Confirmar con el desarrollador que el entorno inicia (informado como resuelto) | Pendiente |
| 2 | SRE | Revisar el resto de las claves del store del desarrollador por el mismo problema de comillas (solo se revisaron las `Authorization`) | Pendiente |
| 3 | SRE | Determinar cómo se copió el store (Portal, `az appconfig kv import/copy` o script) y copiar siempre desde un archivo o con una herramienta que conserve el JSON, ya que pasar JSON en línea por una shell es la forma típica de perder las comillas | Por decidir |
| 4 | SRE | Registrar en la documentación de infraestructura de cloud que estas claves deben contener JSON válido, que el filtro de claves solo admite `*` al final y que leer valores requiere el rol de lector de datos o `--auth-mode key` | Pendiente |
