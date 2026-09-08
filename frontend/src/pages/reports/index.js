import { useEffect } from 'react'
import { useRouter } from 'next/router'
import { Layout as DashboardLayout } from '../../layouts/index.js'

/**
 * 报告中心落地页 — 重定向到第一份报告（身份与访问 → MFA 报表）。
 */
const ReportCenterLanding = () => {
  const router = useRouter()
  useEffect(() => {
    router.replace('/reports/identity/mfa-state')
  }, [router])
  return null
}

ReportCenterLanding.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default ReportCenterLanding
