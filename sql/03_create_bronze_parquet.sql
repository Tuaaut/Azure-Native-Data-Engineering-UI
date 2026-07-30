/*
Create the Bronze Parquet layer.

CETAS does not overwrite an existing storage folder. Use a new run ID for every
rerun, and keep the external table name aligned with the output folder.
*/

CREATE EXTERNAL TABLE dbo.bronze_print_events_run_20260731_01
WITH (
    LOCATION = 'bronze/print_events/run_20260731_01/',
    DATA_SOURCE = DataLake,
    FILE_FORMAT = ParquetFormat
)
AS
SELECT
    src.filename() AS source_file,
    TRY_CONVERT(int, event_json.[key]) AS event_array_index,
    COALESCE(
        JSON_VALUE(event_json.[value], '$.event_id'),
        JSON_VALUE(event_json.[value], '$.id')
    ) AS event_id,
    TRY_CONVERT(
        datetime2(3),
        COALESCE(
            JSON_VALUE(event_json.[value], '$.event_ts'),
            JSON_VALUE(event_json.[value], '$.event_timestamp'),
            JSON_VALUE(event_json.[value], '$.timestamp')
        )
    ) AS event_ts,
    JSON_VALUE(event_json.[value], '$.machine_id') AS machine_id,
    JSON_VALUE(event_json.[value], '$.product_id') AS product_id,
    JSON_VALUE(event_json.[value], '$.product_name') AS product_name,
    UPPER(COALESCE(
        JSON_VALUE(event_json.[value], '$.event_status'),
        JSON_VALUE(event_json.[value], '$.print_status'),
        JSON_VALUE(event_json.[value], '$.status')
    )) AS event_status,
    UPPER(COALESCE(
        JSON_VALUE(event_json.[value], '$.qr_read_status'),
        JSON_VALUE(event_json.[value], '$.qr_status')
    )) AS qr_read_status,
    TRY_CONVERT(
        decimal(10,4),
        COALESCE(
            JSON_VALUE(event_json.[value], '$.qr_grade_score'),
            JSON_VALUE(event_json.[value], '$.qr_grade')
        )
    ) AS qr_grade_score,
    TRY_CONVERT(
        decimal(10,4),
        COALESCE(
            JSON_VALUE(event_json.[value], '$.position_error_mm'),
            JSON_VALUE(event_json.[value], '$.print_position_error_mm')
        )
    ) AS position_error_mm,
    event_json.[value] AS event_json,
    SYSUTCDATETIME() AS bronze_loaded_utc
FROM OPENROWSET(
    BULK = 'raw/machine_api/*/machine_api_response.json',
    DATA_SOURCE = 'DataLake',
    SINGLE_CLOB
) AS src
CROSS APPLY OPENJSON(src.BulkColumn, '$.print_events') AS event_json;
GO

SELECT COUNT_BIG(*) AS bronze_rows
FROM OPENROWSET(
    BULK = 'bronze/print_events/run_20260731_01/*.parquet',
    DATA_SOURCE = 'DataLake',
    FORMAT = 'PARQUET'
) AS bronze;

