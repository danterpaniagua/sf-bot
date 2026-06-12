# Email — Aviso a PMs: Mantenimiento de seguridad planificado

**Para:** Product Managers  
**De:** Dante Paniagua, SRE  
**Asunto:** Aviso: Mantenimiento de seguridad en infraestructura de autenticación — Plataforma SmartFran

---

Estimados,

Les informo que el equipo de SRE se encuentra trabajando en la resolución de una alerta crítica de seguridad emitida por Microsoft Azure el 10 de junio, que afecta a la infraestructura de autenticación de la plataforma SmartFran.

La alerta indica una configuración de seguridad insuficiente en el sistema de autenticación centralizado que utilizan todos los servidores de la plataforma. De no resolverse, esta configuración representa un riesgo de seguridad activo sobre las credenciales de los servicios.

**Impacto potencial durante la remediación**

Los servicios SmartLoyalty y SmartFran podrían experimentar una interrupción breve de autenticación durante la ventana de cambio. Estamos realizando pruebas previas en un entorno aislado para minimizar este riesgo antes de aplicar cualquier cambio en producción. En caso de que la prueba no sea exitosa, la remediación será postergada hasta contar con garantías de continuidad de servicio.

**Estado actual**

Plan de pruebas en ejecución. La remediación en producción está pendiente de la validación de resultados.

Ante cualquier consulta, quedo a disposición.

Saludos,  
Dante Paniagua  
SRE — SmartFran
