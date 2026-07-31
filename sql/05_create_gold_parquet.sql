USE qr_native_lakehouse;
GO

CREATE EXTERNAL TABLE dbo.gold_print_event_kpis_daily
WITH (
    LOCATION = 'gold/print_event_kpis_daily/run_20260731_01',
    DATA_SOURCE = ds_datalake,
    FILE_FORMAT = ff_parquet
)
AS
SELECT
    event_date,
    machine_id,
    product_id,
    product_name,
    COUNT_BIG(*) AS total_events,
    SUM(CASE WHEN print_status = 'PRINTED' THEN 1 ELSE 0 END) AS printed_events,
    SUM(CASE WHEN print_status = 'FAILED' THEN 1 ELSE 0 END) AS failed_events,
    SUM(CASE WHEN is_reject = 1 THEN 1 ELSE 0 END) AS rejected_events,
    SUM(CASE WHEN qr_read_success = 0 THEN 1 ELSE 0 END) AS qr_read_failures,
    SUM(
        CASE
            WHEN print_status = 'PRINTED'
             AND qr_read_success = 1
             AND is_reject = 0
            THEN 1 ELSE 0
        END
    ) AS successful_events,
    CAST(
        100.0 * SUM(
            CASE
                WHEN print_status = 'PRINTED'
                 AND qr_read_success = 1
                 AND is_reject = 0
                THEN 1 ELSE 0
            END
        ) / NULLIF(COUNT_BIG(*), 0)
        AS decimal(9,4)
    ) AS success_rate_pct,
    CAST(
        100.0 * SUM(CASE WHEN is_reject = 1 THEN 1 ELSE 0 END)
        / NULLIF(COUNT_BIG(*), 0)
        AS decimal(9,4)
    ) AS reject_rate_pct,
    CAST(AVG(CAST(qr_grade_score AS decimal(18,6))) AS decimal(9,4))
        AS avg_qr_grade_score,
    CAST(AVG(ABS(CAST(position_error_mm AS decimal(18,6)))) AS decimal(9,4))
        AS avg_abs_position_error_mm,
    MIN(event_ts) AS first_event_ts,
    MAX(event_ts) AS last_event_ts,
    CAST(SYSUTCDATETIME() AS datetime2(0)) AS gold_loaded_utc
FROM dbo.silver_print_events
GROUP BY
    event_date,
    machine_id,
    product_id,
    product_name;
GO

SELECT *
FROM dbo.gold_print_event_kpis_daily
ORDER BY event_date, machine_id, product_id;
