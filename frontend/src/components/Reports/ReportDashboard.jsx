import { useState, useEffect, useMemo } from 'react'
import {
  Card,
  CardContent,
  CardHeader,
  Grid,
  Typography,
  Box,
  Chip,
  IconButton,
  Tooltip,
  Skeleton,
  Alert,
} from '@mui/material'
import {
  TrendingUp,
  TrendingDown,
  People,
  Email,
  Cloud,
  Security,
  Assessment,
  Refresh,
  FileDownload,
} from '@mui/icons-material'
import { useSettings } from '../../hooks/use-settings'
import { ApiGetCall } from '../../api/ApiCall'

// Simple bar chart component (no external chart library)
const SimpleBarChart = ({ data, height = 200, color = '#3B82F6' }) => {
  if (!data || data.length === 0) return null

  const maxValue = Math.max(...data.map((d) => d.value))

  return (
    <Box sx={{ height, display: 'flex', alignItems: 'flex-end', gap: 1, px: 1 }}>
      {data.map((item, index) => (
        <Tooltip key={index} title={`${item.label}: ${item.value}`}>
          <Box
            sx={{
              flex: 1,
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 0.5,
            }}
          >
            <Typography variant="caption" sx={{ fontSize: '0.7rem' }}>
              {item.value}
            </Typography>
            <Box
              sx={{
                width: '100%',
                height: `${(item.value / maxValue) * (height - 40)}px`,
                backgroundColor: color,
                borderRadius: '4px 4px 0 0',
                minHeight: '4px',
                transition: 'height 0.3s ease',
              }}
            />
            <Typography
              variant="caption"
              sx={{
                fontSize: '0.6rem',
                textAlign: 'center',
                overflow: 'hidden',
                textOverflow: 'ellipsis',
                whiteSpace: 'nowrap',
                maxWidth: '100%',
              }}
            >
              {item.label}
            </Typography>
          </Box>
        </Tooltip>
      ))}
    </Box>
  )
}

// Simple pie chart component
const SimplePieChart = ({ data, size = 150 }) => {
  if (!data || data.length === 0) return null

  const total = data.reduce((sum, d) => sum + d.value, 0)
  let currentAngle = 0

  const slices = data.map((item) => {
    const percentage = (item.value / total) * 100
    const angle = (item.value / total) * 360
    const startAngle = currentAngle
    currentAngle += angle
    return { ...item, percentage, startAngle, angle }
  })

  return (
    <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
      <svg width={size} height={size} viewBox="0 0 100 100">
        {slices.map((slice, index) => {
          const startRad = (slice.startAngle * Math.PI) / 180
          const endRad = ((slice.startAngle + slice.angle) * Math.PI) / 180
          const x1 = 50 + 40 * Math.cos(startRad)
          const y1 = 50 + 40 * Math.sin(startRad)
          const x2 = 50 + 40 * Math.cos(endRad)
          const y2 = 50 + 40 * Math.sin(endRad)
          const largeArc = slice.angle > 180 ? 1 : 0

          return (
            <path
              key={index}
              d={`M 50 50 L ${x1} ${y1} A 40 40 0 ${largeArc} 1 ${x2} ${y2} Z`}
              fill={slice.color || `hsl(${index * 60}, 70%, 50%)`}
              stroke="white"
              strokeWidth="0.5"
            />
          )
        })}
      </svg>
      <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0.5 }}>
        {slices.map((slice, index) => (
          <Box key={index} sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <Box
              sx={{
                width: 12,
                height: 12,
                backgroundColor: slice.color || `hsl(${index * 60}, 70%, 50%)`,
                borderRadius: '2px',
              }}
            />
            <Typography variant="caption">
              {slice.label}: {slice.percentage.toFixed(1)}%
            </Typography>
          </Box>
        ))}
      </Box>
    </Box>
  )
}

// Stat card component
const StatCard = ({ title, value, trend, trendValue, icon, color = '#3B82F6', loading }) => {
  const TrendIcon = trend === 'up' ? TrendingUp : trend === 'down' ? TrendingDown : null

  return (
    <Card sx={{ height: '100%' }}>
      <CardContent>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <Box>
            <Typography variant="body2" color="text.secondary" gutterBottom>
              {title}
            </Typography>
            {loading ? (
              <Skeleton variant="text" width={80} height={40} />
            ) : (
              <Typography variant="h4" sx={{ fontWeight: 'bold' }}>
                {value}
              </Typography>
            )}
            {TrendIcon && (
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, mt: 1 }}>
                <TrendIcon
                  sx={{ fontSize: 16, color: trend === 'up' ? 'success.main' : 'error.main' }}
                />
                <Typography
                  variant="caption"
                  sx={{ color: trend === 'up' ? 'success.main' : 'error.main' }}
                >
                  {trendValue}
                </Typography>
              </Box>
            )}
          </Box>
          <Box
            sx={{
              backgroundColor: `${color}20`,
              borderRadius: '12px',
              p: 1.5,
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
            }}
          >
            {icon}
          </Box>
        </Box>
      </CardContent>
    </Card>
  )
}

// Main dashboard component
export const ReportDashboard = ({ tenantFilter }) => {
  const { currentTenant } = useSettings()
  const [refreshKey, setRefreshKey] = useState(0)

  // Fetch active user data
  const activeUsersApi = ApiGetCall({
    url: '/api/ListGraphReports',
    data: {
      tenantFilter: tenantFilter || currentTenant,
      type: 'graph',
      report: 'getOffice365ActiveUserDetail',
      period: 'D30',
    },
    queryKey: `DashboardActiveUsers-${tenantFilter || currentTenant}-${refreshKey}`,
    waiting: !!(tenantFilter || currentTenant),
  })

  // Fetch mailbox usage data
  const mailboxApi = ApiGetCall({
    url: '/api/ListGraphReports',
    data: {
      tenantFilter: tenantFilter || currentTenant,
      type: 'graph',
      report: 'getMailboxUsageDetail',
      period: 'D30',
    },
    queryKey: `DashboardMailbox-${tenantFilter || currentTenant}-${refreshKey}`,
    waiting: !!(tenantFilter || currentTenant),
  })

  // Fetch Teams usage data
  const teamsApi = ApiGetCall({
    url: '/api/ListGraphReports',
    data: {
      tenantFilter: tenantFilter || currentTenant,
      type: 'graph',
      report: 'getTeamsUserActivityUserDetail',
      period: 'D30',
    },
    queryKey: `DashboardTeams-${tenantFilter || currentTenant}-${refreshKey}`,
    waiting: !!(tenantFilter || currentTenant),
  })

  // Fetch OneDrive usage data
  const oneDriveApi = ApiGetCall({
    url: '/api/ListGraphReports',
    data: {
      tenantFilter: tenantFilter || currentTenant,
      type: 'graph',
      report: 'getOneDriveUsageAccountDetail',
      period: 'D30',
    },
    queryKey: `DashboardOneDrive-${tenantFilter || currentTenant}-${refreshKey}`,
    waiting: !!(tenantFilter || currentTenant),
  })

  const handleRefresh = () => {
    setRefreshKey((prev) => prev + 1)
  }

  // Process active user data
  const activeUsersData = useMemo(() => {
    if (!activeUsersApi.data || !Array.isArray(activeUsersApi.data)) return null
    const data = activeUsersApi.data
    return {
      total: data.length,
      active: data.filter((u) => u.LastActivityDate).length,
      inactive: data.filter((u) => !u.LastActivityDate).length,
      byLicense: data.reduce((acc, u) => {
        const license = u.AssignedProducts?.[0] || 'Unknown'
        acc[license] = (acc[license] || 0) + 1
        return acc
      }, {}),
    }
  }, [activeUsersApi.data])

  // Process mailbox usage data
  const mailboxData = useMemo(() => {
    if (!mailboxApi.data || !Array.isArray(mailboxApi.data)) return null
    const data = mailboxApi.data
    const usedStorage = data.reduce(
      (sum, m) => sum + (parseInt(m.StorageUsed?.replace(/[^\d]/g, '') || 0)),
      0
    )
    return {
      total: data.length,
      usedStorageGB: (usedStorage / 1073741824).toFixed(2),
      avgMailboxSize:
        data.length > 0 ? (usedStorage / data.length / 1048576).toFixed(2) + ' MB' : '0 MB',
      inactiveMailboxes: data.filter((m) => !m.LastActivityDate).length,
    }
  }, [mailboxApi.data])

  // Process Teams usage data
  const teamsData = useMemo(() => {
    if (!teamsApi.data || !Array.isArray(teamsApi.data)) return null
    const data = teamsApi.data
    return {
      totalUsers: data.length,
      activeUsers: data.filter((u) => u.LastActivityDate).length,
      meetingsOrganized: data.reduce(
        (sum, u) => sum + (parseInt(u.MeetingCount || 0)),
        0
      ),
    }
  }, [teamsApi.data])

  // Process OneDrive usage data
  const oneDriveData = useMemo(() => {
    if (!oneDriveApi.data || !Array.isArray(oneDriveApi.data)) return null
    const data = oneDriveApi.data
    const totalStorage = data.reduce(
      (sum, d) => sum + (parseInt(d.StorageUsed?.replace(/[^\d]/g, '') || 0)),
      0
    )
    return {
      totalUsers: data.length,
      totalStorageGB: (totalStorage / 1073741824).toFixed(2),
      avgStorage:
        data.length > 0 ? (totalStorage / data.length / 1048576).toFixed(2) + ' MB' : '0 MB',
    }
  }, [oneDriveApi.data])

  const loading =
    activeUsersApi.isFetching ||
    mailboxApi.isFetching ||
    teamsApi.isFetching ||
    oneDriveApi.isFetching

  // Prepare chart data
  const licenseChartData = useMemo(() => {
    if (!activeUsersData?.byLicense) return []
    return Object.entries(activeUsersData.byLicense)
      .map(([label, value]) => ({
        label: label.split(' ').slice(0, 2).join(' '),
        value,
      }))
      .sort((a, b) => b.value - a.value)
      .slice(0, 5)
  }, [activeUsersData])

  const userStatusData = useMemo(() => {
    if (!activeUsersData) return []
    return [
      { label: 'Active', value: activeUsersData.active, color: '#4CAF50' },
      { label: 'Inactive', value: activeUsersData.inactive, color: '#FF9800' },
    ]
  }, [activeUsersData])

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
        <Typography variant="h5">M365 Usage Dashboard</Typography>
        <Tooltip title="Refresh data">
          <IconButton onClick={handleRefresh} disabled={loading}>
            <Refresh />
          </IconButton>
        </Tooltip>
      </Box>

      {/* Stat cards */}
      <Grid container spacing={3} sx={{ mb: 3 }}>
        <Grid item xs={12} sm={6} md={3}>
          <StatCard
            title="Active Users"
            value={activeUsersData?.active || 0}
            trend="up"
            trendValue={`${activeUsersData?.total || 0} total users`}
            icon={<People sx={{ color: '#3B82F6' }} />}
            color="#3B82F6"
            loading={loading}
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <StatCard
            title="Mailbox Storage"
            value={mailboxData?.usedStorageGB || '0 GB'}
            trend="up"
            trendValue={`${mailboxData?.total || 0} mailboxes`}
            icon={<Email sx={{ color: '#4CAF50' }} />}
            color="#4CAF50"
            loading={loading}
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <StatCard
            title="Teams Users"
            value={teamsData?.activeUsers || 0}
            trend="up"
            trendValue={`${teamsData?.meetingsOrganized || 0} meetings`}
            icon={<Cloud sx={{ color: '#FF9800' }} />}
            color="#FF9800"
            loading={loading}
          />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <StatCard
            title="OneDrive Storage"
            value={oneDriveData?.totalStorageGB || '0 GB'}
            trend="up"
            trendValue={`${oneDriveData?.totalUsers || 0} users`}
            icon={<Security sx={{ color: '#9C27B0' }} />}
            color="#9C27B0"
            loading={loading}
          />
        </Grid>
      </Grid>

      {/* Charts */}
      {!loading && activeUsersData && (
        <Grid container spacing={3}>
          {/* License distribution */}
          <Grid item xs={12} md={6}>
            <Card>
              <CardHeader title="License Distribution" />
              <CardContent>
                <SimpleBarChart data={licenseChartData} color="#3B82F6" />
              </CardContent>
            </Card>
          </Grid>

          {/* User status pie chart */}
          <Grid item xs={12} md={6}>
            <Card>
              <CardHeader title="User Activity Status" />
              <CardContent>
                <Box sx={{ display: 'flex', justifyContent: 'center' }}>
                  <SimplePieChart data={userStatusData} />
                </Box>
              </CardContent>
            </Card>
          </Grid>

          {/* Summary stats */}
          <Grid item xs={12}>
            <Card>
              <CardHeader title="Service Summary" />
              <CardContent>
                <Grid container spacing={2}>
                  <Grid item xs={6} md={3}>
                    <Typography variant="caption" color="text.secondary">Mailboxes</Typography>
                    <Typography variant="h6">{mailboxData?.total || 0}</Typography>
                  </Grid>
                  <Grid item xs={6} md={3}>
                    <Typography variant="caption" color="text.secondary">Avg Mailbox Size</Typography>
                    <Typography variant="h6">{mailboxData?.avgMailboxSize || '0 MB'}</Typography>
                  </Grid>
                  <Grid item xs={6} md={3}>
                    <Typography variant="caption" color="text.secondary">Avg OneDrive Storage</Typography>
                    <Typography variant="h6">{oneDriveData?.avgStorage || '0 MB'}</Typography>
                  </Grid>
                  <Grid item xs={6} md={3}>
                    <Typography variant="caption" color="text.secondary">Teams Meetings</Typography>
                    <Typography variant="h6">{teamsData?.meetingsOrganized || 0}</Typography>
                  </Grid>
                </Grid>
              </CardContent>
            </Card>
          </Grid>
        </Grid>
      )}

      {/* Loading state */}
      {loading && (
        <Grid container spacing={3}>
          {[1, 2, 3, 4].map((i) => (
            <Grid item xs={12} md={6} key={i}>
              <Card>
                <CardContent>
                  <Skeleton variant="rectangular" height={200} />
                </CardContent>
              </Card>
            </Grid>
          ))}
        </Grid>
      )}
    </Box>
  )
}
