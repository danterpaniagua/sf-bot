-- ============================================================
-- Acciones requeridas — Jira: [DB] CPU User Time >90% 2026-05-18
-- Base de datos: SmartFran.Solution.SmartLoyalty
-- Tabla: SmlSt.CustomerAdditionalInformation (4.742.925 filas)
--
-- Servidor: SFCG-DB01
-- Edición: Microsoft SQL Server 2022 Standard (16.0.4075.1)
-- ONLINE = ON no está disponible en Standard Edition.
-- Ejecutar en ventana de mantenimiento — la creación de índices
-- en Standard bloquea accesos a la tabla hasta que finaliza.
-- ============================================================

-- Acción 1: Índice sobre CardNumber
-- Cubre el predicado: WHERE ai.CardNumber = @CardNumber
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('[SmlSt].[CustomerAdditionalInformation]')
      AND name = 'IX_CustomerAdditionalInformation_CardNumber'
)
CREATE NONCLUSTERED INDEX [IX_CustomerAdditionalInformation_CardNumber]
    ON [SmlSt].[CustomerAdditionalInformation] ([CardNumber])
    INCLUDE ([FavoriteProduct], [AverageWeight], [LastBuyDate])
    WITH (SORT_IN_TEMPDB = ON);
GO

-- Acción 2: Índice sobre UidCode, UidSerie
-- Cubre el predicado: WHERE ai.UidCode = @UidCode AND ai.UidSerie = @UidSerie
-- Requiere que Query101-sql.xml sea corregida (Acción 3) para eliminar LOWER()
-- y hacer el predicado sargable con este índice.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('[SmlSt].[CustomerAdditionalInformation]')
      AND name = 'IX_CustomerAdditionalInformation_UidCode_UidSerie'
)
CREATE NONCLUSTERED INDEX [IX_CustomerAdditionalInformation_UidCode_UidSerie]
    ON [SmlSt].[CustomerAdditionalInformation] ([UidCode], [UidSerie])
    INCLUDE ([FavoriteProduct], [AverageWeight], [LastBuyDate])
    WITH (SORT_IN_TEMPDB = ON);
GO
