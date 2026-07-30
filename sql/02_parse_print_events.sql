/*
Parse print_events into a tabular result.

This showcase mapping accepts common alternative JSON keys so the script remains
readable without embedding the source payload in Git. Validate the candidates
against 01_inspect_raw_json.sql before running against a new API version.
*/

WITH parsed AS (
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
        event_json.[value] AS event_json
    FROM OPENROWSET(
        BULK = 'raw/machine_api/*/machine_api_response.json',
        DATA_SOURCE = 'DataLake',
        SINGLE_CLOB
    ) AS src
    CROSS APPLY OPENJSON(src.BulkColumn, '$.print_events') AS event_json
)
SELECT TOP (100)
    source_file,
    event_array_index,
    event_id,
    event_ts,
    machine_id,
    product_id,
    product_name,
    event_status,
    qr_read_status,
    qr_grade_score,
    position_error_mm,
    event_json
FROM parsed
ORDER BY source_file, event_array_index;

