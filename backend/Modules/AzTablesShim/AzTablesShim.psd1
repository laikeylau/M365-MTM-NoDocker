@{
    RootModule        = 'AzTablesShim.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'b7e6d9c1-4a2f-4e8b-9c3d-5f1a2b6c8d90'
    Author            = 'M365-MTM'
    CompanyName       = 'M365-MTM'
    Copyright         = 'Internal use'
    Description       = 'Drop-in SQLite-backed replacement for the AzBobbyTables table-storage API. Implements the same command surface so CIPP runs without Azurite/Azure Storage.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'New-AzDataTableContext',
        'New-AzDataTable',
        'Get-AzDataTable',
        'Remove-AzDataTable',
        'Clear-AzDataTable',
        'Get-AzDataTableEntity',
        'Add-AzDataTableEntity',
        'Update-AzDataTableEntity',
        'Remove-AzDataTableEntity',
        'Get-AzDataTableSupportedEntityType'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('SQLite', 'AzBobbyTables', 'Shim', 'Tables')
            ProjectUri = 'https://github.com/laikeylau/CIPP'
        }
    }
}
