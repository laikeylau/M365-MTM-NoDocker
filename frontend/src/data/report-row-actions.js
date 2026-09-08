import { useCippUserActions } from '../components/CippComponents/CippUserActions.jsx'
import useCippDeviceActions from '../components/CippComponents/CippDeviceActions.jsx'

/**
 * B3 行内操作解析 — 注册表 rowActions → CippDataTable actions。
 *
 * 注册表三种写法：
 *   rowActions: { preset: 'user' }                  — 复用 useCippUserActions 全集
 *   rowActions: { preset: 'device' }                — 复用 useCippDeviceActions 全集
 *   rowActions: [{ label, url, data, ... }]         — 内联自定义（零新后端，引用现有 Exec 端点）
 *
 * Hooks 在页面组件层无条件调用（勿在条件分支中调用本 hook 的调用方）。
 */
export const useReportRowActions = (report) => {
  const userActions = useCippUserActions()
  const deviceActions = useCippDeviceActions()

  if (!report?.rowActions) return undefined

  if (Array.isArray(report.rowActions)) return report.rowActions

  switch (report.rowActions.preset) {
    case 'user':
      return userActions
    case 'device':
      return deviceActions
    default:
      return undefined
  }
}

export default useReportRowActions