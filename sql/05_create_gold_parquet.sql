/*
Create reporting-ready daily KPIs from the verified Silver run.
*/

CREATE EXTERNAL TABLE dbo.gold_print_event_kpis_daily_run_20260731_01
WITH (
    LOCATION = 'gold/print_event_kpis_daily/run_20260731_01/',
    DATA_SOURCE = DataLake,
    FILE_FORMAT = ParquetFormat
)
AS
SELECT
    event_date,
    machine_id,
    product_id,
    product_name,
    COUNT_BIG(*) AS total_events,
    SUM(CAST(is_printed AS bigint)) AS printed_events,
    SUM(CAST(is_successful AS bigint)) AS successful_events,
    SUM(CAST(is_rejected AS bigint)) AS rejected_events,
    SUM(CAST(is_failed AS bigint)) AS failed_events,
    SUM(CAST(is_qr_read_failure AS bigint)) AS qr_read_failures,
    CAST(
        100.0 * SUM(CAST(is_successful AS decimal(19,4)))
        / NULLIF(COUNT_BIG(*), 0)
        AS decimal(9,2)
    ) AS success_rate_pct,
    CAST(
        100.0 * SUM(CAST(is_rejected AS decimal(19,4)))
        / NULLIF(COUNT_BIG(*), 0)
        AS decimal(9,2)
    ) AS reject_rate_pct,
    CAST(AVG(CAST(qr_grade_score AS decimal(19,6))) AS decimal(10,4))
        AS avg_qr_grade_score,
    CAST(AVG(ABS(CAST(position_error_mm AS decimal(19,6)))) AS decimal(10,4))
        AS avg_abs_position_error_mm,
    MIN(event_ts) AS first_event_ts,
    MAX(event_ts) AS last_event_ts,
    SYSUTCDATETIME() AS gold_loaded_utc
FROM OPENROWSET(
    BULK = 'silver/print_events/run_20260731_01/*.parquet',
    DATA_SOURCE = 'DataLake',
    FORMAT = 'PARQUET'
) AS silver
GROUP BY
    event_date,
    machine_id,
    product_id,
    product_name;
GO

SELECT *
FROM OPENROWSET(
    BULK = 'gold/print_event_kpis_daily/run_20260731_01/*.parquet',
    DATA_SOURCE = 'DataLake',
    FORMAT = 'PARQUET'
) AS gold
ORDER BY event_date, machine_id, product_id;

