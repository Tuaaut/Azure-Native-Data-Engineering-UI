USE qr_native_lakehouse;
GO

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
FROM dbo.gold_print_event_kpis_daily;
GO

SELECT *
FROM dbo.vw_gold_print_event_kpis_daily
ORDER BY event_date, machine_id, product_id;
