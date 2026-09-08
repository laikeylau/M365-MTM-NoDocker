import { useMemo, useState } from 'react'
import { useRouter } from 'next/router'
import { useTranslation } from 'react-i18next'
import {
  Box,
  Collapse,
  InputAdornment,
  List,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  TextField,
  Typography,
} from '@mui/material'
import {
  ExpandLess,
  ExpandMore,
  Search as SearchIcon,
  AssessmentOutlined,
} from '@mui/icons-material'
import { getReportTree } from '../../data/report-registry'

/**
 * 报告中心树导航（B2）
 * 左侧三级树：服务 → 分类 → 报告。标签按当前语言切换 nameZh/nameEn。
 * 当前报告高亮，路由 /reports/[service]/[reportId]。
 */
export const CippReportTreeNav = ({ currentService, currentReportId }) => {
  const router = useRouter()
  const { i18n } = useTranslation()
  const isZh = i18n.language?.toLowerCase().startsWith('zh')
  const tree = useMemo(() => getReportTree(), [])
  const [expanded, setExpanded] = useState(() => new Set(currentService ? [currentService] : []))
  const [search, setSearch] = useState('')

  const pickLabel = (item) => (isZh ? item.nameZh : item.nameEn)

  const toggle = (serviceId) =>
    setExpanded((prev) => {
      const next = new Set(prev)
      if (next.has(serviceId)) next.delete(serviceId)
      else next.add(serviceId)
      return next
    })

  const filteredTree = useMemo(() => {
    const query = search.trim().toLowerCase()
    if (!query) return tree
    return tree
      .map((service) => ({
        ...service,
        groups: service.groups
          .map((group) => ({
            ...group,
            reports: group.reports.filter(
              (report) =>
                report.nameEn.toLowerCase().includes(query) ||
                report.nameZh.toLowerCase().includes(query)
            ),
          }))
          .filter((group) => group.reports.length > 0),
      }))
      .filter((service) => service.groups.length > 0)
  }, [tree, search])

  return (
    <Box
      sx={{
        width: 300,
        flexShrink: 0,
        borderRight: (theme) => `1px solid ${theme.palette.divider}`,
        overflowY: 'auto',
        height: '100%',
      }}
    >
      <Box sx={{ p: 1.5, position: 'sticky', top: 0, bgcolor: 'background.paper', zIndex: 1 }}>
        <TextField
          fullWidth
          size="small"
          placeholder={isZh ? '搜索报告…' : 'Search reports…'}
          value={search}
          onChange={(event) => setSearch(event.target.value)}
          InputProps={{
            startAdornment: (
              <InputAdornment position="start">
                <SearchIcon fontSize="small" />
              </InputAdornment>
            ),
          }}
        />
      </Box>
      <List dense disablePadding sx={{ pb: 4 }}>
        {filteredTree.map((service) => {
          const isOpen = expanded.has(service.id) || search.trim().length > 0
          const serviceReportCount = service.groups.reduce(
            (count, group) => count + group.reports.length,
            0
          )
          return (
            <Box key={service.id}>
              <ListItemButton onClick={() => toggle(service.id)} sx={{ py: 1 }}>
                <ListItemIcon sx={{ minWidth: 36 }}>
                  <AssessmentOutlined fontSize="small" />
                </ListItemIcon>
                <ListItemText
                  primary={pickLabel(service)}
                  primaryTypographyProps={{ fontWeight: 600, variant: 'body2' }}
                  secondary={`${serviceReportCount}`}
                  secondaryTypographyProps={{ variant: 'caption' }}
                />
                {isOpen ? <ExpandLess fontSize="small" /> : <ExpandMore fontSize="small" />}
              </ListItemButton>
              <Collapse in={isOpen} timeout="auto" unmountOnExit>
                {service.groups.map((group) => (
                  <Box key={group.id}>
                    <Typography
                      variant="caption"
                      color="text.secondary"
                      sx={{ pl: 5, pt: 1, display: 'block', textTransform: 'uppercase' }}
                    >
                      {pickLabel(group)}
                    </Typography>
                    {group.reports.map((report) => {
                      const selected =
                        report.service === currentService && report.id === currentReportId
                      return (
                        <ListItemButton
                          key={report.id}
                          selected={selected}
                          sx={{ pl: 6, py: 0.5 }}
                          onClick={() => router.push(`/reports/${service.id}/${report.id}`)}
                        >
                          <ListItemText
                            primary={pickLabel(report)}
                            primaryTypographyProps={{ variant: 'body2' }}
                          />
                        </ListItemButton>
                      )
                    })}
                  </Box>
                ))}
              </Collapse>
            </Box>
          )
        })}
      </List>
    </Box>
  )
}

export default CippReportTreeNav
