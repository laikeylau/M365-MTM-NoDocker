#Requires -Version 7.4
<#
.SYNOPSIS
    One-shot migration from Azurite / Azure Table Storage to the SQLite (AzTablesShim) store.

.DESCRIPTION
    Reads every table from the source storage account (Azurite emulator or a real Azure
    Storage account) and writes each row into the SQLite database used by the
    AzTablesShim module. Values are carried over as-is (the shim stores properties as
    typed JSON, so strings/ints/dates/guids round-trip without conversion logic).

    Source connection:      $env:AZURITE_CONNECTION_STRING (default 'UseDevelopmentStorage=true'
                            when Azurite runs on localhost with its default endpoints)
    Target database:        -DatabasePath  (default <backend>/data/cipp.db)
    Tables:                 all, or a subset with -Tables

.EXAMPLE
    # Azurite running in Docker on localhost
    pwsh -File scripts/Migrate-AzuriteToSqlite.ps1

.EXAMPLE
    # Explicit connection string and target
    pwsh -File scripts/Migrate-AzuriteToSqlite.ps1 `
        -SourceConnectionString 'DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vd...;TableEndpoint=http://127.0.0.1:10002/devstoreaccount1;' `
        -DatabasePath C:\DEVT\M365-MTM\backend\data\cipp.db
#>

param(
    [string]$SourceConnectionString = $env:AZURITE_CONNECTION_STRING ?? 'UseDevelopmentStorage=true',
    [string]$DatabasePath,
    [string[]]$Tables,
    [int]$BatchSize = 400,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$BackendRoot = Join-Path $RepoRoot 'backend'
$DatabasePath = $DatabasePath ?? (Join-Path $BackendRoot 'data' 'cipp.db')

# ── source: real AzBobbyTables (installed module) ────────────────────────────
if (-not (Get-Module -ListAvailable AzBobbyTables)) {
    throw "AzBobbyTables module is required to read the source store. Install with: Install-Module AzBobbyTables -Force"
}
Import-Module AzBobbyTables -Force

# ── target: the shim ─────────────────────────────────────────────────────────
Import-Module (Join-Path $BackendRoot 'Modules' 'AzTablesShim') -Force
$env:CIPP_SQLITE_DB = $DatabasePath
New-Item -ItemType Directory -Force -Path (Split-Path $DatabasePath) | Out-Null

Write-Host "Source connection: $SourceConnectionString" -ForegroundColor Cyan
Write-Host "Target database:   $DatabasePath" -ForegroundColor Cyan

# Enumerate source tables
$srcContext = New-AzDataTableContext -ConnectionString $SourceConnectionString -TableName 'dummy'
$allTables = Get-AzDataTable -Context $srcContext
if (-not $allTables) { Write-Warning 'No tables found in the source store. Nothing to do.'; return }
if ($Tables) { $allTables = @($allTables | Where-Object { $_ -in $Tables }) }
Write-Host ("Found {0} tables: {1}" -f $allTables.Count, ($allTables -join ', ')) -ForegroundColor Cyan

$totalRows = 0
foreach ($tableName in $allTables) {
    $ctx = New-AzDataTableContext -ConnectionString $SourceConnectionString -TableName $tableName
    $rows = @(Get-AzDataTableEntity -Context $ctx)
    if ($rows.Count -eq 0) {
        Write-Host ("  {0,-50} 0 rows (skipped)" -f $tableName) -ForegroundColor DarkGray
        continue
    }

    Write-Host ("  {0,-50} {1} rows" -f $tableName, $rows.Count) -NoNewline
    if ($WhatIf) { Write-Host ' (whatif)' -ForegroundColor Yellow; continue }

    $dstContext = New-AzDataTableContext -ConnectionString 'UseDevelopmentStorage=true' -TableName $tableName
    $null = New-AzDataTable -Context $dstContext

    $migrated = 0
    for ($i = 0; $i -lt $rows.Count; $i += $BatchSize) {
        $batch = $rows[$i..([math]::Min($i + $BatchSize - 1, $rows.Count - 1))]
        try {
            # Force upsert so re-runs are idempotent
            Add-AzDataTableEntity -Context $dstContext -Entity $batch -Force -ErrorAction Stop
            $migrated += $batch.Count
        } catch {
            # Fall back to row-by-row so one bad row does not sink the table
            foreach ($row in $batch) {
                try {
                    Add-AzDataTableEntity -Context $dstContext -Entity $row -Force -ErrorAction Stop
                    $migrated++
                } catch {
                    Write-Warning ("    row {0}/{1} failed: {2}" -f $row.PartitionKey, $row.RowKey, $_.Exception.Message)
                }
            }
        }
    }
    $totalRows += $migrated
    Write-Host (" -> migrated {0}" -f $migrated) -ForegroundColor Green
}

Write-Host ''
Write-Host "Migration complete. $totalRows rows written to $DatabasePath" -ForegroundColor Green
Write-Host 'Point the server at this database:  $env:CIPP_SQLITE_DB = ' -NoNewline
Write-Host "'$DatabasePath'" -ForegroundColor Yellow
