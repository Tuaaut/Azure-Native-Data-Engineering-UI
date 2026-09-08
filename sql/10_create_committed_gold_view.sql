USE qr_native_lakehouse;
GO
-- Deploy after the first successful v2 publication. A latest validated manifest
-- replaces the entire business date; old snapshots remain available for recovery.
CREATE OR ALTER VIEW dbo.vw_gold_print_event_kpis_daily
AS
WITH commits AS (
 SELECT event_date,MAX(run_key) AS run_key
 FROM OPENROWSET(BULK 'medallion_v2/commits/**',DATA_SOURCE='ds_datalake',FORMAT='PARQUET')
 WITH (event_date date,run_key varchar(80)) AS c GROUP BY event_date
), current_gold AS (
 SELECT g.* FROM OPENROWSET(BULK 'medallion_v2/gold/*/*/*.parquet',DATA_SOURCE='ds_datalake',FORMAT='PARQUET')
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
) AS g
 INNER JOIN commits c ON g.event_date=c.event_date AND g.filepath(2)=c.run_key
), legacy AS (
 SELECT g.* FROM OPENROWSET(BULK 'gold/print_event_kpis_daily/**',DATA_SOURCE='ds_datalake',FORMAT='PARQUET')
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
) AS g
 WHERE NOT EXISTS (SELECT 1 FROM commits c WHERE c.event_date=g.event_date)
)
SELECT event_date,
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
    gold_loaded_utc FROM current_gold
UNION ALL
SELECT event_date,
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
    gold_loaded_utc FROM legacy;
GO
