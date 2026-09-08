<#
.SYNOPSIS
    快速为单个客户租户配置 Exchange Online RBAC 权限
.DESCRIPTION
    简化版脚本，用于快速为单个租户配置 CIPP-SAM 所需的 Exchange 管理权限。
    适用于 Windows PowerShell 环境。
.PARAMETER TenantDomain
    客户租户域名（如 "contoso.onmicrosoft.com"）
.EXAMPLE
    .\Quick-SetupTenantExchange.ps1 -TenantDomain "contoso.onmicrosoft.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$TenantDomain,
    
    [Parameter(Mandatory = $false)]
    [string]$CippAppId = "98779b37-04c7-4714-887a-0c3bae41cb82"
)

Write-Host "🔧 配置 Exchange Online RBAC 权限" -ForegroundColor Cyan
Write-Host "   租户: $TenantDomain" -ForegroundColor White
Write-Host "   应用: $CippAppId" -ForegroundColor White
Write-Host ""

# 检查模块
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Host "⚠️  正在安装 ExchangeOnlineManagement..." -ForegroundColor Yellow
    Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber -Scope CurrentUser
}
Import-Module ExchangeOnlineManagement

# 连接
Write-Host "🔗 连接到 Exchange Online..." -ForegroundColor Cyan
Connect-ExchangeOnline -DelegatedOrganization $TenantDomain -ShowBanner:$false -DisableWAM

try {
    # 注册服务主体
    Write-Host "📝 注册服务主体..." -ForegroundColor Cyan
    try {
        $sp = New-ServicePrincipal -AppId $CippAppId -Organization $TenantDomain
        Write-Host "✅ 服务主体已创建: $($sp.ObjectId)" -ForegroundColor Green
    }
    catch {
        if ($_.Exception.Message -match "already exists") {
            Write-Host "⚠️  服务主体已存在" -ForegroundColor Yellow
        }
        else {
            throw $_
        }
    }
    
    # 分配角色
    Write-Host "🔑 分配管理角色..." -ForegroundColor Cyan
    $roles = @(
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
    
    foreach ($role in $roles) {
        try {
            $assignmentName = "CIPP-SAM-$($role -replace ' ', '-')"
            New-ManagementRoleAssignment -Role $role -App $CippAppId -Name $assignmentName -ErrorAction Stop | Out-Null
            Write-Host "  ✅ $role" -ForegroundColor Green
        }
        catch {
            if ($_.Exception.Message -match "already exists") {
                Write-Host "  ⚠️  $role (已存在)" -ForegroundColor Yellow
            }
            else {
                Write-Host "  ❌ $role - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    
    Write-Host ""
    Write-Host "🎉 配置完成！" -ForegroundColor Green
    Write-Host "   CIPP 现在可以管理此租户的 Exchange Online 了" -ForegroundColor White
}
finally {
    Disconnect-ExchangeOnline -Confirm:$false
    Write-Host "🔌 已断开连接" -ForegroundColor Gray
}
