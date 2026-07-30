/*
Create the stable Power BI-facing view over the verified Gold Parquet run.
Cloud artifact name: sql_06_create_gold_reporting_view.
*/

CREATE OR ALTER VIEW dbo.vw_gold_print_event_kpis_daily
AS
SELECT
    CAST(event_date AS date) AS event_date,
    CAST(machine_id AS varchar(50)) AS machine_id,
    CAST(product_id AS varchar(50)) AS product_id,
    CAST(product_name AS varchar(200)) AS product_name,
    CAST(total_events AS bigint) AS total_events,
    CAST(printed_events AS bigint) AS printed_events,
    CAST(successful_events AS bigint) AS successful_events,
    CAST(rejected_events AS bigint) AS rejected_events,
    CAST(failed_events AS bigint) AS failed_events,
    CAST(qr_read_failures AS bigint) AS qr_read_failures,
    CAST(success_rate_pct AS decimal(9,2)) AS success_rate_pct,
    CAST(reject_rate_pct AS decimal(9,2)) AS reject_rate_pct,
    CAST(avg_qr_grade_score AS decimal(10,4)) AS avg_qr_grade_score,
    CAST(avg_abs_position_error_mm AS decimal(10,4))
        AS avg_abs_position_error_mm,
    CAST(first_event_ts AS datetime2(3)) AS first_event_ts,
    CAST(last_event_ts AS datetime2(3)) AS last_event_ts,
    CAST(gold_loaded_utc AS datetime2(3)) AS gold_loaded_utc
FROM OPENROWSET(
    BULK = 'gold/print_event_kpis_daily/run_20260731_01/*.parquet',
    DATA_SOURCE = 'DataLake',
    FORMAT = 'PARQUET'
) AS gold;
GO

SELECT *
FROM dbo.vw_gold_print_event_kpis_daily
ORDER BY event_date, machine_id, product_id;

