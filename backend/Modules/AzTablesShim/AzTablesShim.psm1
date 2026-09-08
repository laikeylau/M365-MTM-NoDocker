#Requires -Version 7.4

<#
.SYNOPSIS
    SQLite-backed drop-in replacement for the AzBobbyTables command surface.

.DESCRIPTION
    Implements New-AzDataTableContext / New-Get-Remove-Clear-AzDataTable and the four
    entity commands with the same parameter names and semantics CIPP uses, backed by a
    single local SQLite database file instead of Azure Table Storage / Azurite.

    Row layout per table:
        PartitionKey TEXT, RowKey TEXT  (composite PRIMARY KEY)
        Timestamp     TEXT              (ISO 8601 UTC, emitted as DateTimeOffset)
        ETag          TEXT
        Properties    TEXT              (JSON object with all other properties)
        Types         TEXT              (JSON map propertyName -> dt|guid|bin)

    The database file is selected by $env:CIPP_SQLITE_DB, defaulting to
    <CIPPRootPath>/data/cipp.db. Connection strings (including
    'UseDevelopmentStorage=true') are accepted and ignored.
#>

$script:ShimConnections = @{}
$script:ShimLoaded = $false
$script:ShimNativePath = $null

function Initialize-ShimSqlite {
    # Loads the bundled Microsoft.Data.Sqlite assemblies and pins the native
    # e_sqlite3 library for this platform via a DllImport resolver.
    if ($script:ShimLoaded) { return }
    $sqliteDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\Shared\Sqlite'))
    if (-not (Test-Path (Join-Path $sqliteDir 'Microsoft.Data.Sqlite.dll'))) {
        throw "AzTablesShim: bundled SQLite assemblies not found at '$sqliteDir'"
    }

    foreach ($dll in @('SQLitePCLRaw.core.dll', 'SQLitePCLRaw.provider.e_sqlite3.dll', 'SQLitePCLRaw.batteries_v2.dll', 'Microsoft.Data.Sqlite.dll')) {
        $path = Join-Path $sqliteDir $dll
        if (-not ([System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Location -eq $path })) {
            $null = [System.Reflection.Assembly]::LoadFrom($path)
        }
    }

    # Resolve DllImport("e_sqlite3") from the provider assembly to our bundled native lib.
    $arch = ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture).ToString().ToLower()
    if ($IsWindows) {
        $rid = "win-$arch"; $nativeName = 'e_sqlite3.dll'
    } elseif ($IsOsx) {
        $rid = "osx-$arch"; $nativeName = 'libe_sqlite3.dylib'
    } else {
        $musl = $false
        try {
            if (Test-Path '/etc/os-release') { $musl = ((Get-Content '/etc/os-release' -Raw) -match 'alpine|musl') }
            if (-not $musl -and (Get-Command ldd -ErrorAction SilentlyContinue)) {
                $musl = ((ldd --version 2>&1 | Select-Object -First 1) -match 'musl')
            }
        } catch { }
        $rid = if ($musl) { "linux-musl-$arch" } else { "linux-$arch" }
        $nativeName = 'libe_sqlite3.so'
    }
    $nativePath = Join-Path $sqliteDir "native\$rid\$nativeName"
    if (-not (Test-Path $nativePath)) {
        $alt = Get-ChildItem (Join-Path $sqliteDir 'native') -Recurse -Filter $nativeName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($alt) { $nativePath = $alt.FullName }
    }
    if (-not (Test-Path $nativePath)) {
        throw "AzTablesShim: native SQLite library for RID '$rid' not found under '$sqliteDir\native'"
    }
    $script:ShimNativePath = $nativePath

    $providerAsm = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Location -like '*SQLitePCLRaw.provider.e_sqlite3.dll' } | Select-Object -First 1
    $resolver = [System.Runtime.InteropServices.DllImportResolver]{
        param($libraryName, $assembly, $searchPath)
        if ($libraryName -eq 'e_sqlite3' -and $script:ShimNativePath -and (Test-Path $script:ShimNativePath)) {
            return [System.Runtime.InteropServices.NativeLibrary]::Load($script:ShimNativePath)
        }
        return [IntPtr]::Zero
    }
    try {
        $null = [System.Runtime.InteropServices.NativeLibrary]::SetDllImportResolver($providerAsm, $resolver)
    } catch {
        throw "AzTablesShim: failed to install native resolver: $($_.Exception.Message)"
    }

    # Activate the SQLitePCL provider.
    [SQLitePCL.Batteries_V2]::Init() | Out-Null
    $script:ShimLoaded = $true
}

function Get-ShimDatabasePath {
    if ($env:CIPP_SQLITE_DB) { return $env:CIPP_SQLITE_DB }
    $root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { $PSScriptRoot }
    return (Join-Path $root 'data\cipp.db')
}

function Get-ShimConnection {
    param([string]$DbPath)
    $conn = $script:ShimConnections[$DbPath]
    if (-not $conn) {
        $dir = Split-Path $DbPath -Parent
        if ($dir -and -not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        $conn = [Microsoft.Data.Sqlite.SqliteConnection]::new("Data Source=$DbPath;Cache=Shared")
        $conn.DefaultTimeout = 30
        $conn.Open()
        foreach ($pragma in @('PRAGMA journal_mode=WAL', 'PRAGMA synchronous=NORMAL', 'PRAGMA busy_timeout=5000')) {
            $pragmaCmd = $conn.CreateCommand()
            $pragmaCmd.CommandText = $pragma
            $null = $pragmaCmd.ExecuteScalar()
            $pragmaCmd.Dispose()
        }
        $script:ShimConnections[$DbPath] = $conn
    }
    return $conn
}

function New-ShimCommand {
    param($Connection, [string]$CommandText)
    $cmd = $Connection.CreateCommand()
    $cmd.CommandText = $CommandText
    $cmd.CommandTimeout = 30
    return $cmd
}

function Get-ShimSqlTableName {
    param([string]$TableName)
    $safe = ($TableName -replace '[^A-Za-z0-9_]', '_')
    if ($safe -cne $TableName) { $safe = "$safe$(([System.Math]::Abs($TableName.GetHashCode())).ToString('X'))" }
    return "az_$safe"
}

function ConvertTo-ShimPropertyValue {
    # Returns @{ Value = <PS value safe for ConvertTo-Json>; Type = <dt|guid|bin|$null> }
    param($Value)
    if ($Value -is [datetime] -or $Value -is [datetimeoffset]) {
        $dto = if ($Value -is [datetime]) { [datetimeoffset]::new($Value.ToUniversalTime(), [timespan]::Zero) } else { $Value.ToUniversalTime() }
        return @{ Value = $dto.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ'); Type = 'dt' }
    }
    if ($Value -is [guid]) { return @{ Value = $Value.ToString(); Type = 'guid' } }
    if ($Value -is [byte[]]) { return @{ Value = [convert]::ToBase64String($Value); Type = 'bin' } }
    if ($Value -is [char]) { return @{ Value = "$Value"; Type = $null } }
    return @{ Value = $Value; Type = $null }
}

function ConvertTo-ShimEntityRow {
    param($Entity)
    $properties = [ordered]@{}
    $types = [ordered]@{}

    $items = if ($Entity -is [System.Collections.IDictionary]) {
        $Entity.Keys | ForEach-Object { @{ Key = $_; Value = $Entity[$_] } }
    } else {
        $Entity.PSObject.Properties | ForEach-Object { @{ Key = $_.Name; Value = $_.Value } }
    }

    foreach ($item in $items) {
        $name = "$($item.Key)"
        if ($name -in @('PartitionKey', 'RowKey', 'Timestamp', 'ETag')) { continue }
        if ($null -eq $item.Value) { continue }
        $converted = ConvertTo-ShimPropertyValue -Value $item.Value
        $properties[$name] = $converted.Value
        if ($converted.Type) { $types[$name] = $converted.Type }
    }

    @{
        Properties = ($properties | ConvertTo-Json -Depth 100 -Compress)
        Types      = ($types | ConvertTo-Json -Depth 10 -Compress)
    }
}

function ConvertFrom-ShimRow {
    param($Reader, [string[]]$Property)
    $obj = [ordered]@{}
    $obj['PartitionKey'] = "$($Reader['PartitionKey'])"
    $obj['RowKey'] = "$($Reader['RowKey'])"
    $ts = "$($Reader['Timestamp'])"
    $obj['Timestamp'] = if ($ts) { [datetimeoffset]::Parse($ts, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal) } else { [datetimeoffset]::UtcNow }
    $obj['ETag'] = "$($Reader['ETag'])"

    $propsJson = "$($Reader['Properties'])"
    $typesJson = "$($Reader['Types'])"
    if ($propsJson) {
        $parsed = $propsJson | ConvertFrom-Json -AsHashtable
        $types = if ($typesJson) { $typesJson | ConvertFrom-Json -AsHashtable } else { @{} }
        foreach ($key in $parsed.Keys) {
            $value = $parsed[$key]
            switch ($types[$key]) {
                'dt' {
                    try { $value = [datetimeoffset]::Parse("$value", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal) } catch { }
                }
                'guid' {
                    try { $value = [guid]::Parse("$value") } catch { }
                }
                'bin' {
                    try { $value = [convert]::FromBase64String("$value") } catch { }
                }
            }
            $obj[$key] = $value
        }
    }

    if ($Property) {
        $filtered = [ordered]@{}
        foreach ($p in $Property) {
            if ($obj.Contains($p)) { $filtered[$p] = $obj[$p] }
        }
        $obj = $filtered
    }
    return [pscustomobject]$obj
}

# ---------------- OData filter -> SQLite WHERE ----------------
# State bag $S: @{ Pos = <int>; Params = <List>; Counter = <int> }
# Tokens: @{ T = 'str'|'num'|'dt'|'ident'|'op'|'and'|'or'|'not'|'true'|'false'|'null'|'func'|'lparen'|'rparen'|'comma'; V = ... }

function Get-ShimPropertySql {
    param([string]$Name)
    switch ($Name) {
        'PartitionKey' { return '"PartitionKey"' }
        'RowKey' { return '"RowKey"' }
        'Timestamp' { return '"Timestamp"' }
        default {
            $path = ('$.' + $Name).Replace("'", "''")
            return "json_extract(`"Properties`", '$path')"
        }
    }
}

function Add-ShimParam {
    param($S, $Value)
    $S.Counter++
    $name = "p$($S.Counter)"
    $S.Params.Add(@{ Name = $name; Value = $Value })
    return "@$name"
}

function Convert-ShimTokenToOperand {
    param($S, $Token)
    switch ($Token.T) {
        'str' { return @{ Sql = (Add-ShimParam $S $Token.V); Raw = $Token.V; Kind = 'str' } }
        'num' { return @{ Sql = (Add-ShimParam $S ([double]$Token.V)); Raw = $null; Kind = 'num' } }
        'dt' {
            $dto = [datetimeoffset]::Parse($Token.V, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal)
            return @{ Sql = (Add-ShimParam $S $dto.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')); Raw = $null; Kind = 'dt' }
        }
        'ident' { return @{ Sql = (Get-ShimPropertySql $Token.V); Raw = $null; Kind = 'prop' } }
        default { throw "AzTablesShim: unexpected token '$($Token.T)' as operand" }
    }
}

function Invoke-ShimParseOperand {
    param($S, $Tokens)
    if ($S.Pos -ge $Tokens.Count) { throw 'AzTablesShim: unexpected end of filter' }
    $tok = $Tokens[$S.Pos]
    $S.Pos++
    return (Convert-ShimTokenToOperand -S $S -Token $tok)
}

function Invoke-ShimParsePrimary {
    param($S, $Tokens)
    if ($S.Pos -ge $Tokens.Count) { throw 'AzTablesShim: unexpected end of filter' }
    $tok = $Tokens[$S.Pos]

    if ($tok.T -eq 'lparen') {
        $S.Pos++
        $sql = Invoke-ShimParseOr -S $S -Tokens $Tokens
        if ($S.Pos -ge $Tokens.Count -or $Tokens[$S.Pos].T -ne 'rparen') { throw "AzTablesShim: missing ')' in filter" }
        $S.Pos++
        return "($sql)"
    }

    if ($tok.T -eq 'func') {
        $S.Pos++            # consume 'func' (tokenizer already consumed the '(')
        $op1 = Invoke-ShimParseOperand -S $S -Tokens $Tokens
        if ($S.Pos -lt $Tokens.Count -and $Tokens[$S.Pos].T -eq 'comma') { $S.Pos++ }
        $op2 = Invoke-ShimParseOperand -S $S -Tokens $Tokens
        if ($S.Pos -lt $Tokens.Count -and $Tokens[$S.Pos].T -eq 'rparen') { $S.Pos++ }
        if ($op2.Kind -ne 'str') {
            # pattern sourced from a property: use SQL concatenation
            return "$($op1.Sql) LIKE ($($op2.Sql) || '%')"
        }
        $escaped = $op2.Raw.Replace('\', '\\').Replace('%', '\%').Replace('_', '\_')
        $pattern = switch ($tok.V) {
            'startswith' { "$escaped%" }
            'endswith' { "%$escaped" }
            'contains' { "%$escaped%" }
        }
        $p = Add-ShimParam $S $pattern
        return "$($op1.Sql) LIKE $p ESCAPE '\'"
    }

    return (Invoke-ShimParseComparison -S $S -Tokens $Tokens)
}

function Invoke-ShimParseComparison {
    param($S, $Tokens)
    $left = Invoke-ShimParseOperand -S $S -Tokens $Tokens
    if ($S.Pos -ge $Tokens.Count) { throw 'AzTablesShim: unexpected end of filter, expected operator' }
    $tok = $Tokens[$S.Pos]

    if ($tok.T -eq 'true') {
        $S.Pos++
        return "$($left.Sql) = 1"
    }
    if ($tok.T -eq 'false') {
        $S.Pos++
        return "$($left.Sql) = 0"
    }
    if ($tok.T -eq 'null') {
        $S.Pos++
        throw "AzTablesShim: 'prop eq null' must use the eq/ne operator form"
    }
    if ($tok.T -eq 'op') {
        $S.Pos++
        $rightTok = $Tokens[$S.Pos]
        if ($rightTok.T -eq 'null') {
            $S.Pos++
            $sqlOp = if ($tok.V -eq 'ne') { 'IS NOT NULL' } else { 'IS NULL' }
            return "$($left.Sql) $sqlOp"
        }
        if ($rightTok.T -eq 'true' -or $rightTok.T -eq 'false') {
            $S.Pos++
            $v = if ($rightTok.T -eq 'true') { 1 } else { 0 }
            $sqlOp = switch ($tok.V) { 'eq' { '=' }; 'ne' { '<>' }; 'ge' { '>=' }; 'gt' { '>' }; 'le' { '<=' }; 'lt' { '<' } }
            return "$($left.Sql) $sqlOp $v"
        }
        $right = Invoke-ShimParseOperand -S $S -Tokens $Tokens
        $sqlOp = switch ($tok.V) {
            'eq' { '=' }; 'ne' { '<>' }; 'ge' { '>=' }; 'gt' { '>' }; 'le' { '<=' }; 'lt' { '<' }
        }
        return "$($left.Sql) $sqlOp $($right.Sql)"
    }
    throw "AzTablesShim: expected comparison operator, got '$($tok.T)'"
}

function Invoke-ShimParseUnary {
    param($S, $Tokens)
    if ($S.Pos -lt $Tokens.Count -and $Tokens[$S.Pos].T -eq 'not') {
        $S.Pos++
        return "NOT $(Invoke-ShimParsePrimary -S $S -Tokens $Tokens)"
    }
    return (Invoke-ShimParsePrimary -S $S -Tokens $Tokens)
}

function Invoke-ShimParseAnd {
    param($S, $Tokens)
    $parts = @(Invoke-ShimParseUnary -S $S -Tokens $Tokens)
    while ($S.Pos -lt $Tokens.Count -and $Tokens[$S.Pos].T -eq 'and') {
        $S.Pos++
        $parts += (Invoke-ShimParseUnary -S $S -Tokens $Tokens)
    }
    return ($parts -join ' AND ')
}

function Invoke-ShimParseOr {
    param($S, $Tokens)
    $parts = @(Invoke-ShimParseAnd -S $S -Tokens $Tokens)
    while ($S.Pos -lt $Tokens.Count -and $Tokens[$S.Pos].T -eq 'or') {
        $S.Pos++
        $parts += (Invoke-ShimParseAnd -S $S -Tokens $Tokens)
    }
    return ($parts -join ' OR ')
}

function Convert-ShimODataFilter {
    <#
    .SYNOPSIS
        Translates the OData filter subset used by CIPP into a SQLite WHERE clause.
    .NOTES
        Supported: and/or/not, parentheses, eq/ne/gt/ge/lt/le, boolean/number/null/
        string/datetime'...'/GUID literals, startswith/endswith/contains.
        PartitionKey/RowKey/Timestamp map to columns; every other property maps to
        json_extract(Properties, '$.Prop').
    #>
    param([string]$Filter)

    if ([string]::IsNullOrWhiteSpace($Filter)) { return @{ Sql = ''; Params = @() } }

    # ---- tokenize ----
    $tokens = [System.Collections.Generic.List[object]]::new()
    $i = 0; $len = $Filter.Length
    while ($i -lt $len) {
        $c = $Filter[$i]
        if ([char]::IsWhiteSpace($c)) { $i++; continue }
        if ($c -eq "'") {
            $sb = [System.Text.StringBuilder]::new()
            $i++
            while ($i -lt $len) {
                if ($Filter[$i] -eq "'") {
                    if ($i + 1 -lt $len -and $Filter[$i + 1] -eq "'") { $null = $sb.Append("'"); $i += 2; continue }
                    $i++; break
                }
                $null = $sb.Append($Filter[$i]); $i++
            }
            $tokens.Add(@{ T = 'str'; V = $sb.ToString() })
            continue
        }
        if ($c -eq '(') { $tokens.Add(@{ T = 'lparen' }); $i++; continue }
        if ($c -eq ')') { $tokens.Add(@{ T = 'rparen' }); $i++; continue }
        if ($c -eq ',') { $tokens.Add(@{ T = 'comma' }); $i++; continue }

        $rest = $Filter.Substring($i)
        $opMatch = [regex]::Match($rest, '^(eq|ne|ge|gt|le|lt)\b', 'IgnoreCase')
        if ($opMatch.Success) { $tokens.Add(@{ T = 'op'; V = $opMatch.Groups[1].Value.ToLower() }); $i += $opMatch.Length; continue }

        $kwMatch = [regex]::Match($rest, '^(and|or|not|true|false|null|datetime)\b', 'IgnoreCase')
        if ($kwMatch.Success) {
            $kw = $kwMatch.Groups[1].Value.ToLower()
            if ($kw -eq 'datetime') {
                $dtMatch = [regex]::Match($rest, "^datetime\s*'", 'IgnoreCase')
                if ($dtMatch.Success) {
                    $start = $i + $dtMatch.Length
                    $end = $Filter.IndexOf("'", $start)
                    if ($end -lt 0) { throw "AzTablesShim: unterminated datetime literal in filter: $Filter" }
                    $tokens.Add(@{ T = 'dt'; V = $Filter.Substring($start, $end - $start) })
                    $i = $end + 1
                    continue
                }
            }
            $tokens.Add(@{ T = $kw })
            $i += $kwMatch.Length
            continue
        }

        $funcMatch = [regex]::Match($rest, '^(startswith|endswith|contains)\s*\(', 'IgnoreCase')
        if ($funcMatch.Success) {
            $tokens.Add(@{ T = 'func'; V = $funcMatch.Groups[1].Value.ToLower() })
            $i += $funcMatch.Length
            continue
        }

        if ($c -eq '-' -or [char]::IsDigit($c)) {
            $numMatch = [regex]::Match($rest, '^-?\d+(\.\d+)?([eE][+-]?\d+)?')
            if ($numMatch.Success) {
                $tokens.Add(@{ T = 'num'; V = $numMatch.Value }); $i += $numMatch.Length; continue
            }
        }

        $identMatch = [regex]::Match($rest, '^[A-Za-z_][A-Za-z0-9_\.\/\-]*')
        if ($identMatch.Success) {
            $val = $identMatch.Value
            if ($val -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
                $tokens.Add(@{ T = 'str'; V = $val })
            } else {
                $tokens.Add(@{ T = 'ident'; V = $val })
            }
            $i += $identMatch.Length
            continue
        }
        throw "AzTablesShim: cannot parse filter at position $i in: $Filter"
    }

    $S = @{ Pos = 0; Params = [System.Collections.Generic.List[object]]::new(); Counter = 0 }
    $whereSql = Invoke-ShimParseOr -S $S -Tokens $tokens
    return @{ Sql = $whereSql; Params = $S.Params }
}

# ---------------- table + entity commands ----------------

function Get-ShimTableHandle {
    param($Context)
    Initialize-ShimSqlite
    $conn = Get-ShimConnection -DbPath $Context.DbPath
    return @{ Conn = $conn; Table = $Context.SqlTableName }
}

function New-AzDataTableContext {
    <#
    .SYNOPSIS
        Creates a SQLite-backed table context compatible with AzBobbyTables usage.
    .PARAMETER ConnectionString
        Accepted for compatibility; ignored. The database file is chosen via
        $env:CIPP_SQLITE_DB (default: <CIPPRootPath>/data/cipp.db).
    #>
    [CmdletBinding(DefaultParameterSetName = 'ConnectionString')]
    param(
        [Parameter(ParameterSetName = 'ConnectionString', Position = 0)]
        [string]$ConnectionString,

        [Parameter(ParameterSetName = 'AccountName', Position = 0)]
        [string]$StorageAccountName,

        [Parameter(ParameterSetName = 'SAS')]
        [uri]$SharedAccessSignature,

        [Parameter(ParameterSetName = 'AccountKey')]
        [string]$StorageAccountKey,

        [Parameter(ParameterSetName = 'Token')]
        [string]$Token,

        [Parameter(ParameterSetName = 'Token')]
        [string]$ClientId,

        [Parameter(ParameterSetName = 'AccountName')]
        [switch]$ManagedIdentity,

        [string]$TableName,

        [int]$MaxConnectionsPerServer
    )

    Initialize-ShimSqlite
    $dbPath = Get-ShimDatabasePath
    $sqlTable = if ($TableName) { Get-ShimSqlTableName -TableName $TableName } else { '' }
    return [pscustomobject]@{
        ShimType         = 'AzDataTableContext'
        TableName        = $TableName
        ConnectionString = $ConnectionString
        DbPath           = $dbPath
        SqlTableName     = $sqlTable
    }
}

function New-AzDataTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [switch]$Force
    )
    $h = Get-ShimTableHandle -Context $Context
    if (-not $h.Table) { throw 'AzTablesShim: context has no TableName' }
    $cmd = New-ShimCommand -Connection $h.Conn -CommandText @"
CREATE TABLE IF NOT EXISTS "$($h.Table)" (
    "PartitionKey" TEXT NOT NULL,
    "RowKey" TEXT NOT NULL,
    "Timestamp" TEXT NOT NULL,
    "ETag" TEXT,
    "Properties" TEXT,
    "Types" TEXT,
    PRIMARY KEY ("PartitionKey", "RowKey")
)
"@
    $null = $cmd.ExecuteScalar()
    $cmd.Dispose()
    return $true
}

function Get-AzDataTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [string]$Filter
    )
    Initialize-ShimSqlite
    $conn = Get-ShimConnection -DbPath $Context.DbPath
    $cmd = New-ShimCommand -Connection $conn -CommandText "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'az\_%' ESCAPE '\' ORDER BY name"
    $names = @()
    $reader = $cmd.ExecuteReader()
    try {
        while ($reader.Read()) {
            $names += ("$($reader.GetString(0))" -replace '^az_', '')
        }
    } finally { $reader.Dispose(); $cmd.Dispose() }
    if ($Filter -and $Filter -match "TableName\s+eq\s+'([^']+)'") {
        return @($names | Where-Object { $_ -eq $Matches[1] })
    }
    return $names
}

function Remove-AzDataTable {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][object]$Context,
        [switch]$Force
    )
    $h = Get-ShimTableHandle -Context $Context
    if (-not $h.Table) { throw 'AzTablesShim: context has no TableName' }
    $cmd = New-ShimCommand -Connection $h.Conn -CommandText "DROP TABLE IF EXISTS `"$($h.Table)`""
    $null = $cmd.ExecuteScalar()
    $cmd.Dispose()
    return $true
}

function Clear-AzDataTable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Context)
    $h = Get-ShimTableHandle -Context $Context
    if (-not $h.Table) { throw 'AzTablesShim: context has no TableName' }
    $null = (New-AzDataTable -Context $Context)
    $cmd = New-ShimCommand -Connection $h.Conn -CommandText "DELETE FROM `"$($h.Table)`""
    $null = $cmd.ExecuteScalar()
    $cmd.Dispose()
    return $true
}

function Get-AzDataTableEntity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [string]$Filter,
        [string[]]$Property,
        [int]$First,
        [int]$Skip,
        [string[]]$Sort,
        [switch]$Count
    )
    $h = Get-ShimTableHandle -Context $Context
    $null = (New-AzDataTable -Context $Context)

    $where = ''
    $filterParams = @()
    if ($Filter) {
        $parsed = Convert-ShimODataFilter -Filter $Filter
        if ($parsed.Sql) { $where = "WHERE $($parsed.Sql)" }
        $filterParams = $parsed.Params
    }

    if ($Count.IsPresent) {
        $cmd = New-ShimCommand -Connection $h.Conn -CommandText "SELECT COUNT(*) FROM `"$($h.Table)`" $where"
        foreach ($p in $filterParams) { $null = $cmd.Parameters.AddWithValue("@$($p.Name)", $p.Value) }
        $rowCount = [int]$cmd.ExecuteScalar()
        $cmd.Dispose()
        return $rowCount
    }

    $orderBy = ''
    if ($Sort) {
        $cols = foreach ($s in $Sort) {
            $bits = $s -split '\s+'
            $prop = $bits[0]
            $dir = 'ASC'
            if ($bits.Count -gt 1 -and $bits[1] -match '^desc') { $dir = 'DESC' }
            $colSql = switch ($prop) {
                'PartitionKey' { '"PartitionKey"' }
                'RowKey' { '"RowKey"' }
                'Timestamp' { '"Timestamp"' }
                default {
                    $path = ('$.' + $prop).Replace("'", "''")
                    "json_extract(`"Properties`", '$path')"
                }
            }
            "$colSql $dir"
        }
        $orderBy = "ORDER BY $($cols -join ', ')"
    }
    $limit = ''
    if ($First -gt 0 -or $Skip -gt 0) {
        $firstVal = if ($First -gt 0) { $First } else { -1 }
        $skipVal = if ($Skip -gt 0) { $Skip } else { 0 }
        $limit = "LIMIT $firstVal OFFSET $skipVal"
    }

    $sql = "SELECT * FROM `"$($h.Table)`" $where $orderBy $limit"
    $cmd = New-ShimCommand -Connection $h.Conn -CommandText $sql
    foreach ($p in $filterParams) { $null = $cmd.Parameters.AddWithValue("@$($p.Name)", $p.Value) }
    $reader = $cmd.ExecuteReader()
    $results = [System.Collections.Generic.List[object]]::new()
    try {
        while ($reader.Read()) {
            $results.Add((ConvertFrom-ShimRow -Reader $reader -Property $Property))
        }
    } finally { $reader.Dispose(); $cmd.Dispose() }
    return $results
}

function Get-ShimKeyValue {
    param($Entity, [string]$Key)
    if ($Entity -is [System.Collections.IDictionary]) {
        if ($Entity.Contains($Key)) { return "$($Entity[$Key])" }
        return $null
    }
    $prop = $Entity.PSObject.Properties[$Key]
    if ($prop) { return "$($prop.Value)" }
    return $null
}

function Invoke-ShimWrite {
    param(
        [object]$Context,
        [object[]]$Entities,
        [ValidateSet('add', 'replace', 'merge')][string]$Mode
    )
    $h = Get-ShimTableHandle -Context $Context
    $null = (New-AzDataTable -Context $Context)
    $now = [datetimeoffset]::UtcNow.UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')

    $tx = $h.Conn.BeginTransaction()
    try {
        $existsCmd = New-ShimCommand -Connection $h.Conn -CommandText "SELECT COUNT(*) FROM `"$($h.Table)`" WHERE `"PartitionKey`"=@pk AND `"RowKey`"=@rk"
        $existsCmd.Transaction = $tx

        $insertSql = @"
INSERT INTO "$($h.Table)" ("PartitionKey","RowKey","Timestamp","ETag","Properties","Types")
VALUES (@pk,@rk,@ts,@etag,@props,@types)
"@
        $upsertReplace = New-ShimCommand -Connection $h.Conn -CommandText @"
$insertSql
ON CONFLICT("PartitionKey","RowKey") DO UPDATE SET
    "Timestamp"=@ts, "ETag"=@etag, "Properties"=@props, "Types"=@types
"@
        $upsertReplace.Transaction = $tx

        $mergeCmd = New-ShimCommand -Connection $h.Conn -CommandText @"
$insertSql
ON CONFLICT("PartitionKey","RowKey") DO UPDATE SET
    "Timestamp"=@ts, "ETag"=@etag,
    "Properties"=json_patch("Properties", @props),
    "Types"=json_patch("Types", @types)
"@
        $mergeCmd.Transaction = $tx

        $insertOnly = New-ShimCommand -Connection $h.Conn -CommandText $insertSql
        $insertOnly.Transaction = $tx

        foreach ($e in $Entities) {
            if ($null -eq $e) { continue }
            $pk = Get-ShimKeyValue -Entity $e -Key 'PartitionKey'
            $rk = Get-ShimKeyValue -Entity $e -Key 'RowKey'
            if (-not $pk -or -not $rk) { throw 'AzTablesShim: entity is missing PartitionKey or RowKey' }
            $row = ConvertTo-ShimEntityRow -Entity $e
            $etag = [guid]::NewGuid().ToString()

            $null = $existsCmd.Parameters.AddWithValue('@pk', "$pk")
            $null = $existsCmd.Parameters.AddWithValue('@rk', "$rk")
            $exists = [int]$existsCmd.ExecuteScalar() -gt 0
            $existsCmd.Parameters.Clear()

            $cmd = switch ($Mode) {
                'add' {
                    if ($exists) { throw "AzTablesShim: entity with PartitionKey='$pk', RowKey='$rk' already exists (409 conflict)" }
                    $insertOnly
                }
                'replace' { $upsertReplace }
                'merge' {
                    if ($exists) { $mergeCmd } else { $insertOnly }
                }
            }

            $null = $cmd.Parameters.AddWithValue('@pk', "$pk")
            $null = $cmd.Parameters.AddWithValue('@rk', "$rk")
            $null = $cmd.Parameters.AddWithValue('@ts', $now)
            $null = $cmd.Parameters.AddWithValue('@etag', $etag)
            $null = $cmd.Parameters.AddWithValue('@props', $row.Properties)
            $null = $cmd.Parameters.AddWithValue('@types', $row.Types)
            $null = $cmd.ExecuteNonQuery()
            $cmd.Parameters.Clear()
        }
        $tx.Commit()
    } catch {
        $null = $tx.Rollback()
        throw
    } finally { $tx.Dispose() }
    return $true
}

function Add-AzDataTableEntity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory, ValueFromPipeline)][object[]]$Entity,
        [switch]$CreateTableIfNotExists,
        [switch]$Force,
        [ValidateSet('Add', 'UpsertMerge', 'UpsertReplace')]
        [string]$OperationType
    )
    begin { $batch = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($e in $Entity) { $batch.Add($e) } }
    end {
        if ($batch.Count -eq 0) { return }
        $mode = if ($Force.IsPresent -or $OperationType -eq 'UpsertReplace') { 'replace' }
                elseif ($OperationType -eq 'UpsertMerge') { 'merge' }
                else { 'add' }
        Invoke-ShimWrite -Context $Context -Entities $batch -Mode $mode
    }
}

function Update-AzDataTableEntity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory, ValueFromPipeline)][object[]]$Entity,
        [switch]$CreateTableIfNotExists,
        [switch]$Force,
        [ValidateSet('Update', 'UpsertMerge', 'UpsertReplace', 'Merge')]
        [string]$OperationType
    )
    begin { $batch = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($e in $Entity) { $batch.Add($e) } }
    end {
        if ($batch.Count -eq 0) { return }
        # Azure Table Update semantics: full replace of the row's properties.
        # A non-existent row is created (upsert), matching AzBobbyTables behaviour.
        $mode = if ($OperationType -in @('UpsertMerge', 'Merge')) { 'merge' } else { 'replace' }
        Invoke-ShimWrite -Context $Context -Entities $batch -Mode $mode
    }
}

function Remove-AzDataTableEntity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory, ValueFromPipeline)][object[]]$Entity,
        [switch]$CreateTableIfNotExists,
        [switch]$Force,
        [string]$OperationType
    )
    $h = Get-ShimTableHandle -Context $Context
    $null = (New-AzDataTable -Context $Context)
    $tx = $h.Conn.BeginTransaction()
    try {
        $cmd = New-ShimCommand -Connection $h.Conn -CommandText "DELETE FROM `"$($h.Table)`" WHERE `"PartitionKey`"=@pk AND `"RowKey`"=@rk"
        $cmd.Transaction = $tx
        $check = New-ShimCommand -Connection $h.Conn -CommandText "SELECT ETag FROM `"$($h.Table)`" WHERE `"PartitionKey`"=@pk AND `"RowKey`"=@rk"
        $check.Transaction = $tx
        foreach ($e in $Entity) {
            if ($null -eq $e) { continue }
            $pk = Get-ShimKeyValue -Entity $e -Key 'PartitionKey'
            $rk = Get-ShimKeyValue -Entity $e -Key 'RowKey'
            if (-not $pk -or -not $rk) { throw 'AzTablesShim: entity is missing PartitionKey or RowKey' }
            if (-not $Force.IsPresent) {
                $etag = Get-ShimKeyValue -Entity $e -Key 'ETag'
                if ($etag -and $etag -ne '*') {
                    $null = $check.Parameters.AddWithValue('@pk', "$pk")
                    $null = $check.Parameters.AddWithValue('@rk', "$rk")
                    $stored = $check.ExecuteScalar()
                    $check.Parameters.Clear()
                    if ($stored -and "$stored" -cne "$etag") {
                        throw "AzTablesShim: entity has been modified since last retrieved (ETag mismatch on $pk/$rk)"
                    }
                }
            }
            $null = $cmd.Parameters.AddWithValue('@pk', "$pk")
            $null = $cmd.Parameters.AddWithValue('@rk', "$rk")
            $null = $cmd.ExecuteNonQuery()
            $cmd.Parameters.Clear()
        }
        $check.Dispose()
        $cmd.Dispose()
        $tx.Commit()
    } catch {
        $null = $tx.Rollback()
        throw
    } finally { $tx.Dispose() }
    return $true
}

function Get-AzDataTableSupportedEntityType {
    'System.Collections.Hashtable', 'System.Management.Automation.PSCustomObject', 'System.Collections.SortedList'
}

Export-ModuleMember -Function @(
    'New-AzDataTableContext', 'New-AzDataTable', 'Get-AzDataTable', 'Remove-AzDataTable',
    'Clear-AzDataTable', 'Get-AzDataTableEntity', 'Add-AzDataTableEntity',
    'Update-AzDataTableEntity', 'Remove-AzDataTableEntity', 'Get-AzDataTableSupportedEntityType'
)
