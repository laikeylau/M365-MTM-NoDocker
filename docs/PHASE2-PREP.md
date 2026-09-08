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
