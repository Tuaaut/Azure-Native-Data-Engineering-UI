-- This is auto-generated code
SELECT TOP 100
    jsonContent
/* --> place the keys that you see in JSON documents in the WITH clause:
       , JSON_VALUE (jsonContent, '$.key1') ASheader1
       , JSON_VALUE (jsonContent, '$.key2')ASheader2
*/
FROM
    OPENROWSET(
        BULK 'https://stqrdenativeui740561.dfs.core.windows.net/datalake/raw/machine_api/*/machine_api_response.json',
        FORMAT = 'CSV',
        FIELDQUOTE = '0x0b',
        FIELDTERMINATOR ='0x0b',
        ROWTERMINATOR = '0x0b'
    )
    WITH (
        jsonContent varchar(MAX)
    ) AS [result]
