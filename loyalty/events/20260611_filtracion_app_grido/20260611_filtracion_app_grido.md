# [SEC] Incidente – Enumeración y Exfiltración vía App Grido – SmartLoyalty [11/06/2026]

## Resumen
Durante la tarde del 11/06/2026 se detectó un ataque automatizado contra la API de SmartLoyalty, utilizando la app móvil de Grido como vector de entrada. El atacante realizó enumeración de socios por DNI y exfiltración de perfil y movimientos de puntos.

---

## Detección
- **Herramienta:** Zabbix alertó por volumen anómalo de GET requests
- **Correlación:** Graylog confirmó patrón automatizado sobre DNIs del rango `10.000.000`
- **Confirmación con Grido:** descartaron campaña propia activa para la fecha

---

## Vector
Conexión 1:1 entre infraestructura SmartFran y app Grido via firewall dedicado, **sin NAT habilitado**. Esto impide:
- Identificar el origen real del tráfico
- Aplicar reglas de WAF desde nuestra infraestructura

---

## Atacante
| Campo | Valor |
|---|---|
| IP | `2a02:4780:75:9bea::1` (IPv6) |
| ASN | 47583 – Hostinger International |
| User-agent | `okhttp/4.9.2` |
| Source browser / OS | Unknown |
| Device type | Desktop |

---

## Mecanismo del ataque

**Fase 1 – Enumeración**
- Endpoint: `GET /api/Customer/GetCustomerProfile`
- 2 intentos por DNI, secuencial
- HTTP 200 → socio activo → continúa a Fase 2
- HTTP 400/404 → DNI inexistente → descarta

**Fase 2 – Exfiltración**
Para cada DNI con respuesta 200:
- `GET /api/Customer/GetCustomerMovements`
- `GET /api/AdditionalInformation/GetAddicionalInformation`

**Resultado:** sondeo de socios nuevos + obtención de saldo de puntos de socios existentes.

---

## Evidencia

**Graylog**
- ~119.740 hits desde la IP identificada
- Relación códigos: 400 ≈ 0.3–0.4 respecto de 200
- Comportamiento coordinado en los 3 endpoints visible a partir de las **17:00 hs**

**WAF Grido (Cloudflare)**
- IP confirmada desde `api.pedigrido.com`
- Hits coinciden con volumen registrado en Graylog
- Paths con mayor frecuencia de error 400: `/account/customers/13371359`, `/account/customers/10007658`, y otros del rango `10.000.000`

---

## Acciones tomadas

- [x] Baja preventiva de la funcionalidad **Transferencia de Puntos**
- [x] Solicitud a desarrollo de app Grido: auditoría de accesos al repositorio/código fuente para descartar compromiso por acceso SSH no autorizado
- [x] Solicitud a infraestructura Grido: configurar rate limiting en Cloudflare — sugerencia **10 requests por endpoint**


---

## Contexto y antecedentes

> ⚠️ Sección de uso interno

### 1. Reincidencia en Grido
El equipo de Grido ya había implementado medidas de mitigación tras un ataque anterior sobre el mismo vector. La reincidencia indica que dichas medidas fueron insuficientes o que existe un problema estructural no resuelto en la seguridad de su app móvil.

### 2. Intento de desvío de responsabilidad
Durante la gestión del incidente, desde el equipo de Grido se intentó atribuir el origen del tráfico anómalo a **SmartPedidos**. Esto fue descartado con evidencia. Se deja registro como antecedente de cara a futuras discusiones sobre responsabilidades.

### 3. Alerta previa desestimada por Santex
Base4 había informado con anterioridad una filtración de datos publicada en X (ex Twitter). Desde Santex dicha información fue tratada como **Fake News** y desestimada. Este ataque sugiere que la filtración era real y que los datos están siendo utilizados activamente contra el programa de fidelización.

---

## Vinculación con el robo de puntos

Este ataque es el **paso de reconocimiento previo al robo**. La lógica del flujo completo:

```
Enumeración por DNI (/GetCustomerProfile)
        ↓
Identificación de socio activo (HTTP 200)
        ↓
Exfiltración de saldo (/GetCustomerMovements)
        ↓
Transferencia fraudulenta por el total disponible
```

El atacante necesita saber cuántos puntos tiene cada socio antes de operar la transferencia. Este ataque provee exactamente esa información.
