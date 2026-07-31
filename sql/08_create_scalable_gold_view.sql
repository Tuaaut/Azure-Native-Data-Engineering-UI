USE qr_native_lakehouse;
GO

/*
Stable Gold reporting view.

Reads all current and future Parquet partitions below:
gold/print_event_kpis_daily/

Power BI continues using the same view name.
*/

CREATE OR ALTER VIEW dbo.vw_gold_print_event_kpis_daily
AS
SELECT
    event_date,
    machine_id,
    product_id,
    product_name,
    total_events,
    printed_events,
    failed_events,
    rejected_events,
    qr_read_failures,
    successful_events,
    success_rate_pct,
    reject_rate_pct,
    avg_qr_grade_score,
    avg_abs_position_error_mm,
    first_event_ts,
    last_event_ts,
    gold_loaded_utc
FROM OPENROWSET(
    BULK 'gold/print_event_kpis_daily/**',
    DATA_SOURCE = 'ds_datalake',
    FORMAT = 'PARQUET'
)
WITH (
    event_date date,
    machine_id varchar(20),
    product_id varchar(50),
    product_name varchar(100),
    total_events bigint,
    printed_events int,
    failed_events int,
    rejected_events int,
    qr_read_failures int,
    successful_events int,
    success_rate_pct decimal(9,4),
    reject_rate_pct decimal(9,4),
    avg_qr_grade_score decimal(9,4),
    avg_abs_position_error_mm decimal(9,4),
    first_event_ts datetime2(0),
    last_event_ts datetime2(0),
    gold_loaded_utc datetime2(0)
) AS gold;
GO

SELECT
    COUNT_BIG(*) AS gold_rows,
    SUM(total_events) AS total_events,
    SUM(successful_events) AS successful_events,
    SUM(rejected_events) AS rejected_events
FROM dbo.vw_gold_print_event_kpis_daily;
GO
