Function Invoke-ListGlobalAddressList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter

    try {
        # 联调修正(2026-09-09): 反引号后必须紧跟换行；原写法 "` -AsApp"（反引号+空格）
        # 导致续行断裂，"-Select" 被解析为新命令 → "The term '-Select' is not recognized"
        $GAL = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Recipient' -cmdParams @{ ResultSize = 'unlimited'; SortBy = 'DisplayName' } -AsApp -Select 'Identity, DisplayName, Alias, PrimarySmtpAddress, ExternalDirectoryObjectId, HiddenFromAddressListsEnabled, EmailAddresses, IsDirSynced, SKUAssigned, RecipientType, RecipientTypeDetails, AddressListMembership' |
            Select-Object -ExcludeProperty *odata*, *data.type*
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::Forbidden
        $GAL = $ErrorMessage.NormalizedError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GAL)
        })

}
