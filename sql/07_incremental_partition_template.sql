USE qr_native_lakehouse;
GO

/*
Incremental partition template

Before running for a new batch, replace:
1. 20260801_01 = unique run suffix
2. 2026-08-01  = event date
3. 20260801T*  = Raw ingestion-folder pattern

Every CETAS LOCATION must be new and empty.
Do not run until the matching Raw folder exists.
*/


-- =========================================================
-- 1. BRONZE: Process only the new Raw ingestion folders
-- =========================================================

CREATE EXTERNAL TABLE dbo.bronze_print_events_20260801_01
WITH (
    LOCATION =
        'bronze/print_events/event_date=2026-08-01/run_20260801_01',
    DATA_SOURCE = ds_datalake,
    FILE_FORMAT = ff_parquet
)
AS
SELECT
    CAST(r.filepath(1) AS varchar(30)) AS source_folder,
    CAST(JSON_VALUE(r.jsonContent, '$.batch_id') AS varchar(50))
        AS batch_id,
    CAST(JSON_VALUE(r.jsonContent, '$.line_id') AS varchar(30))
        AS line_id,
    e.event_id,
    TRY_CONVERT(datetime2(0), LEFT(e.event_ts, 19)) AS event_ts,
    e.machine_id,
    e.product_id,
    e.product_name,
    e.qr_code,
    e.print_status,
    e.qr_read_success,
    e.is_reject,
    e.qr_grade_score,
    e.position_error_mm,
    CAST(SYSUTCDATETIME() AS datetime2(0)) AS bronze_loaded_utc
FROM OPENROWSET(
    BULK = 'raw/machine_api/20260801T*/machine_api_response.json',
    DATA_SOURCE = 'ds_datalake',
    FORMAT = 'CSV',
    FIELDQUOTE = '0x0b',
    FIELDTERMINATOR = '0x0b',
    ROWTERMINATOR = '0x0b'
)
WITH (
    jsonContent varchar(MAX)
) AS r
CROSS APPLY OPENJSON(r.jsonContent, '$.print_events')
WITH (
    event_id varchar(50) '$.event_id',
    event_ts varchar(30) '$.event_ts',
    machine_id varchar(20) '$.machine_id',
    product_id varchar(50) '$.product_id',
    product_name varchar(100) '$.product_name',
    qr_code varchar(100) '$.qr_code',
    print_status varchar(20) '$.print_status',
    qr_read_success bit '$.qr_read_success',
    is_reject bit '$.is_reject',
    qr_grade_score decimal(5,3) '$.qr_grade_score',
    position_error_mm decimal(8,3) '$.position_error_mm'
) AS e
WHERE
    CAST(
        TRY_CONVERT(datetime2(0), LEFT(e.event_ts, 19))
        AS date
    ) = '2026-08-01';
GO


-- =========================================================
-- 2. SILVER: Clean and deduplicate the new date partition
-- =========================================================

CREATE EXTERNAL TABLE dbo.silver_print_events_20260801_01
WITH (
    LOCATION =
        'silver/print_events/event_date=2026-08-01/run_20260801_01',
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
            ORDER BY
                b.source_folder DESC,
                b.bronze_loaded_utc DESC
        ) AS row_num
    FROM dbo.bronze_print_events_20260801_01 AS b
    WHERE b.event_id IS NOT NULL
      AND b.event_ts IS NOT NULL
      AND b.machine_id IS NOT NULL
      AND b.qr_code IS NOT NULL
      AND b.print_status IN ('PRINTED', 'FAILED')
      AND b.qr_grade_score BETWEEN 0 AND 1
) AS d
WHERE d.row_num = 1;
GO


-- =========================================================
-- 3. GOLD: Aggregate only the new date partition
-- =========================================================

CREATE EXTERNAL TABLE dbo.gold_print_event_kpis_20260801_01
WITH (
    LOCATION =
        'gold/print_event_kpis_daily/event_date=2026-08-01/run_20260801_01',
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

    SUM(
        CASE
            WHEN print_status = 'PRINTED'
            THEN 1 ELSE 0
        END
    ) AS printed_events,

    SUM(
        CASE
            WHEN print_status = 'FAILED'
            THEN 1 ELSE 0
        END
    ) AS failed_events,

    SUM(
        CASE
            WHEN is_reject = 1
            THEN 1 ELSE 0
        END
    ) AS rejected_events,

    SUM(
        CASE
            WHEN qr_read_success = 0
            THEN 1 ELSE 0
        END
    ) AS qr_read_failures,

    SUM(
        CASE
            WHEN print_status = 'PRINTED'
             AND qr_read_success = 1
             AND is_reject = 0
            THEN 1 ELSE 0
        END
    ) AS successful_events,

    CAST(
        100.0 *
        SUM(
            CASE
                WHEN print_status = 'PRINTED'
                 AND qr_read_success = 1
                 AND is_reject = 0
                THEN 1 ELSE 0
            END
        )
        / NULLIF(COUNT_BIG(*), 0)
        AS decimal(9,4)
    ) AS success_rate_pct,

    CAST(
        100.0 *
        SUM(
            CASE
                WHEN is_reject = 1
                THEN 1 ELSE 0
            END
        )
        / NULLIF(COUNT_BIG(*), 0)
        AS decimal(9,4)
    ) AS reject_rate_pct,

    CAST(
        AVG(
            CAST(qr_grade_score AS decimal(18,6))
        )
        AS decimal(9,4)
    ) AS avg_qr_grade_score,

    CAST(
        AVG(
            ABS(
                CAST(position_error_mm AS decimal(18,6))
            )
        )
        AS decimal(9,4)
    ) AS avg_abs_position_error_mm,

    MIN(event_ts) AS first_event_ts,
    MAX(event_ts) AS last_event_ts,

    CAST(SYSUTCDATETIME() AS datetime2(0))
        AS gold_loaded_utc

FROM dbo.silver_print_events_20260801_01
GROUP BY
    event_date,
    machine_id,
    product_id,
    product_name;
GO


-- =========================================================
-- 4. VALIDATION: Run only after successful future processing
-- =========================================================

SELECT
    COUNT_BIG(*) AS bronze_rows
FROM dbo.bronze_print_events_20260801_01;
GO

SELECT
    COUNT_BIG(*) AS silver_rows,
    COUNT(DISTINCT event_id) AS unique_events
FROM dbo.silver_print_events_20260801_01;
GO

SELECT *
FROM dbo.gold_print_event_kpis_20260801_01
ORDER BY
    event_date,
    machine_id,
    product_id;
GO
