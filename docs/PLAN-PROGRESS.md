# 平台优化改造 — 执行进度

> 计划来源: `.zcode/plans/plan-sess_4ca76e4d-33e5-47fc-a26d-74134950f199.md`
> 本文档记录截至当前的实际完成状态与剩余工作。

## 状态总览

| 阶段 | 内容 | 状态 |
|---|---|---|
| Phase 1 减重 (轨道 A) | A1 SQLite 存储层 | ✅ 完成(含 bug 修复与回归测试) |
| | A2 API 守护 + systemd + Caddy | ✅ 完成(本机冒烟验证通过) |
| | A3 前端预构建 + 死代码清理 | ⚠️ 部分完成(见下) |
| | A4 安装与残留清理 | ✅ 完成 |
| | A5 后台任务自持 | ✅ 完成(端到端验证通过) |
| Phase 2 报告中心 (轨道 B) | B1–B3 | ❌ 未开始 |
| Phase 3 双语 (轨道 C) | C | ❌ 未开始 |
| Phase 4 收尾 | 文档+验证 | ⚠️ README 已重写；部署演练需在 Linux 上做 |

## 已完成明细

### A1. SQLite 存储层 (AzTablesShim) ✅
- `backend/Modules/AzTablesShim/` — 9 个同名命令完整实现:OData 过滤翻译器(eq/ne/ge/lt/and/or/startswith/datetime 字面量)、ETag 乐观并发、批量事务、UpsertReplace/Merge 语义
- SQLite DLL 已打包 `backend/Shared/Sqlite/`(win/linux/musl/osx 全 RID)
- **修复**: `Get-AzDataTableEntity` 内局部变量 `$count` 与 `[switch]$Count` 参数同名导致赋值类型冲突 → 改名 `$rowCount`
- 回归测试 `tests/AzTablesShim.Tests.ps1`: **35/35 PASS**
- 接线: `backend/profile.ps1` 改为加载 `AzTablesShim`;CippEntrypoints 批量并行块同步替换
- 迁移脚本: `scripts/Migrate-AzuriteToSqlite.ps1`

### A2. API 直跑宿主 ✅
- `cipp-server.ps1`(仓库根):环境装配 → dot-source profile → HttpListener :7071
  - `Push-OutputBinding` shim(Response 捕获 / QueueItem → SQLite 队列)
  - `Start-NewOrchestration` shim(替代 Durable SDK,编排经队列异步执行)
  - `System.Net.HttpResponseContext` 兼容类型(编译进内存程序集)
- `deploy/systemd/cipp-api.service` + `cipp-worker.service`(Restart=always)
- `deploy/Caddyfile`:静态托管 frontend-dist + /api 反代 + /.auth mock + 登录/注册限流(限流需 caddy-ratelimit 插件,已在文件头注明)
- 冒烟验证: `GET /api/ListTenants` → **200**(带 mock SWA principal 头)

### A4. 安装与清理 ✅
- `install.sh`:检查/安装 pwsh → 复制到 /opt/M365-MTM → SQLite 初始化 + API 冒烟 → 装 systemd 服务 → 装 Caddy → 自检
- 全库清除硬编码 `/root/cipp-deploy/...` 路径(脚本自定位 `$PSScriptRoot`;docs/README/RUNBOOK 同步)
- `scripts/` 中 `AzBobbyTables` 引用改为 `AzTablesShim`
- 删除 `frontend/theme-backup-202605141658/`(grep 确认零引用)

### A5. 后台任务自持 ✅
- Worker 模式(`cipp-server.ps1 -WorkerOnly`):
  - Cronos 驱动 CIPPTimers.json 定时器(每 15s 评估到期)
  - SQLite 队列表 `cippqueue`(可见性超时 + 5 次重试退避 + 死信)
  - 内联编排执行器(`Invoke-CippInlineOrchestration`:batch → Receive-CippActivityTrigger → PostExecution),实例状态写 `<site>Instances` 表
- 核心小补丁: `Receive-CIPPTimerTrigger` 增加 `-DueFunctions` 过滤参数 + 空状态行防御
- **端到端验证**: Start-DurableCleanup ✅;审计日志编排(GUID 存储 → 队列 → Start-NewOrchestration shim → 内联执行)✅;无凭据时优雅失败 ✅
- **踩坑记录**: `WEBSITE_SITE_NAME` 含 `-` 会被节点解析逻辑当作 processor 名,导致 0 个 timer 被调度 → 默认改为无连字符的 `CIPP`

## 剩余工作

### A3. 前端死代码清理(未完成部分)
- [ ] 删除 `frontend/src/sections/dashboard/` 93 个未引用 Devias 演示文件(需 import 图分析 + 构建验证)
- [ ] 11 个占位页、重复版本(dashboardv1、旧 onboarding.js 等)、`ReportDashboard.jsx`
- [ ] 移除未用依赖: react-grid-layout、@nivo/*、Formik、react-quill、react-beautiful-dnd、Recharts(保留 react-window + ApexCharts)、Redux(toast slice 迁 context)
- [ ] `npm install && npm run build` 全量验证后提交 frontend-dist/ 产物
- 注意: 本机有 Node v24,但 node_modules 未安装;构建约需数分钟

### Phase 2. AdminDroid 式报告中心(B1–B3,未开始)
- B1 `frontend/src/data/report-registry.js`(服务→分类→报告树,nameEn/nameZh)
- B2 路由 `/reports/:service/:reportId` + 树导航 + CippDataTable 渲染 + 跨租户聚合
- B3 行内操作(注册表 rowActions → 现有 Exec 端点,零新后端)
- 素材: 现有分散报告页(Email 12/Identity 5/Tenant 4/Security/Intune)+ 72 类 DB 缓存(backend/Config/CIPPDBCacheTypes.json)

### Phase 3. 中英双语(C,未开始)
- i18next + react-i18next 已在依赖中;建 `frontend/src/i18n/`
- 分批: 导航+报告中心 → 常用管理页 → 渐进覆盖

### Phase 4. 收尾(部分完成)
- [x] README 重写(两组件部署)
- [ ] RUNBOOK / MIGRATION-GUIDE 同步新架构
- [ ] 干净 Ubuntu 部署演练(install.sh 全流程)

## 快速自检命令

```bash
# 存储层回归测试(35 断言)
pwsh -NoProfile -File tests/AzTablesShim.Tests.ps1

# API 冒烟
pwsh -File cipp-server.ps1 &
curl -s -H "x-ms-client-principal: $(printf '%s' '{"userRoles":["authenticated","superadmin"]}' | base64 -w0)" \
  http://127.0.0.1:7071/api/ListTenants

# 后台 worker
pwsh -File cipp-server.ps1 -WorkerOnly
# 观察日志: 定时器 firing + 队列执行 + 编排 GUID
```
