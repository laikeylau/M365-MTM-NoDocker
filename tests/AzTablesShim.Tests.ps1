# Test harness for AzTablesShim — run with pwsh on any OS
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $RepoRoot 'backend\Modules\AzTablesShim') -Force

$env:CIPP_SQLITE_DB = Join-Path $env:TEMP "cipp-shim-test-$PID.db"
Remove-Item $env:CIPP_SQLITE_DB* -ErrorAction SilentlyContinue -Force

$failures = 0
function Assert {
    param($Name, $Condition, $Detail)
    if ($Condition) { Write-Host "  PASS  $Name" -ForegroundColor Green }
    else { $failures++; Write-Host "  FAIL  $Name  :: $Detail" -ForegroundColor Red }
}

Write-Host '=== context & table lifecycle ==='
$ctx = New-AzDataTableContext -ConnectionString 'UseDevelopmentStorage=true' -TableName 'TestTable'
Assert 'context created' ($null -ne $ctx -and $ctx.SqlTableName -eq 'az_TestTable') "$ctx"
$null = New-AzDataTable -Context $ctx
$tables = Get-AzDataTable -Context $ctx
Assert 'table listed' ($tables -contains 'TestTable') "$($tables -join ',')"

Write-Host '=== add / get ==='
$now = [datetimeoffset]::UtcNow
$e1 = [PSCustomObject]@{
    PartitionKey = 'Tenants'; RowKey = 'contoso.onmicrosoft.com'
    Name = 'Contoso'; Enabled = $true; UserCount = 125; Size = 92233720368
    Created = $now; Tags = @('a','b')
}
Add-AzDataTableEntity -Context $ctx -Entity $e1 | Out-Null
$row = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Tenants' and RowKey eq 'contoso.onmicrosoft.com'"
Assert 'row returned' ($row.Count -eq 1) "$($row.Count)"
$row = $row[0]
Assert 'string prop' ($row.Name -eq 'Contoso') $row.Name
Assert 'bool prop' ($row.Enabled -eq $true) $row.Enabled
Assert 'int prop is long' ($row.UserCount -is [long] -and $row.UserCount -eq 125) "$($row.UserCount.GetType().Name)=$($row.UserCount)"
Assert 'int64 large' ($row.Size -eq 92233720368) $row.Size
Assert 'date roundtrip is DateTimeOffset' ($row.Created -is [datetimeoffset] -and [math]::Abs(($row.Created - $now).TotalSeconds) -lt 1) "$($row.Created.GetType().Name)=$($row.Created)"
Assert 'array roundtrip' ($row.Tags.Count -eq 2 -and $row.Tags[1] -eq 'b') "$($row.Tags -join ',')"
Assert 'timestamp set' ($row.Timestamp -is [datetimeoffset]) "$($row.Timestamp)"
Assert 'etag set' ($row.ETag -and $row.ETag.Length -gt 10) "$($row.ETag)"

Write-Host '=== conflict semantics ==='
try {
    Add-AzDataTableEntity -Context $ctx -Entity $e1 -ErrorAction Stop
    Assert 'add-existing throws' $false 'no exception'
} catch { Assert 'add-existing throws' ($_.Exception.Message -match 'already exists') "$($_.Exception.Message)" }
Add-AzDataTableEntity -Context $ctx -Entity ([PSCustomObject]@{ PartitionKey='Tenants'; RowKey='contoso.onmicrosoft.com'; Name='Contoso2' }) -Force | Out-Null
$row2 = Get-AzDataTableEntity -Context $ctx -Filter "RowKey eq 'contoso.onmicrosoft.com'"
Assert 'upsert replace' ($row2[0].Name -eq 'Contoso2') "$($row2[0].Name)"

Write-Host '=== merge upsert ==='
Add-AzDataTableEntity -Context $ctx -Entity ([PSCustomObject]@{ PartitionKey='Tenants'; RowKey='fabrikam.onmicrosoft.com'; Name='Fabrikam'; City='Berlin' }) | Out-Null
Add-AzDataTableEntity -Context $ctx -Entity ([PSCustomObject]@{ PartitionKey='Tenants'; RowKey='fabrikam.onmicrosoft.com'; Country='Germany' }) -OperationType UpsertMerge | Out-Null
$f = Get-AzDataTableEntity -Context $ctx -Filter "RowKey eq 'fabrikam.onmicrosoft.com'"
Assert 'merge keeps old prop' ($f[0].Name -eq 'Fabrikam') "$($f[0].Name)"
Assert 'merge adds new prop' ($f[0].Country -eq 'Germany') "$($f[0].Country)"

Write-Host '=== update (replace) ==='
$upd = [PSCustomObject]@{ PartitionKey='Tenants'; RowKey='fabrikam.onmicrosoft.com'; Name='Fabrikam GmbH'; City='Munich' }
Update-AzDataTableEntity -Context $ctx -Entity $upd -Force | Out-Null
$u = Get-AzDataTableEntity -Context $ctx -Filter "RowKey eq 'fabrikam.onmicrosoft.com'"
Assert 'update replaced props' ($u[0].Name -eq 'Fabrikam GmbH' -and $u[0].City -eq 'Munich') "$($u[0] | ConvertTo-Json -Compress)"
Assert 'update removed absent prop' ($null -eq $u[0].Country) "Country=$($u[0].Country)"

Write-Host '=== filters ==='
1..20 | ForEach-Object {
    Add-AzDataTableEntity -Context $ctx -Entity ([PSCustomObject]@{
        PartitionKey = 'Users'; RowKey = "user-$_"; Index = $_; Active = ($_ % 2 -eq 0); Domain = "t$($_ % 3).onmicrosoft.com"
    }) -Force | Out-Null
}
$all = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Users'"
Assert 'eq filter' ($all.Count -eq 20) "$($all.Count)"
$even = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Users' and Active eq true"
Assert 'bool filter' ($even.Count -eq 10) "$($even.Count)"
$range = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Users' and Index ge 5 and Index lt 10"
Assert 'range filter (json num)' ($range.Count -eq 5) "$($range.Count) :: $(($range | ForEach-Object Index) -join ',')"
$dom = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Users' and Domain eq 't1.onmicrosoft.com'"
Assert 'string prop filter' ($dom.Count -eq 7) "$($dom.Count)"
$pref = Get-AzDataTableEntity -Context $ctx -Filter "startswith(RowKey, 'user-1')"
Assert 'startswith' ($pref.Count -eq 11) "$($pref.Count) :: $(($pref.RowKey | ForEach-Object {$_}) -join ',')"
$or = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Users' and (Index eq 3 or Index eq 7)"
Assert 'or+parens' ($or.Count -eq 2) "$($or.Count)"
$ne = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Tenants' and RowKey ne 'contoso.onmicrosoft.com'"
Assert 'ne filter' ($ne.Count -eq 1 -and $ne[0].RowKey -eq 'fabrikam.onmicrosoft.com') "$($ne.Count)"

Write-Host '=== count / first / skip / sort / property ==='
$c = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Users'" -Count
Assert 'count' ($c -eq 20) "$c"
$first3 = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Users'" -Sort @('Index DESC') -First 3
Assert 'sort desc + first' (($first3 | ForEach-Object Index) -join ',' -eq '20,19,18') "$(($_ | ForEach-Object Index) -join ',')"
$skip = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Users'" -Sort @('Index') -Skip 15
Assert 'skip' ($skip.Count -eq 5 -and $skip[0].Index -eq 16) "$($skip.Count)/$($skip[0].Index)"
$prop = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Users' and Index eq 1" -Property @('PartitionKey','RowKey','Index')
Assert 'property projection' ($prop[0].PSObject.Properties.Name.Count -eq 3) "$($prop[0].PSObject.Properties.Name -join ',')"

Write-Host '=== datetime filter ==='
$past = [datetimeoffset]::UtcNow.AddMinutes(-5)
Add-AzDataTableEntity -Context $ctx -Entity ([PSCustomObject]@{ PartitionKey='Logs'; RowKey='log1'; When=$past.AddMinutes(-10); Message='old' }) | Out-Null
Add-AzDataTableEntity -Context $ctx -Entity ([PSCustomObject]@{ PartitionKey='Logs'; RowKey='log2'; When=[datetimeoffset]::UtcNow; Message='new' }) | Out-Null
$old = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Logs' and When lt datetime'$($now.ToString('yyyy-MM-ddTHH:mm:ssZ'))'"
Assert 'datetime lt filter' ($old.Count -eq 1 -and $old[0].RowKey -eq 'log1') "$($old.Count)"

Write-Host '=== remove ==='
Remove-AzDataTableEntity -Context $ctx -Entity @{ PartitionKey='Logs'; RowKey='log1' } -Force | Out-Null
$logs = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Logs'"
Assert 'remove entity' ($logs.Count -eq 1 -and $logs[0].RowKey -eq 'log2') "$($logs.Count)"
$before = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Users'" -Count
Clear-AzDataTable -Context $ctx | Out-Null
$after = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'Users'" -Count
Assert 'clear table' ($before -eq 20 -and $after -eq 0) "$before -> $after"

Write-Host '=== null values skipped, empty string kept ==='
Add-AzDataTableEntity -Context $ctx -Entity ([PSCustomObject]@{ PartitionKey='N'; RowKey='n1'; A=$null; B=''; C=0; D=$false }) | Out-Null
$n = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'N'"
Assert 'null skipped, empty kept' ($null -eq $n[0].A -and $n[0].B -eq '' -and $n[0].C -eq 0 -and $n[0].D -eq $false) "$($n[0] | ConvertTo-Json -Compress)"

Write-Host '=== hashtable entity ==='
Add-AzDataTableEntity -Context $ctx -Entity @{ PartitionKey='H'; RowKey='h1'; Value='from-hashtable' } -Force | Out-Null
$h = Get-AzDataTableEntity -Context $ctx -Filter "PartitionKey eq 'H'"
Assert 'hashtable write/read' ($h[0].Value -eq 'from-hashtable') "$($h[0].Value)"

Write-Host '=== remove table ==='
Remove-AzDataTable -Context $ctx | Out-Null
$tablesAfter = Get-AzDataTable -Context $ctx
Assert 'table dropped' ($tablesAfter -notcontains 'TestTable') "$($tablesAfter -join ',')"

Write-Host ''
if ($failures -eq 0) { Write-Host "ALL TESTS PASSED" -ForegroundColor Green }
else { Write-Host "$failures TEST(S) FAILED" -ForegroundColor Red; exit 1 }
