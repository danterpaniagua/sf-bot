# GITIN-2201 — [CLOUD] Evaluar proveedor de envío de correos

**Etiquetas:** `SmartCloud`, `Azure`, `AWS`

## Resumen

Se evaluó el reemplazo de SendGrid para enviar por correo los comprobantes de venta a los clientes. El volumen informado es de 72.360.308 ventas entre el 01-01 y el 07-10-2026 (11.799.070 solo en enero) y cada venta representará un correo: unos 258 mil por día en promedio (alrededor de 7,9 millones por cada 30 días) y hasta 380 mil por día en enero (unos 4,4 por segundo en promedio); se toma 11,8 millones de correos por mes como cifra de planificación. A precios de lista (tomados de búsquedas web, sin verificar en las páginas de cada proveedor), Amazon SES sale alrededor de USD 1.180 por mes, Azure Communication Services Email alrededor de USD 2.950, Postmark alrededor de USD 2.900, Mailgun alrededor de USD 9.400 y Brevo no publica precio a este volumen. Hoy el comprobante de cada venta solo se imprime en el POS (informado), por lo que el envío por correo sería un flujo nuevo; la aplicación envía otros correos (por ejemplo el cierre de turno) por una interfaz con una única implementación (SendGrid), por lo que cambiar de proveedor es acotado; lo que falta para operar a este volumen no depende del proveedor: cola con reintentos, manejo de rebotes y quejas, y IP Warm-Up (IP y dominio). Con comprobantes adjuntos de 50 KB o de 100 KB se suman 590 GB o 1.180 GB de adjuntos por mes en el mes pico; el costo adicional de transferencia es de unos USD 71 o USD 142 por mes en SES y en Azure Communication Services Email, y guardar 12 meses de comprobantes cuesta entre unos USD 50 y USD 220 por mes según el servicio de almacenamiento (sin contar solicitudes, que no se calcularon). Como referencia, SmartFran onprem ya envía correos por Sendinblue (hoy Brevo) con PDF de 17 a 50 KB (dato informado; no se sabe si el formato de la nube es el mismo). Se recomienda que el POS no tenga la responsabilidad del envío: la venta publica los datos del comprobante en una cola y otro proceso (por ejemplo una Azure Function) los envía. Se recomienda además un dominio dedicado al envío de comprobantes (por ejemplo `comprobantes.smartfran.com`) para separar problemas de lista negra de los correos laborales. No hay proveedor elegido; la decisión depende de los puntos pendientes de la sección «Acciones propuestas».

## Tabla resumen

| Campo | Valor |
|---|---|
| Ticket Jira | [GITIN-2201](https://smartit-ar.atlassian.net/browse/GITIN-2201) |
| ID alerta | NA |
| Sistema | SmartCloud (Sales, envío de correos), proveedor actual SendGrid |
| Severidad | NA |
| Detectado | NA |
| Resuelto | No: evaluación en curso, sin proveedor elegido |
| Responsable | SRE (evaluación y cotizaciones); Dev (cola, reintentos y formato del comprobante) |

## Hallazgos

| # | Hallazgo | Riesgo |
|---|---|---|
| H1 | Volumen (dato informado, origen de los conteos no verificado): 72.360.308 ventas del 01-01 al 07-10-2026, 11.799.070 en enero. Promedio de 258.430 ventas por día en 280 días; enero a 380.615 por día (unos 4,4 correos por segundo en promedio, con picos mayores en horarios de comida, no medidos). Supone que cada venta tiene un correo de cliente; si solo una parte lo tiene, el volumen y el costo bajan en proporción (no verificado). | Medio |
| H2 | Integración actual (rama `main` del código de SmartCloud): los correos pasan por una interfaz (`IEmailProvider`) con una sola implementación, SendGrid. El mensaje solo tiene destinatario, asunto y cuerpo HTML (sin adjuntos ni encabezados propios). Los fallos de envío se registran y se descartan: no hay reintento, cola ni cola de mensajes fallidos, y el código no maneja rebotes ni quejas. El único uso encontrado en Sales es el correo de cierre de turno; no se encontró el envío de comprobantes por venta en esa rama, y se informó que hoy el comprobante de cada venta solo se imprime en la impresora del POS; por lo tanto, enviarlo por correo sería un flujo nuevo en la nube (a confirmar con Desarrollo). | Alto |
| H3 | Precios de lista a 11,8 millones de correos por mes (de búsquedas web; no verificados en las páginas oficiales): Amazon SES unos USD 1.180 por mes (USD 0,10 por mil; el manejo de rebotes, supresión y reputación queda a cargo propio); Azure Communication Services Email unos USD 2.950 (USD 0,00025 por correo; unas 2,5 veces SES); Postmark unos USD 2.900 con una tabla antigua de planes (con una reestructuración de 2026 reportada); Mailgun unos USD 9.400 con la tarifa Flex listada por un sitio comparador (la tarifa Enterprise sería menor, sin verificar); Brevo sin precio público a este volumen (cotizar; si aplicara un excedente de USD 1,00 por mil, unos USD 11.800, solo como cota superior aproximada). SendGrid: el plan Pro listado llega a 2,5 millones por mes (USD 89,95); se desconoce el plan actual y su costo. Ninguna cifra incluye el trabajo de ingeniería. | Medio |
| H4 | Azure Communication Services Email: la cuota por defecto es baja (una respuesta de soporte de 2024 citó 100 mensajes por hora; hay que confirmar el valor actual) y se amplía con un pedido de soporte (según lo reportado, sin costo, hasta unas 72 horas y con tasa de fallos menor al 1%). Se documentan hasta 1 a 2 millones de mensajes por hora según el tráfico y la reputación del dominio. Tamaño máximo por defecto de 10 MB. No se verificó la página oficial de límites. | Medio |
| H5 | Operación a este volumen, para cualquier proveedor: no se puede empezar de cero con unos 380 mil correos por día; hace falta un plan de IP Warm-Up (IP y dominio) de varias semanas, con SendGrid activo durante la transición. Registros SPF, DKIM y DMARC del dominio emisor (hoy `smartfran.com`, dato informado; se recomienda un subdominio dedicado como `comprobantes.smartfran.com`; hay acceso para configurar el DNS; los registros actuales del dominio no se revisaron), lista de supresión alimentada por rebotes y quejas, y revisión de las reglas de protección de datos para las direcciones de los clientes (no revisadas). La entrega debería pasar por una cola con reintentos y cola de fallidos (la plataforma ya usa Azure Service Bus). | Alto |
| H6 | Formato del comprobante (sin decisión): un botón en un correo es solo un enlace, porque los clientes de correo no ejecutan JavaScript; no se puede «renderizar» dentro del mensaje ni compilar un `.tex` adjunto. Opciones: (A) adjuntar un PDF generado en el servidor, (B) un correo corto con un botón a una URL firmada y con vencimiento que muestra el comprobante, (C) ambas. Dirección provisoria: B. | Medio |
| H7 | Almacenamiento: el comprobante ya existe como datos (colección `Sales` de Cosmos DB, lista `Bills` de cada venta); no se encontró un PDF guardado. Renderizar bajo demanda desde esos datos más una versión de plantilla, con una caché temporal, evita guardar un PDF por venta (con 100 KB por comprobante, supuesto no medido, serían unos 1,2 TB por mes). Guardar fuentes LaTeX por comprobante (unos 59 GB en el mes pico, supuesto) traslada el costo a cómputo y riesgo (compilar en cada clic, fijar versiones para reproducir años después, ejecutar con aislamiento). Falta confirmar si el PDF fiscal oficial ya existe en el flujo actual y el plazo legal de conservación. | Medio |
| H8 | QR fiscal del ticket: según el código, la URL que codifica mide unos 313 caracteres con los 13 campos de la especificación y unos 609 con el código actual (que serializa también campos adicionales en nulo); la imagen almacenada pesa entre 23 y 39 KB estimados. Para correo no conviene incrustar la imagen en base64 (varios clientes, como Gmail, no la muestran, y pesaría entre 330 y 610 GB por mes); conviene regenerar un QR chico (unos 300 px) a partir de la URL o servirlo desde la página firmada del comprobante. No se probó si el validador fiscal acepta los campos extra ni si el QR más denso se lee bien en las impresoras. | Bajo |
| H9 | Adjuntos de 50 KB y de 100 KB (tamaños supuestos, el tamaño real del comprobante de la nube no se midió; como referencia, los PDF que envía SmartFran onprem pesan entre 17 y 50 KB, dato informado, y no se sabe si el formato es el mismo que el de la nube, por lo que 50 KB sería el extremo alto de esa referencia y 100 KB queda por encima): a 11,8 millones de correos por mes son 590 GB y 1.180 GB de adjuntos por mes; en 12 meses al promedio de 7,86 millones por mes (94,3 millones de comprobantes) son 4,7 TB y 9,4 TB; en el período del 01-01 al 07-10 (72,4 millones) son 3,6 TB y 7,2 TB. Los tiers de almacenamiento frío facturan un mínimo de 128 KiB por objeto, por lo que para objetos de 50 KB o 100 KB el tier «Cool» no ahorra frente al «Hot» (ver tabla de almacenamiento). | Bajo |
| H10 | Medición de la reputación de envío: no hay hoy una línea base (no se leyeron rebotes ni quejas de SendGrid). La reputación se mide con datos propios del proveedor de envío (entrega, rebotes, quejas), con las herramientas gratuitas de los proveedores de correo (Google Postmaster Tools, Microsoft SNDS), con informes agregados de DMARC, con consultas a listas negras y, de forma opcional y paga, con pruebas de ubicación en bandeja (ver sección «Medición de la reputación de envío»). | Medio |

## Detalle por servicio

Cifras a 11,8 millones de correos por mes (mes pico). Precios de lista de búsquedas web, sin verificar en las páginas oficiales; 1 GB = 1.000.000 KB y 1 MB = 1.000 KB. «Adjuntos» es el cargo por el peso de los adjuntos enviados, no el almacenamiento.

**Recomendación:** usar un nuevo dominio destinado solo al envío de correos de comprobantes, para separar posibles problemas de lista negra (blacklist) de los correos laborales. Ejemplo: `factura@comprobantes.smartfran.com`. El correo laboral sigue en `smartfran.com` y no se usa para envíos masivos. Esto aplica a cualquiera de los proveedores de las tablas. Un subdominio queda bajo el dominio principal: una parte del riesgo de reputación podría alcanzar al dominio principal (a confirmar con el proveedor elegido); un dominio registrado aparte aísla por completo, pero parte sin historial y sin el reconocimiento de la marca.

**Amazon SES**

| Concepto | Valor |
|---|---|
| Precio de envío | USD 0,10 por mil correos |
| Costo de envío a 11,8 M por mes | unos USD 1.180 |
| Adjuntos | USD 0,12 por GB |
| Adjuntos de 50 KB (590 GB por mes) | unos USD 71; total mensual unos USD 1.251 |
| Adjuntos de 100 KB (1.180 GB por mes) | unos USD 142; total mensual unos USD 1.322 |
| IP dedicada | unos USD 24,95 por mes cada una (los planes de IP dedicada administrada tienen valores en conflicto entre fuentes) |
| Costo operativo (trabajo propio) | Única vez: pipeline de rebotes y quejas (SNS, cola o función, almacén de supresión y alertas), solicitud de salida del modo de prueba y de aumento de cuota, y IP Warm-Up de la IP dedicada durante varias semanas. Continuo: monitoreo de las tasas de rebote y de queja (AWS puede revisar o pausar una cuenta por encima de ciertos umbrales; confirmar los valores en su documentación), lectura de informes DMARC y revisión de reputación, bajas manuales y bloqueos. Dinero: costos menores de SNS, función y almacenamiento, y la IP dedicada. No se estimaron horas. SES tiene una lista de supresión a nivel de cuenta que podría reducir el desarrollo (a confirmar en la documentación). |
| Ventajas | costo de envío más bajo de la lista (unas 2,5 veces menos que Azure Communication Services Email); la cuenta de AWS ya existe en la empresa |
| Desventajas | más trabajo propio de operación (fila anterior); aprobación de acceso a producción y de cuota antes de migrar; no es nativo de Azure, donde corre SmartCloud (credenciales de AWS a administrar desde la aplicación); los datos de los clientes salen a otro proveedor de nube |

**Azure Communication Services Email**

| Concepto | Valor |
|---|---|
| Precio de envío | USD 0,00025 por correo (ejemplo ilustrativo de la documentación de Microsoft) |
| Costo de envío a 11,8 M por mes | unos USD 2.950 |
| Adjuntos | USD 0,00012 por MB |
| Adjuntos de 50 KB | unos USD 71; total mensual unos USD 3.021 |
| Adjuntos de 100 KB | unos USD 142; total mensual unos USD 3.092 |
| Límites | cuota por defecto baja, a ampliar con soporte (hasta unas 72 horas; tasa de fallos menor al 1%); tamaño máximo por defecto de 10 MB |
| Ventajas | nativo de Azure, donde corre SmartCloud; autenticación con identidad administrada (sin clave guardada); facturación en Azure |
| Desventajas | unas 2,5 veces el costo de SES; cuota por defecto baja que hay que ampliar con soporte antes de migrar; manejo de rebotes y quejas por Event Grid y disponibilidad de IP dedicada sin verificar |

**Postmark**

| Concepto | Valor |
|---|---|
| Precio de envío | tabla antigua: USD 1.200 por 5 M y USD 0,25 por mil adicionales (una reestructuración de planes de 2026 fue reportada) |
| Costo de envío a 11,8 M por mes | unos USD 2.900 |
| Adjuntos | no se encontró un cargo aparte; el tamaño máximo por mensaje no se verificó |
| Adjuntos de 50 KB y de 100 KB | sin cargo conocido; confirmar en la cotización |
| Notas | buena reputación de entrega; por encima de 1,5 M por mes requiere contactar a ventas |
| Ventajas | reputación de entrega alta; costo del mismo orden que Azure Communication Services Email; según su documentación gestiona la supresión de rebotes y quejas (no verificado) |
| Desventajas | por encima de 1,5 M por mes no hay precio público; reestructuración de planes de 2026 reportada; proveedor externo adicional fuera de AWS y Azure |

**Mailgun**

| Concepto | Valor |
|---|---|
| Precio de envío | Flex: USD 0,80 por mil (cifra de un sitio comparador); Enterprise a cotizar |
| Costo de envío a 11,8 M por mes | unos USD 9.400 con la tarifa Flex |
| Adjuntos | no se encontró un cargo aparte |
| Adjuntos de 50 KB y de 100 KB | sin cargo conocido; confirmar en la cotización |
| Notas | la tarifa Enterprise sería menor; no verificada |
| Ventajas | una tarifa Enterprise podría bajar el costo; es un servicio especializado en correo transaccional |
| Desventajas | con la tarifa Flex listada cuesta unas 8 veces SES; requiere cotización para competir; proveedor externo adicional |

**Brevo**

| Concepto | Valor |
|---|---|
| Precio de envío | planes públicos hasta Professional (USD 499 por mes desde 150.000 correos); Enterprise a cotizar |
| Costo de envío a 11,8 M por mes | sin precio público; si se aplicara un excedente de USD 1,00 por mil (cifra de un sitio de terceros para otro plan, no confirmada para Professional), unos USD 11.800 como cota superior aproximada |
| Adjuntos | no se encontró un cargo aparte |
| Adjuntos de 50 KB y de 100 KB | sin cargo conocido; confirmar en la cotización |
| IP dedicada | las fuentes no coinciden (complemento, incluida en Enterprise, unos USD 251 por año); Brevo la recomienda por encima de 100.000 correos por mes |
| Notas | plataforma orientada a marketing; relé transaccional (SMTP o API) disponible en todos los planes |
| Ventajas | relé transaccional por SMTP o API en todos los planes; permitiría sumar envíos de marketing en el futuro |
| Desventajas | sin precio público a este volumen y con la cota superior más alta de la lista; plataforma orientada a marketing; condiciones de IP dedicada poco claras |
| Uso actual en la empresa | SmartFran onprem ya envía correos por Sendinblue, que hoy se llama Brevo (informado; se supone que es la misma cuenta, a confirmar), con PDF de 17 a 50 KB. Da una cuenta, experiencia y un historial de envío de referencia; se desconocen el plan, el costo, el volumen y la reputación de esa cuenta |

**SendGrid (actual)**

| Concepto | Valor |
|---|---|
| Precio de envío | plan Pro listado en USD 89,95 por mes hasta 2,5 M de correos; no se encontró un plan por encima |
| Costo de envío a 11,8 M por mes | a cotizar; se desconocen el plan y la factura actuales |
| Adjuntos | el correo actual no admite adjuntos (el mensaje solo tiene destinatario, asunto y cuerpo HTML); cargo no evaluado |
| Notas | sigue en uso durante una transición con IP Warm-Up (IP y dominio) |
| Ventajas | ya integrado y en producción: sin trabajo de migración |
| Desventajas | se desconocen el plan y el costo actuales; la integración actual no admite adjuntos ni reintentos |

## Almacenamiento de adjuntos de 50 KB y de 100 KB

Costo mensual de guardar los comprobantes (por ejemplo para la opción de enlace firmado o para reenvíos), solo almacenamiento. Valores por GB por mes: Azure Blob en East US con redundancia local, Hot USD 0,0208, Cool USD 0,0152 y Cold USD 0,0045; Amazon S3 en us-east-1, Standard USD 0,023 y Standard-IA USD 0,0125. Estos valores salen de blogs de terceros de 2024 a 2026, no de las páginas oficiales, y las fuentes difieren entre sí (por ejemplo Hot entre 0,018 y 0,0208 y Cool entre 0,010 y 0,0152); se usó el extremo alto. En Cool, Cold y Standard-IA se factura un mínimo de 128 KiB por objeto (para Azure, según una fuente sin verificar con Microsoft), por eso los objetos de 50 KB y de 100 KB se calcularon como 128 KiB en esos tres tiers.

| Escenario | Adjunto | Datos | Azure Hot | Azure Cool* | Azure Cold* | S3 Standard | S3 Standard-IA* |
|---|---|---|---|---|---|---|---|
| Mes pico (11,8 M de comprobantes) | 50 KB | 590 GB | USD 12 | USD 24 | USD 7 | USD 14 | USD 19 |
| Mes pico (11,8 M de comprobantes) | 100 KB | 1.180 GB | USD 25 | USD 24 | USD 7 | USD 27 | USD 19 |
| 12 meses (94,3 M de comprobantes) | 50 KB | 4,7 TB | USD 98 | USD 188 | USD 56 | USD 108 | USD 155 |
| 12 meses (94,3 M de comprobantes) | 100 KB | 9,4 TB | USD 196 | USD 188 | USD 56 | USD 217 | USD 155 |
| Período 01-01 al 07-10 (72,4 M de comprobantes) | 50 KB | 3,6 TB | USD 75 | USD 144 | USD 43 | USD 83 | USD 119 |
| Período 01-01 al 07-10 (72,4 M de comprobantes) | 100 KB | 7,2 TB | USD 151 | USD 144 | USD 43 | USD 166 | USD 119 |

\* Facturado con el mínimo de 128 KiB por objeto.

Referencia con 17 KB, el extremo bajo de los PDF de SmartFran onprem (informado): 200 GB por mes en el mes pico (SES y Azure Communication Services Email, unos USD 24 por mes de adjuntos); 1,6 TB en 12 meses, unos USD 33 por mes en Azure Hot y unos USD 37 en S3 Standard; en los tiers fríos el mínimo facturable de 128 KiB iguala el costo del caso de 50 KB.

No incluye solicitudes de escritura y lectura (unos 94 millones de objetos en 12 meses, no calculadas), transferencia de salida, cargos de recuperación en los tiers fríos, redundancia geográfica (una fuente la estima en unas 2 veces la local) ni penalidad por borrado anticipado; una fuente estima que esos conceptos suman entre 30% y 70% sobre el costo teórico de almacenamiento.

## Opciones de formato del comprobante: ventajas y desventajas

Las opciones B-1, B-2 y B-3 son variantes de B según cómo se genera y qué se guarda del comprobante; el detalle con el espacio adicional por mes está en la tabla de la sección siguiente.

| Opción | Ventajas | Desventajas |
|---|---|---|
| A. Adjuntar un PDF generado en el servidor | El cliente recibe el comprobante dentro del correo, sin depender de un enlace ni de un servicio nuestro | Los adjuntos suman 590 GB (50 KB) o 1.180 GB (100 KB) por mes en el mes pico y se pagan en SES y en Azure Communication Services Email; los correos más pesados pueden afectar la entrega; hoy la integración no admite adjuntos; un reenvío obliga a regenerar el comprobante |
| B. Correo corto con botón a una URL firmada y con vencimiento (dirección provisoria) | Correo liviano, sin cargo por adjuntos; permite vencimiento y control de acceso; el QR se puede regenerar | Requiere un endpoint y una página propios en un dominio propio, almacenamiento o renderizado bajo demanda, y protección de los datos personales del comprobante; el cliente depende de que el servicio esté disponible mientras el enlace es válido |
| B-1. Enlace firmado al PDF guardado de cada comprobante | El cliente ve exactamente el documento emitido; sin cómputo al abrir el enlace; un reclamo o reenvío no necesita regenerar nada | Es el mayor consumo de almacenamiento (unos 1.180 GB por mes con 100 KB, 590 GB con 50 KB, 200 GB con 17 KB); una escritura por venta; ciclo de vida a definir |
| B-2. Enlace firmado que compila al abrir la fuente LaTeX guardada de cada comprobante | La fuente ocupa mucho menos que un PDF (unos 59 GB por mes con 5 KB, supuesto); permite plantillas con tipografía cuidada | Cada clic compila (con 1 segundo por compilación, supuesto, unos 5 vCPU al promedio de 4,4 por segundo y más tras un envío masivo); hay que fijar la distribución de TeX, los paquetes y las tipografías para que un comprobante se vea igual años después; el texto del cliente debe escaparse y compilarse en aislamiento y sin ejecución de comandos; una fuente guardada por venta |
| B-3. Enlace firmado que renderiza bajo demanda los datos del comprobante, con la versión de plantilla (dirección provisoria) | No agrega almacenamiento ni escrituras (los datos ya están en `Sales` → `Bills`); la plantilla se actualiza en un solo lugar; con una caché temporal no se recompila en cada clic; el QR se regenera a partir de los datos | Hay que guardar la versión de plantilla de cada comprobante para que uno viejo no cambie de aspecto ni de importes; requiere un renderizador propio (aislado, solo con plantillas propias) y disponibilidad del servicio al abrir el enlace; el documento fiscal oficial exacto no se guarda como archivo (a confirmar con Contabilidad y Legal) |
| C. Ambas | Combina la copia dentro del correo con el enlace | Suma el costo y la complejidad de A y de B |

### Generación y almacenamiento del comprobante: PDF guardado, fuente LaTeX y datos con renderizado bajo demanda

Cifras a 11,8 millones de comprobantes por mes. Los tamaños (100 KB por PDF, 5 KB por fuente LaTeX, 1 segundo de CPU por compilación) son supuestos sin medir. Complementa la tabla anterior: ahí se decide cómo llega el comprobante al cliente (adjunto o enlace); aquí, cómo se obtiene y qué se guarda.

| Opción | Ventajas | Desventajas | Espacio adicional por mes |
|---|---|---|---|
| 1. Guardar un PDF por comprobante | El cliente recibe exactamente el documento emitido; sirve para el adjunto o para el enlace; sin cómputo al abrirlo; un reenvío o un reclamo no necesita regenerar nada | Es el mayor consumo de almacenamiento (ver tabla de almacenamiento); hay que definir retención y ciclo de vida de millones de objetos; se agrega una escritura por venta | unos 1.180 GB con 100 KB (590 GB con 50 KB) |
| 2. Guardar la fuente LaTeX por comprobante y compilarla al abrir | Ocupa mucho menos que un PDF; permite plantillas con tipografía cuidada | Mueve el costo a cómputo y riesgo: cada clic compila (con 1 segundo por compilación y 4,4 comprobantes por segundo en promedio, unos 5 vCPU y más en picos tras un envío masivo); hay que fijar la distribución de TeX, paquetes y tipografías para que un comprobante se vea igual años después; el texto del cliente debe escaparse y compilarse en aislamiento con la ejecución de comandos desactivada; se genera y guarda un archivo fuente por venta | unos 59 GB con 5 KB |
| 3. Guardar los datos del comprobante y renderizarlos bajo demanda (dirección provisoria) | Los datos ya existen (colección `Sales` de Cosmos DB, lista `Bills` de cada venta), por lo que no agrega almacenamiento ni escrituras; la plantilla se actualiza en un solo lugar; con una caché temporal del PDF se evita recompilar en cada clic; el QR se regenera a partir de los datos | Requiere una versión de plantilla guardada para cada comprobante (si la plantilla cambia, uno viejo no debe cambiar de aspecto ni de importes); requiere un renderizador propio (aislado, solo con plantillas propias) y disponibilidad del servicio cuando el cliente abre el enlace; el documento fiscal oficial exacto no se guarda como archivo, lo que hay que confirmar con contabilidad y legal | ninguno (solo la caché temporal) |

Lo que falta confirmar para decidir entre las tres: si el PDF fiscal oficial ya existe en el flujo actual y dónde, el plazo legal de conservación, y el tamaño real de un comprobante. En las opciones 2 y 3 el motor de render puede ser LaTeX u otro (por ejemplo HTML a PDF); la elección del motor no se evaluó.

## Recomendación de arquitectura del envío

**Recomendación:** quitarle al POS la responsabilidad del envío del comprobante por correo. El flujo de la venta publica los datos del comprobante en una cola, y otro proceso, por ejemplo una Azure Function, consume la cola, genera el comprobante o su enlace y lo envía por el proveedor de correo elegido.

```
Venta (POS / Sales)  →  cola (mensaje con los datos del comprobante)  →  Azure Function  →  proveedor de correo
                                      ↓ fallos tras los reintentos
                                cola de mensajes fallidos
```

Por qué (sin medir en este ticket):
- El POS no depende del proveedor de correo ni de su disponibilidad: si el proveedor falla, la venta no se ve afectada.
- La cola permite reintentos con espera y una cola de mensajes fallidos, que hoy no existen (los fallos de envío se descartan).
- El consumo se puede limitar a la velocidad que acepta el proveedor y a la rampa del IP Warm-Up (IP y dominio) (ver «IP Warm-Up (IP y dominio)»), y con el volumen pico (unos 4,4 por segundo en promedio, más en picos) la cola absorbe las ráfagas.
- La plantilla y su versión quedan en un solo lugar (el proceso que genera el comprobante), no en cada POS.
- La plataforma ya usa Azure Service Bus y Azure Functions en otras partes; no se evaluó cuál de las Functions existentes serviría.

A definir con Desarrollo:
- En qué momento de la venta se publica el mensaje (por ejemplo al obtener el CAE) y qué lleva: identificadores de la venta y del comprobante, inquilino y versión de la plantilla, y leer los datos al procesar en lugar de copiarlos al mensaje (menos datos personales en la cola).
- Idempotencia: la cola entrega al menos una vez; un identificador de comprobante evita enviar el mismo correo dos veces.
- Cómo se resuelve el inquilino en la Function (la nube es multi-inquilino).
- Dónde se registra el estado de cada envío y dónde se guarda el consentimiento del cliente.

Costos no calculados: Azure Service Bus y Azure Functions a este volumen (unos 11,8 millones de mensajes por mes en el mes pico, como máximo) son parte de las cotizaciones a pedir (ver acciones).

## IP Warm-Up (IP y dominio)

**Qué es:** subir de forma gradual el volumen de correos que se envía desde una IP o un dominio nuevos, para que los proveedores de correo (Gmail, Outlook, Yahoo y otros) aprendan a confiar en ese remitente antes de recibir el volumen completo.

**Por qué hace falta:** los proveedores de correo puntúan cada IP y cada dominio por su historial. Una IP o un dominio sin historial que pasa de golpe a cientos de miles de correos por día se parece a un envío de spam: puede recibir limitaciones de velocidad (los mensajes se difieren), llegar a la carpeta de spam, ser rechazado o terminar en una lista negra. Un comprobante que no llega o llega tarde es el efecto visible para el cliente.

**Cómo se hace (práctica general, sin un calendario fijo en este ticket):**
- Empezar con un volumen pequeño por día y subirlo cada uno o dos días durante varias semanas; el calendario concreto lo define el proveedor y la reacción de los proveedores de correo.
- Enviar primero a las direcciones con más probabilidad de ser válidas y de recibir el correo con gusto, y mantener muy bajos los rebotes y las quejas (ver «Medición de la reputación de envío»).
- Si aparecen diferidos, rechazos o un aumento de quejas, mantener o reducir el volumen en lugar de seguir subiendo.
- Mientras tanto, el resto del volumen sigue saliendo por SendGrid; se traslada por tramos.

**Qué aplica en este caso:**
- El volumen objetivo es de unos 380 mil correos por día en el mes pico, por lo que no se puede cambiar de proveedor de un día para otro.
- Se calientan dos cosas: la IP (o el grupo de IP compartidas del proveedor) y el dominio emisor. El dominio dedicado recomendado, `comprobantes.smartfran.com`, no tiene historial de envío masivo y necesita su propio warm-up, además de los registros SPF, DKIM y DMARC.
- Con IP dedicada (por ejemplo en Amazon SES, unos USD 24,95 por mes cada una) el IP Warm-Up es a cargo propio, o del proveedor si ofrece uno automático (no verificado para SES). Con un conjunto de IP compartidas del proveedor, la IP ya está calentada, pero la reputación se comparte con otros remitentes.
- Cualquiera sea el proveedor elegido, el plan de IP Warm-Up debe estar definido antes de migrar, porque determina la duración de la transición con SendGrid activo.

## Medición de la reputación de envío

No existe un puntaje único de entregabilidad: se mide con varias señales. Los umbrales son referencias generales de la práctica de correo, sin verificar para estas cuentas; confirmarlos en la documentación de cada proveedor.

| Fuente | Qué mide | Nota |
|---|---|---|
| Datos propios del proveedor de envío | Tasa de entrega; rebotes duros (la dirección no existe) y blandos o diferidos (códigos 4xx, como «demasiadas conexiones»); quejas por spam; tiempo de entrega | Disponible desde el primer día. Referencias generales: rebotes duros por debajo de alrededor de 2%; quejas por debajo de 0,1% y nunca por encima de 0,3% (pautas de Gmail para remitentes masivos, a confirmar). Aperturas y clics son una señal débil para comprobantes |
| Google Postmaster Tools | Reputación de dominio e IP, tasa de spam, autenticación y errores de entrega hacia Gmail | Gratuito; requiere un volumen mínimo diario hacia Gmail |
| Microsoft SNDS y JMRP | Reputación de IP y quejas en Outlook y Hotmail | Gratuito; se basa en la IP |
| Bucle de quejas de Yahoo | Quejas de los destinatarios de Yahoo | Disponible para remitentes que se registran |
| Panel del proveedor de envío | Amazon SES: reputación de la cuenta y métricas de rebotes y quejas en CloudWatch (hay además un panel de entregabilidad pago, a confirmar); Azure Communication Services Email: eventos por Azure Monitor y Event Grid (sin verificar); Postmark, Mailgun y Brevo: sus paneles | Es la fuente principal para alertar |
| Listas negras | Si la IP o el dominio figuran en las principales listas (Spamhaus, Barracuda y otras) | Consulta manual o con una herramienta de consulta, con periodicidad |
| Informes agregados de DMARC | Porcentaje de correos que pasan SPF y DKIM por remitente, y quién más envía con el dominio | Requiere una casilla o servicio que reciba los informes |
| Pruebas de ubicación en bandeja | Si el mensaje llega a la bandeja de entrada o a spam en cuentas de prueba de Gmail y Outlook | De pago, opcional |

Durante el IP Warm-Up conviene revisar a diario rebotes duros, quejas, diferidos y la reputación del dominio en Google Postmaster Tools, y alertar por tasas y no por volumen.

## Recursos afectados

| Componente | Estado observado |
|---|---|
| Envío de correos de SmartCloud (SendGrid) | Una sola implementación, sin cola ni reintentos; plan y costo actuales desconocidos |
| Dominio emisor de correos de comprobantes | Hoy `smartfran.com` (informado); recomendado un subdominio dedicado (`comprobantes.smartfran.com`); acceso al DNS disponible; registros SPF, DKIM y DMARC actuales sin revisar; IP Warm-Up y línea base de reputación pendientes |

## Comandos ejecutados

Ninguno contra sistemas: la evaluación se hizo con lectura del código local y búsquedas web.

## Preguntas para Desarrollo

Pendientes que solo puede responder el equipo de Desarrollo; de las respuestas dependen el almacenamiento, el formato y el costo.

| # | Pregunta | Qué se sabe hoy | Cómo responderla |
|---|---|---|---|
| 1 | Con la recomendación de que el POS no tenga esta responsabilidad y publique los datos del comprobante en una cola que procesa otro proceso (por ejemplo una Azure Function): ¿en qué momento de la venta se publicaría el mensaje y qué llevaría?, ¿qué componente genera el comprobante que se envía, con qué plantilla y formato? | Se informó que hoy el comprobante de cada venta solo se imprime en el POS, así que el envío por correo sería nuevo. En el código de SmartCloud (rama `main`) solo existe el correo de cierre de turno. SmartFran onprem sí envía correos con PDF por Sendinblue (Brevo). No se encontró un PDF generado por el servidor | Pregunta abierta para Desarrollo: momento de la publicación, contenido del mensaje, componente que genera el comprobante, plantilla y formato, y si es el mismo que usa el sistema onprem |
| 2 | ¿Cuánto pesa un comprobante? | No está medido en la nube. Se supusieron 50 KB y 100 KB (ver tablas de almacenamiento); SmartFran onprem, que envía por Sendinblue (Brevo), usa PDF de 17 a 50 KB (informado) y no se sabe si el formato es el mismo. El comprobante existe como datos (`Sales` → `Bills` en Cosmos DB) y se imprime desde plantillas; no se encontró un PDF guardado | Generar un comprobante real con la plantilla, con QR y sin adjuntos, y anotar el tamaño del PDF (o del HTML); anotar también el tamaño del documento de la venta con su lista `Bills`. Hacerlo para una venta chica y una grande (muchos ítems y promociones) y informar promedio y máximo |
| 3 | ¿Hay que guardar una copia del comprobante que se envía? | Como hoy el comprobante solo se imprime en el POS, todavía no hay comprobantes enviados que guardar. El comprobante existe como datos de la venta (`Sales` → `Bills`) y se imprime desde plantillas; no se encontró un PDF guardado | Pregunta abierta para Desarrollo: si hay que guardar una copia y qué guardar y dónde, y si hace falta un registro de cada envío. Las alternativas de generación y almacenamiento están en la tabla correspondiente |
| 4 | ¿Durante cuánto tiempo hay que guardarlo? | No está determinado: depende del plazo legal para comprobantes fiscales y del plazo en que un cliente puede reclamar. El costo crece con la retención (ver tabla de almacenamiento: 12 meses de comprobantes de 100 KB ocupan unos 9,4 TB). El historial de eventos que conserva cada proveedor de envío suele ser limitado (a confirmar con el elegido) | Consultar a Contabilidad y Legal el plazo del comprobante fiscal y del registro de envío; definir si el registro propio debe durar más que el historial del proveedor; definir el ciclo de vida del almacenamiento a partir de ese plazo |
| 5 | ¿Cada venta tiene correo del cliente y se puede usar para enviar el comprobante? | No verificado. El volumen supone un correo por venta; si solo una parte tiene dirección, el volumen baja en proporción | Medir qué porcentaje de las ventas tiene correo; confirmar con Legal el consentimiento y la protección de datos para enviarlo |

## Acciones propuestas

1. (SRE) Obtener el plan, el costo mensual y los dominios emisores actuales de SendGrid (factura y página de uso de la cuenta).
2. (SRE) Pedir cotización escrita a 12 millones de correos por mes, transaccional, a Microsoft (Azure Communication Services Email) y a los proveedores que queden en la lista corta; confirmar las páginas oficiales de precios y límites de Amazon SES y Azure Communication Services Email.
3. (Dev / SRE) Confirmar que hoy el comprobante solo se imprime en el POS (informado), definir dónde se dispararía el envío por correo y quién genera el PDF, y medir el tamaño promedio.
4. (Operaciones / Legal) Confirmar el plazo legal de conservación de los comprobantes fiscales y si el PDF fiscal oficial ya existe en el flujo actual.
5. (SRE) Definir con Operaciones la prioridad entre menor costo (Amazon SES, con manejo propio de rebotes y reputación) y menos piezas a operar (Azure Communication Services Email o un proveedor administrado con cotización).
6. (Dev) Diseñar el envío con la arquitectura recomendada (el flujo de la venta publica en una cola y otro proceso, por ejemplo una Azure Function, la consume): reintentos con espera, cola de mensajes fallidos, idempotencia por comprobante, manejo de rebotes y quejas y lista de supresión, previo a cambiar de proveedor.
7. (SRE) Revisar los registros SPF, DKIM y DMARC actuales de `smartfran.com` (límite de 10 consultas DNS del SPF y política DMARC vigente) y preparar los cambios del proveedor elegido junto con el plan de IP Warm-Up (IP y dominio) (ver «IP Warm-Up (IP y dominio)»). Aplicar la recomendación de dominio dedicado (por ejemplo `comprobantes.smartfran.com`): crear el subdominio en el DNS, configurar SPF, DKIM y DMARC (DMARC primero en modo de monitoreo), usar la misma identidad en la dirección de rebotes, y registrar el dominio en Google Postmaster Tools y Microsoft SNDS.
8. (Dev) Probar el contenido del QR fiscal (13 campos contra el código actual) en el validador y en las impresoras.
9. (SRE / Dev) Medir el tamaño real de un comprobante (se supusieron 50 KB y 100 KB), decidir si se adjunta o se envía un enlace, y elegir el tier de almacenamiento y la retención sobre los precios oficiales de Azure Blob Storage y Amazon S3 (los de este ticket son de terceros).
10. (SRE) Definir la medición de la reputación de envío: obtener la línea base actual de SendGrid (rebotes duros y quejas), registrar el dominio emisor en Google Postmaster Tools y Microsoft SNDS, activar los informes agregados de DMARC, configurar alertas por tasa de rebotes duros y de quejas en el proveedor elegido, consultar las listas negras con periodicidad y revisar las señales a diario durante el IP Warm-Up.
11. (Dev) Responder las preguntas de la sección «Preguntas para Desarrollo»: en qué momento se enviaría y quién genera el comprobante, tamaño real de un comprobante, si hay que guardar una copia y qué guardar, tiempo de retención (con Contabilidad y Legal) y porcentaje de ventas con correo del cliente.
12. (SRE) Obtener de la cuenta de Sendinblue (Brevo) que usa SmartFran onprem el plan, el costo, el volumen mensual, las tasas de rebotes y de quejas y los dominios emisores, como referencia y línea base; confirmar si es la cuenta que se evaluaría para la nube.
13. (SRE) Incluir en las cotizaciones de nube el costo de Azure Service Bus (cola) y de Azure Functions (procesamiento) a este volumen, y el almacenamiento, junto con los proveedores de correo.

## Fuentes de los precios de almacenamiento (blogs de terceros consultados el 2026-10-13, no oficiales)

- [Azure Storage pricing (nOps)](https://www.nops.io/blog/azure-storage-pricing/)
- [Azure Storage Pricing Guide (Lucidity)](https://lucidity.cloud/feeds/blog/azure-storage-cost)
- [AWS S3 Pricing Explained 2026 (Upstash)](https://upstash.com/blog/aws-s3-pricing-explained-2026)
- [AWS S3 pricing (DevZero)](https://www.devzero.io/blog/aws-s3-pricing)
