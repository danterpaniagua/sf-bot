Asunto: Acceso habilitado — Exportación diaria de datos SmartPedidos

Estimados,

Les confirmamos que el acceso a los datos exportados diariamente está listo para su consumo.

**Cómo acceder a los datos**

Los archivos se publican diariamente en:

```
https://smartpedidos-orders.s3.amazonaws.com/grido/{AAAA}/{MM}/news{AAAAMMDD}.json
```

Por ejemplo, el archivo correspondiente al 14 de septiembre de 2026 se encuentra en:

```
https://smartpedidos-orders.s3.amazonaws.com/grido/2026/09/news20260914.json
```

Cada archivo corresponde a un día completo y se publica de forma automática, sin necesidad de solicitarlo. El contenido y los campos incluidos corresponden exactamente al formato de ejemplo que ya intercambiamos previamente.

Actualmente hay datos disponibles desde el **1 de mayo de 2026 hasta el día de hoy**, sin días faltantes, y el histórico se actualiza automáticamente todos los días.

**Restricción de acceso**

El acceso está restringido a la IP que nos indicaron (`40.121.111.127`, runtime `IntegrationRuntimeComercial`). Cualquier consulta desde una IP distinta será rechazada. Si en el futuro necesitan habilitar otra IP o runtime adicional, avísennos y lo agregamos.

Quedamos atentos ante cualquier consulta o si detectan algún inconveniente al acceder a los datos.

Saludos,
Equipo SmartPedidos
