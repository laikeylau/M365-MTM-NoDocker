# CIPP Direct Tenant 租户管理指南

## 概述

CIPP 支持两种租户管理模式：
- **GDAP（Granular Delegated Admin Privileges）**：通过 Partner Center 管理，适合 MSP 多租户场景
- **Direct Tenant（平行租户）**：每个租户独立 OAuth 授权，适合单租户或少量租户管理

本指南针对 **Direct Tenant** 模式，已在 Linux + cipp-server.ps1 本地服务器环境下验证通过。

## 前置条件

1. CIPP-SAM App Registration 已配置（见 root-level README）
2. CIPP API 服务器正在运行：`DisableCIPPRestMethod=true pwsh -File ./cipp-server.ps1`
3. Azurite 存储服务正在运行（用于存储租户和 token 数据）

## 新租户接入流程（4步完成）

### Step 1: 在 Setup Wizard 中选择 "Add a tenant"

打开 CIPP 仪表板 → Setup Wizard → 选择 **"Add a tenant"**（不是 "First Setup"）

### Step 2: 选择租户类型 "Direct"

选择 **Direct** — 平行租户模式（每租户独立 OAuth）

### Step 3: OAuth 授权

点击 **"Connect to Tenant"** 按钮：
1. 弹出 Microsoft OAuth 窗口
2. 用目标租户的**全局管理员**账号登录
3. 授权 CIPP-SAM 的委托权限
4. 授权完成后页面会自动跳转

### Step 4: 一键验证修复

OAuth 完成后，运行一键修复脚本：

```bash
cd /opt/M365-MTM/CIPP-API
pwsh -NoProfile -Command "& ./scripts/Post-TenantSetup.ps1 -TenantId '<租户ID>'"
```

脚本会自动完成：
1. ✅ 验证租户是否写入 Azurite
2. ✅ 重置 GraphErrorCount
3. ✅ 验证 refresh token 是否存储
4. ✅ 测试 Graph API（ListUsers、ListLicenses、ListGraphRequest）
5. ✅ **同步报告数据库**（Mailboxes + MailboxPermissions + CalendarPermissions）
6. ✅ 测试 Exchange Online（ListMailboxes）
7. ✅ 最终清理

**如果 Exchange Online 测试失败（403 Forbidden）：**
需要在目标租户为 CIPP-SAM 分配 Exchange Administrator 角色：
1. 登录 Azure Portal → 切换到目标租户
2. Enterprise Applications → 搜索 CIPP-SAM
3. Users and groups → Add user/group
4. 选择角色: **Exchange Administrator** → Assign
5. 重新运行脚本验证

## 环境信息

| 项目 | 值 |
|------|-----|
| CIPP-SAM AppId | 98779b37-04c7-4714-887a-0c3bae41cb82 |
| Host Tenant | 2b2ccf22-1af7-4ef4-a191-ad9b9a3b5de1 (SYSTEX) |
| API Base URL | http://localhost:7071 |
| Azurite Table | Tenants (PartitionKey: Tenants, RowKey: customerId) |
| Token Storage | DevSecrets (PartitionKey: Secret, RowKey: Secret) |

## 已验证租户

| 租户 | TenantId | 状态 |
|------|----------|------|
| demfre05outlook.onmicrosoft.com | 15dc8949-c50b-438d-9a9a-26fe501c5895 | ✅ 完全正常 |
| lenitech.onmicrosoft.com | 2df8b2f9-1714-4246-825d-d655b1577ec3 | ✅ 完全正常 |
| admbek55outlook.onmicrosoft.com | 7e5a7e02-336b-4872-a0dd-bd2d531ae44d | ✅ 完全正常 |
| hugfox39outlook.onmicrosoft.com | e4278fa3-27f5-41f7-8b35-5eb0d8e523ba | ✅ 完全正常 |
| xamser765outlook.onmicrosoft.com | d665f8bc-d31a-4974-b11c-2f6cb81fe6de | ✅ 完全正常 |
| zoneitechoutlook.onmicrosoft.com | 1b263910-e1ee-4514-8160-bb3a64d0dd08 | ✅ 完全正常 |

## 脚本清单

| 脚本 | 用途 |
|------|------|
| `Post-TenantSetup.ps1` | **推荐** OAuth 后一键修复（Graph + EXO + 权限同步全测试） |
| `Sync-AllCache.ps1` | **推荐** 全量缓存同步（72 类型，覆盖 Dashboard/Identity/Exchange/SharePoint/Intune/Security/Copilot/PIM/Compliance） |
| `Sync-ReportData.ps1` | 同步报告数据库（邮箱、权限、日历权限、规则） |
| `Add-DirectTenant.ps1` | 租户管理（list/add/import/reset） |
| `Monitor-TenantHealth.ps1` | 健康监控 |

## 许可证相关功能限制

以下功能需要额外的 Microsoft 365 许可证：

| 功能 | 需要的许可证 |
|------|-------------|
| Intune / Autopilot | Microsoft Intune Plan 1/2 |
| Defender TVM | Microsoft Defender for Endpoint Plan 2 |
| Safe Links / MDO | Microsoft Defender for Office 365 |
| Security Incidents | Microsoft 365 Defender |

## 常见问题

### Q: Graph API 超时或返回 AADSTS 错误？
A: 运行 `Post-TenantSetup.ps1`，脚本会自动重置 GraphErrorCount 并测试连接。

### Q: 邮箱功能报 403 Forbidden？
A: 在目标租户为 CIPP-SAM 分配 Exchange Administrator 角色（见 Step 4 说明）。

### Q: 如何检查租户状态？
A: 运行 `./scripts/Monitor-TenantHealth.ps1` 或 `./scripts/Add-DirectTenant.ps1 -Action list`

### Q: 如何重置某个租户的错误计数？
A: 运行 `./scripts/Add-DirectTenant.ps1 -Action reset -TenantId '<租户ID>'`

### Q: 日历权限页面显示空数组？
A: 这是预期行为。`ListCalendarPermissions` 会过滤掉默认权限（Default/Anonymous），只显示自定义权限。如果租户没有自定义日历权限，返回 `[]` 是正确的。

### Q: 租户数据加载非常慢？
A: 这通常是因为 Azurite Tenants 表中该租户的 `RequiresRefresh` 被设为 `True`，导致 CIPP 每次加载都尝试从 Graph API 重新拉取全量数据。运行 `Post-TenantSetup.ps1` 会自动修复此问题。手动修复：

```python
# Python 脚本修复 RequiresRefresh
from azure.data.tables import TableServiceClient
conn = 'DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNoBnZf6KgBVU4=;TableEndpoint=http://127.0.0.1:10002/devstoreaccount1'
svc = TableServiceClient.from_connection_string(conn)
table = svc.get_table_client('Tenants')
entity = table.get_entity('Tenants', '<TENANT_ID>')
entity['RequiresRefresh'] = False
entity['GraphErrorCount'] = 0
entity['delegatedPrivilegeStatus'] = ''
entity['domains'] = entity.get('defaultDomainName', '')
table.update_entity(entity)
```

**关键字段说明：**
- `RequiresRefresh` — 必须为 `False`，否则 CIPP 每次加载都重新拉取全量数据（极慢）
- `GraphErrorCount` — 必须为 `0`，超过阈值会被 CIPP 过滤
- `delegatedPrivilegeStatus` — 非 GDAP 租户必须为空字符串（非 `directTenant`）
- `domains` — 至少包含租户的默认域名

### Q: 如何手动同步报告数据？
A: 运行 `./scripts/Sync-ReportData.ps1 -TenantFilter '<租户域名>' -Types 'All'`，支持的类型包括：
- `Mailboxes` — 邮箱列表
- `Permissions` — 邮箱权限（FullAccess、SendAs、SendOnBehalf）
- `CalendarPermissions` — 日历权限
- `Rules` — 邮箱规则

### Q: 如何同步所有租户的全量缓存数据？
A: 运行 `./scripts/Sync-AllCache.ps1`，支持以下参数：
- `-TenantFilter '<租户ID>'` — 只同步指定租户
- `-SkipExisting` — 跳过已有数据的租户（增量同步）
- `-Categories 'Dashboard,Identity,Exchange'` — 只同步指定分类

**示例：**
```bash
# 同步所有活跃租户（完整）
pwsh -File ./scripts/Sync-AllCache.ps1

# 只同步指定租户
pwsh -File ./scripts/Sync-AllCache.ps1 -TenantFilter '2df8b2f9-1714-4246-825d-d655b1577ec3'

# 增量同步（跳过已有数据）
pwsh -File ./scripts/Sync-AllCache.ps1 -SkipExisting
```

**支持的分类：**
- `Dashboard` — Users, Guests, Groups, Devices, SecureScore, MFA, LicenseOverview
- `Identity` — RiskyUsers, RiskDetections, CredentialUserRegistrationDetails, ServicePrincipals, Apps
- `Exchange` — Mailboxes, CASMailboxes, MailboxUsage, TransportRules, AntiSpam/Phish/Malware policies
- `SharePoint` — SharePointSiteUsage, OneDriveUsage
- `Intune` — ManagedDevices, DeviceCompliance, DeviceConfigurations, DetectedApps
- `Security` — ConditionalAccessPolicies, AuthorizationPolicy, CrossTenantAccessPolicy, B2BManagementPolicy
- `Copilot` — CopilotReadinessActivity, CopilotUsageUserDetail
- `PIM` — Roles, PIMSettings, RoleAssignmentScheduleInstances, RoleEligibilitySchedules
- `Compliance` — BitlockerKeys, MDEOnboarding, DirectoryRecommendations
- `Other` — Domains, Settings, Organization, OfficeActivations

### Q: 如何设置定时任务自动同步？
A: 使用 Hermes cronjob 设置定时任务，例如每6小时同步一次：
```bash
# 创建定时任务
hermes cronjob create --name "CIPP Full Cache Sync" --schedule "0 */6 * * *" --command "cd /opt/M365-MTM/CIPP-API && pwsh -File scripts/Sync-AllCache.ps1"
```

---

## 故障排除

### Q: Dashboard 数据加载缓慢，RequiresRefresh 字段反复变 True？

A: Azurite Tenants 表中新租户的 `RequiresRefresh` 被设为 `True` 会导致 CIPP 每次加载都重新拉取全量数据。修复方法：

```powershell
# 检查当前值
az storage entity query --account-name devstoreaccount1 --table-name Tenants \
  --filter "PartitionKey eq 'xxx.onmicrosoft.com'" --query "items[0].{RR:RequiresRefresh,GEC:GraphErrorCount,DPS:delegatedPrivilegeStatus}"

# 修复（用 python + azure-data-tables 或 az storage entity merge）
# RequiresRefresh=False, GraphErrorCount=0, delegatedPrivilegeStatus='' (空字符串，非 directTenant)
```

`Post-TenantSetup.ps1` 已自动设置这些字段，新添加的租户不会再出现此问题。

### Q: Roles 页面显示 400 错误或空白？

A: ~~这是因为 `New-GraphBulkRequest` 在 delegated 模式下附带了 `client_secret`，Azure AD 拒绝 public client + secret 组合（`AADSTS700025`）。~~

**✅ 已在代码层面修复 (2026-05-13, commit `59d4685`):**
- `Get-GraphToken.ps1`: 委托流程（refresh_token）不再发送 `client_secret`，避免 `AADSTS700025` 错误。
- `Get-CIPPMFAState.ps1`: 所有 Graph API 调用（users、secure defaults、role assignments、role definitions、group bulk requests）均已添加 `-AsApp $true`，使用 app-only 流程。

手动同步（仅在代码修复前需要）：
```powershell
cd /opt/M365-MTM/CIPP-API
$env:DisableCIPPRestMethod = "true"
$Roles = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directoryRoles" -tenantid "xxx.onmicrosoft.com" -AsApp $true
Add-CIPPDbItem -TenantFilter "xxx.onmicrosoft.com" -Type "Roles" -Data $Roles
```

### Q: ApplicationSecret 无效（AADSTS7000215）？

A: DevSecrets 表中的 `ApplicationSecret` 必须是客户端密码的**值**（不是密钥ID）。在 Azure Portal → 应用注册 → CIPP-SAM → 证书和密码 → 新建客户端密码，复制**值**列。密钥ID 格式类似 `xxxx-xxxx-xxxx`，而 secret 值通常以 `~` 结尾。

```powershell
# 验证 secret 是否有效
curl -X POST "https://login.microsoftonline.com/<TENANT_ID>/oauth2/v2.0/token" \
  -d "client_id=<APP_ID>&client_secret=<SECRET>&grant_type=client_credentials&scope=https://graph.microsoft.com/.default"
```

### Q: 邮箱页面显示 "No mailbox data found"？

A: 新接入的租户需要同时满足 **3 个条件** 才能通过 EXO app-only 同步邮箱数据：

> **✅ 已修复 (2026-05-13):** `Set-CIPPDBCacheMailboxes` 的 `cmdParams` bug 已在 CIPP-API 中修复。现在可以直接使用 `Set-CIPPDBCacheMailboxes -TenantFilter $d -Types 'None'` 而无需内联脚本绕过。修复内容：将 `AsApp = $true` 从 `cmdParams`（传给 `Get-Mailbox`）移除，仅保留在 `ExoRequest` 层级（用于认证）。

**条件 1：EXO `full_access_as_app` 应用权限**
在目标租户为 CIPP-SAM 授权 Exchange Online 的 `full_access_as_app` application permission：

```powershell
# 查询 EXO SP 的 full_access_as_app appRoleId
$ExoSp = Get-MgServicePrincipal -Filter "appId eq '00000002-0000-0ff1-ce00-000000000000'"
$FullAccess = ($ExoSp.AppRoles | Where-Object { $_.Value -eq 'full_access_as_app' }).Id

# 查找 CIPP-SAM 在目标租户的 SP
$SamSp = Get-MgServicePrincipal -Filter "appId eq '98779b37-04c7-4714-887a-0c3bae41cb82'"

# 授权
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $SamSp.Id -BodyParameter @{
    PrincipalId = $SamSp.Id
    ResourceId  = $ExoSp.Id
    AppRoleId   = $FullAccess
}
```

**条件 2：Exchange Administrator 目录角色**
EXO app-only 要求 CIPP-SAM 在每个租户被分配 **Exchange Administrator** 角色：
1. Azure Portal → 切换到目标租户
2. Enterprise Applications → CIPP-SAM → Users and groups
3. Add user/group → 选择角色 **Exchange Administrator** → Assign

**~~条件 3：移除 `publicClient.redirectUris`~~ ✅ 代码层面修复 (2026-05-13)**
~~如果 App Registration 中存在 `publicClient.redirectUris`（含 `msal...://auth` nativeclient URI），v2.0 token endpoint 会拒绝 EXO 的 client_secret（`AADSTS700025`）：~~

**已在代码层面修复：** `Get-GraphToken.ps1` 的委托流程不再发送 `client_secret`，`Get-CIPPMFAState.ps1` 改用 `-AsApp $true`。无需手动修改 App Registration。

手动检查（仅供参考）：
```powershell
$App = Get-MgApplication -Filter "appId eq '98779b37-04c7-4714-887a-0c3bae41cb82'"
# publicClient.redirectUris 可能为空数组，这是正常的
$App.PublicClient.RedirectUris
```

**修复后验证：**
```powershell
# 必须用 v1.0 endpoint（v2.0 不支持 EXO client_secret）
$TenantId = '<TARGET_TENANT_ID>'
$body = "client_id=98779b37-04c7-4714-887a-0c3bae41cb82&client_secret=<SECRET>&grant_type=client_credentials&scope=https://outlook.office365.com/.default"
$Token = (curl -X POST "https://login.microsoftonline.com/$TenantId/oauth2/token" -d $body | ConvertFrom-Json).access_token

# 同步邮箱数据
New-ExoRequest -tenantid "xxx.onmicrosoft.com" -cmdlet "Get-Mailbox" -cmdParams @{ ResultSize = 'Unlimited' } -AsApp $true
```

**~~注意~~ ✅ 已修复 (2026-05-13):** `Set-CIPPDBCacheMailboxes` 函数的 `cmdParams` bug 已修复（commit `8d2b4e07e`）。现在可直接使用 CIPP 内置函数同步邮箱，无需内联脚本绕过。

### Q: Risky Users 页面报 "required scopes are missing"？

A: CIPP-SAM 默认只有 `IdentityRiskEvent.Read.All`，Risky Users 功能需要 `IdentityRiskyUser.Read.All` + `IdentityRiskyUser.ReadWrite.All`。此外还需要 Azure AD Premium P2 许可证（免费租户无法使用此功能）。

```powershell
# 授予权限（需对每个租户执行 Admin Consent）
$GraphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$RiskyUserRead = ($GraphSp.AppRoles | Where-Object { $_.Value -eq 'IdentityRiskyUser.Read.All' }).Id
$RiskyUserReadWrite = ($GraphSp.AppRoles | Where-Object { $_.Value -eq 'IdentityRiskyUser.ReadWrite.All' }).Id

# 对 CIPP-SAM 授权
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $SamSp.Id -BodyParameter @{
    PrincipalId = $SamSp.Id; ResourceId = $GraphSp.Id; AppRoleId = $RiskyUserRead
}
New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $SamSp.Id -BodyParameter @{
    PrincipalId = $SamSp.Id; ResourceId = $GraphSp.Id; AppRoleId = $RiskyUserReadWrite
}
```

### Q: Dashboard "All users auth methods" 显示无数据？

A: **✅ 已在代码层面修复 (2026-05-13, commit `59d4685`):**

根本原因：`Get-CIPPMFAState.ps1` 使用委托流程（delegated）调用 Graph API 获取用户列表和角色信息，但 CIPP-SAM 应用注册存在 `publicClient` 属性（即使 redirectUris 为空），Azure AD 拒绝 `client_secret`（`AADSTS700025`），导致静默失败。

修复内容：
1. `Get-GraphToken.ps1`: 委托流程不再发送 `client_secret`
2. `Get-CIPPMFAState.ps1`: 所有 Graph API 调用改用 `-AsApp $true`（app-only 流程）

修复后验证：
```powershell
# 在 CIPP Dashboard 中查看各租户的 "All users auth methods" 应有数据
# 免费租户 MFARegistration 显示 "not available - licensing required" 是正常的（需 P2 许可证）
```

---

## 新租户完整接入 Checklist

每次添加新租户时，按此清单逐项检查，避免重复踩坑：

| # | 步骤 | 验证方式 |
|---|------|---------|
| 1 | Graph API Admin Consent（59 个权限） | `Get-MgServicePrincipalAppRoleAssignment` |
| 2 | EXO `full_access_as_app` 授权 | 查看 EXO SP 的 AppRoleAssignedTo |
| 3 | Exchange Administrator 目录角色 | Enterprise App → Users and groups |
| 4 | `IdentityRiskyUser.Read.All` + `ReadWrite.All` | Graph SP 的 AppRoleAssignedTo |
| 5 | ~~移除 `publicClient.redirectUris`~~ | ✅ 代码层面修复，委托流程不再发 client_secret |
| 6 | ~~CIPP-SAM 是 confidential client~~ | ✅ 代码层面修复，MFA 等改用 -AsApp 流程 |
| 7 | Azurite 写入正确字段 | `RequiresRefresh=False, GraphErrorCount=0, delegatedPrivilegeStatus='', domains=默认域名` |
| 8 | EXO token 用 v1.0 endpoint | `https://login.microsoftonline.com/{tenant}/oauth2/token` |
| 9 | ✅ 已修复，直接用 `Set-CIPPDBCacheMailboxes` | `Set-CIPPDBCacheMailboxes -TenantFilter $d -Types 'None'` |
