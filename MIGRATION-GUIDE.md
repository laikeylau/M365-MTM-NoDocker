# CIPP 迁移指南：Azure → Linux 自托管

本指南帮助你将 CIPP 从 Azure（Static Web Apps + Azure Functions）迁移到自托管 Linux 虚拟机部署。

> **源仓库**: [github.com/laikeylau/CIPP](https://github.com/laikeylau/CIPP)

## 迁移前准备

### 你需要
- 一台 Linux 虚拟机（Ubuntu 20.04+ 推荐）
- Docker 和 Docker Compose 已安装
- 你的 CIPP fork 仓库（或使用 [laikeylau/CIPP](https://github.com/laikeylau/CIPP)）
- 现有的 CIPP 凭据（APPLICATIONID, APPLICATIONSECRET, REFRESHTOKEN, TENANTID）

### 不再需要
- Azure Static Web Apps 资源
- Azure Functions 资源
- Azure Key Vault（凭据改由 .env 文件管理）
- Azure AD 管理员权限（认证改为本地）

## 迁移步骤

### 第 1 步：克隆仓库

```bash
git clone https://github.com/laikeylau/CIPP.git
cd CIPP
```

### 第 2 步：获取 CIPP-Linux 部署配置

将本目录（CIPP-Linux）放到 CIPP 仓库根目录下：

```
CIPP/
├── CIPP-API/
├── CIPP-Frontend/
└── CIPP-Linux/        ← 放在这里
```

### 第 3 步：配置环境变量

```bash
cd CIPP-Linux
cp .env.example .env
chmod 600 .env
```

编辑 `.env`，填入你的 CIPP 凭据：

```env
APPLICATIONID=你的-App-Registration-Client-ID
APPLICATIONSECRET=你的-App-Registration-Secret
REFRESHTOKEN=你的-Refresh-Token
TENANTID=你的-Tenant-ID
```

### 第 4 步：运行部署脚本

```bash
bash deploy.sh
```

部署脚本会自动：
1. 验证目录结构
2. 应用本地认证补丁
3. 构建前端
4. 启动 Docker 容器

### 第 5 步：首次登录

1. 打开 `http://你的服务器IP`
2. 点击 "Register" 标签
3. 创建管理员账号（第一个用户自动获得 admin 角色）
4. 使用新账号登录

## 认证变更说明

### 之前（Azure 部署）
- 使用 Azure Static Web Apps 内置认证
- 用户通过 Azure AD 登录
- SWA 在请求头中注入 `x-ms-client-principal`

### 现在（Linux 部署）
- 使用本地邮箱密码认证
- 用户通过注册页面创建账号
- 前端在请求头中注入 `Authorization: Bearer <JWT>`

### 向后兼容
- 后端同时支持两种认证方式
- 如果请求包含 `x-ms-client-principal` 头，优先使用 SWA 认证
- 如果请求包含 `Authorization: Bearer` 头，使用 JWT 认证

## 文件变更清单

### 新增文件

| 文件 | 用途 |
|------|------|
| `CippLocalAuth.psm1` | 本地认证 PowerShell 模块 |
| `Invoke-AuthRegister.ps1` | 用户注册 API 端点 |
| `Invoke-AuthLogin.ps1` | 用户登录 API 端点 |
| `Invoke-AuthVerify.ps1` | Token 验证 API 端点 |
| `local-auth-context.js` | 前端认证状态管理 |
| `login.js` | 登录页面组件 |

### 修改文件

| 文件 | 变更 |
|------|------|
| `Test-CIPPAccess.ps1` | 添加 JWT Token 认证支持 |
| `profile.ps1` | 加载 CippLocalAuth 模块 |
| `PrivateRoute.js` | 使用本地认证替代 SWA 认证 |
| `ApiCall.jsx` | 自动添加 Authorization 头 |
| `next.config.js` | 移除 SWA/MSAL 配置 |

## 数据迁移

### 用户数据
- 本地认证用户数据存储在 Azurite（Azure Storage 模拟器）的 Table Storage 中
- Azurite 数据在 Docker volume `azurite-data` 中持久化
- 如需从 Azure 迁移用户数据，需导出 Azure Table Storage 并导入 Azurite

### 配置数据
- CIPP 的租户配置、策略等存储在 Table Storage 中
- 如已在 Azure 上运行 CIPP，需通过 API 或手动导出配置

## 回滚方案

如需回滚到 Azure 部署：
1. 停止 Docker 容器：`docker compose down`
2. CIPP-Linux 的所有修改都有 `.backup` 备份文件
3. 重新部署到 Azure：使用原始 Azure 部署流程

## 常见问题

**Q: 迁移后需要重新配置所有租户吗？**
A: 是的，因为 Azurite 是全新的存储实例。建议通过 CIPP API 批量导入配置。

**Q: 能否保留 Azure AD 认证？**
A: 可以。后端代码保留了 SWA 认证的兼容路径。只需在 Nginx 中配置 Azure AD 相关的环境变量，并使用 MSAL 前端代码（需自行添加）。

**Q: 生产环境安全吗？**
A: 当前方案适合小团队内部使用。生产环境建议：
- 升级密码哈希到 bcrypt/argon2
- 启用 HTTPS
- 使用外部数据库替代 Azurite
- 添加邮箱验证

**Q: 如何更新 CIPP 版本？**
A: 拉取最新代码后重新运行 `deploy.sh`。补丁脚本会检测已应用的补丁并跳过。
