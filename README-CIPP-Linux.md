# CIPP Linux Deployment

将 CIPP (CyberDrain Improved Incident Portal) 从 Azure Static Web Apps 迁移到自托管 Linux 虚拟机部署。

> **来源仓库**: [github.com/laikeylau/CIPP](https://github.com/laikeylau/CIPP)

## 快速开始

```bash
# 1. 克隆 CIPP 仓库
git clone https://github.com/laikeylau/CIPP.git
cd CIPP

# 2. 将 CIPP-Linux 目录放入仓库根目录
# (如果从 ZIP 解压，确保 CIPP-Linux/ 在 CIPP/ 根目录下)

# 3. 配置环境变量
cd CIPP-Linux
cp .env.example .env
chmod 600 .env
# 编辑 .env 填入你的 CIPP 凭据

# 4. 一键部署
bash deploy.sh
```

## 目录结构

```
CIPP/                          ← 你的 fork
├── CIPP-API/                  ← 后端 (PowerShell Azure Functions)
├── CIPP-Frontend/             ← 前端 (Next.js)
└── CIPP-Linux/                ← 本目录 (Linux 部署配置)
    ├── docker-compose.yml     ← Docker 服务编排
    ├── deploy.sh              ← 一键部署脚本
    ├── apply-patches.sh       ← 本地认证补丁脚本
    ├── nginx.conf             ← Nginx 反向代理配置
    ├── .env.example           ← 环境变量模板
    ├── backend-patches/       ← 后端认证补丁文件
    ├── frontend-changes/      ← 前端认证修改文件
    ├── setup-ssl.sh           ← SSL 证书配置脚本
    └── azure-quickfix.sh      ← Azure 部署快速修复 (可选)
```

## 架构

```
┌─────────────────────────────────────────┐
│              Linux VM                    │
│                                         │
│  ┌──────────┐  ┌──────────┐  ┌────────┐│
│  │  Nginx   │  │ CIPP-API │  │Azurite ││
│  │  :80/443 │→ │  :7071   │→ │:10000+ ││
│  │ (前端+   │  │(PowerShell│  │(存储   ││
│  │  反代)   │  │ Functions)│  │ 模拟)  ││
│  └──────────┘  └──────────┘  └────────┘│
│       ↑              │                  │
│       │              ↓                  │
│   用户浏览器    Microsoft Graph API      │
└─────────────────────────────────────────┘
```

## 认证方案

本部署使用 **本地邮箱密码 + JWT Token** 认证，无需 Azure AD 或 Static Web Apps：

- 用户通过邮箱+密码注册/登录
- 后端颁发 JWT Token（24小时有效）
- 前端通过 `Authorization: Bearer <token>` 调用 API
- 第一个注册用户自动获得 admin 角色

## 安全加固

- Nginx 登录端点速率限制：5 req/s（防暴力破解）
- 注册端点速率限制：2 req/s
- 安全响应头（X-Frame-Options, X-Content-Type-Options 等）
- 密码使用 SHA-256 + 随机盐值存储
- JWT Token 24小时过期，需重新登录

> **建议生产环境加固**：
> - 将密码哈希升级为 bcrypt/argon2
> - 启用 HTTPS（运行 `setup-ssl.sh`）
> - 使用外部数据库替代 Azurite

## 环境变量

参见 `.env.example` 了解所有可配置项。必需项：

| 变量 | 说明 |
|------|------|
| `APPLICATIONID` | Azure AD App Registration 的 Application ID |
| `APPLICATIONSECRET` | App Registration 的 Client Secret |
| `REFRESHTOKEN` | OAuth2 Refresh Token |
| `TENANTID` | Microsoft 365 租户 ID |

## 常用命令

```bash
# 查看日志
docker compose logs -f

# 重启 API 容器
docker compose restart cippapi

# 停止所有服务
docker compose down

# 完全重建
docker compose up -d --build

# 检查服务健康状态
docker compose ps
```

## 故障排除

**API 容器启动失败**
```bash
docker compose logs cippapi | tail -50
```
常见原因：CIPP-API/Dockerfile 缺失、PowerShell 模块安装失败。

**前端白屏**
检查 `frontend-dist/` 目录是否有内容。如没有，重新运行 `deploy.sh`。

**认证失败**
确认 `.env` 中的凭据正确，且 `apply-patches.sh` 已成功运行。
