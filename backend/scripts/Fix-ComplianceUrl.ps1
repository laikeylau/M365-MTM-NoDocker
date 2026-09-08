#!/usr/bin/env pwsh
<#
.SYNOPSIS
    自动发现并设置 CIPP 租户的 ComplianceUrl
.DESCRIPTION
    Compliance API (DlpCompliancePolicies, DlpComplianceRules 等) 需要
    通过 ps.compliance.protection.outlook.com 的 302 重定向获取正确的区域端点。
    本脚本自动探测并将 ComplianceUrl 写入 Azurite Tenants 表。

    已知限制: Compliance API 使用端口 446 (非标准 HTTPS)。
    Oracle Cloud 等部分云平台默认阻止端口 446 出站，会导致 Compliance 功能不可用。
    参见 TROUBLESHOOTING.md。

.PARAMETER TenantFilter
    可选。指定单个租户域名。省略则处理所有租户。

.PARAMETER Force
    强制重新探测，即使已有 ComplianceUrl。

.EXAMPLE
    ./Fix-ComplianceUrl.ps1
    ./Fix-ComplianceUrl.ps1 -TenantFilter 'llatech.onmicrosoft.com'
    ./Fix-ComplianceUrl.ps1 -Force
#>
[CmdletBinding()]
param(
    [string]$TenantFilter,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
$ConnStr = "DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNoBnZf6KgBVU4=;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;QueueEndpoint=http://127.0.0.1:10001/devstoreaccount1;TableEndpoint=http://127.0.0.1:10002/devstoreaccount1;"

# Module may be in ../backend/Modules (when running from scripts/) or ../Modules (when running from backend/scripts/)
$modPath = "$PSScriptRoot/../backend/Modules/AzBobbyTables"
if (-not (Test-Path $modPath)) { $modPath = "$PSScriptRoot/../Modules/AzBobbyTables" }
Import-Module $modPath -Force

# ─── Load tenants ─────────────────────────────────
$Ctx = New-AzDataTableContext -ConnectionString $ConnStr -TableName "Tenants"
$Table = @{ Context = $Ctx }
$Entities = Get-AzDataTableEntity @Table
$Tenants = $Entities | Where-Object { $_.PartitionKey -eq 'Tenants' }

if ($TenantFilter) {
    $Tenants = $Tenants | Where-Object { $_.defaultDomainName -eq $TenantFilter }
}

if (-not $Tenants -or $Tenants.Count -eq 0) {
    Write-Host "[FAIL] No tenants found" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Fix ComplianceUrl ===" -ForegroundColor Cyan
Write-Host "Tenants: $($Tenants.Count)" -ForegroundColor Gray
Write-Host ""

# ─── Probe compliance endpoint ────────────────────
$Updated = 0; $Skipped = 0; $Failed = 0

foreach ($Tenant in $Tenants) {
    $Name = if ($Tenant.displayName) { $Tenant.displayName } else { "(unknown)" }
    $Domain = $Tenant.defaultDomainName

    # Skip if already set (unless -Force)
    $ExistingUrl = if ($Tenant.ComplianceUrl) { $Tenant.ComplianceUrl } else { $null }
    if ($ExistingUrl -and -not $Force) {
        Write-Host "  [SKIP] $Name — ComplianceUrl already set: $ExistingUrl" -ForegroundColor DarkGray
        $Skipped++
        continue
    }

    Write-Host "  [PROBE] $Name ($Domain)..." -ForegroundColor Yellow -NoNewline

    try {
        # Get token via CIPP auth
        $env:AzureWebJobsStorage = $ConnStr
        $env:NonLocalHostAzurite = 'true'
        $env:CIPPRootPath = "$PSScriptRoot/.."
        Import-Module "$PSScriptRoot/../Modules/CIPPCore" -Force -ErrorAction SilentlyContinue

        $Auth = Get-CIPPAuthentication
        $TokenBody = @{
            grant_type    = 'client_credentials'
            client_id     = $env:ApplicationID
            client_secret = $env:ApplicationSecret
            scope         = 'https://ps.compliance.protection.outlook.com/.default'
            tenant_id     = $Tenant.RowKey
        }
        $TokenResp = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$($Tenant.RowKey)/oauth2/v2.0/token" `
            -Method POST -Body $TokenBody -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 30
        $Token = $TokenResp.access_token

        # Probe compliance endpoint (follow redirect to get actual URL)
        $Headers = @{ Authorization = "Bearer $Token" }
        $ComplianceUrl = $null

        try {
            $null = Invoke-WebRequest -Uri "https://ps.compliance.protection.outlook.com/adminapi/v1.0/$($Tenant.RowKey)/casMailbox" `
                -Headers $Headers -Method GET -TimeoutSec 30 -MaximumRedirection 0 -ErrorAction Stop
        } catch {
            if ($_.Exception.Response.StatusCode -eq 302) {
                $Redirect = $_.Exception.Response.Headers.Location
                if ($Redirect) {
                    $Uri = [System.Uri]$Redirect
                    $ComplianceUrl = "$($Uri.Scheme)://$($Uri.Host):$($Uri.Port)"
                }
            }
        }

        if (-not $ComplianceUrl) {
            # Fallback: try direct redirect following
            try {
                $Resp = Invoke-WebRequest -Uri "https://ps.compliance.protection.outlook.com/adminapi/v1.0/$($Tenant.RowKey)/casMailbox" `
                    -Headers $Headers -Method GET -TimeoutSec 30 -MaximumRedirection 5 -ErrorAction Stop
                if ($Resp.BaseResponse.ResponseUri) {
                    $Uri = $Resp.BaseResponse.ResponseUri
                    $ComplianceUrl = "$($Uri.Scheme)://$($Uri.Host):$($Uri.Port)"
                }
            } catch {
                # Last resort: use known region
                $ComplianceUrl = "https://nam01b.admin.protection.outlook.com:446"
                Write-Host " (fallback)" -NoNewline
            }
        }

        if ($ComplianceUrl) {
            # Check if port is reachable
            $Host_ = ([System.Uri]$ComplianceUrl).Host
            $Port = ([System.Uri]$ComplianceUrl).Port
            $TcpTest = Test-NetConnection -ComputerName $Host_ -Port $Port -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
            $PortStatus = if ($TcpTest.TcpTestSucceeded) { "OK" } else { "BLOCKED" }

            # Update tenant table
            if ($null -eq $Tenant.ComplianceUrl) {
                $Tenant | Add-Member -NotePropertyName 'ComplianceUrl' -NotePropertyValue $ComplianceUrl -Force
            } else {
                $Tenant.ComplianceUrl = $ComplianceUrl
            }
            Update-AzDataTableEntity @Table -Entity $Tenant

            $Color = if ($PortStatus -eq "OK") { "Green" } else { "Yellow" }
            Write-Host " → $ComplianceUrl [Port $PortStatus]" -ForegroundColor $Color
            $Updated++
        } else {
            Write-Host " → FAILED (no redirect)" -ForegroundColor Red
            $Failed++
        }
    } catch {
        Write-Host " → ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $Failed++
    }
}

Write-Host ""
Write-Host "Results: Updated=$Updated Skipped=$Skipped Failed=$Failed" -ForegroundColor Cyan
Write-Host ""

if ($Updated -gt 0) {
    Write-Host "NOTE: Compliance API requires port 446 outbound." -ForegroundColor Yellow
    Write-Host "If port 446 is blocked (e.g. Oracle Cloud), DlpCompliancePolicies will not work." -ForegroundColor Yellow
    Write-Host "See TROUBLESHOOTING.md for details." -ForegroundColor Yellow
}
