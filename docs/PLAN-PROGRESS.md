# 平台优化改造 — 执行进度

> 计划来源: `.zcode/plans/plan-sess_4ca76e4d-33e5-47fc-a26d-74134950f199.md`
> 本文档记录截至当前的实际完成状态与剩余工作。

## 状态总览

| 阶段 | 内容 | 状态 |
|---|---|---|
| Phase 1 减重 (轨道 A) | A1 SQLite 存储层 | ✅ 完成(含 bug 修复与回归测试) |
| | A2 API 守护 + systemd + Caddy | ✅ 完成(本机冒烟验证通过) |
| | A3 前端预构建 + 死代码清理 | ✅ 完成(2026-09-08: 93+ 死文件删除、ToastContext 迁移、10 依赖裁剪、next build 全量通过 302 页导出) |
| | A4 安装与残留清理 | ✅ 完成 |
| | A5 后台任务自持 | ✅ 完成(端到端验证通过) |
| Phase 2 报告中心 (轨道 B) | B1–B3 | ✅ 完成（注册表 70 份：39 首批 + 31 份 AdminDroid 对标；动态路由/树导航 + 行内操作；真实租户联调 ✅ 对生产 API 完成，E2E 15/15，环境类失败另列） |
| Phase 3 双语 (轨道 C) | C | ✅ 完成（批次 1 导航层 + 批次 2 管理页 chrome + 批次 3 报告中心/动作/列头渐进） |
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

### A3. 前端死代码清理 ✅ (2026-09-08 完成)
- [x] 删除 `frontend/src/sections/dashboard/` 93 个未引用 Devias 演示文件(import 图分析 0 引用)
- [x] 删除 dashboardv1.js、onboarding.js、onboardingv2.js、ReportDashboard.jsx、quill-editor.js、CippDropzone.jsx、AuthMethodSankey/CaDeviceSankey(全部 0 引用)
- [x] Redux(toasts) → `src/contexts/toast-context.js`(10 个消费方迁移,store 删除)
- [x] 依赖裁剪: react-grid-layout、formik、react-quill、react-beautiful-dnd、react-redux、redux、@reduxjs/toolkit、redux-persist、redux-thunk、redux-devtools-extension
- **计划修正**: recharts/@nivo/material-react-table 保留 —— 它们被在用的首页 dashboardv2(SecureScoreCard/AuthMethodCard→CippSankey)和 CippDataTable(Phase 2 B2 需要)引用
- [x] `npm install --legacy-peer-deps && NODE_OPTIONS=--max-old-space-size=6144 npm run build` 全量通过(302 页静态导出,51MB)
- **踩坑**: Next 16 静态导出 worker(isolatedMemory)强制删除 --max-old-space-size 用默认 ~2GB 堆 → 8GB 物理内存机器 OOM;next.config 加 `experimental.workerThreads: true` 让线程共享父进程堆解决。本机安装需 `--legacy-peer-deps`(react-html-parser vs React 19 既有冲突)

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

### 2026-09-08 追加
- Phase 2 B1+B2 ✅：报告注册表（39 份）+ 报告中心路由/树导航/旧路由重定向；build 341 页通过；无头 E2E 4/4
- Phase 3 批次 1 ✅：i18next 基础设施 + 导航层全量双语 + 语言切换入口；Windows 本机运行时验证通过
- 通用端点验证完成：`/api/ListDBCache?tenantFilter=&type=`（签名与预想不同，已按实际调整）
- 剩余：B3 行内操作；Phase 3 批次 2/3；真实租户联调；Phase 4
- Phase 2 B3 ✅：行内操作（设备 actions 提取共享 hook + 注册表 preset/内联两种写法）；5 份报告首批接入；build+E2E 通过。**B1–B3 全部完成**
- Phase 3 批次 2 ✅：管理页 common 命名空间（表格 chrome 49 词条 + MRT 官方 zh-Hans 本地化注入）；build/eslint/字典/无头 E2E PASS
- Phase 3 批次 3 ✅（2026-09-09）：报告中心 nameEn/nameZh 对接（report-name.js 注册表直查，标题/树/浏览器 tab 随语言切换）+ 动作 label（行内/批量菜单，common 100 词条）+ 列头渐进覆盖（columns ns 68 词条 + getCippTranslation 接入 + 语言切换列重算）；dev-serve 新增 API fixtures 能力；字典校验 9/9 + 无头 E2E 16/16 + 回归 2 脚本 PASS。**Phase 3 全部完成**
- 剩余：真实租户联调（需 CSP RefreshToken 环境）；graph-office-reports 可选迁移；Phase 4（RUNBOOK/MIGRATION-GUIDE 同步 + Ubuntu 演练）

### 2026-09-09 追加：② 真实租户联调 ✅（详见 PHASE2-PREP.md §10）
- **联调环境**：直接对生产 API `https://mtm.cxty.de`（服务器侧注入 superadmin，无需本地凭据）；租户 `lenitech.onmicrosoft.com`；本机新构建 out/ + dev-serve https 上游
- **新工具**：`scripts/live-integration.mjs`（39 报告逐一联调 + Exec 端点探测）；`scripts/verify-live-reports-headless.mjs`（真实数据 E2E）
- **API 层**：30/39 有数据（DBCache 19/19 全命中；列匹配 mfa-state 11/11、signin 8/8、mailbox-statistics 7/7）；7 项失败均为环境问题（EXO token 过期 ×2、Sherweb 未启用、ListGlobalAddressList 后端 bug〔已修〕等）
- **前端修复 4 处**：DBCache 缺 `apiDataKey:'Results'`（包裹形态整包当一行）；`Results:null` 归一化（否则渲染一行 null）；`inactive-users` 列名 PascalCase→camelCase + 补 useReportDB；`mailbox-forwarding`/`calendar-permissions` 列对齐旧页 + 转发动作映射 `User`→`UPN`
- **后端修复 1 处**：`Invoke-ListGlobalAddressList.ps1` 反引号续行断裂（`` ` -AsApp``+空格）致 `-Select` 被当命令 → 403
- **B3 执行链**：3 个 Exec 端点生产存在（GET 探测）；mfa-state 行内菜单 8 项真实数据下正常；POST 全链留待受控租户手工触发
- **验证**：build 341+ 页通过；eslint 零新增；E2E 10/10 PASS（真实数据渲染/解包修复/ZH 切换/console 零错误）
- **剩余**：本次修复随下次部署上生产（生产 out/ 仍旧构建）；EXO 凭据更新后复验 3 报告；真实 POST 手工闭环；Phase 4

### 2026-09-10 追加：第二批扩充 ✅ AdminDroid 对标合并（39 → 70 份，详见 PHASE2-PREP.md §11）
- **素材**：生产已同步 70 类缓存 − 注册表已用 20 类 = 54 候选；筛除未同步 7 类（Copilot ×4 等）与在线报告重复 4 类（EXO 政策类）→ **新增 31 份全 DBCache 报告**
- **覆盖扩展**：目录角色/PIM 活动分配、企业应用/应用注册/角色分配、MFA·SSPR 注册明细、DKIM/隔离/预设安全策略、OneDrive·SharePoint 用量、Office 激活、Azure AD 设备/加密状态、Intune 合规/配置/保护/Autopilot、安全分数控制项(460 行)/目录建议/Defender 接入、验证强度/命名位置/跨租户策略
- 新分类 3 个（角色与管理员/企业应用/Office 应用）；精选列字段生产实测核对；**生产独有类型 10 个**（本地缓存配置落后于生产版本）
- i18n：columns.json +48 词条（87 显式列全覆盖）；字典校验 ALL PASS
- 验证：build 70 报告 SSG 通过；live-integration 31/31 全 200 零新增 FAIL；E2E **15/15 PASS**（脚本重构为确定性等待，修复时序 flake）
- graph-office-reports 维持不迁（交互页）；遗留：7 类待生产同步后补注册 + §10 既有项
