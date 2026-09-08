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
