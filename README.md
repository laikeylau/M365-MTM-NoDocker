# M365-MTM - Microsoft 365 Multi-Tenant Manager

基于 [CIPP (CyberDrain Improved Partner Portal)](https://github.com/KelvinTegelaar/CIPP) 的 Linux 自托管部署版本，专注于 Microsoft 365 多租户管理。

## 项目结构

```
M365-MTM/
├── cipp-server.ps1    # 直跑宿主：API 守护 (端口 7071) + 后台 Worker (-WorkerOnly)
├── install.sh         # 一键安装（仅需 PowerShell 7 + Linux）
├── frontend/          # CIPP 前端 (Next.js，本地预构建，服务器零 Node)
├── backend/           # CIPP-API 后端 (PowerShell)
│   ├── Modules/AzTablesShim/   # SQLite 存储层（替代 Azurite/Azure Table Storage）
│   └── data/cipp.db            # 全部表/队列数据
├── deploy/
│   ├── Caddyfile               # Web 层（静态托管 + /api 反代 + /.auth mock + HTTPS）
│   ├── systemd/                # cipp-api.service + cipp-worker.service
│   └── docker-compose.yml      # （已废弃，仅旧环境参考）
├── scripts/           # 自定义管理脚本（在 CIPP 服务器上执行）
│   ├── Migrate-AzuriteToSqlite.ps1   # 旧 Azurite 数据 → SQLite 一次性迁移
│   ├── Add-DirectTenant.ps1          # 租户管理（list/add/reset/fix-compliance/fix-status/delete/import）
│   ├── Fix-ComplianceUrl.ps1         # 自动发现并设置 ComplianceUrl
│   ├── Fix-CIPPTenantPermissions.ps1 # 授予租户额外权限
│   ├── Monitor-TenantHealth.ps1      # 健康监控（GraphErrorCount + ComplianceUrl + 端口检查）
│   ├── Setup-TenantPermissions.ps1   # 一次性权限配置（59 Graph + 2 EXO + Exchange Admin）
│   ├── Sync-AllCache.ps1             # 全量缓存同步（覆盖 72 个缓存函数）
│   └── Sync-DashboardData.ps1        # Dashboard 数据同步（Users/Groups/Devices/MFA/License）
├── docs/              # 文档
├── TROUBLESHOOTING.md # 故障排除指南
├── RUNBOOK.md         # 部署运维手册
└── frontend-dist/     # 构建后的前端静态文件（发布产物）
```

## 架构（无 Docker 版）

```
浏览器 ──> Caddy（静态 frontend-dist + 自动 HTTPS）
              │ /api/* 反代
              ▼
        cipp-api   (cipp-server.ps1, :7071, PowerShell 直跑 HTTP 宿主)
              │ SQLite (AzTablesShim, backend/data/cipp.db)
              ▼
        cipp-worker (cipp-server.ps1 -WorkerOnly: 28 个 cron 定时器 + SQLite 队列 + 内联编排器)
```

## 快速开始

### 前置要求

- Linux 服务器 (推荐 Ubuntu 22.04+)
- PowerShell 7.x（install.sh 可自动安装）
- 域名 (可选，用于自动 HTTPS)

> Docker、Node.js、Azurite 均不再需要。

### 部署步骤

```bash
# 1. 克隆项目
git clone https://github.com/laikeylau/M365-MTM.git
cd M365-MTM

# 2. 一键安装（装 pwsh → 初始化 SQLite → 装 systemd 服务 → 装 Caddy → 启动自检）
sudo bash install.sh
# 可选环境变量：
#   M365_MTM_DOMAIN=panel.example.com   # 自动 HTTPS 域名
#   M365_MTM_RUN_CADDY=no               # 跳过 Web 层

# 3. 发布前端（在任意有 Node 的机器上构建一次，把产物放到服务器 frontend-dist/）
cd frontend && npm install && npm run build
scp -r out/* server:/opt/M365-MTM/frontend-dist/

# 4. （可选）迁移旧 Azurite 数据
pwsh -File scripts/Migrate-AzuriteToSqlite.ps1
```

### 手动运行（不用 systemd）

```bash
# API（监听 127.0.0.1:7071）
pwsh -File cipp-server.ps1

# 后台 Worker（cron 定时任务 + 队列）
pwsh -File cipp-server.ps1 -WorkerOnly

# Web 层
sudo caddy run --config deploy/Caddyfile
```

---

## 添加租户

### 方式一：Web UI（推荐）

1. 访问 `https://your-domain/tenant/administration/tenants/add`
2. 输入租户域名
3. 完成 OAuth 授权流程

> 适用于有 GDAP 授权链的场景。如果是 Direct Tenant 模式（无 GDAP），请使用方式二或方式三。

### 方式二：CLI 添加单个租户

> ⚠️ **此操作必须 SSH 登录到 CIPP 部署服务器上执行**，因为脚本需要访问本地 Azurite 表存储和 CIPP 模块。

```bash
# SSH 登录到 CIPP 部署服务器
ssh root@your-cipp-server

# 进入脚本目录
cd $(dirname "$(readlink -f "$0"))/../scripts

# 添加租户（必须提供 TenantId）
pwsh -File Add-DirectTenant.ps1 -Action add \
  -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" \
  -DisplayName "Contoso Ltd" \
  -DefaultDomain "contoso.onmicrosoft.com"
```

添加后会自动调用 `Setup-TenantPermissions.ps1` 配置 CIPP-SAM 的 61 个权限。

### 方式三：批量导入多个租户

> ⚠️ **此操作必须 SSH 登录到 CIPP 部署服务器上执行**。

```bash
# SSH 登录到 CIPP 部署服务器
ssh root@your-cipp-server
cd $(dirname "$(readlink -f "$0"))/../scripts

# 1. 准备 tenants.json（参考格式如下）
cat > tenants.json << 'EOF'
{
  "tenants": [
    {
      "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
      "displayName": "Contoso Ltd",
      "defaultDomain": "contoso.onmicrosoft.com",
      "initialDomain": "contoso.onmicrosoft.com"
    },
    {
      "tenantId": "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy",
      "displayName": "Fabrikam Inc",
      "defaultDomain": "fabrikam.onmicrosoft.com",
      "initialDomain": "fabrikam.onmicrosoft.com"
    }
  ]
}
EOF

# 2. 批量导入
pwsh -File Add-DirectTenant.ps1 -Action import -ConfigFile ./tenants.json
```

---

## 租户管理（全部在 CIPP 服务器上执行）

所有脚本都在 `scripts/` 目录下，通过 SSH 登录服务器后执行。

### 查看所有租户

```bash
cd $(dirname "$(readlink -f "$0"))/../scripts
pwsh -File Add-DirectTenant.ps1 -Action list
```

输出示例：
```
  Name: LLaTech
  Domain: llatech.onmicrosoft.com
  TenantID: 2df8b2f9-1714-4246-825d-d655b1577ec3
  Errors: 0
  PrivilegeStatus: (not set)
  ComplianceUrl: https://apc01b.admin.protection.outlook.com:446
```

### 重置 GraphErrorCount

当 CIPP Dashboard 显示 "Tenant not found" 时，通常是 GraphErrorCount 超过 50 被自动排除：

```bash
# 重置单个租户
pwsh -File Add-DirectTenant.ps1 -Action reset -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# 自动修复所有超限租户
pwsh -File Monitor-TenantHealth.ps1 -AutoFix
```

### 设置 ComplianceUrl

Compliance API (DlpCompliancePolicies 等) 需要正确的区域端点。自动探测：

```bash
# 探测所有租户
pwsh -File Fix-ComplianceUrl.ps1

# 强制重新探测（即使已有值）
pwsh -File Fix-ComplianceUrl.ps1 -Force

# 单个租户
pwsh -File Fix-ComplianceUrl.ps1 -TenantFilter "contoso.onmicrosoft.com"
```

### 修正 delegatedPrivilegeStatus

```bash
# 清除为空值（使用 app-only auth，适用于 GDAP 租户）
pwsh -File Add-DirectTenant.ps1 -Action fix-status \
  -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Status ""

# 设置为 GDAP 模式
pwsh -File Add-DirectTenant.ps1 -Action fix-status \
  -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" -Status "granularDelegatedAdminPrivileges"
```

### 删除租户

```bash
pwsh -File Add-DirectTenant.ps1 -Action delete -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

---

## 健康监控

```bash
cd $(dirname "$(readlink -f "$0"))/../scripts

# 基本监控（GraphErrorCount + ComplianceUrl + 端口 446 检查）
pwsh -File Monitor-TenantHealth.ps1

# 自动修复超限租户
pwsh -File Monitor-TenantHealth.ps1 -AutoFix

# 自定义告警阈值
pwsh -File Monitor-TenantHealth.ps1 -Threshold 5 -AutoFix
```

输出示例：
```
=== CIPP Tenant Health Monitor ===
Time: 2025-05-13 01:11:00 UTC
Threshold: 10 | AutoFix: False

  [OK] LLaTech
    Domain: llatech.onmicrosoft.com
    TenantID: 2df8b2f9-1714-4246-825d-d655b1577ec3
    Errors: 0 | Status: (not set)
    ComplianceUrl: https://apc01b.admin.protection.outlook.com:446

─── Compliance API Port Check ─────────
  Port 446: BLOCKED ✗ (DlpCompliancePolicies will not work)
  Fix: Open port 446 outbound in your cloud firewall
```

---

## 数据同步

### Dashboard 数据

```bash
cd $(dirname "$(readlink -f "$0"))/../scripts

# 同步所有租户的 Dashboard 数据
pwsh -File Sync-DashboardData.ps1

# 同步单个租户
pwsh -File Sync-DashboardData.ps1 -TenantFilter "contoso.onmicrosoft.com"
```

覆盖的数据类型：Users, Guests, Groups, Devices, SecureScore, MFAState, LicenseOverview

### 全量缓存同步

```bash
# 同步所有缓存类别
pwsh -File Sync-AllCache.ps1

# 仅同步 Dashboard
pwsh -File Sync-AllCache.ps1 -Categories Dashboard

# 仅同步 Exchange
pwsh -File Sync-AllCache.ps1 -Categories Exchange
```

### 定时任务

```bash
# 每 6 小时同步所有租户缓存
0 */6 * * * cd $(dirname "$(readlink -f "$0"))/../scripts && pwsh -File Sync-AllCache.ps1 >> /var/log/cipp-sync.log 2>&1

# 每小时检查租户健康并自动修复
0 * * * * cd $(dirname "$(readlink -f "$0"))/../scripts && pwsh -File Monitor-TenantHealth.ps1 -AutoFix >> /var/log/cipp-health.log 2>&1
```

---

## 权限配置

CIPP-SAM (`98779b37-04c7-4714-887a-0c3bae41cb82`) 需要以下权限：

- **Microsoft Graph**: 59 个 Application 权限
- **Exchange Online**: 2 个权限 (`Exchange.ManageAsApp`, `Exchange.ManageAsAppV2`)
- **目录角色**: Exchange Administrator
- **Compliance**: `SecurityCompliance.RBAC.Read`, `SecurityCompliance.RBAC.Write`

```bash
# 自动配置权限（在 CIPP 服务器上执行）
cd $(dirname "$(readlink -f "$0"))/../scripts
pwsh -File Setup-TenantPermissions.ps1 -TenantId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

---

## 故障排除

常见问题和修复方案请参见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)：

1. GraphErrorCount 累积导致 "Tenant not found"
2. LicenseOverview 权限不足 (403 Forbidden)
3. DlpCompliancePolicies 超时（端口 446 被阻）
4. delegatedPrivilegeStatus 设置错误
5. ComplianceUrl 未设置或不正确
6. MFAState 同步超时

---

## 文档

- [故障排除指南](TROUBLESHOOTING.md) — 常见问题诊断和修复
- [部署运维手册](RUNBOOK.md) — 完整部署和运维流程
- [迁移指南](MIGRATION-GUIDE.md) — 从 OpenClaw 迁移
- [Direct Tenant 模式指南](docs/direct-tenant-guide.md)
- [租户接入操作指南](docs/tenant-onboarding-guide.md)
- [权限修复指南](docs/permission-fix-guide.md)

---

## 技术架构

- **前端**: Next.js + React + Material-UI
- **后端**: PowerShell 7 + Azure Functions
- **存储**: Azurite (Azure Storage 模拟器) — Docker 容器
- **代理**: Nginx (反向代理 + 静态文件服务)
- **认证**: Microsoft Entra ID (Azure AD) OAuth 2.0
- **Compliance API**: 端口 446 (需云平台开放出站)

---

## 与原版 CIPP 的区别

1. **Linux 原生部署**: 不依赖 Azure Functions 运行时，直接在宿主机运行
2. **Direct Tenant 模式**: 支持直接添加租户，无需 GDAP 代理链
3. **自动权限配置**: 新租户添加时自动配置完整权限
4. **全量缓存同步**: 覆盖 72 个缓存函数的完整同步脚本
5. **租户健康监控**: 自动检测和修复 GraphErrorCount、ComplianceUrl 等问题
6. **故障排除文档**: 详细的已知问题和修复方案

---

## 许可证

本项目基于原版 CIPP 的自定义许可证。详见 [LICENSE.CustomLicenses](backend/LICENSE.CustomLicenses)。

## 致谢

- [KelvinTegelaar/CIPP](https://github.com/KelvinTegelaar/CIPP) - 原版 CIPP 项目
- [CyberDrain](https://www.cyberdrain.com/) - CIPP 开发团队

## 支持

如有问题，请提交 [Issue](https://github.com/laikeylau/M365-MTM/issues)。
