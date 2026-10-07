# [SP] Propuesta checkUTC

**Tags:** `SmartPedidos`, `SRE`

## Resumen

El Concentrador de SmartPedidos envía en producción el correo "Concentrador: informacion cambios UTC en entorno production" cada vez que su chequeo de zonas horarias detecta una diferencia entre el UTC configurado por país y el que devuelve una API externa (`timezonedb`). Se observaron avisos que parecen no corresponder a un cambio real (por ejemplo, Chile con -4 según la API y -3 configurado, cuando la base de zonas horarias IANA da -3 a la fecha de la revisión), y el chequeo depende de un servicio externo y de una clave de API escrita en el código. Se revisó el código del chequeo, los logs de Graylog de los últimos 30 días y los datos de zonas horarias de Node. Se propone reemplazar la consulta a la API por el cálculo local del UTC esperado con la base IANA que trae Node, manteniendo la comparación, la frecuencia y el correo. El cambio todavía no está implementado.

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2194](https://smartit-ar.atlassian.net/browse/GITIN-2194) |
| ID alerta | Concentrador: informacion cambios UTC en entorno production |
| Sistema | Concentrador (SmartPedidos), producción |
| Severidad | Por definir |
| Detectado | 2026-10-07 |
| Resuelto | Pendiente: propuesta elaborada, cambio sin implementar |
| Responsable | SRE — Operaciones |

## Causa raíz

NA

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | El chequeo (`checkUTC`) compara el `tzo` de cada país guardado en MongoDB con el `gmtOffset` que devuelve `timezonedb` para cinco zonas (Argentina, Perú, Uruguay, Paraguay, Chile) y envía un correo por SendGrid si difieren. El `tzo` se usa además para convertir a UTC los horarios de apertura/cierre de sucursales. | Bajo |
| H2 | Se ejecuta solo en producción, con un cron diario a las 07:00 UTC y también una vez al iniciar el servicio. | Bajo |
| H3 | En Graylog (2026-09-08 a 2026-10-07) hay 43 registros "Ejecución de checkUTC" del Concentrador: 24 programados y 19 de arranque. Los de arranque se concentran alrededor de las 06:3x UTC, aproximadamente cada dos días, y algunos alrededor de las 12:xx UTC, lo que indica reinicios frecuentes del servicio (causa sin investigar). | Medio |
| H4 | La ejecución programada de las 07:00 UTC no aparece en 6 días (2026-09-13, 09-25, 09-27, 09-29, 10-03 y 10-05), que solo tienen ejecución de arranque. Causa no determinada; una posibilidad es que el cron se registre recién al ejecutarse una ruta de código concreta (`syncCheckUTC` se llama desde `branch.js`), sin verificar. | Medio |
| H5 | No hay días con dos ejecuciones programadas, pero Graylog muestra un único origen (`aws-kinesis-raw-logs`) y no permite distinguir tareas, por lo que no se puede confirmar ni descartar que varias tareas registren el cron. | Bajo |
| H6 | La búsqueda por `timezonedb` devuelve exactamente los mismos 43 registros: no hay líneas "Error al consultar API timezonedb" en la ventana revisada. Se infiere que las fallas de la API no explican los correos de ese período; el registro de esas líneas usa la misma vía que el de las ejecuciones, sin verificarlo por separado. | Bajo |
| H7 | Por el código, un fallo de la API agrega una fila "ERROR" y envía correo; una respuesta sin zonas genera `NaN` (nunca igual al valor guardado) o una excepción que envía un segundo correo. Son caminos posibles de aviso sin diferencia real; no se observaron en los logs del período. | Bajo |
| H8 | La base de zonas horarias de la imagen de producción (`node:20.20-alpine`, Node 20.20.2) es la versión 2025c, que incluye el cambio de Paraguay a UTC-3 permanente. Con la base local de 2023c, Chile da -3 el 2026-10-07 (coincide con lo configurado). Los datos cambian solo al reconstruir la imagen con una versión de Node más nueva. | Bajo |
| H9 | NTP no aplica a este chequeo: una respuesta NTP trae solo la hora UTC, no la zona horaria ni las reglas de horario de un país. Un contenedor usa el reloj del host y no puede ejecutar NTP propio. | Bajo |
| H10 | La clave de la API de `timezonedb` está escrita en el código fuente de `checkUTC.js` (valor no reproducido aquí). | Alto |

## Recursos afectados

| Recurso | Detalle |
|---|---|
| Concentrador (producción) | `api/src/utils/checkUTC.js`, cron en `controllers/branch.js`, llamada de arranque en `index.js` |
| `timezonedb` (API externa) | Fuente del UTC con la que se compara hoy |
| SendGrid | Envío del correo de aviso |
| MongoDB, colección de países | Valor `tzo` configurado por país |
| Graylog (SmartPedidos/SmartLoyalty) | Fuente de los registros revisados |

## Comandos ejecutados

Detalle en `scripts.sh`; salidas en `data/`. Todos son de solo lectura.

| # | Comando / Script | Propósito |
|---|---|---|
| C1 | Offsets por zona IANA con Node local y versión de tzdata | Obtener el UTC esperado por zona |
| C2 | Versión de Node y tzdata de la imagen de producción | Verificar los datos de zonas horarias disponibles |
| C3 | `GET /api/system` de Graylog con token | Comprobar acceso a la API |
| C4 | Búsqueda en Graylog de 30 días por `checkUTC` | Contar ejecuciones del chequeo |
| C5 | Búsqueda en Graylog de 30 días por `timezonedb` | Buscar errores de la API externa |
| C6 | Resumen local de C4 y C5 | Contar ejecuciones por tipo y por día |

## Código actual

`api/src/utils/checkUTC.js` (recortado a Argentina; Perú, Uruguay, Paraguay y Chile repiten el mismo bloque). La clave de la API se reemplazó por un marcador.

```js
let keytzo = "<API_KEY>"
let countryAPIAr;
try {
    countryAPIAr = await httpClient.get(`https://api.timezonedb.com/v2.1/list-time-zone?key=${keytzo}&format=json&by=zone&zone=America/Argentina/Buenos_Aires`);
} catch (error) {
    Log.saveError(error, { message: 'Error al consultar API timezonedb Argentina', ... });
    countriesToChange.push("Argentina")
    countriesToSend += `<tr><td>Argentina</td><td>${countriesUTC.find(r => r.country === "Argentina").tzo}</td><td>ERROR</td></tr>`
}
await delay(2000);   // espera entre consultas (se repite por país)

if (!countriesToChange.some(r => r === "Argentina") &&
    countriesUTC.find(r => r.country === "Argentina").tzo !== (countryAPIAr?.data?.zones[0]?.gmtOffset / 3600).toString())
    countriesToSend += `<tr><td>Argentina</td><td>${countriesUTC.find(r => r.country === "Argentina").tzo}</td><td>${(countryAPIAr?.data?.zones[0]?.gmtOffset / 3600).toString()}</td></tr>`
```

## Código propuesto

Mismo archivo, sin consulta externa, sin clave y sin esperas. El UTC esperado sale de la base IANA de Node (`Intl.DateTimeFormat`, `timeZoneName: 'longOffset'`, Node 18 o superior; la imagen usa Node 20). Es un borrador: no se ejecutó ni se probó, y todavía no está aplicado en el repositorio.

```js
import Log from './log';
import countryModel from '../models/country';
import settings from '../config/settings';
const sgMail = require('@sendgrid/mail');

// País -> zona IANA. Mismos cinco países que hoy.
const ZONES = {
  'Argentina': 'America/Argentina/Buenos_Aires',
  'Perú': 'America/Lima',
  'Uruguay': 'America/Montevideo',
  'Paraguay': 'America/Asuncion',
  'Chile': 'America/Santiago'
};

// Offset actual en horas (p. ej. -3, -4, 5.5) según la base IANA que trae Node.
function currentOffsetHours(timeZone, date = new Date()) {
  const part = new Intl.DateTimeFormat('en-US', { timeZone, timeZoneName: 'longOffset' })
    .formatToParts(date)
    .find(p => p.type === 'timeZoneName').value;          // "GMT-03:00" o "GMT"
  const m = part.match(/GMT(?:([+-])(\d{2}):(\d{2}))?/);
  if (!m || !m[1]) return 0;
  return (m[1] === '-' ? -1 : 1) * (parseInt(m[2], 10) + parseInt(m[3], 10) / 60);
}

class checkUTC {
  static async checkUTC(ejecution) {
    Log.saveError(null, { message: 'Ejecución de checkUTC', ejecution, platform: 'tzdata' });
    try {
      const countries = await countryModel.find({});
      let rows = '';
      for (const [country, zone] of Object.entries(ZONES)) {
        const stored = countries.find(c => c.country === country);
        const expected = currentOffsetHours(zone);
        if (!stored) {
          rows += `<tr><td>${country}</td><td>sin registro</td><td>${expected}</td></tr>`;
        } else if (parseFloat(stored.tzo) !== expected) {
          rows += `<tr><td>${country}</td><td>${stored.tzo}</td><td>${expected}</td></tr>`;
        }
      }
      if (rows.length > 0) {
        sgMail.setApiKey(settings.SENDGRID_API_KEY);
        const msg = {
          to: settings.mail,
          from: 'info@smartfran.com',
          subject: `Concentrador: informacion cambios UTC en entorno ${process.env.NODE_ENV}`,
          text: 'Informacion cambios UTC',
          html: `Se detectaron diferencias entre el UTC registrado en SmartPedidos y la base de zonas horarias (IANA)
                 <table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse; width: 100%;">
                   <tr style="background-color: #f2f2f2;"><th>País</th><th>SmartPedidos</th><th>IANA</th></tr>
                   ${rows}
                 </table>`
        };
        sgMail.send(msg).then(() => {}, error =>
          Log.saveError(error, { category: 'INFRA', message: '[INFRA/ERROR] sendgrid_send failed', platform: 'SendGrid' }));
      }
    } catch (err) {
      // Solo falla si Mongo o SendGrid fallan; se registra, sin enviar un segundo correo.
      Log.saveError(err, { category: 'INFRA', message: '[INFRA/ERROR] checkUTC failed', platform: 'tzdata' });
    }
  }
}

module.exports = checkUTC;
```

Cambios respecto del código actual: se elimina la consulta a `timezonedb`, la clave, las cinco esperas de 2 s, las filas "ERROR" por fallo de la API y el segundo correo "Error al actualizar zonas horarias". Se mantienen el cron, la comparación contra el valor configurado, el destinatario y el formato del correo. El resultado depende de la versión de zonas horarias que trae Node en la imagen (hoy 2025c).

## Acciones propuestas

1. (Dev) Reemplazar en `checkUTC.js` la consulta a `timezonedb` por el cálculo local del UTC esperado con la base IANA de Node (`Intl`), según el código propuesto de este ticket, manteniendo la comparación contra el valor configurado, el cron y el correo. Pendiente: el cambio no está implementado.
2. (SRE) Definir con el equipo si se mantiene la ejecución del chequeo al iniciar el servicio en producción.
3. (SRE) Confirmar la fecha del correo de Chile (-3 vs -4) para clasificarlo como valor erróneo o desactualizado de la API, o como cambio de horario legítimo.
4. (SRE) Investigar los reinicios frecuentes del Concentrador y los 6 días sin ejecución programada, y verificar si más de una tarea registra el cron.
5. (SRE) Retirar la clave de `timezonedb` del código una vez reemplazada la consulta, y evaluar con el barrido de credenciales en curso si corresponde revocarla.
6. (SRE) Al reconstruir la imagen, verificar la versión de tzdata para que incluya los cambios de reglas de horario vigentes.
