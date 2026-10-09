/*
    04_register_benchmark_connection.sql
    Target: Microsoft Fabric SQL Database (sqldb_ingestion_control)
    Purpose: Register the dedicated Amazon RDS for SQL Server benchmark source connection.

    Create Fabric connection cn_rds_sql_server_ingestion_benchmark first, then paste its
    environment-specific connection ID below. Do not commit the real ID.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @BenchmarkSourceConnectionId NVARCHAR(100) = NULL;

IF @BenchmarkSourceConnectionId IS NULL
BEGIN
    THROW 51120, 'Set BenchmarkSourceConnectionId before running this script.', 1;
END;

DECLARE @ConnectionSettings NVARCHAR(MAX) =
    CONCAT(
        N'{"connectionId":"',
        @BenchmarkSourceConnectionId,
        N'"}'
    );

IF EXISTS
(
    SELECT 1
    FROM control.connection_settings
    WHERE connection_ref = 'RDS_INGESTION_BENCHMARK'
)
BEGIN
    UPDATE control.connection_settings
    SET
        connection_type = 'AMAZON_RDS_SQL_SERVER',
        connection_settings = @ConnectionSettings,
        updated_at = SYSUTCDATETIME()
    WHERE connection_ref = 'RDS_INGESTION_BENCHMARK';
END
ELSE
BEGIN
    INSERT INTO control.connection_settings
    (
        connection_ref,
        connection_type,
        connection_settings
    )
    VALUES
    (
        'RDS_INGESTION_BENCHMARK',
        'AMAZON_RDS_SQL_SERVER',
        @ConnectionSettings
    );
END;

SELECT *
FROM control.connection_settings
WHERE connection_ref = 'RDS_INGESTION_BENCHMARK';
