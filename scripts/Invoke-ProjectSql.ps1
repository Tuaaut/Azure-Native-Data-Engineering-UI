param(
    [string]$File,
    [string]$Query,
    [string]$Database = 'qr_native_lakehouse',
    [int]$Timeout = 180
)
$ErrorActionPreference = 'Stop'
if ($File) { $Query = Get-Content -LiteralPath $File -Raw }
if (-not $Query) { throw 'Supply -File or -Query.' }
$sqlToken = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Azure authentication failed.' }
$sqlConnection = [System.Data.SqlClient.SqlConnection]::new("Server=tcp:syn-qr-de-native-ui-740561-ondemand.sql.azuresynapse.net,1433;Database=$Database;Encrypt=True;TrustServerCertificate=False;Connection Timeout=20;")
$sqlConnection.AccessToken = $sqlToken
try {
    $sqlConnection.Open()
    foreach ($batch in [regex]::Split($Query, '(?im)^\s*GO\s*\r?$')) {
        if (-not $batch.Trim()) { continue }
        $sqlCommand = $sqlConnection.CreateCommand()
        $sqlCommand.CommandTimeout = $Timeout
        $sqlCommand.CommandText = $batch
        $sqlReader = $sqlCommand.ExecuteReader()
        try {
            do {
                while ($sqlReader.Read()) {
                    $sqlRow = [ordered]@{}
                    for ($i = 0; $i -lt $sqlReader.FieldCount; $i++) {
                        $sqlRow[$sqlReader.GetName($i)] = if ($sqlReader.IsDBNull($i)) { $null } else { $sqlReader.GetValue($i) }
                    }
                    [pscustomobject]$sqlRow | ConvertTo-Json -Compress -Depth 10
                }
            } while ($sqlReader.NextResult())
        } finally { $sqlReader.Dispose(); $sqlCommand.Dispose() }
    }
} finally { $sqlConnection.Dispose(); $sqlToken = $null }
