/**
 * B1 报告注册表 — 报告中心的单一事实来源
 *
 * 三种数据源形态：
 *  1. ListX            — 普通在线端点 (url 必填, apiData 可选)
 *  2. ListX + ReportDB — 走 useCippReportDB 的缓存/在线切换页 (useReportDB 配置)
 *  3. DBCache          — 通用缓存直读 /api/ListDBCache?tenantFilter=<tenant>&type=<cache>
 *                        (tenantFilter 由 CippTablePage 自动注入当前租户)
 *
 * 消费方 (B2 动态路由 /reports/[service]/[reportId]) 将 entry 映射为 CippTablePage props。
 * columns 为空数组 → CippDataTable 自动从数据生成列；跨租户模式自动附加 Tenant 列。
 */

export const SERVICES = [
  {
    id: 'identity',
    nameEn: 'Identity & Access',
    nameZh: '身份与访问',
    categories: ['usersGroups', 'authSecurity'],
  },
  {
    id: 'licenses',
    nameEn: 'Licences & Subscriptions',
    nameZh: '许可与订阅',
    categories: ['subscriptions'],
  },
  {
    id: 'email',
    nameEn: 'Email & Exchange',
    nameZh: '邮件与 Exchange',
    categories: ['mailboxes', 'mailSecurity', 'mailReports'],
  },
  {
    id: 'collab',
    nameEn: 'Collaboration',
    nameZh: '协作（Teams · SP · OneDrive）',
    categories: ['onedrive', 'sharepoint'],
  },
  {
    id: 'endpoint',
    nameEn: 'Endpoints & Intune',
    nameZh: '端点与 Intune',
    categories: ['devices', 'policies'],
  },
  {
    id: 'security',
    nameEn: 'Security & Compliance',
    nameZh: '安全与合规',
    categories: ['access', 'risk', 'posture'],
  },
]

export const CATEGORIES = {
  usersGroups: { nameEn: 'Users & Groups', nameZh: '用户与组' },
  authSecurity: { nameEn: 'Authentication & Security', nameZh: '身份验证与安全' },
  subscriptions: { nameEn: 'Subscriptions', nameZh: '订阅' },
  mailboxes: { nameEn: 'Mailboxes', nameZh: '邮箱' },
  mailSecurity: { nameEn: 'Mail Security', nameZh: '邮件安全' },
  mailReports: { nameEn: 'Mail Reports', nameZh: '邮件报表' },
  onedrive: { nameEn: 'OneDrive', nameZh: 'OneDrive' },
  sharepoint: { nameEn: 'SharePoint', nameZh: 'SharePoint' },
  devices: { nameEn: 'Devices', nameZh: '设备' },
  policies: { nameEn: 'Policies', nameZh: '策略' },
  access: { nameEn: 'Access Policies', nameZh: '访问策略' },
  risk: { nameEn: 'Risk & Detections', nameZh: '风险与检测' },
  posture: { nameEn: 'Security Posture', nameZh: '安全态势' },
}

const ListX = (url, extra = {}) => ({ type: 'ListX', url, ...extra })
const DBCache = (cache) => ({ type: 'DBCache', cache })

export const REPORTS = [
  // ───────────────────────── 身份与访问 ─────────────────────────
  {
    id: 'mfa-state',
    service: 'identity',
    category: 'authSecurity',
    nameEn: 'MFA Report',
    nameZh: 'MFA 报表',
    source: ListX('/api/ListMFAUsers', {
      useReportDB: { cacheName: 'MFAState', allowToggle: false },
    }),
    columns: [
      'UPN',
      'AccountEnabled',
      'isLicensed',
      'MFARegistration',
      'PerUser',
      'CoveredBySD',
      'CoveredByCA',
      'MFAMethods',
      'CAPolicies',
      'IsAdmin',
      'UserType',
    ],
    syncCache: 'MFAState',
    rowActions: [
      {
        label: 'Set Per-User MFA',
        type: 'POST',
        url: '/api/ExecPerUserMFA',
        data: { userId: 'ID', userPrincipalName: 'UPN' },
        fields: [
          {
            type: 'autoComplete',
            name: 'State',
            label: 'State',
            options: [
              { label: 'Enforced', value: 'Enforced' },
              { label: 'Enabled', value: 'Enabled' },
              { label: 'Disabled', value: 'Disabled' },
            ],
            multiple: false,
            creatable: false,
          },
        ],
        confirmText: 'Are you sure you want to set per-user MFA for these users?',
        multiPost: false,
      },
      {
        label: 'Re-require MFA registration',
        type: 'POST',
        url: '/api/ExecResetMFA',
        data: { ID: 'ID' },
        confirmText: "Are you sure you want to re-require MFA registration for [UPN]?",
        multiPost: false,
      },
    ],
  },
  {
    id: 'inactive-users',
    service: 'identity',
    category: 'usersGroups',
    nameEn: 'Inactive Users Report',
    nameZh: '非活跃用户报表',
    source: ListX('/api/ListInactiveAccounts'),
    columns: ['UPN', 'DisplayName', 'CreatedDateTime', 'SignInActivity'],
    rowActions: { preset: 'user' },
  },
  {
    id: 'signin-report',
    service: 'identity',
    category: 'authSecurity',
    nameEn: 'Sign-in Report',
    nameZh: '登录报表',
    source: ListX('/api/ListGraphRequest', {
      apiData: { Endpoint: 'auditLogs/signIns', '$top': 200 },
    }),
    columns: [
      'createdDateTime',
      'userPrincipalName',
      'appDisplayName',
      'status.errorCode',
      'ipAddress',
      'clientAppUsed',
      'location.city',
      'location.countryOrRegion',
    ],
  },
  {
    id: 'azure-ad-connect',
    service: 'identity',
    category: 'usersGroups',
    nameEn: 'Azure AD Connect Report',
    nameZh: 'Azure AD Connect 报表',
    source: ListX('/api/ListAzureADConnectStatus'),
    columns: [],
  },
  {
    id: 'risk-detections',
    service: 'identity',
    category: 'risk',
    nameEn: 'Risk Detections',
    nameZh: '风险检测',
    source: ListX('/api/ListGraphRequest', {
      apiData: { Endpoint: 'identityProtection/riskDetections' },
    }),
    columns: [
      'riskDetectionDateTime',
      'userPrincipalName',
      'riskState',
      'riskLevel',
      'riskEventType',
      'ipAddress',
      'detectedBy',
    ],
  },
  {
    id: 'users-cache',
    service: 'identity',
    category: 'usersGroups',
    nameEn: 'Users (Cache)',
    nameZh: '用户（缓存）',
    source: DBCache('Users'),
    columns: [],
    syncCache: 'Users',
    rowActions: { preset: 'user' },
  },
  {
    id: 'groups-cache',
    service: 'identity',
    category: 'usersGroups',
    nameEn: 'Groups (Cache)',
    nameZh: '组（缓存）',
    source: DBCache('Groups'),
    columns: [],
    syncCache: 'Groups',
  },
  {
    id: 'guests-cache',
    service: 'identity',
    category: 'usersGroups',
    nameEn: 'Guests (Cache)',
    nameZh: '来宾（缓存）',
    source: DBCache('Guests'),
    columns: [],
    syncCache: 'Guests',
  },
  {
    id: 'oauth2-permission-grants-cache',
    service: 'identity',
    category: 'authSecurity',
    nameEn: 'OAuth2 Permission Grants (Cache)',
    nameZh: 'OAuth2 授权记录（缓存）',
    source: DBCache('OAuth2PermissionGrants'),
    columns: [],
    syncCache: 'OAuth2PermissionGrants',
  },

  // ───────────────────────── 许可与订阅 ─────────────────────────
  {
    id: 'licenses',
    service: 'licenses',
    category: 'subscriptions',
    nameEn: 'Licence Report',
    nameZh: '许可报表',
    source: ListX('/api/ListLicenses'),
    columns: [],
  },
  {
    id: 'csp-licenses',
    service: 'licenses',
    category: 'subscriptions',
    nameEn: 'Sherweb Licence Report',
    nameZh: 'Sherweb 许可报表',
    source: ListX('/api/listCSPLicenses'),
    columns: [],
  },
  {
    id: 'license-overview-cache',
    service: 'licenses',
    category: 'subscriptions',
    nameEn: 'Licence Overview (Cache)',
    nameZh: '许可总览（缓存）',
    source: DBCache('LicenseOverview'),
    columns: [],
    syncCache: 'LicenseOverview',
  },

  // ───────────────────────── 邮件与 Exchange ─────────────────────────
  {
    id: 'shared-mailbox-enabled-account',
    service: 'email',
    category: 'mailboxes',
    nameEn: 'Shared Mailbox with Enabled Account',
    nameZh: '已启用账户的共享邮箱',
    source: ListX('/api/ListSharedMailboxAccountEnabled'),
    columns: [],
  },
  {
    id: 'activesync-devices',
    service: 'email',
    category: 'mailboxes',
    nameEn: 'ActiveSync Devices',
    nameZh: 'ActiveSync 设备',
    source: ListX('/api/ListActiveSyncDevices'),
    columns: [],
  },
  {
    id: 'calendar-permissions',
    service: 'email',
    category: 'mailboxes',
    nameEn: 'Calendar Permissions',
    nameZh: '日历权限',
    source: ListX('/api/ListCalendarPermissions', {
      useReportDB: { cacheName: 'Mailboxes' },
    }),
    columns: ['User', 'FolderName', 'Userwithaccess', 'AccessLevel', 'AccessType'],
    syncCache: 'Mailboxes',
  },
  {
    id: 'global-address-list',
    service: 'email',
    category: 'mailboxes',
    nameEn: 'Global Address List',
    nameZh: '全局地址列表',
    source: ListX('/api/ListGlobalAddressList'),
    columns: [],
  },
  {
    id: 'mailbox-cas-settings',
    service: 'email',
    category: 'mailboxes',
    nameEn: 'Mailbox Client Access Settings',
    nameZh: '邮箱客户端访问设置',
    source: ListX('/api/ListMailboxCAS'),
    columns: [],
  },
  {
    id: 'mailbox-forwarding',
    service: 'email',
    category: 'mailboxes',
    nameEn: 'Mailbox Forwarding',
    nameZh: '邮箱转发',
    source: ListX('/api/ListMailboxForwarding', {
      useReportDB: { cacheName: 'Mailboxes' },
    }),
    columns: ['User', 'ForwardTo', 'ForwardingSmtpAddress', 'DeliverToMailboxAndForward'],
    syncCache: 'Mailboxes',
    rowActions: [
      {
        label: 'Disable Email Forwarding',
        type: 'POST',
        url: '/api/ExecEmailForward',
        data: {
          username: 'User',
          userid: 'User',
          ForwardOption: '!disabled',
        },
        confirmText: "Are you sure you want to disable forwarding of [User]'s emails?",
        multiPost: false,
      },
    ],
  },
  {
    id: 'mailbox-permissions',
    service: 'email',
    category: 'mailboxes',
    nameEn: 'Mailbox Permissions',
    nameZh: '邮箱权限',
    source: ListX('/api/ListMailboxPermissions', {
      useReportDB: { cacheName: 'Mailboxes' },
    }),
    columns: ['User', 'UserWithPermission', 'Permissions'],
    syncCache: 'Mailboxes',
  },
  {
    id: 'mailbox-statistics',
    service: 'email',
    category: 'mailReports',
    nameEn: 'Mailbox Statistics',
    nameZh: '邮箱统计',
    source: ListX('/api/ListGraphRequest', {
      apiData: { Endpoint: "reports/getMailboxUsageDetail(period='D7')", '$format': 'application/json' },
      apiDataKey: 'Results',
    }),
    columns: [
      'userPrincipalName',
      'displayName',
      'recipientType',
      'lastActivityDate',
      'storageUsedInBytes',
      'itemCount',
      'hasArchive',
    ],
  },
  {
    id: 'mailbox-activity',
    service: 'email',
    category: 'mailReports',
    nameEn: 'Mailbox Activity',
    nameZh: '邮箱活动',
    source: ListX('/api/ListGraphRequest', {
      apiData: { Endpoint: "reports/getEmailActivityUserDetail(period='D7')" },
    }),
    columns: [],
  },
  {
    id: 'antiphishing-filters',
    service: 'email',
    category: 'mailSecurity',
    nameEn: 'Anti-Phishing Filters',
    nameZh: '反钓鱼筛选器',
    source: ListX('/api/ListAntiPhishingFilters'),
    columns: [],
  },
  {
    id: 'malware-filters',
    service: 'email',
    category: 'mailSecurity',
    nameEn: 'Malware Filters',
    nameZh: '反恶意软件筛选器',
    source: ListX('/api/ListMalwareFilters'),
    columns: [],
  },
  {
    id: 'safeattachments-filters',
    service: 'email',
    category: 'mailSecurity',
    nameEn: 'Safe Attachments Filters',
    nameZh: '安全附件筛选器',
    source: ListX('/api/ListSafeAttachmentsFilters'),
    columns: [],
  },
  {
    id: 'mailboxes-cache',
    service: 'email',
    category: 'mailboxes',
    nameEn: 'Mailboxes (Cache)',
    nameZh: '邮箱（缓存）',
    source: DBCache('Mailboxes'),
    columns: [],
    syncCache: 'Mailboxes',
  },
  {
    id: 'cas-mailboxes-cache',
    service: 'email',
    category: 'mailboxes',
    nameEn: 'Client Access Settings (Cache)',
    nameZh: '客户端访问设置（缓存）',
    source: DBCache('CASMailboxes'),
    columns: [],
    syncCache: 'CASMailboxes',
  },
  {
    id: 'mailbox-usage-cache',
    service: 'email',
    category: 'mailReports',
    nameEn: 'Mailbox Usage (Cache)',
    nameZh: '邮箱使用量（缓存）',
    source: DBCache('MailboxUsage'),
    columns: [],
    syncCache: 'MailboxUsage',
  },
  {
    id: 'transport-rules-cache',
    service: 'email',
    category: 'mailSecurity',
    nameEn: 'Transport Rules (Cache)',
    nameZh: '传输规则（缓存）',
    source: DBCache('ExoTransportRules'),
    columns: [],
    syncCache: 'ExoTransportRules',
  },
  {
    id: 'accepted-domains-cache',
    service: 'email',
    category: 'mailSecurity',
    nameEn: 'Accepted Domains (Cache)',
    nameZh: '接受的域（缓存）',
    source: DBCache('ExoAcceptedDomains'),
    columns: [],
    syncCache: 'ExoAcceptedDomains',
  },

  // ───────────────────────── 协作 ─────────────────────────
  {
    id: 'onedrive-sites-cache',
    service: 'collab',
    category: 'onedrive',
    nameEn: 'OneDrive Sites (Cache)',
    nameZh: 'OneDrive 站点（缓存）',
    source: DBCache('OneDriveSiteListing'),
    columns: [],
    syncCache: 'OneDriveSiteListing',
  },
  {
    id: 'sharepoint-sites-cache',
    service: 'collab',
    category: 'sharepoint',
    nameEn: 'SharePoint Sites (Cache)',
    nameZh: 'SharePoint 站点（缓存）',
    source: DBCache('SharePointSiteListing'),
    columns: [],
    syncCache: 'SharePointSiteListing',
  },

  // ───────────────────────── 端点与 Intune ─────────────────────────
  {
    id: 'managed-devices-cache',
    service: 'endpoint',
    category: 'devices',
    nameEn: 'Managed Devices (Cache)',
    nameZh: '受管设备（缓存）',
    source: DBCache('ManagedDevices'),
    columns: [],
    syncCache: 'ManagedDevices',
    rowActions: { preset: 'device' },
  },
  {
    id: 'detected-apps-cache',
    service: 'endpoint',
    category: 'devices',
    nameEn: 'Detected Apps (Cache)',
    nameZh: '检测到的应用（缓存）',
    source: DBCache('DetectedApps'),
    columns: [],
    syncCache: 'DetectedApps',
  },
  {
    id: 'intune-policies-cache',
    service: 'endpoint',
    category: 'policies',
    nameEn: 'Intune Policies (Cache)',
    nameZh: 'Intune 策略（缓存）',
    source: DBCache('IntunePolicies'),
    columns: [],
    syncCache: 'IntunePolicies',
  },

  // ───────────────────────── 安全与合规 ─────────────────────────
  {
    id: 'app-consent',
    service: 'security',
    category: 'access',
    nameEn: 'Consented Applications',
    nameZh: '已授权应用',
    source: ListX('/api/ListOAuthApps'),
    columns: [],
  },
  {
    id: 'conditional-access-cache',
    service: 'security',
    category: 'access',
    nameEn: 'Conditional Access Policies (Cache)',
    nameZh: '条件访问策略（缓存）',
    source: DBCache('ConditionalAccessPolicies'),
    columns: [],
    syncCache: 'ConditionalAccessPolicies',
  },
  {
    id: 'risky-users-cache',
    service: 'security',
    category: 'risk',
    nameEn: 'Risky Users (Cache)',
    nameZh: '有风险用户（缓存）',
    source: DBCache('RiskyUsers'),
    columns: [],
    syncCache: 'RiskyUsers',
  },
  {
    id: 'risk-detections-cache',
    service: 'security',
    category: 'risk',
    nameEn: 'Risk Detections (Cache)',
    nameZh: '风险检测（缓存）',
    source: DBCache('RiskDetections'),
    columns: [],
    syncCache: 'RiskDetections',
  },
  {
    id: 'secure-score-cache',
    service: 'security',
    category: 'posture',
    nameEn: 'Secure Score (Cache)',
    nameZh: '安全功能分数（缓存）',
    source: DBCache('SecureScore'),
    columns: [],
    syncCache: 'SecureScore',
  },
]

// ── 查询辅助 ──────────────────────────────────────────────────────────

export const getReportById = (reportId) => REPORTS.find((report) => report.id === reportId)

export const getReportsByService = (serviceId) =>
  REPORTS.filter((report) => report.service === serviceId)

/**
 * 报告中心树数据：SERVICES × CATEGORIES × 报告
 * 返回 [{ ...service, groups: [{ ...category, reports: [...] }] }]
 */
export const getReportTree = () =>
  SERVICES.map((service) => ({
    ...service,
    groups: service.categories
      .map((categoryId) => ({
        id: categoryId,
        ...CATEGORIES[categoryId],
        reports: getReportsByService(service.id).filter((report) => report.category === categoryId),
      }))
      .filter((group) => group.reports.length > 0),
  }))

/**
 * 注册表条目 → CippTablePage props 映射。
 * DBCache 条目走 /api/ListDBCache，tenantFilter 由 CippTablePage 自动注入。
 * ListX+ReportDB 条目由 B2 页面交给 useCippReportDB 处理缓存/在线切换。
 */
export const reportToTableProps = (report) => {
  const { source } = report
  if (source.type === 'DBCache') {
    return {
      title: report.nameEn,
      apiUrl: '/api/ListDBCache',
      apiData: { type: source.cache },
      simpleColumns: report.columns ?? [],
      queryKey: `ListDBCache-${source.cache}`,
    }
  }
  return {
    title: report.nameEn,
    apiUrl: source.url,
    apiData: source.apiData,
    apiDataKey: source.apiDataKey,
    simpleColumns: report.columns ?? [],
    queryKey: report.id,
    ...(source.useReportDB ? { reportDBConfig: source.useReportDB } : {}),
  }
}

export default REPORTS
