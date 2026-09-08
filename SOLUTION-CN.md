# CIPP Linux 部署方案

## 问题背景

CIPP 原生设计运行在 Azure 平台上：
- **前端**: Azure Static Web Apps (SWA)
- **后端**: Azure Functions (PowerShell)
- **存储**: Azure Table Storage
- **认证**: SWA 内置 Azure AD 认证

对于没有 Azure 管理员权限、或希望在本地 Linux 服务器自托管的场景，需要解决以下挑战：

1. **存储替代** → 使用 Azurite（Azure Storage 模拟器）
2. **认证替代** → 本地邮箱密码 + JWT Token 认证
3. **前端部署** → Next.js 静态导出 + Nginx 反向代理
4. **后端部署** → Azure Functions 容器化（Docker）

## 解决方案概览

```
┌─────────────────────────────────────────────────────┐
│                   Docker Compose                     │
│                                                     │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │   Nginx     │  │  CIPP-API    │  │  Azurite   │ │
│  │  :80/:443   │→ │   :7071      │→ │  :10000+   │ │
│  │             │  │              │  │            │ │
│  │ • 静态前端  │  │ • PowerShell │  │ • Blob     │ │
│  │ • API 反代  │  │ • Functions  │  │ • Queue    │ │
│  │ • 速率限制  │  │ • Graph API  │  │ • Table    │ │
│  │ • SSL 终止  │  │ • 本地认证   │  │            │ │
│  └─────────────┘  └──────────────┘  └────────────┘ │
│                                                     │
│  Linux VM / 虚拟机                                   │
└─────────────────────────────────────────────────────┘
```

## 认证流程

```
用户浏览器                    Nginx                    CIPP-API
    │                          │                          │
    │  POST /api/Invoke-AuthLogin  │                        │
    │  { email, password }     │                          │
    │─────────────────────────→│─────────────────────────→│
    │                          │   (速率限制: 5 req/s)    │
    │                          │                          │ 验证密码
    │                          │                          │ 生成 JWT
    │  ← 200 { token, user }  │←─────────────────────────│
    │←────────────────────────│                          │
    │                          │                          │
    │  GET /api/xxx            │                          │
    │  Authorization: Bearer   │                          │
    │─────────────────────────→│─────────────────────────→│
    │                          │                          │ 验证 JWT
    │  ← 200 data              │←────────────────────────│
    │←────────────────────────│                          │
```

## 关键修改

### 后端 (CIPP-API)

1. **新增 CippLocalAuth 模块**
   - `CippLocalAuth.psm1`: 用户注册、登录、JWT 生成/验证
   - 密码使用 SHA-256 + 随机盐值存储

2. **新增 HTTP 端点**
   - `Invoke-AuthRegister.ps1`: 用户注册
   - `Invoke-AuthLogin.ps1`: 用户登录
   - `Invoke-AuthVerify.ps1`: Token 验证

3. **修改 Test-CIPPAccess.ps1**
   - 支持从 `Authorization: Bearer` 头读取 JWT
   - 保持 SWA `x-ms-client-principal` 向后兼容

### 前端 (CIPP-Frontend)

1. **新增 local-auth-context.js**
   - 替代 SWA 内置认证和 MSAL
   - 管理 JWT Token、登录状态

2. **修改 PrivateRoute.js**
   - 使用本地认证上下文替代 SWA 认证检查

3. **新增 login.js**
   - 邮箱密码登录页面

4. **修改 ApiCall.jsx**
   - 自动在所有请求中添加 `Authorization: Bearer` 头

## 部署步骤

```bash
# 1. 克隆仓库
git clone https://github.com/laikeylau/CIPP.git
cd CIPP

# 2. 配置
cd CIPP-Linux
cp .env.example .env
vim .env  # 填入凭据

# 3. 部署
bash deploy.sh
```

## 局限性

- **密码存储**: 当前使用 SHA-256 + salt，建议生产环境升级为 bcrypt/argon2
- **Token 刷新**: JWT 24小时过期后需重新登录，无 refresh token 机制
- **多用户**: 无邮箱验证，适合小团队内部使用
- **高可用**: 单节点部署，不支持水平扩展
