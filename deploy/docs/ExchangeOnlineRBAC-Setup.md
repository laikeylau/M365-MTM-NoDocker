# Exchange Online RBAC 配置指南

本文档说明如何为 CIPP-SAM 应用配置 Exchange Online 管理权限。

## 背景

CIPP 需要 Exchange Online 的管理权限才能执行以下操作：
- 查看和管理邮箱
- 管理邮件流规则
- 查看邮件跟踪日志
- 管理通讯组
- 配置组织设置

仅配置 Azure AD 的 Graph API 权限（如 `Exchange.ManageAsApp`）是不够的，还需要在 Exchange Online 内部注册服务主体并分配 RBAC 角色。

## 前提条件

1. **Windows PowerShell**（Linux 上的 ExchangeOnlineManagement 模块存在兼容性问题）
2. **ExchangeOnlineManagement 模块**
3. **CIPP-SAM 应用凭据**（Application ID 和证书）

## 快速开始

### 方式一：为单个租户配置

在 Windows PowerShell 中运行：

```powershell
# 下载脚本
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/laikeylau/CIPP-Linux/main/scripts/Quick-SetupTenantExchange.ps1" -OutFile "Quick-SetupTenantExchange.ps1"

# 运行脚本
.\Quick-SetupTenantExchange.ps1 -TenantDomain "contoso.onmicrosoft.com"
```

### 方式二：批量配置多个租户

```powershell
# 下载脚本
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/laikeylau/CIPP-Linux/main/scripts/Setup-ExchangeRBAC.ps1" -OutFile "Setup-ExchangeRBAC.ps1"

# 配置指定租户
.\Setup-ExchangeRBAC.ps1 -TenantIds @("contoso.onmicrosoft.com", "fabrikam.onmicrosoft.com")

# 或配置所有已加入的租户（从 CIPP API 自动获取）
.\Setup-ExchangeRBAC.ps1 -AllTenants
```

## 手动配置步骤

如果需要手动配置，请按以下步骤操作：

### 1. 连接到客户租户的 Exchange Online

```powershell
Connect-ExchangeOnline -DelegatedOrganization "contoso.onmicrosoft.com" -DisableWAM
```

> ⚠️ 必须使用 `-DisableWAM` 参数，否则在某些环境下会报错。

### 2. 注册服务主体

```powershell
New-ServicePrincipal -AppId "98779b37-04c7-4714-887a-0c3bae41cb82" -Organization "contoso.onmicrosoft.com"
```

### 3. 分配管理角色

```powershell
$appId = "98779b37-04c7-4714-887a-0c3bae41cb82"

# 分配 9 个管理角色
New-ManagementRoleAssignment -Role "View-Only Configuration" -App $appId -Name "CIPP-SAM-View-Only-Configuration"
New-ManagementRoleAssignment -Role "View-Only Recipients" -App $appId -Name "CIPP-SAM-View-Only-Recipients"
New-ManagementRoleAssignment -Role "Mail Recipients" -App $appId -Name "CIPP-SAM-Mail-Recipients"
New-ManagementRoleAssignment -Role "Organization Configuration" -App $appId -Name "CIPP-SAM-Organization-Configuration"
New-ManagementRoleAssignment -Role "Distribution Groups" -App $appId -Name "CIPP-SAM-Distribution-Groups"
New-ManagementRoleAssignment -Role "Mail Recipient Creation" -App $appId -Name "CIPP-SAM-Mail-Recipient-Creation"
New-ManagementRoleAssignment -Role "Message Tracking" -App $appId -Name "CIPP-SAM-Message-Tracking"
New-ManagementRoleAssignment -Role "User Options" -App $appId -Name "CIPP-SAM-User-Options"
New-ManagementRoleAssignment -Role "Role Management" -App $appId -Name "CIPP-SAM-Role-Management"
```

### 4. 验证配置

```powershell
# 获取服务主体对象 ID
$sp = Get-ServicePrincipal -Filter "AppId -eq '$appId'"

# 查看已分配的角色
Get-ManagementRoleAssignment -RoleAssignee $sp.ObjectId | Where-Object { $_.Name -like "CIPP-SAM-*" }
```

### 5. 断开连接

```powershell
Disconnect-ExchangeOnline -Confirm:$false
```

## 故障排查

### 问题：ApplicationImpersonation 角色分配失败

**原因**：该角色已被微软弃用。

**解决方案**：可以忽略此错误。CIPP 的核心功能不依赖此角色。

### 问题：WAM 窗口句柄错误

**错误信息**：`AcquireTokenAsync failed with WAM error`

**解决方案**：在 `Connect-ExchangeOnline` 命令中添加 `-DisableWAM` 参数。

### 问题：Linux 上 ExchangeOnlineManagement 模块不工作

**原因**：ExchangeOnlineManagement 模块在 Linux 上的 PowerShell 存在兼容性问题。

**解决方案**：在 Windows 机器上运行 Exchange 配置脚本。

## CIPP-SAM 所需的管理角色说明

| 角色 | 用途 |
|------|------|
| View-Only Configuration | 查看组织配置 |
| View-Only Recipients | 查看收件人信息 |
| Mail Recipients | 管理邮件收件人 |
| Organization Configuration | 管理组织设置 |
| Distribution Groups | 管理通讯组 |
| Mail Recipient Creation | 创建邮件收件人 |
| Message Tracking | 查看邮件跟踪日志 |
| User Options | 管理用户选项 |
| Role Management | 管理角色分配 |

## 自动化新租户配置

当通过 CIPP 添加新客户租户时，需要为此租户运行 Exchange RBAC 配置。建议：

1. 在 CIPP 中添加新租户
2. 运行 `Quick-SetupTenantExchange.ps1` 脚本
3. 在 CIPP 中验证 Exchange 功能正常

## 相关文件

- `scripts/Setup-ExchangeRBAC.ps1` - 批量配置脚本
- `scripts/Quick-SetupTenantExchange.ps1` - 快速单租户配置脚本

## 参考链接

- [CIPP 官方文档](https://docs.cipp.app/)
- [Exchange Online RBAC](https://learn.microsoft.com/en-us/exchange/permissions-exo/permissions-exo)
- [ApplicationImpersonation 弃用说明](https://learn.microsoft.com/en-us/exchange/recipients-in-exo-online/mailbox-permissions)
