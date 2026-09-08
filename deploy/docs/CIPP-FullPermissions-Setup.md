# CIPP 完整权限配置指南

本文档说明如何为 CIPP-SAM 应用配置所有必要的 Microsoft 365 管理权限。

## 权限概览

CIPP 需要以下类别的权限才能完整管理 Microsoft 365 租户：

| 类别 | 权限类型 | 配置位置 |
|------|----------|----------|
| Azure AD / Entra ID | Graph API 应用权限 | Azure 门户 - 应用注册 |
| Exchange Online | RBAC 管理角色 | Exchange Online PowerShell |
| SharePoint Online | Graph API 权限 + 目录角色 | Azure 门户 |
| Microsoft Teams | Graph API 权限 + 目录角色 | Azure 门户 |
| Intune (可选) | Graph API 权限 + 目录角色 | Azure 门户 |
| Security & Compliance | 目录角色 | Azure 门户 |

---

## 1. Azure AD 应用权限 (Graph API)

在 Azure 门户中为 CIPP-SAM 应用配置以下 **Application** 权限：

### 核心权限（必需）
| 权限 | 用途 |
|------|------|
| `User.ReadWrite.All` | 管理用户账户 |
| `Group.ReadWrite.All` | 管理安全组和通讯组 |
| `Directory.ReadWrite.All` | 管理目录对象 |
| `Organization.ReadWrite.All` | 管理组织设置 |
| `RoleManagement.ReadWrite.Directory` | 管理目录角色 |
| `Domain.ReadWrite.All` | 管理域名 |
| `Policy.ReadWrite.All` | 管理策略 |

### Exchange & Mail 权限
| 权限 | 用途 |
|------|------|
| `Exchange.ManageAsApp` | Exchange 管理（需配合 RBAC） |
| `Mail.ReadWrite` | 读写邮件 |
| `Mail.Send` | 发送邮件 |
| `MailboxSettings.ReadWrite` | 管理邮箱设置 |
| `Contacts.ReadWrite` | 管理联系人 |
| `Calendars.ReadWrite` | 管理日历 |

### SharePoint 权限
| 权限 | 用途 |
|------|------|
| `Sites.FullControl.All` | 完全控制 SharePoint 站点 |
| `Sites.ReadWrite.All` | 读写 SharePoint 站点 |

### Teams 权限
| 权限 | 用途 |
|------|------|
| `Team.ReadBasic.All` | 读取团队信息 |
| `TeamSettings.ReadWrite.All` | 管理团队设置 |
| `Channel.ReadWrite.All` | 管理频道 |
| `ChannelMessage.Read.All` | 读取消息 |

### Intune 权限（可选）
| 权限 | 用途 |
|------|------|
| `DeviceManagementApps.ReadWrite.All` | 管理应用 |
| `DeviceManagementConfiguration.ReadWrite.All` | 管理配置 |
| `DeviceManagementManagedDevices.ReadWrite.All` | 管理设备 |
| `DeviceManagementServiceConfig.ReadWrite.All` | 服务配置 |

---

## 2. Azure AD 目录角色

为 CIPP-SAM 的服务主体分配以下 **目录角色**（App Role Assignments）：

### 必需角色
| 角色 | 用途 |
|------|------|
| Exchange Administrator | Exchange Online 管理 |
| SharePoint Administrator | SharePoint Online 管理 |
| Teams Administrator | Microsoft Teams 管理 |

### 可选角色
| 角色 | 用途 |
|------|------|
| Intune Administrator | 设备管理（如果使用） |
| Compliance Administrator | 合规管理 |
| Security Reader | 安全读取 |

---

## 3. Exchange Online RBAC

Exchange Online 需要额外的 RBAC 配置（Graph API 权限不足）：

### 所需管理角色
| 角色 | 用途 |
|------|------|
| View-Only Configuration | 查看组织配置 |
| View-Only Recipients | 查看收件人 |
| Mail Recipients | 管理收件人 |
| Organization Configuration | 管理组织设置 |
| Distribution Groups | 管理通讯组 |
| Mail Recipient Creation | 创建收件人 |
| Message Tracking | 邮件跟踪 |
| User Options | 用户选项 |
| Role Management | 角色管理 |

**注意**：`ApplicationImpersonation` 角色已被微软弃用，不再需要。

---

## 快速配置

### 方式一：完整配置脚本（推荐）

```powershell
# 在 Windows PowerShell 上运行

# 下载脚本
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/laikeylau/CIPP-Linux/main/scripts/Setup-CIPPFullPermissions.ps1" -OutFile "Setup-CIPPFullPermissions.ps1"

# 配置单个租户
.\Setup-CIPPFullPermissions.ps1 -TenantIds @("contoso.onmicrosoft.com")

# 配置所有租户
.\Setup-CIPPFullPermissions.ps1 -AllTenants -SkipConfirmation
```

### 方式二：仅配置 Exchange Online

```powershell
.\Quick-SetupTenantExchange.ps1 -TenantDomain "contoso.onmicrosoft.com"
```

---

## 手动配置步骤

### 步骤 1：配置 Azure AD 应用权限

1. 登录 [Azure 门户](https://portal.azure.com)
2. 导航到 **App registrations** -> **CIPP-SAM**
3. 点击 **API permissions** -> **Add a permission**
4. 添加上述 Graph API 权限
5. 点击 **Grant admin consent**

### 步骤 2：分配目录角色

1. 导航到 **Azure AD** -> **Roles and administrators**
2. 为每个角色（Exchange Administrator, SharePoint Administrator, Teams Administrator）：
   - 点击角色名称
   - 点击 **Add assignments**
   - 搜索并选择 CIPP-SAM 服务主体
   - 点击 **Add**

### 步骤 3：配置 Exchange Online RBAC

参考 [Exchange Online RBAC 配置指南](ExchangeOnlineRBAC-Setup.md)。

---

## 验证配置

运行 CIPP 的访问检查：

```bash
curl -s "http://localhost:7071/api/execAccessChecks" | python3 -m json.tool
```

或在 CIPP 界面中：
1. 登录 CIPP
2. 进入 **Settings** -> **CIPP** -> **Access Check**
3. 查看各项权限的检查结果

---

## 故障排查

### 问题：CIPP 返回 403 Forbidden

**原因**：缺少必要的 Graph API 权限或目录角色。

**解决方案**：
1. 检查 Azure 门户中的应用权限是否已授予管理员同意
2. 检查目录角色是否已分配给服务主体
3. 等待 5-10 分钟让权限传播

### 问题：Exchange 功能不可用

**原因**：Exchange Online RBAC 未配置。

**解决方案**：运行 `Quick-SetupTenantExchange.ps1` 脚本。

### 问题：SharePoint/Teams 功能不可用

**原因**：缺少相应的目录角色或 Graph API 权限。

**解决方案**：
1. 在 Azure 门户中分配 SharePoint Administrator 和 Teams Administrator 角色
2. 确保 Graph API 权限已授予管理员同意

---

## 新租户上线流程

当添加新的客户租户时：

1. **在 CIPP 中添加租户**（通过 GDAP 或直接添加）
2. **运行权限配置脚本**：
   ```powershell
   .\Setup-CIPPFullPermissions.ps1 -TenantIds @("新租户.onmicrosoft.com")
   ```
3. **在 Azure 门户中验证**：
   - 确认目录角色已分配
   - 确认 Graph API 权限已授予
4. **在 CIPP 中测试**：
   - 运行 Access Check
   - 测试各项功能

---

## 相关文件

- `scripts/Setup-CIPPFullPermissions.ps1` - 完整权限配置脚本
- `scripts/Setup-ExchangeRBAC.ps1` - 仅 Exchange RBAC 配置
- `scripts/Quick-SetupTenantExchange.ps1` - 快速 Exchange 配置
- `docs/ExchangeOnlineRBAC-Setup.md` - Exchange RBAC 详细指南

---

## 参考链接

- [CIPP 官方文档](https://docs.cipp.app/)
- [Microsoft Graph 权限参考](https://learn.microsoft.com/en-us/graph/permissions-reference)
- [Exchange Online RBAC](https://learn.microsoft.com/en-us/exchange/permissions-exo/permissions-exo)
- [Azure AD 目录角色](https://learn.microsoft.com/en-us/azure/active-directory/roles/permissions-reference)
