import { useMemo } from 'react'
import { useRouter } from 'next/router'
import { useTranslation } from 'react-i18next'
import { Box, Stack } from '@mui/material'
import { Layout as DashboardLayout } from '../../../../layouts/index.js'
import { CippTablePage } from '../../../../components/CippComponents/CippTablePage.jsx'
import { CippReportTreeNav } from '../../../../components/CippComponents/CippReportTreeNav.jsx'
import { useCippReportDB } from '../../../../components/CippComponents/CippReportDBControls'
import {
  REPORTS,
  getReportById,
  reportToTableProps,
} from '../../../../data/report-registry'
import { useReportRowActions } from '../../../../data/report-row-actions'
import { useNavTitle } from '../../../../i18n/nav'

/**
 * B2 统一报告中心 — 动态报告页
 * 路由 /reports/[service]/[reportId]，左侧树导航 + 右侧 CippTablePage。
 * 渲染配置全部来自 B1 注册表（reportToTableProps）。
 */

const ReportContent = ({ report, tableProps, rowActions, translateTitle }) => {
  const useReportDB = tableProps.reportDBConfig
  if (useReportDB) {
    return (
      <ReportWithCacheMode
        report={report}
        tableProps={tableProps}
        rowActions={rowActions}
        translateTitle={translateTitle}
      />
    )
  }
  return <ReportPlain tableProps={tableProps} rowActions={rowActions} translateTitle={translateTitle} />
}

const ReportPlain = ({ tableProps, rowActions, translateTitle }) => (
  <CippTablePage
    title={translateTitle(tableProps.title)}
    apiUrl={tableProps.apiUrl}
    apiData={tableProps.apiData}
    apiDataKey={tableProps.apiDataKey}
    queryKey={tableProps.queryKey}
    simpleColumns={tableProps.simpleColumns}
    actions={rowActions}
  />
)

const ReportWithCacheMode = ({ tableProps, rowActions, translateTitle }) => {
  const reportDB = useCippReportDB({
    apiUrl: tableProps.apiUrl,
    queryKey: tableProps.queryKey,
    cacheName: tableProps.reportDBConfig.cacheName,
    allowToggle: tableProps.reportDBConfig.allowToggle ?? true,
    defaultCached: tableProps.reportDBConfig.defaultCached ?? true,
  })
  return (
    <>
      <CippTablePage
        title={translateTitle(tableProps.title)}
        apiUrl={reportDB.resolvedApiUrl}
        apiData={reportDB.resolvedApiData}
        queryKey={reportDB.resolvedQueryKey}
        simpleColumns={tableProps.simpleColumns}
        actions={rowActions}
        cardButton={reportDB.controls}
      />
      {reportDB.syncDialog}
    </>
  )
}

const DynamicReportPage = () => {
  const router = useRouter()
  const { i18n } = useTranslation()
  const translateTitle = useNavTitle()
  const { service, reportId } = router.query

  const report = useMemo(
    () => (service && reportId ? getReportById(reportId) : null),
    [service, reportId]
  )
  const tableProps = useMemo(
    () => (report ? reportToTableProps(report) : null),
    [report]
  )
  const rowActions = useReportRowActions(report)

  if (!router.isReady || !report || report.service !== service) {
    return (
      <Box sx={{ p: 4 }}>
        <CippReportTreeNav currentService={service} currentReportId={reportId} />
      </Box>
    )
  }

  return (
    <Stack direction="row" sx={{ height: 'calc(100vh - 64px)', overflow: 'hidden' }}>
      <CippReportTreeNav currentService={service} currentReportId={reportId} />
      <Box sx={{ flexGrow: 1, overflowY: 'auto', p: 2, pt: 3 }}>
        <ReportContent
          report={report}
          tableProps={tableProps}
          rowActions={rowActions}
          translateTitle={translateTitle}
        />
      </Box>
    </Stack>
  )
}

export async function getStaticPaths() {
  return {
    paths: REPORTS.map((report) => ({
      params: { service: report.service, reportId: report.id },
    })),
    fallback: false,
  }
}

export async function getStaticProps() {
  return { props: {} }
}

DynamicReportPage.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default DynamicReportPage
