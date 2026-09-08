WITH raw_json AS (
    SELECT jsonContent
    FROM OPENROWSET(
        BULK 'https://stqrdenativeui740561.dfs.core.windows.net/datalake/raw/machine_api/*/machine_api_response.json',
        FORMAT = 'CSV',
        FIELDQUOTE = '0x0b',
        FIELDTERMINATOR = '0x0b',
        ROWTERMINATOR = '0x0b'
    )
    WITH (jsonContent varchar(MAX)) AS src
)
SELECT TOP (100)
    JSON_VALUE(r.jsonContent, '$.batch_id') AS batch_id,
    JSON_VALUE(r.jsonContent, '$.line_id') AS line_id,
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
    e.position_error_mm
FROM raw_json AS r
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
ORDER BY event_ts;
