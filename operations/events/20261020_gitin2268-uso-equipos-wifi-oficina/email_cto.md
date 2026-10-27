**Asunto:** Estado de GITIN-2268 (problemas de WiFi en la oficina): router y switches, opciones y precios

Hola,

Te resumo el estado de [GITIN-2268](https://smartit-ar.atlassian.net/browse/GITIN-2268) y las opciones de compra del router y los switches. Más detalle en [GITIN-2288](https://smartit-ar.atlassian.net/browse/GITIN-2288).

## Estado

- La causa de los problemas de conexión no está determinada. Las mediciones del 2026-10-22 son corridas individuales, con solo dos personas en la oficina, sin la carga normal de unos 40 usuarios.
- Los dos servicios de internet entregan mucho más de lo que se ve en los puestos: conectado directo al módem, Claro dio 678 Mb/s de download y el servicio dedicado 369.
- Los puestos cableados en dos de los tres switches (HP 1910-24) negociaron 100 Mb/s. El tercero (HPE 1620-24G) negoció gigabit.
- El WiFi tiene velocidad suficiente (408 a 709 Mb/s) pero jitter alto (27 a 70 ms) en todas las configuraciones. No medí la causa.
- Detrás del router actual (Cisco RV325, fin de venta anunciado en 2020 y fin de soporte en 2021, firmware de 2020) las descargas fueron de 75 a 92 Mb/s con las dos líneas conectadas. No pude explicarlo.
- Tickets hijos: [GITIN-2269](https://smartit-ar.atlassian.net/browse/GITIN-2269) (calidad de Meet) cerrado sin integración; [GITIN-2270](https://smartit-ar.atlassian.net/browse/GITIN-2270) (script de auditoría) con una primera corrida completa en una notebook; [GITIN-2271](https://smartit-ar.atlassian.net/browse/GITIN-2271) (correos de regla de uso y de procedimiento de reporte) redactados.

## Qué se propone comprar (todavía no aprobado)

1. **Router MikroTik** que reemplace al RV325. El modelo se define por la capacidad de las dos líneas (600 y 200 Mb/s). Requisitos: load balancing por destino o con reglas, failover entre las líneas, VPN para el acceso remoto, soporte vigente. Requisitos obligatorios: SNMP y que sea rackeable.
2. **Switches administrables de 1 Gb/s**, con SNMP y rackeables (requisitos obligatorios), en una de dos opciones: un switch de 48 puertos o dos de 24, para reemplazar a los dos HP 1910-24.
3. Aparte, quedan los patch cords Cat6, un switch gigabit chico por mesa y los adaptadores Ethernet USB gigabit; no están incluidos en esta comparación.

## Precios de referencia en MercadoLibre

Los modelos de la tabla son ejemplos para tener un orden de precio, no una selección. Los precios son los vistos en las publicaciones el 2026-10-26; solo la del RB4011 muestra el precio con y sin impuestos nacionales (de las demás no sé si incluyen IVA) y pueden cambiar. Otra publicación del RB4011 estaba a $429.123,09.

| Equipo | Modelo candidato | Precio (ARS) | Link |
|---|---|---|---|
| Router | MikroTik RB5009UG+S+IN (7 puertos Gigabit, 1 de 2,5 Gb, 1 SFP) | $459.997 | [Publicación](https://www.mercadolibre.com.ar/router-mikrotik-rb5009ugsin-7-gbe-1-puerto-25gbe-1-sfp/p/MLA47311205?pdp_filters=item_id%3AMLA1895835401) |
| Router | MikroTik RB4011iGS+RM (10 puertos Gigabit, formato rack) | $461.311 (sin impuestos nacionales: $417.476; 3 cuotas de $153.770,33 con tarjeta Mercado Pago) | [Publicación](https://www.mercadolibre.com.ar/router-mikrotik-rb4011igsrm-10-gigabit-1-sfp-1gb-ram/up/MLAU161878871?pdp_filters=item_id%3AMLA924559794) |
| Switch 48 puertos | MikroTik CRS354-48G-4S+2Q+RM (48 puertos Gigabit, 4 SFP+, 2 QSFP+ de 40 Gb) | $1.269.990 | [Publicación](https://www.mercadolibre.com.ar/switch-gestionable-mikrotik-crs354-48g-4s2qrm-50-puertos-gigabit-2-qsfp-40g/p/MLA16050680?pdp_filters=item_id%3AMLA1172536154) |
| Switch 48 puertos | TP-Link JetStream T2600G-52TS (L2, 48 puertos, 4 SFP) | $899.990 (12 cuotas de $74.999,17 con tarjeta Mercado Pago) | [Publicación](https://www.mercadolibre.com.ar/switch-tplink-48-puertos-4-sfp-l2-t2600g52ts-tlsg3452/up/MLAU173468670?pdp_filters=item_id%3AMLA2856228366) |
| Switch 24 puertos (x2) | MikroTik CRS326-24G-2S+RM (24 puertos Gigabit, 2 SFP+, rack) | $416.750 cada uno, $833.500 los dos | [Publicación](https://www.mercadolibre.com.ar/switch-gestionable-mikrotik-crs326-24g-2srm-24-puertos-rack-42gbs/p/MLA14650032?pdp_filters=item_id%3AMLA1975528158) |

Los modelos son candidatos que propongo; no los comparé con los requisitos ni abrí sus hojas de datos. Hay que verificar el throughput documentado de NAT contra la suma de las líneas, y que el switch entregue por SNMP la velocidad negociada, los errores, la CPU y la memoria de cada puerto.

## Pendientes

- Definir el modelo de router y la opción de switches una vez verificados los requisitos de arriba contra las hojas de datos.
- Confirmar con Administración el servicio dedicado contratado (hoy se informa 200 Mb/s simétricos, pero el módem midió 369 Mb/s de download).
- Repetir las mediciones con la carga normal de la oficina.
- Los correos de [GITIN-2271](https://smartit-ar.atlassian.net/browse/GITIN-2271) no se enviaron, hasta donde muestra el chat.

Saludos,
