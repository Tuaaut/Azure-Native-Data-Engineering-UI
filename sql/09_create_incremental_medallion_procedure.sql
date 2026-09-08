USE qr_native_lakehouse;
GO
-- Incremental by business date: read actual source payloads, replace one date.
-- Immutable candidates are invisible until a validated commit manifest exists.
-- Unique attempt keys recover empty legacy tables without deleting data.
CREATE OR ALTER PROCEDURE dbo.usp_process_machine_api_incremental
    @window_end_utc varchar(50),
    @event_date date = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @run_time datetimeoffset(0) = TRY_CONVERT(datetimeoffset(0), @window_end_utc, 127);
    IF @run_time IS NULL THROW 50001, 'Invalid window_end_utc value.', 1;
    DECLARE @scheduled_date date = CAST(SWITCHOFFSET(@run_time, '+07:00') AS date);
    IF @event_date IS NULL SET @event_date = DATEADD(day,-1,@scheduled_date);
    IF @event_date >= @scheduled_date THROW 50002, 'Event date must precede the scheduled Bangkok date.', 1;
    DECLARE @date_iso char(10) = CONVERT(char(10),@event_date,23);
    DECLARE @run_key varchar(64) = CONVERT(char(8),SYSUTCDATETIME(),112)
        + REPLACE(CONVERT(varchar(12),SYSUTCDATETIME(),114),':','')
        + '_' + REPLACE(CONVERT(varchar(36),NEWID()),'-','');
    DECLARE @bronze sysname = 'bronze_v2_' + @run_key;
    DECLARE @silver sysname = 'silver_v2_' + @run_key;
    DECLARE @gold sysname = 'gold_v2_' + @run_key;
    DECLARE @commit sysname = 'commit_v2_' + @run_key;
    DECLARE @bronze_path varchar(300) = 'medallion_v2/bronze/event_date=' + @date_iso + '/run_' + @run_key;
    DECLARE @silver_path varchar(300) = 'medallion_v2/silver/event_date=' + @date_iso + '/run_' + @run_key;
    DECLARE @gold_path varchar(300) = 'medallion_v2/gold/event_date=' + @date_iso + '/run_' + @run_key;
    DECLARE @commit_path varchar(300) = 'medallion_v2/commits/' + @run_key;
    DECLARE @sql nvarchar(max), @source_rows bigint, @silver_rows bigint, @gold_events bigint, @bad_rows bigint;
    -- Preflight uses event dates in JSON, not folder names or workstation date.
    SELECT @source_rows = COUNT_BIG(*)
    FROM OPENROWSET(BULK 'raw/machine_api/*/machine_api_response.json', DATA_SOURCE='ds_datalake',
        FORMAT='CSV', FIELDQUOTE='0x0b', FIELDTERMINATOR='0x0b', ROWTERMINATOR='0x0b')
        WITH (jsonContent varchar(MAX)) AS r
    CROSS APPLY OPENJSON(r.jsonContent,'$.print_events') WITH (event_ts varchar(30) '$.event_ts') AS e
    WHERE CAST(TRY_CONVERT(datetime2(0),LEFT(e.event_ts,19)) AS date)=@event_date;
    IF @source_rows=0 THROW 50003, 'No Raw events for expected business date; source is missing or stale.', 1;
SET @sql = N'CREATE EXTERNAL TABLE dbo.[' + @bronze + N'] WITH (LOCATION = ''' + @bronze_path + N''', DATA_SOURCE = ds_datalake, FILE_FORMAT = ff_parquet) AS
SELECT
    CAST(r.filepath(1) AS varchar(30)) AS source_folder,
    CAST(JSON_VALUE(r.jsonContent, ''$.batch_id'') AS varchar(50)) AS batch_id,
    CAST(JSON_VALUE(r.jsonContent, ''$.line_id'') AS varchar(30)) AS line_id,
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
    BULK ''raw/machine_api/*/machine_api_response.json'',
    DATA_SOURCE = ''ds_datalake'',
    FORMAT = ''CSV'',
    FIELDQUOTE = ''0x0b'',
    FIELDTERMINATOR = ''0x0b'',
    ROWTERMINATOR = ''0x0b''
)
WITH (jsonContent varchar(MAX)) AS r
CROSS APPLY OPENJSON(r.jsonContent, ''$.print_events'')
WITH (
    event_id varchar(50) ''$.event_id'',
    event_ts varchar(30) ''$.event_ts'',
    machine_id varchar(20) ''$.machine_id'',
    product_id varchar(50) ''$.product_id'',
    product_name varchar(100) ''$.product_name'',
    qr_code varchar(100) ''$.qr_code'',
    print_status varchar(20) ''$.print_status'',
    qr_read_success bit ''$.qr_read_success'',
    is_reject bit ''$.is_reject'',
    qr_grade_score decimal(5,3) ''$.qr_grade_score'',
    position_error_mm decimal(8,3) ''$.position_error_mm''
) AS e
WHERE CAST(TRY_CONVERT(datetime2(0), LEFT(e.event_ts,19)) AS date) = ''' + @date_iso + N''';';
EXEC sys.sp_executesql @sql;
SET @sql = N'SELECT @bad=COUNT_BIG(*) FROM dbo.[' + @bronze + N']
WHERE event_id IS NULL OR event_ts IS NULL OR machine_id IS NULL OR qr_code IS NULL
OR print_status IS NULL OR print_status NOT IN (''PRINTED'',''FAILED'')
OR qr_grade_score IS NULL OR qr_grade_score NOT BETWEEN 0 AND 1
OR position_error_mm IS NULL OR qr_read_success IS NULL OR is_reject IS NULL
OR is_reject <> CASE WHEN print_status <> ''PRINTED'' OR qr_read_success=0 OR ABS(position_error_mm)>0.45 THEN 1 ELSE 0 END;';
EXEC sys.sp_executesql @sql,N'@bad bigint OUTPUT',@bad=@bad_rows OUTPUT;
IF @bad_rows>0 THROW 50004, 'Source data quality validation failed; candidate not published.',1;
SET @sql = N'CREATE EXTERNAL TABLE dbo.[' + @silver + N'] WITH (LOCATION = ''' + @silver_path + N''', DATA_SOURCE = ds_datalake, FILE_FORMAT = ff_parquet) AS
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
    FROM dbo.[' + @bronze + N'] AS b
    WHERE b.event_id IS NOT NULL
      AND b.event_ts IS NOT NULL
      AND b.machine_id IS NOT NULL
      AND b.qr_code IS NOT NULL
      AND b.print_status IN (''PRINTED'', ''FAILED'')
      AND b.qr_grade_score BETWEEN 0 AND 1
) AS d
WHERE d.row_num = 1;';
EXEC sys.sp_executesql @sql;
SET @sql = N'SELECT @n=COUNT_BIG(*) FROM dbo.[' + @silver + N'];';
EXEC sys.sp_executesql @sql,N'@n bigint OUTPUT',@n=@silver_rows OUTPUT;
IF @silver_rows=0 THROW 50005,'Silver is empty; candidate not published.',1;
SET @sql = N'CREATE EXTERNAL TABLE dbo.[' + @gold + N'] WITH (LOCATION = ''' + @gold_path + N''', DATA_SOURCE = ds_datalake, FILE_FORMAT = ff_parquet) AS
SELECT
    event_date,
    machine_id,
    product_id,
    product_name,
    COUNT_BIG(*) AS total_events,
    SUM(CASE WHEN print_status = ''PRINTED'' THEN 1 ELSE 0 END) AS printed_events,
    SUM(CASE WHEN print_status = ''FAILED'' THEN 1 ELSE 0 END) AS failed_events,
    SUM(CASE WHEN is_reject = 1 THEN 1 ELSE 0 END) AS rejected_events,
    SUM(CASE WHEN qr_read_success = 0 THEN 1 ELSE 0 END) AS qr_read_failures,
    SUM(
        CASE
            WHEN print_status = ''PRINTED''
             AND qr_read_success = 1
             AND is_reject = 0
            THEN 1 ELSE 0
        END
    ) AS successful_events,
    CAST(
        100.0 * SUM(
            CASE
                WHEN print_status = ''PRINTED''
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
FROM dbo.[' + @silver + N']
GROUP BY
    event_date,
    machine_id,
    product_id,
    product_name;';
EXEC sys.sp_executesql @sql;
SET @sql = N'SELECT @n=SUM(total_events) FROM dbo.[' + @gold + N'];';
EXEC sys.sp_executesql @sql,N'@n bigint OUTPUT',@n=@gold_events OUTPUT;
IF @gold_events IS NULL OR @gold_events<>@silver_rows THROW 50006,'Gold reconciliation failed; candidate not published.',1;
SET @sql = N'CREATE EXTERNAL TABLE dbo.[' + @commit + N'] WITH (LOCATION = ''' + @commit_path + N''', DATA_SOURCE = ds_datalake, FILE_FORMAT = ff_parquet) AS
SELECT CAST(''' + @date_iso + N''' AS date) AS event_date, CAST(''run_' + @run_key + N''' AS varchar(80)) AS run_key;';
EXEC sys.sp_executesql @sql;
SELECT @event_date AS event_date,@source_rows AS bronze_rows,@silver_rows AS unique_events,
       @gold_events AS gold_events,@run_key AS committed_attempt;
END;
GO
