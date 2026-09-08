#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CIPP Tenant Health Monitor
    监控所有租户的 GraphErrorCount、ComplianceUrl 和连接状态

.PARAMETER AutoFix
    自动重置 GraphErrorCount >= 50 的租户

.PARAMETER Threshold
    告警阈值（默认 10）

.EXAMPLE
    ./Monitor-TenantHealth.ps1
    ./Monitor-TenantHealth.ps1 -AutoFix
    ./Monitor-TenantHealth.ps1 -Threshold 5 -AutoFix
#>
[CmdletBinding()]
param(
    [switch]$AutoFix,
    [int]$Threshold = 10
)

$ErrorActionPreference = 'Stop'
$ConnStr = "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNoBnZf6KgBVU4=;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;QueueEndpoint=http://127.0.0.1:10001/devstoreaccount1;TableEndpoint=http://127.0.0.1:10002/devstoreaccount1;"

# Module may be in ../backend/Modules (when running from scripts/) or ../Modules (when running from backend/scripts/)
$modPath = "$PSScriptRoot/../backend/Modules/AzBobbyTables"
if (-not (Test-Path $modPath)) { $modPath = "$PSScriptRoot/../Modules/AzBobbyTables" }
Import-Module $modPath -Force

$Ctx = New-AzDataTableContext -ConnectionString $ConnStr -TableName "Tenants"
$Table = @{ Context = $Ctx }
$Entities = Get-AzDataTableEntity @Table
$Tenants = $Entities | Where-Object { $_.PartitionKey -eq 'Tenants' }

Write-Host ""
Write-Host "=== CIPP Tenant Health Monitor ===" -ForegroundColor Cyan
Write-Host "Time: $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss UTC'))" -ForegroundColor Gray
Write-Host "Threshold: $Threshold | AutoFix: $AutoFix" -ForegroundColor Gray
Write-Host ""

$Healthy = 0; $Warning = 0; $Critical = 0; $Fixed = 0

foreach ($Tenant in $Tenants) {
    $Name = if ($Tenant.displayName) { $Tenant.displayName } else { "(unknown)" }
    $Domain = if ($Tenant.defaultDomainName) { $Tenant.defaultDomainName } else { "(none)" }
    $Errors = if ($null -ne $Tenant.GraphErrorCount) { $Tenant.GraphErrorCount } else { 0 }
    $Status = if ($Tenant.delegatedPrivilegeStatus) { $Tenant.delegatedPrivilegeStatus } else { "(not set)" }
    $ComplianceUrl = if ($Tenant.ComplianceUrl) { $Tenant.ComplianceUrl } else { "(not set)" }

    if ($Errors -ge 50) {
        $Level = "CRITICAL"
        $Color = "Red"
        $Critical++
        if ($AutoFix) {
            $Tenant.GraphErrorCount = 0
            Update-AzDataTableEntity @Table -Entity $Tenant
            $Level = "FIXED"
            $Color = "Yellow"
            $Fixed++
            $Critical--
        }
    } elseif ($Errors -ge $Threshold) {
        $Level = "WARNING"
        $Color = "Yellow"
        $Warning++
    } else {
        $Level = "OK"
        $Color = "Green"
        $Healthy++
    }

    Write-Host "  [$Level] $Name" -ForegroundColor $Color
    Write-Host "    Domain: $Domain" -ForegroundColor Gray
    Write-Host "    TenantID: $($Tenant.RowKey)" -ForegroundColor DarkGray
    Write-Host "    Errors: $Errors | Status: $Status" -ForegroundColor Gray
    Write-Host "    ComplianceUrl: $ComplianceUrl" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "─── Summary ───────────────────────────" -ForegroundColor DarkGray
Write-Host "  Healthy:  $Healthy" -ForegroundColor Green
Write-Host "  Warning:  $Warning" -ForegroundColor Yellow
Write-Host "  Critical: $Critical" -ForegroundColor Red
if ($AutoFix) {
    Write-Host "  Fixed:    $Fixed" -ForegroundColor Yellow
}
Write-Host ""

# Check port 446 connectivity (Compliance API)
Write-Host "─── Compliance API Port Check ─────────" -ForegroundColor DarkGray
$PortTest = Test-NetConnection -ComputerName "apc01b.admin.protection.outlook.com" -Port 446 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
if ($PortTest.TcpTestSucceeded) {
    Write-Host "  Port 446: OPEN ✓" -ForegroundColor Green
} else {
    Write-Host "  Port 446: BLOCKED ✗ (DlpCompliancePolicies will not work)" -ForegroundColor Red
    Write-Host "  Fix: Open port 446 outbound in your cloud firewall" -ForegroundColor Yellow
    Write-Host "  See TROUBLESHOOTING.md for details" -ForegroundColor Yellow
}
Write-Host ""
