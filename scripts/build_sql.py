"""Build the date-replacement procedure from the checked-in medallion mappings."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
def select_body(name):
    text = (ROOT / 'sql' / name).read_text(encoding='utf-8-sig')
    return text.split('\nAS\n', 1)[1].split(';\nGO', 1)[0]
def dynamic(text):
    return "SET @sql = N'" + text.replace("'", "''") + "';\n"
def table_sql(layer, select):
    return (f"CREATE EXTERNAL TABLE dbo.[{{{layer}}}] WITH (LOCATION = '{{{layer}_path}}', "
            f"DATA_SOURCE = ds_datalake, FILE_FORMAT = ff_parquet) AS\n{select};")
def substitute(sql):
    for layer in ['bronze', 'silver', 'gold', 'commit']:
        sql = sql.replace('{'+layer+'}', "' + @"+layer+" + N'")
        sql = sql.replace('{'+layer+'_path}', "' + @"+layer+"_path + N'")
    return sql.replace('{date}', "' + @date_iso + N'").replace('{key}', "' + @run_key + N'")

bronze = select_body('03_create_bronze_parquet.sql')
bronze += "\nWHERE CAST(TRY_CONVERT(datetime2(0), LEFT(e.event_ts,19)) AS date) = '{date}'"
silver = select_body('04_create_silver_parquet.sql').replace('dbo.bronze_print_events', 'dbo.[{bronze}]')
gold = select_body('05_create_gold_parquet.sql').replace('dbo.silver_print_events', 'dbo.[{silver}]')

proc = '''USE qr_native_lakehouse;
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
'''
for layer,body in [('bronze',bronze),('silver',silver),('gold',gold)]:
    proc += substitute(dynamic(table_sql(layer,body))) + 'EXEC sys.sp_executesql @sql;\n'
    if layer == 'bronze':
        check = '''SELECT @bad=COUNT_BIG(*) FROM dbo.[{bronze}]
WHERE event_id IS NULL OR event_ts IS NULL OR machine_id IS NULL OR qr_code IS NULL
OR print_status IS NULL OR print_status NOT IN ('PRINTED','FAILED')
OR qr_grade_score IS NULL OR qr_grade_score NOT BETWEEN 0 AND 1
OR position_error_mm IS NULL OR qr_read_success IS NULL OR is_reject IS NULL
OR is_reject <> CASE WHEN print_status <> 'PRINTED' OR qr_read_success=0 OR ABS(position_error_mm)>0.45 THEN 1 ELSE 0 END;'''
        proc += substitute(dynamic(check))
        proc += "EXEC sys.sp_executesql @sql,N'@bad bigint OUTPUT',@bad=@bad_rows OUTPUT;\nIF @bad_rows>0 THROW 50004, 'Source data quality validation failed; candidate not published.',1;\n"
    if layer == 'silver':
        proc += substitute(dynamic('SELECT @n=COUNT_BIG(*) FROM dbo.[{silver}];'))
        proc += "EXEC sys.sp_executesql @sql,N'@n bigint OUTPUT',@n=@silver_rows OUTPUT;\nIF @silver_rows=0 THROW 50005,'Silver is empty; candidate not published.',1;\n"
proc += substitute(dynamic('SELECT @n=SUM(total_events) FROM dbo.[{gold}];'))
proc += "EXEC sys.sp_executesql @sql,N'@n bigint OUTPUT',@n=@gold_events OUTPUT;\nIF @gold_events IS NULL OR @gold_events<>@silver_rows THROW 50006,'Gold reconciliation failed; candidate not published.',1;\n"
proc += substitute(dynamic(table_sql('commit',"SELECT CAST('{date}' AS date) AS event_date, CAST('run_{key}' AS varchar(80)) AS run_key")))
proc += '''EXEC sys.sp_executesql @sql;
SELECT @event_date AS event_date,@source_rows AS bronze_rows,@silver_rows AS unique_events,
       @gold_events AS gold_events,@run_key AS committed_attempt;
END;
GO
'''
(ROOT/'sql'/'09_create_incremental_medallion_procedure.sql').write_text(proc,encoding='utf-8')

old = (ROOT/'sql'/'08_create_scalable_gold_view.sql').read_text(encoding='utf-8-sig')
schema = old.split('WITH (',1)[1].split(') AS gold',1)[0]
cols = old.split('AS\nSELECT\n',1)[1].split('\nFROM OPENROWSET',1)[0].strip()
view = f'''USE qr_native_lakehouse;
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
 WITH ({schema}) AS g
 INNER JOIN commits c ON g.event_date=c.event_date AND g.filepath(2)=c.run_key
), legacy AS (
 SELECT g.* FROM OPENROWSET(BULK 'gold/print_event_kpis_daily/**',DATA_SOURCE='ds_datalake',FORMAT='PARQUET')
 WITH ({schema}) AS g
 WHERE NOT EXISTS (SELECT 1 FROM commits c WHERE c.event_date=g.event_date)
)
SELECT {cols} FROM current_gold
UNION ALL
SELECT {cols} FROM legacy;
GO
'''
(ROOT/'sql'/'10_create_committed_gold_view.sql').write_text(view,encoding='utf-8')
