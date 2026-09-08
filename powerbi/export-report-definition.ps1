param(
    [string]$WorkspaceId = '7476d3d8-5ac1-4db5-8628-98876c92581c',
    [string]$ReportId = '17fe59dd-771e-4c81-95a0-e127d8c1adc3',
    [string]$SemanticModelId = 'f3f6f6e3-4c30-4153-94c9-f42198a66a5b',
    [string]$ProjectName = 'rpt_print_event_kpis_daily',
    [string]$OutputDirectory = $PSScriptRoot,
    [switch]$IncludeSemanticModel
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Get-FabricDefinition {
    param(
        [string]$Uri,
        [hashtable]$Headers
    )

    $response = Invoke-WebRequest -Method Post -Uri $Uri -Headers $Headers -ContentType 'application/json'
    $definitionResponse = $null
    if ($response.StatusCode -eq 200) {
        $definitionResponse = $response.Content | ConvertFrom-Json
    } elseif ($response.StatusCode -eq 202) {
        $operationUri = [string]@($response.Headers['Location'])[0]
        for ($attempt = 0; $attempt -lt 24; $attempt++) {
            Start-Sleep -Seconds 3
            $operationResponse = Invoke-WebRequest -Method Get -Uri $operationUri -Headers $Headers
            $operation = $operationResponse.Content | ConvertFrom-Json
            if ($operation.status -eq 'Succeeded') {
                $resultUri = [string]@($operationResponse.Headers['Location'])[0]
                $definitionResponse = (Invoke-WebRequest -Method Get -Uri $resultUri -Headers $Headers).Content | ConvertFrom-Json
                break
            }
            if ($operation.status -eq 'Failed') {
                throw ('Fabric definition operation failed: ' + $operationResponse.Content)
            }
        }
    } else {
        throw ('Unexpected Fabric definition response: HTTP ' + $response.StatusCode)
    }

    if ($null -eq $definitionResponse) {
        throw 'Fabric definition operation did not return a result.'
    }
    return $definitionResponse
}

function Write-DefinitionParts {
    param(
        [object]$Definition,
        [string]$OutputRoot
    )

    $targetRoot = (Resolve-Path $OutputRoot).Path
    $prefix = $targetRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    foreach ($part in $Definition.parts) {
        if ($part.payloadType -ne 'InlineBase64') {
            throw ('Unsupported definition payload type: ' + $part.payloadType)
        }
        $relativePath = ([string]$part.path).Replace('/', [IO.Path]::DirectorySeparatorChar)
        if ([IO.Path]::IsPathRooted($relativePath) -or $relativePath.Contains('..')) {
            throw ('Unsafe definition path: ' + $part.path)
        }
        $destination = [IO.Path]::GetFullPath((Join-Path $targetRoot $relativePath))
        if (!$destination.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw ('Definition path escaped output directory: ' + $part.path)
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        [IO.File]::WriteAllBytes($destination, [Convert]::FromBase64String([string]$part.payload))
    }
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$projectBase = Join-Path $OutputDirectory $ProjectName
if ((Test-Path ($projectBase + '.pbip')) -or (Test-Path ($projectBase + '.Report')) -or ($IncludeSemanticModel -and (Test-Path ($projectBase + '.SemanticModel')))) {
    $projectBase = Join-Path $OutputDirectory ($ProjectName + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$reportDirectory = $projectBase + '.Report'
New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null

$token = az account get-access-token --resource 'https://api.fabric.microsoft.com' --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
    throw 'Azure CLI did not return a Fabric access token.'
}
$headers = @{ Authorization = 'Bearer ' + $token }

$reportUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/reports/$ReportId/getDefinition"
$reportResponse = Get-FabricDefinition -Uri $reportUri -Headers $headers
if ($reportResponse.definition.format -ne 'PBIR') {
    throw ('The service returned an unexpected report format: ' + $reportResponse.definition.format)
}
Write-DefinitionParts -Definition $reportResponse.definition -OutputRoot $reportDirectory

$semanticModelDirectory = $null
if ($IncludeSemanticModel) {
    $semanticModelDirectory = $projectBase + '.SemanticModel'
    New-Item -ItemType Directory -Force -Path $semanticModelDirectory | Out-Null
    $semanticUri = "https://api.fabric.microsoft.com/v1/workspaces/$WorkspaceId/semanticModels/$SemanticModelId/getDefinition?format=TMDL"
    $semanticResponse = Get-FabricDefinition -Uri $semanticUri -Headers $headers
    if ($semanticResponse.definition.format -ne 'TMDL') {
        throw ('The service returned an unexpected semantic model format: ' + $semanticResponse.definition.format)
    }
    Write-DefinitionParts -Definition $semanticResponse.definition -OutputRoot $semanticModelDirectory

    $pbirPath = Join-Path $reportDirectory 'definition.pbir'
    $pbir = Get-Content -LiteralPath $pbirPath -Raw | ConvertFrom-Json
    $pbir.datasetReference = [ordered]@{
        byPath = [ordered]@{
            path = '../' + [IO.Path]::GetFileName($semanticModelDirectory)
        }
    }
    [IO.File]::WriteAllText($pbirPath, ($pbir | ConvertTo-Json -Depth 8), $utf8NoBom)
}

$pbip = [ordered]@{
    '$schema' = 'https://developer.microsoft.com/json-schemas/fabric/pbip/pbipProperties/1.0.0/schema.json'
    version = '1.0'
    artifacts = @(
        [ordered]@{
            report = [ordered]@{ path = [IO.Path]::GetFileName($reportDirectory) }
        }
    )
}
[IO.File]::WriteAllText(($projectBase + '.pbip'), ($pbip | ConvertTo-Json -Depth 8), $utf8NoBom)

Write-Output ('PBIP: ' + $projectBase + '.pbip')
Write-Output ('Report folder: ' + $reportDirectory)
if ($semanticModelDirectory) {
    Write-Output ('Semantic model folder: ' + $semanticModelDirectory)
}
Write-Output ('Report PBIR parts: ' + $reportResponse.definition.parts.Count)
if ($semanticModelDirectory) {
    Write-Output ('Semantic TMDL parts: ' + $semanticResponse.definition.parts.Count)
}
