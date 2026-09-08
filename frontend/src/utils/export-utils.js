/**
 * Enhanced Export Utilities for CIPP Reports
 * Supports CSV, Excel (XLSX), JSON, and PDF export
 */

// Export to CSV
export const exportToCSV = (data, filename = 'report', options = {}) => {
  const {
    delimiter = ',',
    includeHeaders = true,
    selectedColumns = null,
    dateFormat = 'YYYY-MM-DD',
  } = options

  if (!data || data.length === 0) {
    console.warn('No data to export')
    return false
  }

  const columns = selectedColumns || Object.keys(data[0])

  const escapeCSV = (value) => {
    if (value === null || value === undefined) return ''
    const stringValue = String(value)
    if (
      stringValue.includes(delimiter) ||
      stringValue.includes('"') ||
      stringValue.includes('\n')
    ) {
      return `"${stringValue.replace(/"/g, '""')}"`
    }
    return stringValue
  }

  const formatDate = (value) => {
    if (!value) return ''
    const date = new Date(value)
    if (isNaN(date.getTime())) return value

    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, '0')
    const day = String(date.getDate()).padStart(2, '0')

    switch (dateFormat) {
      case 'YYYY-MM-DD':
        return `${year}-${month}-${day}`
      case 'MM/DD/YYYY':
        return `${month}/${day}/${year}`
      case 'DD/MM/YYYY':
        return `${day}/${month}/${year}`
      default:
        return `${year}-${month}-${day}`
    }
  }

  const rows = []

  if (includeHeaders) {
    rows.push(columns.map(escapeCSV).join(delimiter))
  }

  data.forEach((row) => {
    const values = columns.map((col) => {
      const value = row[col]
      if (
        value &&
        (col.toLowerCase().includes('date') ||
          col.toLowerCase().includes('time') ||
          col.toLowerCase().includes('lastactivity'))
      ) {
        return escapeCSV(formatDate(value))
      }
      if (typeof value === 'object' && value !== null) {
        return escapeCSV(JSON.stringify(value))
      }
      return escapeCSV(value)
    })
    rows.push(values.join(delimiter))
  })

  const csvContent = rows.join('\n')
  const blob = new Blob(['\ufeff' + csvContent], { type: 'text/csv;charset=utf-8;' })
  downloadBlob(blob, `${filename}.csv`)

  return true
}

// Export to Excel (HTML table format)
export const exportToExcel = (data, filename = 'report', options = {}) => {
  const { selectedColumns = null, sheetName = 'Report' } = options

  if (!data || data.length === 0) {
    console.warn('No data to export')
    return false
  }

  const columns = selectedColumns || Object.keys(data[0])

  let html = `
    <html xmlns:o="urn:schemas-microsoft-com:office:office"
          xmlns:x="urn:schemas-microsoft-com:office:excel"
          xmlns="http://www.w3.org/TR/REC-html40">
    <head>
      <meta charset="utf-8">
      <!--[if gte mso 9]>
      <xml>
        <x:ExcelWorkbook>
          <x:ExcelWorksheets>
            <x:ExcelWorksheet>
              <x:Name>${sheetName}</x:Name>
              <x:WorksheetOptions>
                <x:DisplayGridlines/>
              </x:WorksheetOptions>
            </x:ExcelWorksheet>
          </x:ExcelWorksheets>
        </x:ExcelWorkbook>
      </xml>
      <![endif]-->
      <style>
        th { background-color: #4472C4; color: white; font-weight: bold; }
        td { border: 1px solid #D9D9D9; }
        tr:nth-child(even) { background-color: #F2F2F2; }
      </style>
    </head>
    <body>
      <table>
        <thead>
          <tr>
            ${columns.map((col) => `<th>${escapeHTML(col)}</th>`).join('')}
          </tr>
        </thead>
        <tbody>
  `

  data.forEach((row) => {
    html += '<tr>'
    columns.forEach((col) => {
      const value = row[col]
      let displayValue = ''

      if (value === null || value === undefined) {
        displayValue = ''
      } else if (typeof value === 'object') {
        displayValue = JSON.stringify(value)
      } else {
        displayValue = String(value)
      }

      const isNumber = !isNaN(displayValue) && displayValue !== ''
      const style = isNumber ? 'style="mso-number-format:\\@;"' : ''

      html += `<td ${style}>${escapeHTML(displayValue)}</td>`
    })
    html += '</tr>'
  })

  html += `
        </tbody>
      </table>
    </body>
    </html>
  `

  const blob = new Blob([html], { type: 'application/vnd.ms-excel' })
  downloadBlob(blob, `${filename}.xls`)

  return true
}

// Export to JSON
export const exportToJSON = (data, filename = 'report', options = {}) => {
  const { pretty = true, selectedColumns = null } = options

  if (!data || data.length === 0) {
    console.warn('No data to export')
    return false
  }

  let exportData = data

  if (selectedColumns) {
    exportData = data.map((row) => {
      const filtered = {}
      selectedColumns.forEach((col) => {
        filtered[col] = row[col]
      })
      return filtered
    })
  }

  const jsonContent = pretty ? JSON.stringify(exportData, null, 2) : JSON.stringify(exportData)
  const blob = new Blob([jsonContent], { type: 'application/json' })
  downloadBlob(blob, `${filename}.json`)

  return true
}

// Export to PDF (browser print dialog)
export const exportToPDF = (data, filename = 'report', options = {}) => {
  const { title = 'Report', selectedColumns = null } = options

  if (!data || data.length === 0) {
    console.warn('No data to export')
    return false
  }

  const columns = selectedColumns || Object.keys(data[0])

  const printWindow = window.open('', '_blank')
  if (!printWindow) {
    console.warn('Popup blocked. Please allow popups for this site.')
    return false
  }

  const html = `
    <!DOCTYPE html>
    <html>
    <head>
      <title>${title}</title>
      <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; border-bottom: 2px solid #3B82F6; padding-bottom: 10px; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th { background-color: #3B82F6; color: white; padding: 12px 8px; text-align: left; }
        td { border: 1px solid #ddd; padding: 8px; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        tr:hover { background-color: #f5f5f5; }
        .meta { color: #666; font-size: 14px; margin-bottom: 20px; }
        @media print {
          body { margin: 0; }
          .no-print { display: none; }
        }
      </style>
    </head>
    <body>
      <h1>${title}</h1>
      <div class="meta">
        <p>Generated: ${new Date().toLocaleString()}</p>
        <p>Total Records: ${data.length}</p>
      </div>
      <table>
        <thead>
          <tr>
            ${columns.map((col) => `<th>${escapeHTML(col)}</th>`).join('')}
          </tr>
        </thead>
        <tbody>
          ${data
            .map(
              (row) => `
            <tr>
              ${columns
                .map((col) => {
                  const value = row[col]
                  const display =
                    value === null || value === undefined
                      ? ''
                      : typeof value === 'object'
                        ? JSON.stringify(value)
                        : String(value)
                  return `<td>${escapeHTML(display)}</td>`
                })
                .join('')}
            </tr>
          `
            )
            .join('')}
        </tbody>
      </table>
      <div class="no-print" style="margin-top: 20px; text-align: center;">
        <button onclick="window.print()">Print / Save as PDF</button>
      </div>
    </body>
    </html>
  `

  printWindow.document.write(html)
  printWindow.document.close()

  return true
}

// HTML escape helper
const escapeHTML = (str) => {
  if (typeof str !== 'string') return str
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}

// Download blob helper
const downloadBlob = (blob, filename) => {
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}

// Multi-sheet export
export const exportMultipleSheets = (sheets, filename = 'report') => {
  sheets.forEach((sheet, index) => {
    const sheetFilename = sheets.length > 1 ? `${filename}_${sheet.name}` : filename
    exportToCSV(sheet.data, sheetFilename, sheet.options)
  })
  return true
}

// Export utilities object
export const ExportUtils = {
  csv: exportToCSV,
  excel: exportToExcel,
  json: exportToJSON,
  pdf: exportToPDF,
  multiSheet: exportMultipleSheets,
}

export default ExportUtils
