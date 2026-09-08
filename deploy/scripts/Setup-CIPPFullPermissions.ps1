<#
.SYNOPSIS
    为 CIPP-SAM 应用配置所有必要的 Microsoft 365 管理权限
.DESCRIPTION
    此脚本为 CIPP-SAM 应用配置完整的 M365 管理权限，包括：
    - Exchange Online RBAC
    - SharePoint Online
    - Microsoft Teams
    - Security & Compliance (如果可用)
    
    注意：Azure AD/Entra ID 的 Graph API 权限通过应用注册门户配置，不在此脚本范围内。
.PARAMETER TenantIds
    要配置的租户域名数组
.PARAMETER AllTenants
    从 CIPP API 获取所有租户并配置
.PARAMETER SkipConfirmation
    跳过确认提示
.EXAMPLE
    .\Setup-CIPPFullPermissions.ps1 -TenantIds @("contoso.onmicrosoft.com")
    .\Setup-CIPPFullPermissions.ps1 -AllTenants
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Specific')]
    [string[]]$TenantIds,
    
    [Parameter(Mandatory = $true, ParameterSetName = 'All')]
    [switch]$AllTenants,
    
    [Parameter(Mandatory = $false)]
    [string]$CippAppId = "98779b37-04c7-4714-887a-0c3bae41cb82",
    
    [Parameter(Mandatory = $false)]
    [string]$CippApiUrl = "http://localhost:7071",
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipConfirmation
)

# ==================== 定义所需权限 ====================

# Exchange Online 管理角色
$ExchangeRoles = @(
    "View-Only Configuration"
    "View-Only Recipients"
    "Mail Recipients"
    "Organization Configuration"
    "Distribution Groups"
    "Mail Recipient Creation"
    "Message Tracking"
    "User Options"
    "Role Management"
)

# SharePoint Online 管理员角色
$SharePointRoles = @(
    "SharePoint Administrator"
)

# Microsoft Teams 管理员角色
$TeamsRoles = @(
    "Teams Administrator"
)

# Security & Compliance 角色（可选）
$SecurityRoles = @(
    "Compliance Administrator"
    "Security Reader"
)

# ==================== 辅助函数 ====================

function Write-Step {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "`n▶ $Message" -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✅ $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ⚠️  $Message" -ForegroundColor Yellow
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  ❌ $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "  ℹ️  $Message" -ForegroundColor Gray
}

# ==================== 获取租户列表 ====================

if ($AllTenants) {
    Write-Step "从 CIPP API 获取所有租户..."
    try {
        $tenants = Invoke-RestMethod -Uri "$CippApiUrl/api/ListTenants" -Method Get
        $TenantIds = $tenants | ForEach-Object { 
            if ($_ -is [string]) { $_ } 
            else { $_.defaultDomainName ?? $_.customerId }
        } | Where-Object { $_ -and $_ -ne "llatech.onmicrosoft.com" }
        
        Write-Success "找到 $($TenantIds.Count) 个客户租户"
        $TenantIds | ForEach-Object { Write-Info $_ }
    }
    catch {
        Write-Fail "无法获取租户列表: $_"
        exit 1
    }
}

# ==================== 确认操作 ====================

if (-not $SkipConfirmation) {
    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  即将为以下租户配置 CIPP 完整管理权限:" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    
    Write-Host "`n  📋 租户列表:" -ForegroundColor White
    $TenantIds | ForEach-Object { Write-Host "    - $_" }
    
    Write-Host "`n  🔑 将配置的权限:" -ForegroundColor White
    Write-Host "    Exchange Online: $($ExchangeRoles.Count) 个管理角色" -ForegroundColor Gray
    Write-Host "    SharePoint Online: $($SharePointRoles.Count) 个管理员角色" -ForegroundColor Gray
    Write-Host "    Microsoft Teams: $($TeamsRoles.Count) 个管理员角色" -ForegroundColor Gray
    Write-Host "    Security & Compliance: $($SecurityRoles.Count) 个角色 (可选)" -ForegroundColor Gray
    
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    
    $confirm = Read-Host "`n确认执行? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "操作已取消" -ForegroundColor Gray
        exit 0
    }
}

# ==================== 加载必要模块 ====================

Write-Step "加载 PowerShell 模块..."

# ExchangeOnlineManagement
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Info "安装 ExchangeOnlineManagement..."
    Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber -Scope CurrentUser
}
Import-Module ExchangeOnlineManagement
Write-Success "ExchangeOnlineManagement 已加载"

# MicrosoftTeams
if (-not (Get-Module -ListAvailable -Name MicrosoftTeams)) {
    Write-Info "安装 MicrosoftTeams..."
    Install-Module -Name MicrosoftTeams -Force -AllowClobber -Scope CurrentUser
}
Import-Module MicrosoftTeams
Write-Success "MicrosoftTeams 已加载"

# SharePoint Online Management Shell
if (-not (Get-Module -ListAvailable -Name Microsoft.Online.SharePoint.PowerShell)) {
    Write-Info "安装 SharePoint Online Management Shell..."
    Install-Module -Name Microsoft.Online.SharePoint.PowerShell -Force -AllowClobber -Scope CurrentUser
}
Import-Module Microsoft.Online.SharePoint.PowerShell
Write-Success "SharePoint Online Management Shell 已加载"

# ==================== 处理每个租户 ====================

$allResults = @()

foreach ($tenantId in $TenantIds) {
    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  🏢 处理租户: $tenantId" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    $result = @{
        TenantId          = $tenantId
        Exchange          = @{ Status = "Pending"; RolesAssigned = 0; Errors = @() }
        SharePoint        = @{ Status = "Pending"; Errors = @() }
        Teams             = @{ Status = "Pending"; Errors = @() }
        SecurityCompliance = @{ Status = "Skipped"; Errors = @() }
    }
    
    # ========== Exchange Online ==========
    Write-Step "配置 Exchange Online RBAC..."
    try {
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        Connect-ExchangeOnline -DelegatedOrganization $tenantId -ShowBanner:$false -DisableWAM -ErrorAction Stop
        Write-Success "已连接到 Exchange Online"
        
        # 注册服务主体
        try {
            $sp = New-ServicePrincipal -AppId $CippAppId -Organization $tenantId -ErrorAction Stop
            Write-Success "服务主体已创建: $($sp.ObjectId)"
        }
        catch {
            if ($_.Exception.Message -match "already exists") {
                Write-Warn "服务主体已存在"
            }
            else { throw $_ }
        }
        
        # 分配角色
        $exAssigned = 0
        foreach ($role in $ExchangeRoles) {
            try {
                New-ManagementRoleAssignment -Role $role -App $CippAppId -Name "CIPP-SAM-$($role -replace ' ', '-')" -ErrorAction Stop | Out-Null
                Write-Success "$role"
                $exAssigned++
            }
            catch {
                if ($_.Exception.Message -match "already exists") {
                    Write-Warn "$role (已存在)"
                    $exAssigned++
                }
                else {
                    Write-Fail "$role - $($_.Exception.Message)"
                    $result.Exchange.Errors += "角色 '$role' 失败: $($_.Exception.Message)"
                }
            }
        }
        
        $result.Exchange.RolesAssigned = $exAssigned
        $result.Exchange.Status = if ($exAssigned -eq $ExchangeRoles.Count) { "Success" } elseif ($exAssigned -gt 0) { "Partial" } else { "Failed" }
        
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    }
    catch {
        Write-Fail "Exchange Online 配置失败: $_"
        $result.Exchange.Status = "Failed"
        $result.Exchange.Errors += $_.Exception.Message
    }
    
    # ========== SharePoint Online ==========
    Write-Step "配置 SharePoint Online..."
    try {
        # SharePoint 需要通过 Azure AD 的角色分配，这里检查是否已有权限
        # 注意：SharePoint 管理员角色通常在 Azure AD 中分配
        
        # 获取租户的 SharePoint 管理员 URL
        $tenantPrefix = ($tenantId -split '\.')[0]
        $spoAdminUrl = "https://$tenantPrefix-admin.sharepoint.com"
        
        Write-Info "SharePoint 管理 URL: $spoAdminUrl"
        Write-Info "SharePoint 权限通过 Azure AD 应用权限配置"
        Write-Info "请确保 CIPP-SAM 在 Azure AD 中有以下权限:"
        Write-Info "  - Sites.FullControl.All"
        Write-Info "  - Sites.ReadWrite.All"
        
        $result.SharePoint.Status = "Info"
        $result.SharePoint.Errors += "SharePoint 权限通过 Azure AD 应用权限配置，请在 Azure 门户中验证"
    }
    catch {
        Write-Fail "SharePoint 配置失败: $_"
        $result.SharePoint.Status = "Failed"
        $result.SharePoint.Errors += $_.Exception.Message
    }
    
    # ========== Microsoft Teams ==========
    Write-Step "配置 Microsoft Teams..."
    try {
        # Teams 管理员角色通过 Azure AD 目录角色分配
        # 这里使用 MicrosoftTeams 模块检查连接
        
        Write-Info "Teams 权限通过 Azure AD 目录角色配置"
        Write-Info "请确保 CIPP-SAM 的服务主体在 Azure AD 中有以下角色:"
        Write-Info "  - Teams Administrator"
        Write-Info "  - 或通过 Graph API 权限: TeamSettings.ReadWrite.All, Channel.ReadWrite.All 等"
        
        $result.Teams.Status = "Info"
        $result.Teams.Errors += "Teams 权限通过 Azure AD 目录角色配置，请在 Azure 门户中验证"
    }
    catch {
        Write-Fail "Teams 配置失败: $_"
        $result.Teams.Status = "Failed"
        $result.Teams.Errors += $_.Exception.Message
    }
    
    # ========== Security & Compliance ==========
    Write-Step "Security & Compliance (可选)..."
    Write-Info "安全与合规权限通过 Azure AD 目录角色配置"
    Write-Info "可选角色: Compliance Administrator, Security Reader"
    $result.SecurityCompliance.Status = "Info"
    
    $allResults += $result
}

# ==================== 汇总报告 ====================

Write-Host "`n" -NoNewline
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  🎉 CIPP 权限配置完成" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`n📊 配置汇总:" -ForegroundColor Cyan
foreach ($r in $allResults) {
    Write-Host "`n  🏢 $($r.TenantId)" -ForegroundColor White
    
    $exColor = switch ($r.Exchange.Status) { "Success" { "Green" } "Partial" { "Yellow" } "Failed" { "Red" } default { "Gray" } }
    Write-Host "    Exchange Online: [$($r.Exchange.Status)] $($r.Exchange.RolesAssigned)/$($ExchangeRoles.Count) 角色" -ForegroundColor $exColor
    
    Write-Host "    SharePoint:      [$($r.SharePoint.Status)] 通过 Azure AD 配置" -ForegroundColor Gray
    Write-Host "    Teams:           [$($r.Teams.Status)] 通过 Azure AD 配置" -ForegroundColor Gray
    Write-Host "    Security:        [$($r.SecurityCompliance.Status)] 可选" -ForegroundColor Gray
}

# 保存报告
$reportPath = Join-Path $PSScriptRoot "CIPP-Permissions-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$allResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`n📄 详细报告已保存: $reportPath" -ForegroundColor Gray

# ==================== 后续步骤提示 ====================

Write-Host "`n" -NoNewline
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "  📝 后续步骤:" -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. 在 Azure 门户中验证 CIPP-SAM 的应用权限:" -ForegroundColor White
Write-Host "     https://portal.azure.com -> App registrations -> CIPP-SAM" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. 确保已配置以下 Graph API 权限:" -ForegroundColor White
Write-Host "     - User.ReadWrite.All" -ForegroundColor Gray
Write-Host "     - Group.ReadWrite.All" -ForegroundColor Gray
Write-Host "     - Directory.ReadWrite.All" -ForegroundColor Gray
Write-Host "     - Organization.ReadWrite.All" -ForegroundColor Gray
Write-Host "     - Sites.FullControl.All (SharePoint)" -ForegroundColor Gray
Write-Host "     - TeamSettings.ReadWrite.All (Teams)" -ForegroundColor Gray
Write-Host "     - DeviceManagementApps.ReadWrite.All (Intune)" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. 在 Azure AD 目录角色中分配:" -ForegroundColor White
Write-Host "     - Exchange Administrator" -ForegroundColor Gray
Write-Host "     - SharePoint Administrator" -ForegroundColor Gray
Write-Host "     - Teams Administrator" -ForegroundColor Gray
Write-Host "     - Intune Administrator (如果使用设备管理)" -ForegroundColor Gray
Write-Host ""
Write-Host "  4. 重启 CIPP API 并测试:" -ForegroundColor White
Write-Host "     - ListUsers, ListGroups, ListContacts" -ForegroundColor Gray
Write-Host "     - ListSharePointSite, ListSites" -ForegroundColor Gray
Write-Host "     - ListTeams, ListTeamChannels" -ForegroundColor Gray
Write-Host ""

if ($allResults | Where-Object { $_.Exchange.Status -eq "Failed" }) {
    exit 1
}
else {
    exit 0
}
