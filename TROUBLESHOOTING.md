# CIPP Linux 部署故障排除指南

## 已知问题

### 1. GraphErrorCount 累积导致 "Tenant not found"

**症状**: Dashboard 或 API 调用返回 "Tenant not found"，但租户确实存在于 Azurite 表中。

**原因**: CIPP 的 `Get-Tenants.ps1` 过滤 `GraphErrorCount lt 50`。当错误累积超过 50 时，租户被自动排除。

**修复**:
```bash
# 单个租户重置
pwsh -File scripts/Add-DirectTenant.ps1 -Action reset -TenantId "<tenant-id>"

# 自动修复所有超限租户
pwsh -File scripts/Monitor-TenantHealth.ps1 -AutoFix
```

---

### 2. LicenseOverview 权限不足 (403 Forbidden)

**症状**: LicenseOverview 同步失败，Graph API 返回 403。

**原因**: CIPP-SAM App Registration 已声明 `Organization.Read.All` 和 `SubscribedSkus.Read.All`，但 Service Principal 未在各租户获得 Admin Consent。

**修复**: 使用用户手动 consent 链接（在浏览器中打开）：
```
https://login.microsoftonline.com/<tenant-id>/adminconsent?client_id=<cipp-sam-app-id>&redirect_uri=<redirect-uri>
```

---

### 3. DlpCompliancePolicies 超时 (端口 446 被阻)

**症状**: DlpCompliancePolicies、DlpComplianceRules 同步超时，其他功能正常。

**原因**: Microsoft Compliance API 使用端口 446（非标准 HTTPS 端口）。`ps.compliance.protection.outlook.com` 返回 302 重定向到 `apc01b.admin.protection.outlook.com:446`。部分云平台（如 Oracle Cloud）默认阻止端口 446 出站。

**验证**:
```bash
# 测试端口 446 连通性
timeout 5 nc -zv -w 3 apc01b.admin.protection.outlook.com 446
```

**修复方案**:
- **Oracle Cloud**: 在 VCN → Security Lists → Default Security List 中添加 Egress Rule: `0.0.0.0/0`, TCP, Port 446
- **其他云**: 检查安全组/防火墙是否允许 TCP 446 出站
- **无法开放端口**: 暂时忽略，DLP 策略同步不影响核心 CIPP 功能

---

### 4. delegatedPrivilegeStatus 设置错误

**症状**: CIPP 尝试使用 refresh token 认证（而非 app-only），导致超时或认证失败。

**原因**: `delegatedPrivilegeStatus = 'directTenant'` 会导致 CIPP 从 Azure Key Vault 获取 refresh token。在 Linux standalone 模式下，没有 Key Vault 配置。

**修复**:
```bash
# 清除 delegatedPrivilegeStatus（使用 app-only auth）
pwsh -File scripts/Add-DirectTenant.ps1 -Action fix-status -TenantId "<tenant-id>" -Status ""

# 设置为 GDAP 模式
pwsh -File scripts/Add-DirectTenant.ps1 -Action fix-status -TenantId "<tenant-id>" -Status "granularDelegatedAdminPrivileges"
```

**说明**:
- 空值或 `granularDelegatedAdminPrivileges`: 使用 app-only (client_credentials) 认证
- `directTenant`: 使用 delegated (refresh token) 认证，需要 Key Vault

---

### 5. ComplianceUrl 未设置或不正确

**症状**: Compliance API 调用返回 302 重定向循环或超时。

**修复**:
```bash
# 自动探测并设置 ComplianceUrl
pwsh -File scripts/Fix-ComplianceUrl.ps1

# 强制重新探测（即使已有值）
pwsh -File scripts/Fix-ComplianceUrl.ps1 -Force

# 单个租户
pwsh -File scripts/Fix-ComplianceUrl.ps1 -TenantFilter 'llatech.onmicrosoft.com'
```

---

### 6. MFAState 同步超时

**症状**: MFAState 同步挂起或超时。

**原因**: 通常是 GraphErrorCount 过高或网络连接问题。

**修复**:
```bash
# 重置 GraphErrorCount
pwsh -File scripts/Monitor-TenantHealth.ps1 -AutoFix

# 单独测试 MFAState
pwsh -File scripts/Sync-DashboardData.ps1 -TenantFilter '<tenant-domain>'
```

---

## 常用诊断命令

```bash
# 查看所有租户状态
pwsh -File scripts/Add-DirectTenant.ps1 -Action list

# 健康监控（含 ComplianceUrl 和端口检查）
pwsh -File scripts/Monitor-TenantHealth.ps1

# 自动修复所有 GraphErrorCount 超限
pwsh -File scripts/Monitor-TenantHealth.ps1 -AutoFix

# 同步所有 Dashboard 数据
pwsh -File scripts/Sync-DashboardData.ps1

# 同步单个租户
pwsh -File scripts/Sync-DashboardData.ps1 -TenantFilter '<domain>'

# 探测 ComplianceUrl
pwsh -File scripts/Fix-ComplianceUrl.ps1

# 测试端口 446
timeout 5 nc -zv -w 3 apc01b.admin.protection.outlook.com 446
```

---

## Oracle Cloud 特别注意事项

1. **端口 446 被阻**: OCI 默认安全组不开放非标准端口，需手动添加 Egress Rule
2. **出站规则**: OCI 默认允许所有出站，但某些端口可能被底层网络阻断
3. **NSG vs Security List**: 如果使用了 NSG（网络安全组），需要同时检查 NSG 和 Security List 的规则
