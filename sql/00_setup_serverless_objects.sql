/*
Azure-Native Data Engineering UI
Showcase export of the Synapse Serverless SQL setup performed through the UI.

Run once in a user database such as qr_native_demo.
Never commit a real master-key password, SAS token, or storage key.
The Synapse workspace managed identity requires Storage Blob Data Reader/
Contributor access appropriate to the operations performed.
*/

-- Create the database from the master database if it does not already exist:
-- CREATE DATABASE qr_native_demo;
-- GO
-- USE qr_native_demo;
-- GO

-- A database master key is required before creating a database-scoped credential.
-- Run once with a secret supplied outside source control:
-- CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<SUPPLY_SECURE_PASSWORD_AT_RUNTIME>';
-- GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_scoped_credentials
    WHERE name = 'WorkspaceIdentity'
)
BEGIN
    EXEC (
        'CREATE DATABASE SCOPED CREDENTIAL WorkspaceIdentity
         WITH IDENTITY = ''Managed Identity'';'
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.external_data_sources
    WHERE name = 'DataLake'
)
BEGIN
    EXEC (
        'CREATE EXTERNAL DATA SOURCE DataLake
         WITH (
             LOCATION = ''abfss://datalake@stqrdenativeui740561.dfs.core.windows.net'',
             CREDENTIAL = WorkspaceIdentity
         );'
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.external_file_formats
    WHERE name = 'ParquetFormat'
)
BEGIN
    EXEC (
        'CREATE EXTERNAL FILE FORMAT ParquetFormat
         WITH (FORMAT_TYPE = PARQUET);'
    );
END;
GO

SELECT name, location, type_desc
FROM sys.external_data_sources
WHERE name = 'DataLake';

SELECT name, format_type
FROM sys.external_file_formats
WHERE name = 'ParquetFormat';

