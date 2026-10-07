-- Remediation for CPU spike investigation 2026-09-20 (events/20260920_cpu-spikes/investigation.md)
-- Same indexes proposed in GITIN-1267 (2026-05-17, events/20260517_query101_webservicev2/)
-- Target: SmartFran.Solution.SmartLoyalty (production)
-- CORRECTED 2026-09-21: WITH (ONLINE = ON) is Enterprise-only (confirmed via Msg 1712 on this server,
-- SQL Server 2022 Standard). Original script incorrectly claimed Standard support since 2016 SP1 -
-- that SP1 change applied to partitioning and other features, not online index operations.
-- This is now an OFFLINE build: takes a shared (S) table lock for the full duration.
-- Reads continue; ALL writes (INSERT/UPDATE/DELETE) against CustomerAdditionalInformation block until done.
-- Table appears to be written per sale (LastBuyDate/AverageWeight/FavoriteProduct) - run in a
-- low-traffic/maintenance window, not during active hours.
-- Partial mitigation only: helps the CardNumber branch of Query101's WHERE clause.
-- The UidCode branch is wrapped in LOWER() in the query text, which blocks index use
-- regardless of this index's existence, until the query itself is rewritten (Dev-owned, WSV2 app-side XML resource).

USE [SmartFran.Solution.SmartLoyalty];

CREATE NONCLUSTERED INDEX IX_CustomerAdditionalInformation_CardNumber
ON SmlSt.CustomerAdditionalInformation (CardNumber)
INCLUDE (FavoriteProduct, AverageWeight, LastBuyDate);

CREATE NONCLUSTERED INDEX IX_CustomerAdditionalInformation_UidCode_UidSerie
ON SmlSt.CustomerAdditionalInformation (UidCode, UidSerie)
INCLUDE (FavoriteProduct, AverageWeight, LastBuyDate);
