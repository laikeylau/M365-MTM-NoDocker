#!/usr/bin/env pwsh
<#
.SYNOPSIS
    CIPP Tenant Onboarding Script for Linux/GDAP mode
.DESCRIPTION
    Automates all permission setup for a new Microsoft 365 tenant in CIPP.
    Run this ONCE per tenant after adding it to CIPP via GDAP.

    What it does:
    1. Assigns Exchange Administrator directory role to CIPP-SAM service principal
    2. Triggers CPV (Cross-Tenant Access) admin consent
    3. Syncs mailbox cache to reporting database
    4. Verifies connectivity

.PARAMETER TenantDomain
    The tenant's default domain (e.g. contoso.onmicrosoft.com)

.PARAMETER CippSamAppId
    CIPP-SAM Application ID. Default: 98779b37-04c7-4714-887a-0c3bae41cb82

.PARAMETER CippUrl
    CIPP frontend URL for redirect. Default: https://mtm.cxty.de

.EXAMPLE
    ./Onboard-CIPPTenant.ps1 -TenantDomain "contoso.onmicrosoft.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantDomain,

    [string]$CippSamAppId = '98779b37-04c7-4714-887a-0c3bae41cb82',
    [string]$CippUrl = 'https://mtm.cxty.de/authredirect',
    [string]$CippApiUrl = 'http://localhost:7071'
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "`n[$Step] $Message" -ForegroundColor Cyan
}

function Write-OK {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  ✗ $Message" -ForegroundColor Red
}

# ============================================================
# Step 1: Get access token for customer tenant
# ============================================================
Write-Step "1/5" "Authenticating to tenant $TenantDomain..."

try {
    $Body = @{
        grant_type    = 'client_credentials'
        client_id     = $env:CIPP_SAM_CLIENT_ID
        client_secret = $env:CIPP_SAM_CLIENT_SECRET
        scope         = 'https://graph.microsoft.com/.default'
    }
    $TokenResponse = Invoke-RestMethod -Method Post -Uri "https://login.microsoftonline.com/$TenantDomain/oauth2/v2.0/token" -Body $Body -ContentType 'application/x-www-form-urlencoded'
    $AccessToken = $TokenResponse.access_token
    Write-OK "Got access token for $TenantDomain"
} catch {
    Write-Fail "Authentication failed: $($_.Exception.Message)"
    Write-Host "`nEnsure CIPP_SAM_CLIENT_ID and CIPP_SAM_CLIENT_SECRET environment variables are set."
    exit 1
}

$Headers = @{ Authorization = "Bearer $AccessToken"; 'Content-Type' = 'application/json' }

# ============================================================
# Step 2: Get CIPP-SAM Service Principal ID in customer tenant
# ============================================================
Write-Step "2/5" "Finding CIPP-SAM service principal in $TenantDomain..."

try {
    $SP = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?filter=appId eq '$CippSamAppId'" -Headers $Headers
    if ($SP.value.Count -eq 0) {
        Write-Host "  Service principal not found. Creating..." -ForegroundColor Yellow
        $NewSP = @{ appId = $CippSamAppId } | ConvertTo-Json
        $SP = Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/v1.0/servicePrincipals" -Body $NewSP -Headers $Headers
        $SpId = $SP.id
    } else {
        $SpId = $SP.value[0].id
    }
    Write-OK "Service Principal ID: $SpId"
} catch {
    Write-Fail "Failed to get service principal: $($_.Exception.Message)"
    exit 1
}

# ============================================================
# Step 3: Assign Exchange Administrator directory role
# ============================================================
Write-Step "3/5" "Assigning Exchange Administrator role..."

try {
    # Exchange Administrator role template ID
    $ExoAdminRoleId = '29232cdf-9323-42fd-ade2-1d097af3e4de'

    # Check if already assigned
    $ExistingRoles = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SpId/appRoleAssignments" -Headers $Headers
    $AlreadyAssigned = $ExistingRoles.value | Where-Object { $_.appRoleId -eq $ExoAdminRoleId }

    if ($AlreadyAssigned) {
        Write-OK "Exchange Administrator role already assigned"
    } else {
        $RoleBody = @{
            principalId = $SpId
            resourceId  = $SpId  # For directory roles, resourceId = SP itself
            appRoleId   = $ExoAdminRoleId
        } | ConvertTo-Json

        # Try via directory role assignment (different API for directory roles)
        $DirRole = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/directoryRoles?filter=roleTemplateId eq '$ExoAdminRoleId'" -Headers $Headers
        if ($DirRole.value.Count -eq 0) {
            # Activate the role first
            $ActivateBody = @{ roleTemplateId = $ExoAdminRoleId } | ConvertTo-Json
            $DirRole = Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/v1.0/directoryRoles" -Body $ActivateBody -Headers $Headers
            $DirRoleId = $DirRole.id
        } else {
            $DirRoleId = $DirRole.value[0].id
        }

        $MemberBody = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/servicePrincipals/$SpId" } | ConvertTo-Json
        Invoke-RestMethod -Method Post -Uri "https://graph.microsoft.com/v1.0/directoryRoles/$DirRoleId/members/`$ref" -Body $MemberBody -Headers $Headers
        Write-OK "Exchange Administrator role assigned"
    }
} catch {
    Write-Warn "Role assignment issue (may already exist): $($_.Exception.Message)"
}

# ============================================================
# Step 4: Sync mailbox cache
# ============================================================
Write-Step "4/5" "Syncing mailbox cache for $TenantDomain..."

try {
    $CacheBody = '{}' 
    $CacheResult = Invoke-RestMethod -Method Post -Uri "$CippApiUrl/api/ExecCIPPDBCache?Name=Mailboxes&TenantFilter=$TenantDomain" -Body $CacheBody -ContentType 'application/json'
    Write-OK "Cache sync initiated: $($CacheResult.Results)"
} catch {
    Write-Warn "Cache sync via API failed: $($_.Exception.Message)"
}

# Direct sync (since orchestrator is disabled on Linux)
Write-Host "  Running direct mailbox cache sync..." -ForegroundColor Yellow
try {
    $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNoBnZf6KgBVU4=;BlobEndpoint=http://127.0.0.1:10000/devstoreaccount1;QueueEndpoint=http://127.0.0.1:10001/devstoreaccount1;TableEndpoint=http://127.0.0.1:10002/devstoreaccount1;'
    $env:NonLocalHostAzurite = 'true'
    $env:CIPPRootPath = (Resolve-Path "$PSScriptRoot/../CIPP-API").Path
    $env:DisableCIPPRestMethod = 'true'

    Import-Module "$env:CIPPRootPath/Modules/CIPPDB" -Force -ErrorAction SilentlyContinue
    Import-Module "$env:CIPPRootPath/Modules/CIPPCore" -Force -ErrorAction SilentlyContinue
    Set-CIPPDBCacheMailboxes -TenantFilter $TenantDomain
    Write-OK "Mailbox cache synced"
} catch {
    Write-Warn "Direct sync issue: $($_.Exception.Message)"
}

# ============================================================
# Step 5: Verify
# ============================================================
Write-Step "5/5" "Verifying connectivity..."

try {
    $Mailboxes = Invoke-RestMethod -Uri "$CippApiUrl/api/ListMailboxes?TenantFilter=$TenantDomain&UseReportDB=true"
    if ($Mailboxes -is [array] -and $Mailboxes.Count -gt 0 -and $Mailboxes[0].UPN) {
        Write-OK "Found $($Mailboxes.Count) mailboxes:"
        foreach ($mb in $Mailboxes) {
            Write-Host "    - $($mb.UPN) ($($mb.recipientTypeDetails))" -ForegroundColor Gray
        }
    } else {
        Write-Warn "Mailbox list returned unexpected data: $($Mailboxes | ConvertTo-Json -Depth 1)"
    }
} catch {
    Write-Warn "Verification issue: $($_.Exception.Message)"
}

# ============================================================
# CPV Consent URL
# ============================================================
Write-Host "`n" + "=" * 60 -ForegroundColor Cyan
Write-Host "NEXT STEP: CPV Admin Consent" -ForegroundColor Yellow
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "`nOpen this URL in a browser and sign in as Global Admin:"
Write-Host "https://login.microsoftonline.com/$TenantDomain/adminconsent?client_id=$CippSamAppId&redirect_uri=$CippUrl" -ForegroundColor Green
Write-Host "`nAfter consent, the tenant is fully onboarded.`n"
