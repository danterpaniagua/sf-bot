# Email — Aviso a PMs: Mantenimiento de seguridad planificado

**Para:** Product Managers  
**De:** Dante Paniagua, SRE  
**Asunto:** Aviso: Mantenimiento de seguridad en infraestructura de autenticación — SmartLoyalty

---

Estimados,

Les informo que el equipo de SRE se encuentra trabajando en la resolución de una alerta crítica de seguridad emitida por Microsoft Azure el 10 de junio, que afecta a la infraestructura de autenticación de la plataforma SmartFran.

La alerta indica una configuración de seguridad insuficiente en el sistema de autenticación centralizado. De no resolverse, esta configuración representa un riesgo de seguridad activo sobre las credenciales de acceso a los servicios de la plataforma.

**Servicio afectado: SmartLoyalty**

El componente de autenticación impactado es utilizado transversalmente por todos los servidores web de SmartLoyalty. Esto incluye los servicios de puntos, consultas de saldo, y operaciones de canje que los franquiciados y usuarios finales utilizan a través de la plataforma.

**Impacto potencial durante la remediación**

Durante la ventana de cambio, los servicios de SmartLoyalty podrían experimentar una interrupción breve de acceso mientras el sistema de autenticación aplica la nueva configuración de seguridad. Estamos realizando pruebas previas en un entorno aislado con el mismo tipo de componente para validar que la continuidad de servicio está garantizada antes de aplicar cualquier cambio en producción. En caso de que la prueba no sea exitosa, la remediación será postergada.

**Estado actual**

Plan de pruebas en ejecución. La remediación en producción está pendiente de la validación de resultados.

Ante cualquier consulta, quedo a disposición.

Saludos,  
Dante Paniagua  
SRE — SmartFran
