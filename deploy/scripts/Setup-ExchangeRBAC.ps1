<#
.SYNOPSIS
    为 CIPP-SAM 应用配置 Exchange Online RBAC 权限
.DESCRIPTION
    此脚本为 CIPP-SAM 应用在指定的客户租户中注册服务主体并分配必要的管理角色。
    支持单个租户或批量处理多个租户。
.PARAMETER TenantIds
    要配置的租户域名数组（如 @("contoso.onmicrosoft.com", "fabrikam.onmicrosoft.com")）
.PARAMETER CippAppId
    CIPP-SAM 应用的 Application ID
.PARAMETER ServicePrincipalObjectId
    服务主体对象 ID（可选，首次运行后会自动获取）
.EXAMPLE
    # 配置单个租户
    .\Setup-ExchangeRBAC.ps1 -TenantIds @("contoso.onmicrosoft.com")
    
    # 批量配置多个租户
    .\Setup-ExchangeRBAC.ps1 -TenantIds @("contoso.onmicrosoft.com", "fabrikam.onmicrosoft.com", "northwind.onmicrosoft.com")
    
    # 配置所有已加入的客户租户（从 CIPP API 获取）
    .\Setup-ExchangeRBAC.ps1 -AllTenants
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

# 管理角色列表（CIPP 所需）
$ManagementRoles = @(
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

# 角色分配名称前缀
$RolePrefix = "CIPP-SAM"

function Write-Step {
    param([string]$Message)
    Write-Host "`n▶ $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✅ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "  ⚠️  $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "  ❌ $Message" -ForegroundColor Red
}

# 如果选择了 AllTenants，从 CIPP API 获取租户列表
if ($AllTenants) {
    Write-Step "从 CIPP API 获取所有租户..."
    try {
        $tenants = Invoke-RestMethod -Uri "$CippApiUrl/api/ListTenants" -Method Get
        $TenantIds = $tenants | ForEach-Object { 
            if ($_ -is [string]) { $_ } 
            else { $_.defaultDomainName ?? $_.customerId }
        } | Where-Object { $_ -and $_ -notmatch "onmicrosoft.com$" -or $_ -eq "llatech.onmicrosoft.com" }
        
        # 排除合作伙伴租户（如果需要）
        $TenantIds = $TenantIds | Where-Object { $_ -ne "llatech.onmicrosoft.com" }
        
        Write-Success "找到 $($TenantIds.Count) 个客户租户"
        $TenantIds | ForEach-Object { Write-Host "    - $_" }
    }
    catch {
        Write-Error "无法获取租户列表: $_"
        exit 1
    }
}

# 确认操作
if (-not $SkipConfirmation) {
    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host "  即将为以下租户配置 Exchange Online RBAC 权限:" -ForegroundColor Yellow
    $TenantIds | ForEach-Object { Write-Host "    - $_" -ForegroundColor White }
    Write-Host "`n  管理角色 ($($ManagementRoles.Count) 个):" -ForegroundColor Yellow
    $ManagementRoles | ForEach-Object { Write-Host "    - $_" -ForegroundColor White }
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Yellow
    
    $confirm = Read-Host "`n确认执行? (Y/N)"
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "操作已取消" -ForegroundColor Gray
        exit 0
    }
}

# 检查 ExchangeOnlineManagement 模块
Write-Step "检查 ExchangeOnlineManagement 模块..."
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Host "  正在安装 ExchangeOnlineManagement..." -ForegroundColor Yellow
    Install-Module -Name ExchangeOnlineManagement -Force -AllowClobber -Scope CurrentUser
}
Import-Module ExchangeOnlineManagement -ErrorAction Stop
Write-Success "ExchangeOnlineManagement 模块已加载"

# 存储结果
$results = @()

# 处理每个租户
foreach ($tenantId in $TenantIds) {
    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  处理租户: $tenantId" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    
    $result = @{
        TenantId        = $tenantId
        Status          = "Pending"
        ServicePrincipal = $null
        RolesAssigned   = 0
        RolesFailed     = 0
        Errors          = @()
    }
    
    try {
        # 连接到 Exchange Online
        Write-Step "连接到 Exchange Online ($tenantId)..."
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
        Connect-ExchangeOnline -DelegatedOrganization $tenantId -ShowBanner:$false -DisableWAM -ErrorAction Stop
        Write-Success "已连接"
        
        # 注册服务主体
        Write-Step "注册 CIPP-SAM 服务主体..."
        try {
            $sp = New-ServicePrincipal -AppId $CippAppId -Organization $tenantId -ErrorAction Stop
            Write-Success "服务主体已创建: $($sp.ObjectId)"
            $result.ServicePrincipal = $sp.ObjectId
        }
        catch {
            if ($_.Exception.Message -match "already exists") {
                Write-Warning "服务主体已存在"
                # 尝试获取现有服务主体
                $existingSp = Get-ServicePrincipal -Filter "AppId -eq '$CippAppId'" -Organization $tenantId -ErrorAction SilentlyContinue
                if ($existingSp) {
                    $result.ServicePrincipal = $existingSp.ObjectId
                    Write-Host "    现有对象 ID: $($existingSp.ObjectId)" -ForegroundColor Gray
                }
            }
            else {
                throw $_
            }
        }
        
        # 获取服务主体对象 ID（用于角色分配）
        $spObjectId = $result.ServicePrincipal
        if (-not $spObjectId) {
            Write-Error "无法获取服务主体对象 ID，跳过角色分配"
            $result.Status = "Failed"
            $result.Errors += "无法获取服务主体对象 ID"
            $results += $result
            continue
        }
        
        # 分配管理角色
        Write-Step "分配管理角色..."
        $assignedCount = 0
        $failedCount = 0
        
        foreach ($role in $ManagementRoles) {
            $assignmentName = "$RolePrefix-$($role -replace ' ', '-')"
            try {
                # 检查是否已存在
                $existing = Get-ManagementRoleAssignment -RoleAssignee $spObjectId -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Role -eq $role }
                
                if ($existing) {
                    Write-Warning "$role - 已存在"
                    $assignedCount++
                }
                else {
                    New-ManagementRoleAssignment -Role $role -App $CippAppId -Name $assignmentName -ErrorAction Stop | Out-Null
                    Write-Success "$role - 已分配"
                    $assignedCount++
                }
            }
            catch {
                if ($_.Exception.Message -match "already exists") {
                    Write-Warning "$role - 已存在"
                    $assignedCount++
                }
                else {
                    Write-Error "$role - 失败: $($_.Exception.Message)"
                    $failedCount++
                    $result.Errors += "角色 '$role' 分配失败: $($_.Exception.Message)"
                }
            }
        }
        
        $result.RolesAssigned = $assignedCount
        $result.RolesFailed = $failedCount
        
        # 验证角色分配
        Write-Step "验证角色分配..."
        $assignments = Get-ManagementRoleAssignment -RoleAssignee $spObjectId -ErrorAction SilentlyContinue
        $cippRoles = $assignments | Where-Object { $_.Name -like "$RolePrefix-*" }
        Write-Host "  已分配 CIPP 角色: $($cippRoles.Count)/$($ManagementRoles.Count)" -ForegroundColor $(if ($cippRoles.Count -eq $ManagementRoles.Count) { "Green" } else { "Yellow" })
        
        if ($assignedCount -eq $ManagementRoles.Count) {
            $result.Status = "Success"
        }
        elseif ($assignedCount -gt 0) {
            $result.Status = "Partial"
        }
        else {
            $result.Status = "Failed"
        }
    }
    catch {
        Write-Error "处理租户失败: $_"
        $result.Status = "Failed"
        $result.Errors += $_.Exception.Message
    }
    
    $results += $result
}

# 断开 Exchange Online 连接
Write-Step "断开 Exchange Online 连接..."
Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
Write-Success "已断开连接"

# 输出汇总报告
Write-Host "`n" -NoNewline
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Exchange Online RBAC 配置完成" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Green

Write-Host "`n汇总:" -ForegroundColor Cyan
$successCount = ($results | Where-Object { $_.Status -eq "Success" }).Count
$partialCount = ($results | Where-Object { $_.Status -eq "Partial" }).Count
$failedCount = ($results | Where-Object { $_.Status -eq "Failed" }).Count

Write-Host "  ✅ 成功: $successCount" -ForegroundColor Green
Write-Host "  ⚠️  部分成功: $partialCount" -ForegroundColor Yellow
Write-Host "  ❌ 失败: $failedCount" -ForegroundColor Red

Write-Host "`n详细结果:" -ForegroundColor Cyan
foreach ($r in $results) {
    $statusColor = switch ($r.Status) {
        "Success" { "Green" }
        "Partial" { "Yellow" }
        "Failed"  { "Red" }
        default   { "Gray" }
    }
    Write-Host "  [$($r.Status)] $($r.TenantId)" -ForegroundColor $statusColor
    Write-Host "    角色分配: $($r.RolesAssigned)/$($ManagementRoles.Count)" -ForegroundColor Gray
    if ($r.ServicePrincipal) {
        Write-Host "    服务主体: $($r.ServicePrincipal)" -ForegroundColor Gray
    }
    if ($r.Errors.Count -gt 0) {
        Write-Host "    错误:" -ForegroundColor Red
        $r.Errors | ForEach-Object { Write-Host "      - $_" -ForegroundColor Red }
    }
}

# 保存结果到文件
$reportPath = Join-Path $PSScriptRoot "ExchangeRBAC-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$results | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8
Write-Host "`n详细报告已保存: $reportPath" -ForegroundColor Gray

# 退出码
if ($failedCount -gt 0) {
    exit 1
}
else {
    exit 0
}