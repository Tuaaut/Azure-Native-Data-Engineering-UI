USE qr_native_lakehouse;
GO

CREATE EXTERNAL TABLE dbo.silver_print_events
WITH (
    LOCATION = 'silver/print_events/run_20260731_01',
    DATA_SOURCE = ds_datalake,
    FILE_FORMAT = ff_parquet
)
AS
SELECT
    d.source_folder,
    d.batch_id,
    d.line_id,
    d.event_id,
    d.event_ts,
    CAST(d.event_ts AS date) AS event_date,
    DATEPART(hour, d.event_ts) AS event_hour,
    d.machine_id,
    d.product_id,
    d.product_name,
    d.qr_code,
    d.print_status,
    d.qr_read_success,
    d.is_reject,
    d.qr_grade_score,
    d.position_error_mm,
    CAST(SYSUTCDATETIME() AS datetime2(0)) AS silver_loaded_utc
FROM (
    SELECT
        b.*,
        ROW_NUMBER() OVER (
            PARTITION BY b.event_id
            ORDER BY b.source_folder DESC, b.bronze_loaded_utc DESC
        ) AS row_num
    FROM dbo.bronze_print_events AS b
    WHERE b.event_id IS NOT NULL
      AND b.event_ts IS NOT NULL
      AND b.machine_id IS NOT NULL
      AND b.qr_code IS NOT NULL
      AND b.print_status IN ('PRINTED', 'FAILED')
      AND b.qr_grade_score BETWEEN 0 AND 1
) AS d
WHERE d.row_num = 1;
GO

SELECT
    COUNT_BIG(*) AS silver_row_count,
    COUNT(DISTINCT event_id) AS distinct_event_count,
    MIN(event_ts) AS min_event_ts,
    MAX(event_ts) AS max_event_ts
FROM dbo.silver_print_events;
