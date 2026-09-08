Import-Module "C:\DEVT\M365-MTM\backend\Modules\AzTablesShim" -Force
$ctx = New-AzDataTableContext -ConnectionString x -TableName CountTest

$conn = [Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=:memory:")
$conn.Open()
$cmd = $conn.CreateCommand()
Write-Host "A: cmd is null? $($null -eq $cmd)"
$cmd.CommandText = "SELECT COUNT(*) FROM sqlite_master"
$raw = $cmd.ExecuteScalar()
Write-Host "B: raw=[$raw] type=$($raw.GetType().FullName)"
$cmd.Dispose()

# now through the shim handle
$h = Get-ShimTableHandle -Context $ctx
Write-Host "C: h.Conn null? $($null -eq $h.Conn)  h.Table=$($h.Table)"
$cmd2 = $h.Conn.CreateCommand()
Write-Host "D: cmd2 null? $($null -eq $cmd2)"
$cmd2.CommandText = "SELECT COUNT(*) FROM `"$($h.Table)`""
$raw2 = $cmd2.ExecuteScalar()
Write-Host "E: raw2=[$raw2]"
$cmd2.Dispose()

# the failing pattern: foreach over params then execute
$parsed = Convert-ShimODataFilter -Filter "PartitionKey eq 'P'"
$cmd3 = $h.Conn.CreateCommand()
$cmd3.CommandText = "SELECT COUNT(*) FROM `"$($h.Table)`" WHERE $($parsed.Sql)"
foreach ($p in $parsed.Params) {
    Write-Host "F: binding @p Name=$($p.Name) Value=$($p.Value)"
    $null = $cmd3.Parameters.AddWithValue("@$($p.Name)", $p.Value)
    Write-Host "G: cmd3 still null? $($null -eq $cmd3)"
}
$raw3 = $cmd3.ExecuteScalar()
Write-Host "H: raw3=[$raw3] cmd3 null? $($null -eq $cmd3)"
