import { useEffect } from 'react'
import { useRouter } from 'next/router'
import { Layout as DashboardLayout } from '../../../../layouts/index.js'

/**
 * B2 旧路由重定向 — 本页已迁移至统一报告中心 (identity/mfa-state)。
 */
const Page = () => {
  const router = useRouter()
  useEffect(() => {
    router.replace('/reports/identity/mfa-state')
  }, [router])
  return null
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page
