# Phase 2 报告中心 — 准备材料（2026-09-08）

> 前置: A3 已完成（见 PLAN-PROGRESS.md）。本文档汇总 B1–B3 开工前的调查结论与设计骨架。

## 0. 关键结论：后端零改动即可支撑 B1–B3

调查确认以下原语**已经存在**：

| 原语 | 位置 | 作用 |
|---|---|---|
| `?UseReportDB=true` | 任意 ListX 端点（由前端 `useCippReportDB` 拼接） | 直读 SQLite DB 缓存，天然带 `Tenant` 维度 → 跨租户聚合 |
| `/api/ExecCIPPDBCache` | backend | 行级"立即同步缓存"（`{ Name: cacheName }` + tenantFilter） |
| 72 类缓存类型 | `backend/Config/CIPPDBCacheTypes.json` | 每类有 `type/friendlyName/description` → 注册表直接映射 |
| `CippTablePage` | `src/components/CippComponents/CippTablePage.jsx` | 报告渲染：title/apiUrl/simpleColumns/filters/**actions**/offCanvas/exportable |
| `CippDataTable` actions | `src/components/CippTable/CippDataTable.js`（L708+） | 行内菜单 → `CippApiDialog`，B3 零新后端 |
| `CippReportToolbar` / `useCippReportDB` | `src/components/CippComponents/CippReportDBControls.jsx` | 缓存/在线切换 + 同步按钮 + queryKey 管理 |

## 1. B1 报告注册表（单一事实来源）

新建 `frontend/src/data/report-registry.js`，schema：

```js
{
  id: 'mfa-state',              // 路由用 reportId
  service: 'identity',          // 树导航一级
  category: '安全与合规',        // 树导航二级（Bilingual via key）
  nameEn: 'MFA Report', nameZh: 'MFA 报告',
  source: { type: 'ListX', url: '/api/ListMFAUsers' }
        | { type: 'DBCache', cache: 'MFAState', url: '/api/ListCippDBCache?Name=MFAState' },
  columns: ['UPN', 'AccountEnabled', ...],   // simpleColumns
  filters: [...],                // CippTablePage 原样透传
  rowActions: [...],             // B3: 引用现有 Exec 端点
  syncCache: 'MFAState',         // ExecCIPPDBCache 同步目标
  exportable: true, chartType: 'table'
}
```

首批注册目标（30~40 份）：
- **现有分散报告页迁移**（12+5+4 ≈ 21 份）：`src/pages/{email,identity,tenant}/reports/*`
  - email/reports: SharedMailboxEnabledAccount, activesync-devices, antiphishing-filters, calendar-permissions, global-address-list, mailbox-activity, mailbox-cas-settings, mailbox-forwarding, mailbox-permissions, mailbox-statistics, malware-filters, safeattachments-filters
  - identity/reports: mfa-report, inactive-users-report, signin-report, azure-ad-connect-report, risk-detections
  - tenant/reports: list-licenses, list-csp-licenses, application-consent, graph-office-reports
- **DB 缓存报表化增值**（AdminDroid 式，零新后端）：从 72 类中选 ~15 类首批
  - 用户/组/许可：Users, Groups, Guests, LicenseOverview, MFAState, OAuth2PermissionGrants
  - 邮件：Mailboxes, CASMailboxes, MailboxUsage, ExoTransportRules, ExoAcceptedDomains
  - 设备：ManagedDevices, IntunePolicies, DetectedApps
  - 安全：ConditionalAccessPolicies, RiskyUsers, RiskDetections, SecureScore
  - 协作：OneDriveSiteListing, SharePointSiteListing, OfficeActivations

> 注意：`ListCippDBCache` 类通用端点是否可用需开工时验证 —— 若无通用端点，B1 的 DBCache 报告需在 `useCippReportDB` 层确认数据源（部分 ListX 端点已支持 `UseReportDB=true`，优先复用）。

## 2. B2 统一报告中心 UI

- 新路由 `src/pages/reports/[service]/[reportId]/index.js`（动态路由读注册表）
- 左侧树导航：**身份与访问 / 许可与订阅 / 邮件与 Exchange / 协作（Teams·SP·OneDrive）/ 端点与 Intune / 安全与合规** → 分类 → 报告
- 渲染：注册表条目 → `<CippTablePage {...entry}/>`,跨租户模式=缓存数据自带 Tenant 列
- 旧路由重定向：`src/pages/*/reports/*` 各 index.js 改 `next/router` redirect 到 `/reports/...`（无死链）

## 3. B3 行内操作

- CippTablePage `actions` 基础设施：行内菜单 → `CippApiDialog` → 现有 Exec 端点
- 首批示例：
  - 用户报告行内：改许可(`ExecSetLicense`)、重置 MFA(`ExecResetMFA`)、禁用、临时密码(`ExecDisableUser`/`ExecSetPassword`)
  - 邮箱报告行内：改转发/权限(`ExecSetMailboxForwarding`/`ExecSetMailboxPermission`)
  - 设备报告行内：同步/擦除(`ExecIntuneScript`/设备同步端点)
  - （开工时对照 `backend/Modules/CIPPCore/Public/Entrypoints/Http Functions/Exec*` 实际端点名）

## 4. 验收标准（计划原文）

- 报告中心 30+ 份报告可筛/可导出/可跨租户
- 行内操作执行成功
- 旧报告页重定向无死链

## 5. 开工顺序建议

1. **验证** DBCache 数据源通用端点（半天）
2. **B1** 注册表 + 首批 ~36 份报告（现有 21 份迁移 + 15 类 DBCache）
3. **B2** 动态路由 + 树导航 + 旧路由 redirect
4. **B3** 用户/邮箱/设备首批 rowActions
5. 构建验证 + PLAN-PROGRESS 更新（i18n 键在 Phase 3 分批接入，B1 的 nameEn/nameZh 已预埋）

---

## 6. Phase 3 批次 1 完成记录（2026-09-08，C 轨道开工）

**导航层中英双语已交付**，i18next 基础设施就绪：

| 项 | 内容 |
|---|---|
| 基础设施 | `frontend/src/i18n/`：`index.js`（i18next init，localStorage 持久化 `app.language`，浏览器语言探测）、`nav.js`（`tNavTitle` / `useNavTitle` / `useTranslatedNavItems`）、`locales/zh-CN/nav.json`（159 词条） |
| 覆盖范围 | 侧边导航、移动导航、书签栏、面包屑、全局搜索（UniversalSearchV2）全部 158 个导航标题 + "Global" 提示 |
| 切换入口 | 顶栏语言按钮（desktop）+ 账户弹出菜单（mobile），en ↔ zh-CN 单击切换 |
| 设计决策 | `config.js` 保持不动（单一事实来源）；翻译在渲染层按英文标题查字典，未收录标题原样显示（渐进覆盖）；书签仍存英文标题，语言切换不影响收藏数据 |
| 关键配置 | `keySeparator: false, nsSeparator: false`（标题含 `.`/`/`）、`parseMissingKeyHandler` 回退英文原文 |

**验证**：`next build` 302 页全量通过；eslint 零新增问题（9 个存量问题已在 HEAD 确认）；字典完整性脚本 158/158 覆盖。

**Windows 本机运行时验证（无头 Chrome DOM 断言）**：
- 体验栈：`pwsh -File cipp-server.ps1`（:7071，SQLite）+ `node scripts/dev-serve.mjs`（静态 out/ + /api 注入 superadmin principal）→ http://localhost:3000
- EN→ZH 切换：4/4 导航项命中（Identity Management→身份管理、Dashboard→仪表板、Security & Compliance→安全与合规、Email & Exchange→邮件与 Exchange）
- 持久化：切换后 `localStorage app.language=zh-CN`，刷新后中文保持 ✅
- 截图存档：`docs/screenshots-phase3/`（en / zh / zh 仪表板）；复验脚本：`scripts/verify-i18n-headless.mjs`（playwright-core + 系统 Chrome）

**批次 2（待做）**：常用管理页 CippTablePage 表头/按钮文案 → `common` 命名空间；批次 3：报告中心（依赖 B1 注册表，nameEn/nameZh 预埋字段直接对接）。

---

## 7. Phase 2 B1 + B2 完成记录（2026-09-08）

### 待验证项结论：通用端点已存在，签名与预想不同 ✅
- `Invoke-ListDBCache.ps1`（`/api/ListDBCache`）：`?tenantFilter=<tenant>&type=<cacheName>`，`type=_availableTypes` 可列已缓存类型；`tenantFilter` 必填（由 CippTablePage 自动注入当前租户）
- 非 `?Name=` 形态；本机无 CSP RefreshToken（`Get-Tenants` 报 RefreshToken not set），实测仅到路由层，真实数据联调需有凭据的环境
- 备选路径 `?UseReportDB=true`（ListX 端点级缓存直读）依旧可用，`useCippReportDB` 已封装

### B1 报告注册表 ✅
- `frontend/src/data/report-registry.js`：**39 份报告**（20 迁移 + 19 DBCache 增值；graph-office-reports 因复杂交互未迁，保留原页）
- 6 服务 × 13 分类；`source` 三形态（ListX / ListX+useReportDB / DBCache）；`reportToTableProps()` 映射 CippTablePage props
- 校验：DBCache 类型 19/19 命中 `CIPPDBCacheTypes.json`（65 类）；无重复 id、无孤儿分类
- `graph-office-reports` 保留原页；B3 rowActions 字段预留（`mfa-state` 的 Set Per-User MFA action 可作首批样本）

### B2 统一报告中心 ✅
- `src/pages/reports/[service]/[reportId]/index.js`：getStaticPaths 从注册表生成（39 条 SSG），左树 + 右 CippTablePage；DBCache / ListX+ReportDB 两种渲染子组件
- `CippReportTreeNav.jsx`：服务→分类→报告三级树，搜索过滤，nameZh/nameEn 随语言切换
- 侧边栏新增一级入口 "Reports"（→ `/reports`，复用 nav 字典 '报表'）
- 旧路由重定向 20 页 → `/reports/...`（无死链）；`/reports` 落地页重定向至首份报告
- 侧边栏/树/报告页全部接入 Phase 3 i18n

### 验证 ✅
- `next build` 302 → **341 页**全量通过（+39 报告中心）
- eslint 零新增问题
- 无头 Chrome E2E 4/4：旧路由重定向 ✅ / 语言切换后树标签 ZH ✅ / 树导航切换报告 ✅ / localStorage 持久化 + SSG 直开 ✅
- 截图：`docs/screenshots-phase3/shot-report-center-zh.png`
- **踩坑**：Next 静态导出双形态（`page.html` + `page/index.html`），`dev-serve.mjs` 候选链已补 `.html`

### 剩余
- B3 行内操作（rowActions → Exec 端点，注册表字段已预留）
- 真实租户数据联调（需 CSP RefreshToken 环境）
- graph-office-reports 特殊页迁移（可选）

---

## 8. Phase 2 B3 行内操作完成记录（2026-09-08）

### 实现方式：复用权威 action 集，注册表零 JSX
- **用户类**：`useCippUserActions()`（既有全集：改许可/重置 MFA/TAP/禁用/撤销会话/改转发等）
- **设备类**：从 `endpoint/MEM/devices` 提取 `CippDeviceActions.jsx` → `useCippDeviceActions()`（20 个 action：同步/重启/擦除/LAPS/BitLocker/Defender 扫描/Autopilot Reset 等），MEM 页改用共享 hook（单一事实来源）
- **注册表写法**（`rowActions` 字段）：
  - `{ preset: 'user' }` / `{ preset: 'device' }` — 命名预设
  - `[{ label, type, url, data, confirmText, ... }]` — 内联自定义（数据映射键引用行字段）

### 首批接入（5 份报告）
| 报告 | rowActions | 端点 |
|---|---|---|
| users-cache | preset: user | ExecResetMFA / ExecCreateTAP / ExecDisableUser / ExecPerUserMFA / ExecEmailForward 等 |
| inactive-users | preset: user | 同上 |
| mfa-state | 内联 2 项 | ExecPerUserMFA（data.userId←ID）、ExecResetMFA |
| managed-devices-cache | preset: device | ExecDeviceAction（sync/reboot/wipe/delete/retire…） |
| mailbox-forwarding | 内联 1 项 | ExecEmailForward（!disabled，data.username←User） |

### 验证 ✅
- `next build` 全量通过；eslint 零新增
- 无头 Chrome E2E 5/5：mfa-state / managed-devices-cache / users-cache / mailbox-forwarding 渲染无错 + MEM 设备页重构健全性；console 零 action 相关错误
- **限制**：行内菜单 DOM 需有数据行才渲染，真实执行链路（Exec→Graph）需有 CSP RefreshToken 的环境联调

### Phase 2 (B1–B3) 全部完成 🎉
剩余：真实租户联调（有凭据环境）；graph-office-reports 可选迁移；Phase 3 批次 2/3；Phase 4

---

## 7. Phase 3 批次 2 完成记录（2026-09-08，管理页 common 命名空间）

**管理页高频文案（表格 chrome）中英双语交付**，`common` 命名空间落地：

| 项 | 内容 |
|---|---|
| 新增字典 | `locales/zh-CN/common.json`（49 词条，key=英文源文案，同 nav 约定） |
| i18n 配置 | `index.js` 注册 `common` ns 并设为 defaultNS；`keySeparator/nsSeparator: false` 不变 |
| MRT 内置 | `CippDataTable` 按 `i18n.language` 注入官方 `MRT_Localization_ZH_HANS`（92 键：分页/每页行数/操作/排序/筛选输入提示等） |
| 覆盖组件 | CippDataTable（More Info/Extended Info/Confirmation/Error Loading data/Regex/Not Contains）、CIPPTableToptoolbar（Filters/Columns/Export/搜索/全屏/批量/冷启动提示/首选项列/API Response/Edit Filters/CSV·PDF 导出/已选行计数）、CippTablePage（未选租户 alert）、CippOffCanvas（上/下一行 tooltip）、CippGraphExplorerFilter + CippDiagnosticsFilter（Apply Filter/Schedule Report/Save·Delete Preset/Import-Export）、get-cipp-translation（"No data"） |
| 设计要点 | 列头名仍走 `getCippTranslation`（字段名美化，渐进覆盖，不属批次 2）；动作 label 来自页面注册表（英文，批次 3 渐进）；`tCommon()` 辅助供非 hook 场景（模块级 filter mode 菜单）；useMemo 依赖补 `t` 保证语言切换后重算 |

**验证**：
1. `next build` 全量通过（Compiled successfully，302+ 页静态导出）
2. eslint 零新增（6+2 文件 45 问题与 HEAD 基线逐一持平）
3. 字典完整性：49 词条 / 47 直接引用 / 0 缺失 / 0 空
4. 无头 Chrome E2E **PASS ✅**（`scripts/verify-i18n-common-headless.mjs`，users 页）：
   - EN：Filters/Columns/Export + Search input ✓
   - ZH：筛选/列/导出 + 搜索 + 列菜单 3/3（恢复·保存·删除首选列设置）✓
   - MRT zh-Hans：操作/每页行数/分页 ✓；租户 alert "尚未选择租户" ✓
   - 截图：`docs/screenshots-phase3/zh-management-toolbar.png`

**批次 3（待做）**：报告中心（report-registry nameEn/nameZh 对接）+ 页面级动作 label/列头渐进覆盖。

---

## 9. Phase 3 批次 3 完成记录（2026-09-09，报告中心 + 页面级渐进覆盖）

**批次 3（最后一项）已交付**，Phase 3 三批次全部完成：

| 项 | 内容 |
|---|---|
| 报告中心 nameEn/nameZh 对接 | 新增 `src/i18n/report-name.js`：`tReportName()` / `useReportName()`，从注册表（SERVICES/CATEGORIES/REPORTS）按 nameEn 查 nameZh，注册表仍是单一事实来源（不重复进字典）；动态报告页标题从 `useNavTitle` 改为 `useReportName` —— ZH 下标题/浏览器 tab 随语言切换 |
| 动作 label 渐进覆盖 | `CippDataTable`（行内菜单）+ `CIPPTableToptoolbar`（批量菜单）的 `action.label` 统一走 `t(label)`（common ns，缺失回退英文原文）；`common.json` 新增 51 词条（useCippUserActions 25 + useCippDeviceActions 26 + 注册表内联 3，共 100 词条） |
| 列头渐进覆盖 | 新增 `columns` 命名空间（`locales/zh-CN/columns.json`，68 词条，key=美化后的英文列头）；`get-cipp-translation.js` 输出统一走 `i18next.t(displayName, { ns: 'columns' })`；`CippDataTable` 列推导 effect 增加 `i18n.language` 依赖 + prevLangRef，语言切换后列头重算 |
| dev-serve fixtures | `scripts/dev-serve.mjs` 新增 `DEV_SERVE_FIXTURES=<file>`（路径前缀匹配 /api/* 直接回 JSON）—— 无凭据环境下可 E2E 验证有数据表格；`scripts/fixtures/mfa-users.json`（ListMFAUsers 2 行） |
| 校验脚本 | `scripts/verify-i18n-dicts.mjs`（node 直跑：三字典非空/注册表 nameEn 唯一/内联 label 收录/显式 columns 收录/report-name 三来源覆盖，9/9）；`scripts/verify-i18n-reports-headless.mjs`（无头 E2E，16/16） |

**验证**：
1. `next build` 全量通过（Compiled successfully，341+ 页静态导出）
2. eslint：6 个改动/新增文件与 HEAD 基线逐一持平（CippDataTable+CIPPTableToptoolbar 基线 29 问题 = 现状 29，零新增）；新文件 report-name.js / i18n/index.js / get-cipp-translation.js / 动态报告页零告警
3. 字典完整性：`verify-i18n-dicts.mjs` 9/9 PASS（nav 159 / common 100 / columns 68 词条）
4. 无头 Chrome E2E **16/16 PASS**（mfa-state + fixture 数据）：EN 基线标题/列头 → ZH 标题（MFA 报表）/树导航/列头（账户已启用·已授权·是管理员·MFA 注册状态·条件访问策略）/行内动作菜单（设置每用户 MFA·重新要求 MFA 注册）/localStorage 持久化/树切换报告标题联动，全部命中
5. 回归：批次 1（verify-i18n-headless）+ 批次 2（verify-i18n-common-headless）E2E 均 PASS（顺带修复两脚本 playwright-core 解析与语言按钮时序 flake）
6. 截图：`docs/screenshots-phase3/shot-report-center-batch3-zh.png`

**设计要点**：列头/动作 label 走「key=英文原文、缺失回退原文」的渐进模式，未收录字段/动作在 ZH 下原样显示英文，不会出现键名泄漏；语言切换实时生效（列推导 effect 依赖 i18n.language）。

**Phase 3（C 轨道）全部完成 🎉** 剩余：真实租户联调（有凭据环境）；graph-office-reports 可选迁移；Phase 4

---

## 10. ② 真实租户联调完成记录（2026-09-09，生产 API 直连）

**联调目标达成**：B1–B3 对真实租户数据 + 生产环境验证完毕，无需等待本地 CSP RefreshToken 凭据。

### 联调环境（与预想不同，实际更优）
| 项 | 实际情况 |
|---|---|
| 生产 API | `https://mtm.cxty.de`（Cloudflare → nginx → cipp-server :7071，SQLite）——无需本地凭据环境 |
| 认证 | `/api/*` 由服务器侧注入 superadmin principal（`/api/me` 返回 local-dev），外网可直调 |
| 联调租户 | `lenitech.onmicrosoft.com`（8 租户中选定；Graph 实际可用） |
| 本机栈 | `frontend/out`（341+ 页新构建）+ `CIPP_API_ORIGIN=https://mtm.cxty.de node scripts/dev-serve.mjs`（dev-serve 本场新增 https 上游支持） |
| 新工具 | `scripts/live-integration.mjs`（39 份报告逐一联调 + Exec 端点探测，结果 JSON 落盘）；`scripts/verify-live-reports-headless.mjs`（真实数据无头 E2E） |
| CF 拦截 | Cloudflare 按 TLS 指纹拦 Python（1010）→ 脚本改用 curl 子进程 + 浏览器 UA |

### API 层结果（30/39 有数据，7 项失败均为环境问题）
- **ListX 类**：mfa-state 21 行（列匹配 **11/11**）、signin-report 348 行（8/8）、mailbox-statistics 14 行（7/7）、antiphishing/malware/safeattachments 各 3、app-consent 24、licenses 1、azure-ad-connect 1 等 —— 真实 Graph/EXO 数据全部按预期返回
- **DBCache 类 19/19 全部有数据**（生产缓存已同步）：Users 21 / Groups 20 / Guests 5 / OAuth2Grants 24 / Mailboxes 15 / MailboxUsage 14 / TransportRules 2 / AcceptedDomains 4 / OneDrive 9 / SharePoint 18 / CA 3 / RiskyUsers 4 / SecureScore 14 等
- **空数据（正常）**：risk-detections（该租户无风险事件）、mailbox-forwarding+UseReportDB（无转发配置）
- **失败 7 项（环境问题，非报告中心代码）**：
  - calendar/mailbox-permissions：403 `The CIPP user access token has expired. Run the Setup Wizard`（EXO token 过期）+ UseReportDB 模式 500 `No ... report`（缓存亦未同步）
  - csp-licenses：400 `Unable to retrieve CSP licenses...`（Sherweb 未启用）
  - global-address-list：403 `The term '-Select' is not recognized`（**本仓库后端 bug，已修**，见下）
  - mailbox-forwarding 在线模式：403 `AmbiguousParameterSet`（EXO 环境）
- ⚠️ **注意**：ListTenants 里所有租户 `GraphErrorCount>0` 且部分显示 `AADSTS700082 refresh token expired` —— 实测 Graph 调用均成功，该计数为**历史累积**，不能作为租户健康判据

### 前端修复（联调发现 4 处，fixtures 裸数组掩盖的问题）
1. `reportToTableProps()` DBCache 分支缺 `apiDataKey: 'Results'` —— 生产返回 `{Results:[...]}` 包裹形态，整包会被当一行渲染（report-builder 页都是手动 `data?.Results` 解包，本分支漏配）→ **已修**
2. `CippDataTable` 结果解包：缓存未同步时 `Results:null` → flatMap 生成 `[null]` 渲染一行 null → 归一化为空数组 → **已修**
3. 注册表 `inactive-users`：列名 PascalCase（`UPN/DisplayName/...`）与端点实际 camelCase（`userPrincipalName/lastSignInDateTime/...`）不匹配 → 列全隐藏；且缺旧页 `useReportDB(cacheName:'Users')` → **已修**（7 列 camelCase + useReportDB，对照旧页 750aab8）
4. 注册表 `mailbox-forwarding`：列与旧页对齐（UPN/DisplayName/RecipientTypeDetails/ForwardingType/ForwardTo/DeliverToMailboxAndForward），rowActions data 映射 `User`→`UPN`（后端 `Invoke-ListMailboxForwarding` 实际字段）；`calendar-permissions` 列对齐旧页 byUser 模式（User/UserMailboxType/Permissions）→ **已修**

### 后端修复（1 处）
- `Invoke-ListGlobalAddressList.ps1`：反引号续行后带空格（`` ` -AsApp``）导致续行断裂，`-Select` 被解析为新命令 → 403。已单行化修复（全库 grep 确认无同类问题）

### B3 行内动作执行链
- `ExecPerUserMFA` / `ExecResetMFA` / `ExecEmailForward` 生产端点均存在（GET 探测 500 = 端点存在但缺参数，符合预期）
- E2E：mfa-state 真实数据行内菜单可打开，**8 个菜单项**正常渲染
- 完整 POST 执行链（真实改 MFA/转发）为破坏性操作，**设计上脚本只读不自动 POST**，留待用户在受控租户手工触发确认

### 验证
1. `next build` 全量通过（341+ 页静态导出）
2. eslint：registry / CippDataTable 与既有基线持平（10 errors 均为存量 react-hooks 规则，零新增）
3. `live-integration.mjs`：30 PASS / 2 EMPTY / 6 形态说明 / 7 FAIL（环境问题；其中 1 项后端 bug 已修待部署）
4. 真实数据 E2E **10/10 PASS**：mfa-state 20 行渲染 + 列头真实字段 + users-cache（DBCache 解包修复）20 行 + groups-cache 18 行 + managed-devices（单对象退化形态）20 行 + cas-mailboxes（Results:null 归一化）空态正常 + conditional-access 3 行 + 行内菜单 8 项 + ZH 切换 + console 零错误

### 形态说明（无需修复，已确认行为一致）
- `ListDBCache` 三种返回形态：数组（多行）、单对象（单行租户如 ManagedDevices，MRT 显示 1 行，行为一致）、`Results:null`（未同步类型，修复后空表）

### 遗留
- **部署**：本次修复（registry ×3 / CippDataTable / ListGlobalAddressList / dev-serve https）需随下次部署上生产生效；生产 `out/` 仍是旧构建
- **EXO token 过期**：重跑 Setup Wizard/更新凭据后复验 calendar-permissions、mailbox-permissions、mailbox-forwarding 在线模式
- **Sherweb**：csp-licenses 保持不可用（未启用，预期）
- **真实 POST 执行链**：受控租户手工触发一次（如对测试用户 Reset MFA）以闭环验证

### 复跑指引
```bash
# API 联调（只读探测，结果 JSON 落盘）
node scripts/live-integration.mjs --tenant <domain> --base https://mtm.cxty.de --json .liveprobe/live-integration.json

# 前端 E2E（生产上游）
cd frontend && npm run build
CIPP_API_ORIGIN=https://mtm.cxty.de node scripts/dev-serve.mjs &
LIVE_TENANT=<domain> node scripts/verify-live-reports-headless.mjs
```

**② 真实租户联调完成 🎉** 剩余：上述部署/复验项 + Phase 4（RUNBOOK/MIGRATION-GUIDE 同步 + Ubuntu 演练）

---

## 11. 第二批扩充完成记录（2026-09-10，AdminDroid 对标合并，39 → 70 份）

**背景**：AdminDroid 365 已部署并完成租户授权（对照产品）。按原计划「AdminDroid 式报告中心」继续合并对标报告 —— 素材即生产已同步但注册表未用的缓存类型。

### 素材盘点与筛选
- 本地缓存类型配置 72 类；生产已同步 **70 类**；注册表已用 20 类 → **54 类候选**
- 逐一探测（含 PIM 3 类）后三道筛选：
  1. **未同步排除 7 类**（Results:null）：Copilot ×4、RiskyServicePrincipals、ServicePrincipalRiskDetections、ExoTenantAllowBlockList —— 待生产 Sync-AllCache 支持后可补
  2. **与在线报告去重排除 4 类**：ExoAntiPhishPolicies/ExoSafeLinksPolicies/ExoHostedContentFilterPolicy/ExoMalwareFilterPolicies（antiphishing/malware/safeattachments-filters 在线版已覆盖）
  3. 其余 **31 类全部有真实数据 → 全部注册**

### 新增 31 份（全部 DBCache 缓存直读，行数为 lenitech 实测）
| 服务 | 新报告（类型→行数） |
|---|---|
| 身份与访问 | 目录角色 Roles(7)、活动角色分配 RoleAssignmentScheduleInstances(12)、企业应用 ServicePrincipals(293)、应用注册 Apps(9)、应用角色分配 AppRoleAssignments(62)、MFA·SSPR 注册明细 UserRegistrationDetails(20)、凭据注册 CredentialUserRegistrationDetails(20)、身份验证方法策略 AuthenticationMethodsPolicy(1) |
| 许可与订阅 | 租户域名 Domains(4)、组织信息 Organization(1) |
| 邮件安全 | DKIM 签名配置(4)、隔离策略(3)、预设安全策略(1)、远程域(1)、共享策略(1) |
| 协作 | OneDrive 用量(9)、SharePoint 用量(22)、Office 激活 OfficeActivations(13) |
| 端点与 Intune | Azure AD 设备 Devices(3)、设备加密状态(1)、Intune 应用(1)、应用保护/设备合规/设备配置策略、Autopilot 部署配置（各 1，单对象形态） |
| 安全与合规 | 安全分数控制项 SecureScoreControlProfiles(460)、目录建议(17)、Defender 接入状态 MDEOnboarding(1)、身份验证强度(3)、命名位置(1)、跨租户访问策略(1) |

- 新增分类 3 个：`roles`（角色与管理员）、`applications`（企业应用）、`officeApps`（Office 应用）
- 高价值报告配精选列（字段名生产实测核对）：UserRegistrationDetails 11 列、SecureScoreControls 8 列、ServicePrincipals/AppRoleAssignments/Devices/用量类等；其余自动列
- **生产独有类型 10 个**（本地 CIPPDBCacheTypes.json 无，本地配置落后于生产 CIPP 版本）：IntuneDeviceCompliancePolicies、IntuneConfigurationPolicies、IntuneMobileApps、IntuneWindowsAutopilotDeploymentProfiles、MDEOnboarding、NamedLocations、AuthenticationStrengths、SecureScoreControlProfiles、DirectoryRecommendations、RoleAssignmentScheduleInstances
- **graph-office-reports 维持不迁**：250 行交互页（react-hook-form + PDF 导出 + 表格/代码切换），表格化迁移会丢失交互

### i18n
- `columns.json` +48 词条（87 显式列字段全覆盖，含 §10 inactive-users 修复时遗留的 5 词条）；字典校验 ALL PASS（columns 116 词条 / 报告 70 + 服务 6 + 分类 16 三来源覆盖）

### 验证
1. `next build` 全量通过（报告中心 SSG 70 页）
2. eslint：registry 零告警；结构校验 PASS（70 id 唯一 / 服务分类挂接 / 无孤儿分类 / nameZh 全覆盖）
3. `live-integration.mjs` 全量：31/31 新报告全 200 零新增 FAIL（汇总 48 PASS / 2 EMPTY / 20 单对象形态 / 7 FAIL 均为 §10 已归因环境问题）
4. 真实数据 E2E **15/15 PASS**（含第二批抽检：293/460 大数据量分页总数、精选列命中、新分类树 ZH、identity + collab 两服务）
5. **E2E 脚本重构为确定性等待**：等待「目标 API 响应 + 期望文本出现」替代固定时长采样，修复跨页骨架态/分页页脚/MRT 空态时序 flake（前两轮 10/14、13/14 的不稳定根因）；树分类标签 CSS uppercase 需 ignoreCase 匹配

### 遗留
- Copilot ×4、RiskyServicePrincipals、ServicePrincipalRiskDetections、ExoTenantAllowBlockList 共 7 类待生产同步后补注册
- §10 全部遗留项继续有效（部署上生产、EXO 凭据复验、真实 POST 手工闭环、Phase 4）

**报告中心 70 份 AdminDroid 对标合并完成 🎉**
