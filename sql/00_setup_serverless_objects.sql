IF DB_ID('qr_native_lakehouse') IS NULL
BEGIN
    EXEC (
        'CREATE DATABASE qr_native_lakehouse
         COLLATE Latin1_General_100_BIN2_UTF8'
    );
END;
GO

USE qr_native_lakehouse;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.external_data_sources
    WHERE name = 'ds_datalake'
)
BEGIN
    EXEC (
        'CREATE EXTERNAL DATA SOURCE ds_datalake
         WITH (
             LOCATION = ''https://stqrdenativeui740561.dfs.core.windows.net/datalake''
         )'
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.external_file_formats
    WHERE name = 'ff_parquet'
)
BEGIN
    EXEC (
        'CREATE EXTERNAL FILE FORMAT ff_parquet
         WITH (FORMAT_TYPE = PARQUET)'
    );
END;
GO

SELECT DB_NAME() AS database_name;

SELECT name, location
FROM sys.external_data_sources
WHERE name = 'ds_datalake';

SELECT name, format_type
FROM sys.external_file_formats
WHERE name = 'ff_parquet';
