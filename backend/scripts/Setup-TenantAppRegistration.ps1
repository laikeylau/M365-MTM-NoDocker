#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CIPP Mode C: Setup Independent App Registration per Tenant
    为每个租户创建独立的 App Registration 并配置权限

.DESCRIPTION
    在目标租户中创建独立的 App Registration，配置所需的 Application Permissions，
    并将凭据存储到 Azurite DevSecrets 表中。适用于需要高安全隔离的场景。

.PARAMETER TenantId
    目标租户 ID (GUID)

.PARAMETER AppDisplayName
    App Registration 显示名称 (默认: CIPP-Managed)

.PARAMETER AdminCredential
    目标租户 Global Admin 凭据 (用于授权 Admin Consent)

.EXAMPLE
    ./Setup-TenantAppRegistration.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [string]$AppDisplayName = "CIPP-Managed",

    [PSCredential]$AdminCredential,

    [string]$AzuriteConnectionString = "AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;TableEndpoint=http://127.0.0.1:10002/devstoreaccount1"
)

$ErrorActionPreference = "Stop"

# ── Helper: Get property value (兼容 Invoke-MgGraphRequest camelCase 和 cmdlet PascalCase) ──
function Get-Prop($Obj, $PascalName) {
    if ($null -eq $Obj) { return $null }
    if ($Obj.PSObject.Properties[$PascalName]) { return $Obj.$PascalName }
    $CamelName = $PascalName.Substring(0,1).ToLower() + $PascalName.Substring(1)
    if ($Obj.PSObject.Properties[$CamelName]) { return $Obj.$CamelName }
    return $null
}

Write-Host "`n=== CIPP Mode C: Independent App Registration Setup ===" -ForegroundColor Cyan
Write-Host "Target Tenant: $TenantId" -ForegroundColor DarkGray

# ── Step 1: Connect to Target Tenant ──
Write-Host "`n[1/6] Connecting to target tenant..." -ForegroundColor Yellow
try {
    if ($AdminCredential) {
        Connect-MgGraph -TenantId $TenantId -Credential $AdminCredential -NoWelcome
    } else {
        Connect-MgGraph -TenantId $TenantId -Scopes "Application.ReadWrite.All", "AppRoleAssignment.ReadWrite.All" -NoWelcome
    }
    $Context = Get-MgContext
    Write-Host "  ✅ Connected as $($Context.Account) to $($Context.TenantId)" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Failed to connect: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ── Step 2: Create App Registration ──
Write-Host "`n[2/6] Creating App Registration '$AppDisplayName'..." -ForegroundColor Yellow
try {
    # Try to find existing app first
    $ExistingApp = $null
    try {
        $ExistingApp = Get-MgApplication -Filter "displayName eq '$AppDisplayName'" -ErrorAction SilentlyContinue
    } catch {
        $AllApps = Get-MgApplication -ErrorAction SilentlyContinue
        $ExistingApp = $AllApps | Where-Object { $_.DisplayName -eq $AppDisplayName } | Select-Object -First 1
    }

    if ($ExistingApp) {
        $AppId = Get-Prop $ExistingApp 'AppId'
        Write-Host "  ⚠️ App '$AppDisplayName' already exists (AppId: $AppId). Using existing." -ForegroundColor Yellow
        $App = $ExistingApp
    } else {
        Write-Host "  Creating new app via REST API..." -ForegroundColor DarkGray

        # Get access token from MgGraph context
        $Token = (Get-MgContext).AccessToken
        $Headers = @{ Authorization = "Bearer $Token" }

        $AppBody = @{
            displayName    = $AppDisplayName
            signInAudience = "AzureADMyOrg"
        } | ConvertTo-Json

        $App = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/applications" `
            -Method POST -Headers $Headers -Body $AppBody -ContentType "application/json"
        Write-Host "  ✅ App created: AppId=$($App.appId), Id=$($App.id)" -ForegroundColor Green
    }
} catch {
    Write-Host "  ❌ Failed to create app" -ForegroundColor Red
    Write-Host "  Error Type: $($_.Exception.GetType().FullName)" -ForegroundColor DarkGray
    Write-Host "  Error Message: $($_.Exception.Message)" -ForegroundColor DarkGray
    if ($_.Exception.Response) {
        Write-Host "  Status Code: $($_.Exception.Response.StatusCode)" -ForegroundColor DarkGray
    }
    if ($_.ErrorDetails.Message) {
        Write-Host "  API Error: $($_.ErrorDetails.Message)" -ForegroundColor DarkGray
    }
    if ($_.Exception.InnerException) {
        Write-Host "  Inner: $($_.Exception.InnerException.Message)" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  常见原因:" -ForegroundColor Yellow
    Write-Host "  1. 当前账号没有 Application.ReadWrite.All 权限" -ForegroundColor Yellow
    Write-Host "  2. 租户策略禁止创建 App Registration" -ForegroundColor Yellow
    Write-Host "  3. Microsoft.Graph 模块版本问题 - 尝试: Install-Module Microsoft.Graph -Force -AllowClobber" -ForegroundColor Yellow
    exit 1
}

$AppId = Get-Prop $App 'AppId'
$AppObjId = Get-Prop $App 'Id'

# ── Step 3: Create Client Secret ──
Write-Host "`n[3/6] Creating Client Secret..." -ForegroundColor Yellow
try {
    $SecretBody = @{
        passwordCredential = @{
            displayName = "CIPP-Secret-$(Get-Date -Format 'yyyyMMdd')"
            endDateTime = (Get-Date).AddYears(2).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    } | ConvertTo-Json -Depth 5

    $SecretResp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/applications/$AppObjId/addPassword" `
        -Method POST -Headers $Headers -Body $SecretBody -ContentType "application/json"
    $SecretText = $SecretResp.secretText
    $SecretExpiry = $SecretResp.endDateTime
    Write-Host "  ✅ Secret created (expires: $SecretExpiry)" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Failed to create secret: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) { Write-Host "  API Error: $($_.ErrorDetails.Message)" -ForegroundColor DarkGray }
    exit 1
}

# ── Step 4: Create Service Principal ──
Write-Host "`n[4/6] Creating Service Principal..." -ForegroundColor Yellow
try {
    $SPResp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$AppId'" `
        -Method GET -Headers $Headers -ContentType "application/json"
    if ($SPResp.value.Count -gt 0) {
        $SP = $SPResp.value[0]
        Write-Host "  ⚠️ Service Principal already exists" -ForegroundColor Yellow
    } else {
        $SPBody = @{ appId = $AppId } | ConvertTo-Json
        $SP = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals" `
            -Method POST -Headers $Headers -Body $SPBody -ContentType "application/json"
        Write-Host "  ✅ Service Principal created" -ForegroundColor Green
    }
} catch {
    Write-Host "  ❌ Failed to create SP: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$SPId = $SP.id

# ── Step 5: Assign Application Permissions ──
Write-Host "`n[5/6] Assigning Application Permissions..." -ForegroundColor Yellow

$GraphSPResp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'" `
    -Method GET -Headers $Headers -ContentType "application/json"
$GraphSP = $GraphSPResp.value[0]
$GraphSPId = $GraphSP.id

$RequiredPermissions = @(
    "Application.ReadWrite.All"
    "Directory.ReadWrite.All"
    "User.ReadWrite.All"
    "Group.ReadWrite.All"
    "Mail.ReadWrite"
    "Calendars.ReadWrite"
    "Sites.FullControl.All"
    "DeviceManagementManagedDevices.ReadWrite.All"
    "DeviceManagementConfiguration.ReadWrite.All"
    "Policy.ReadWrite.ConditionalAccess"
    "RoleManagement.ReadWrite.Directory"
    "AuditLog.Read.All"
    "SecurityEvents.ReadWrite.All"
    "Organization.ReadWrite.All"
    "Domain.ReadWrite.All"
    "Reports.Read.All"
    "Contacts.ReadWrite"
    "MailboxSettings.ReadWrite"
    "TeamSettings.ReadWrite.All"
    "ChannelSettings.ReadWrite.All"
    "Exchange.ManageAsApp"
)

$Assigned = 0; $Skipped = 0
foreach ($Permission in $RequiredPermissions) {
    $AppRole = $GraphSP.AppRoles | Where-Object { $_.Value -eq $Permission }
    if (-not $AppRole) {
        Write-Host "  ⚠️ Permission not found: $Permission" -ForegroundColor DarkYellow
        $Skipped++
        continue
    }

    # Check existing assignments
    $ExistingResp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SPId/appRoleAssignments" `
        -Method GET -Headers $Headers -ContentType "application/json" -ErrorAction SilentlyContinue
    $Existing = $ExistingResp.value | Where-Object { $_.appRoleId -eq $AppRole.Id }
    if ($Existing) {
        $Skipped++
        continue
    }

    try {
        $GrantBody = @{
            principalId = $SPId
            resourceId  = $GraphSPId
            appRoleId   = $AppRole.Id
        } | ConvertTo-Json
        Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SPId/appRoleAssignments" `
            -Method POST -Headers $Headers -Body $GrantBody -ContentType "application/json" | Out-Null
        Write-Host "  ✅ $Permission" -ForegroundColor Green
        $Assigned++
    } catch {
        Write-Host "  ❌ $Permission - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "  Assigned: $Assigned, Skipped: $Skipped" -ForegroundColor DarkGray

# ── Step 6: Store Credentials in Azurite ──
Write-Host "`n[6/6] Storing credentials in Azurite..." -ForegroundColor Yellow

# Note: This step requires Azurite to be accessible from this machine
# If running on Windows (not the CIPP server), this will fail — record credentials manually
$StoredInAzurite = $false
try {
    $Ctx = New-AzStorageContext -ConnectionString $AzuriteConnectionString
    $SecretsTable = Get-AzStorageTable -Name "DevSecrets" -Context $Ctx -ErrorAction SilentlyContinue
    if (-not $SecretsTable) {
        $SecretsTable = New-AzStorageTable -Name "DevSecrets" -Context $Ctx
    }
    $CloudTable = $SecretsTable.CloudTable

    $SafeTenantId = $TenantId -replace '-', '_'

    # Store using direct table API (avoid CIPP-specific cmdlets that may not be available on Windows)
    $Entity = @{
        PartitionKey         = "Secret"
        RowKey               = "Secret"
        "AppId_$SafeTenantId"    = $AppId
        "AppSecret_$SafeTenantId" = $SecretText
    }
    Add-AzTableRow -Table $CloudTable -PartitionKey "Secret" -RowKey "Secret" -Property @{
        "AppId_$SafeTenantId"    = $AppId
        "AppSecret_$SafeTenantId" = $SecretText
    } -UpdateExisting
    $StoredInAzurite = $true
    Write-Host "  ✅ Credentials stored in Azurite (AppId_$SafeTenantId)" -ForegroundColor Green
} catch {
    Write-Host "  ⚠️ Cannot reach Azurite from this machine (expected if running on Windows)" -ForegroundColor Yellow
    Write-Host "  Please record the credentials below and store them manually on the CIPP server." -ForegroundColor Yellow
}

# ── Summary ──
Write-Host "`n=== Setup Complete ===" -ForegroundColor Cyan
Write-Host @"

Tenant ID:         $TenantId
App Name:          $AppDisplayName
App ID:            $AppId
App Object ID:     $AppObjId
Secret Text:       $SecretText
Secret Expires:    $SecretExpiry
Service Principal: $SPId

"@ -ForegroundColor White

if (-not $StoredInAzurite) {
    Write-Host "⚠️ Manual Step Required: Store credentials on CIPP server" -ForegroundColor Yellow
    Write-Host @"
SSH to CIPP server and run:

pwsh -Command "
  Import-Module $env:CIPPRootPath/Modules/AzBobbyTables
  `$ConnStr = 'AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==;TableEndpoint=http://127.0.0.1:10002/devstoreaccount1'
  `$Ctx = New-AzDataTableContext -ConnectionString `$ConnStr -TableName 'DevSecrets'
  `$T = @{ Context = `$Ctx }
  `$SafeTenantId = '$TenantId' -replace '-', '_'
  `$Entity = @{
    PartitionKey = 'Secret'
    RowKey = 'Secret'
    'AppId_' + `$SafeTenantId = '$AppId'
    'AppSecret_' + `$SafeTenantId = '$SecretText'
  }
  Add-AzDataTableEntity @T -Entity `$Entity -Force
  Write-Host 'Done'
"
"@ -ForegroundColor DarkGray
}

Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host @"

1. Grant Admin Consent:
   Azure Portal → App Registrations → $AppDisplayName → API Permissions → Grant admin consent
   Or visit: https://login.microsoftonline.com/$TenantId/adminconsent?client_id=$AppId

2. Run Patch-GraphTokenForModeC.ps1 on CIPP server to enable per-tenant auth

3. Test: ./Monitor-TenantHealth.ps1

"@ -ForegroundColor White

# Disconnect
Disconnect-MgGraph | Out-Null

