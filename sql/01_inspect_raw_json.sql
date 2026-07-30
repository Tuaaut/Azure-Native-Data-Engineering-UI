/*
Inspect Raw machine API JSON before applying a schema.
Verified cloud artifact: sql_00_inspect_raw_json.
*/

SELECT TOP (10)
    src.filename() AS source_file,
    src.BulkColumn AS raw_json
FROM OPENROWSET(
    BULK = 'raw/machine_api/*/machine_api_response.json',
    DATA_SOURCE = 'DataLake',
    SINGLE_CLOB
) AS src;
GO

-- Confirm that the print_events array exists and count events by source file.
SELECT
    src.filename() AS source_file,
    COUNT_BIG(*) AS print_event_count
FROM OPENROWSET(
    BULK = 'raw/machine_api/*/machine_api_response.json',
    DATA_SOURCE = 'DataLake',
    SINGLE_CLOB
) AS src
CROSS APPLY OPENJSON(src.BulkColumn, '$.print_events') AS event_json
GROUP BY src.filename()
ORDER BY src.filename();
GO

-- Discover the keys and JSON types present in the first event objects.
SELECT TOP (100)
    src.filename() AS source_file,
    event_json.[key] AS event_array_index,
    property_json.[key] AS property_name,
    property_json.[value] AS property_value,
    property_json.[type] AS json_type
FROM OPENROWSET(
    BULK = 'raw/machine_api/*/machine_api_response.json',
    DATA_SOURCE = 'DataLake',
    SINGLE_CLOB
) AS src
CROSS APPLY OPENJSON(src.BulkColumn, '$.print_events') AS event_json
CROSS APPLY OPENJSON(event_json.[value]) AS property_json
ORDER BY src.filename(), TRY_CONVERT(int, event_json.[key]), property_json.[key];

