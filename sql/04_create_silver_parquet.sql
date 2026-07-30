/*
Create typed, standardized Silver print events from the verified Bronze run.
*/

CREATE EXTERNAL TABLE dbo.silver_print_events_run_20260731_01
WITH (
    LOCATION = 'silver/print_events/run_20260731_01/',
    DATA_SOURCE = DataLake,
    FILE_FORMAT = ParquetFormat
)
AS
SELECT
    CAST(event_ts AS date) AS event_date,
    CAST(event_ts AS datetime2(3)) AS event_ts,
    CAST(event_id AS varchar(100)) AS event_id,
    CAST(machine_id AS varchar(50)) AS machine_id,
    CAST(product_id AS varchar(50)) AS product_id,
    CAST(product_name AS varchar(200)) AS product_name,
    CAST(event_status AS varchar(30)) AS event_status,
    CAST(qr_read_status AS varchar(30)) AS qr_read_status,
    CAST(qr_grade_score AS decimal(10,4)) AS qr_grade_score,
    CAST(position_error_mm AS decimal(10,4)) AS position_error_mm,
    CAST(CASE
        WHEN event_status IN ('PRINTED', 'SUCCESS', 'SUCCESSFUL') THEN 1
        ELSE 0
    END AS tinyint) AS is_printed,
    CAST(CASE
        WHEN event_status IN ('PRINTED', 'SUCCESS', 'SUCCESSFUL') THEN 1
        ELSE 0
    END AS tinyint) AS is_successful,
    CAST(CASE
        WHEN event_status IN ('REJECT', 'REJECTED', 'FAILED') THEN 1
        ELSE 0
    END AS tinyint) AS is_rejected,
    CAST(CASE
        WHEN event_status = 'FAILED' THEN 1
        ELSE 0
    END AS tinyint) AS is_failed,
    CAST(CASE
        WHEN qr_read_status IN ('FAIL', 'FAILED', 'FAILURE', 'UNREADABLE') THEN 1
        ELSE 0
    END AS tinyint) AS is_qr_read_failure,
    CAST(source_file AS varchar(400)) AS source_file,
    SYSUTCDATETIME() AS silver_loaded_utc
FROM OPENROWSET(
    BULK = 'bronze/print_events/run_20260731_01/*.parquet',
    DATA_SOURCE = 'DataLake',
    FORMAT = 'PARQUET'
) AS bronze
WHERE
    event_ts IS NOT NULL
    AND machine_id IS NOT NULL
    AND product_id IS NOT NULL;
GO

SELECT
    COUNT_BIG(*) AS silver_rows,
    SUM(CASE WHEN event_id IS NULL THEN 1 ELSE 0 END) AS missing_event_ids,
    MIN(event_ts) AS first_event_ts,
    MAX(event_ts) AS last_event_ts
FROM OPENROWSET(
    BULK = 'silver/print_events/run_20260731_01/*.parquet',
    DATA_SOURCE = 'DataLake',
    FORMAT = 'PARQUET'
) AS silver;

