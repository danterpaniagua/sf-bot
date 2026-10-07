**Asunto:** Incorporación completa del segundo servidor de WebServiceV2 — redundancia y monitoreo al día

Hola equipo,

Les comento que la incorporación del segundo servidor de WebServiceV2 (SmartLoyalty), SFCG-WSV2-02,
quedó completa.

Identificamos y corregimos una configuración de red en el balanceador de carga que impedía que este
segundo servidor recibiera tráfico real de clientes, a pesar de estar operativo. En la práctica, todo
el tráfico venía siendo atendido exclusivamente por el primer servidor (SFCG-WSV2-01) desde que el
segundo fue puesto en producción. Con la corrección aplicada, confirmamos que ambos servidores
distribuyen el tráfico real correctamente, restableciendo la redundancia prevista para este servicio.

Además, completamos la puesta a punto del monitoreo del segundo servidor, que ya cuenta con la misma
cobertura que el primero — permitiendo detectar cualquier problema futuro en cualquiera de los dos
servidores con la misma visibilidad.

Como resultado de la redundancia restablecida, se abre la posibilidad de evaluar una reducción en el
tamaño del primer servidor, que actualmente está dimensionado para soportar la totalidad de la carga
por sí solo — una configuración que ya no sería necesaria ahora que la carga se distribuye entre ambos
servidores.

Para más información, los tickets de referencia son GITIN-1238 (redundancia de tráfico) y GITIN-1956
(puesta a punto del monitoreo).

**Próximos pasos:**
- Evaluar la posibilidad de redimensionar el servidor SFCG-WSV2-01 a un tamaño menor, aprovechando la
  redundancia ahora restablecida.

Saludos,
Dante
