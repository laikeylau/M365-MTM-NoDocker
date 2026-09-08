#Requires -Version 7.4
<#
.SYNOPSIS
    Self-hosted CIPP API server — replaces Azure Functions host + Azurite with plain PowerShell.

.DESCRIPTION
    Direct-run host for the CIPP backend on Linux/Windows with only PowerShell 7 required.

    Modes (same script, systemd runs one instance of each):
      cipp-server.ps1                -> API mode: HTTP listener on :7071 (default)
      cipp-server.ps1 -WorkerOnly    -> Worker mode: cron timers + SQLite queue poller +
                                        inline orchestrator executor (no Durable Functions)

    Storage is fully SQLite via the bundled AzTablesShim module (CIPP_SQLITE_DB).
    Queues are a SQLite table (cippqueue) written by the Push-OutputBinding shim.
    Orchestrations started via Start-NewOrchestration (Durable SDK shim) are executed
    inline by the worker (sequential fan-out + PostExecution).

    Usage:
      pwsh -File cipp-server.ps1              # API
      pwsh -File cipp-server.ps1 -WorkerOnly  # background worker
#>

param(
    [int]$Port = $(if ($env:CIPP_API_PORT) { [int]$env:CIPP_API_PORT } else { 7071 }),
    [switch]$WorkerOnly,
    [switch]$DebugStartup
)

$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
# Allow unsigned local modules (Linux has no execution policy; Windows dev machines do)
if (($PSVersionTable.PSVersion.Major -ge 6) -and ($env:ProcessScopePolicy -ne 'Set')) {
    $env:ProcessScopePolicy = 'Set'
    try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue } catch { }
}
$RepoRoot = $PSScriptRoot
$BackendRoot = Join-Path $RepoRoot 'backend'

# ─────────────────────────────────────────────────────────────────────────────
# Environment assembly (must happen before profile.ps1 runs)
# ─────────────────────────────────────────────────────────────────────────────
$env:CIPPRootPath = $BackendRoot
# NOTE: must NOT contain a dash - CIPP's node routing parses WEBSITE_SITE_NAME by '-' and
# treats the suffix as a processor node name, which would exclude all cron timers.
$env:WEBSITE_SITE_NAME = $env:WEBSITE_SITE_NAME ?? 'CIPP'
# SQLite storage for the AzTablesShim (Azure connection strings are accepted and ignored)
$env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'
$env:CIPP_SQLITE_DB = $env:CIPP_SQLITE_DB ?? (Join-Path $BackendRoot 'data' 'cipp.db')
New-Item -ItemType Directory -Force -Path (Split-Path $env:CIPP_SQLITE_DB) | Out-Null

if ($WorkerOnly) {
    # Worker process: HTTP entrypoint off, orchestrator entrypoint off so that
    # Start-CIPPOrchestrator routes orchestration input through the queue (SQLite).
    $env:AzureWebJobs_CIPPHttpTrigger_Disabled = 'true'
    $env:AzureWebJobs_CIPPOrchestrator_Disabled = 'true'
    $env:ExternalDurablePowerShellSDK = 'false'
} else {
    # API process: everything except HTTP is off (worker process handles those).
    $env:AzureWebJobs_CIPPQueueTrigger_Disabled = 'true'
    $env:AzureWebJobs_CIPPOrchestrator_Disabled = 'true'
    $env:AzureWebJobs_CIPPActivityFunction_Disabled = 'true'
    $env:AzureWebJobs_CIPPTimer_Disabled = 'true'
    $env:ExternalDurablePowerShellSDK = 'false'
}

# ─────────────────────────────────────────────────────────────────────────────
# Load CIPP runtime (profile imports CIPPCore, CippExtensions, AzTablesShim,
# CippLocalAuth + the worker-type modules) and the entrypoints module.
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[cipp-server] loading CIPP runtime from $BackendRoot ..." -ForegroundColor Cyan
& (Join-Path $BackendRoot 'profile.ps1')
Import-Module (Join-Path $BackendRoot 'Modules' 'CippEntrypoints') -Force -ErrorAction Stop
Write-Host '[cipp-server] CIPP runtime loaded.' -ForegroundColor Cyan

# Azure Functions compatibility types (normally provided by the Functions worker)
if (-not ('System.Net.HttpResponseContext' -as [type])) {
    Add-Type -TypeDefinition @'
namespace System.Net {
    public class HttpResponseContext {
        public System.Net.HttpStatusCode StatusCode { get; set; }
        public object Body { get; set; }
        public System.Collections.Hashtable Headers { get; set; }
        public string ContentType { get; set; }
        public override string ToString() {
            return Body == null ? string.Empty : Body.ToString();
        }
    }
}
'@
}

# ─────────────────────────────────────────────────────────────────────────────
# SQLite-backed queue (replaces Azure Storage Queue / Azurite)
# Message layout: PartitionKey = state ('msg' | 'dead'), RowKey = message id
# VisibleAt gates delivery (retry backoff), DequeueCount bounds attempts.
# ─────────────────────────────────────────────────────────────────────────────
$script:QueueContext = New-AzDataTableContext -ConnectionString 'UseDevelopmentStorage=true' -TableName 'cippqueue'
$null = New-AzDataTable -Context $script:QueueContext

function Add-CippSqliteQueueMessage {
    param(
        [string]$Cmdlet,
        $Parameters = @{},
        [int]$DelaySeconds = 0
    )
    $entity = [PSCustomObject]@{
        PartitionKey = 'msg'
        RowKey       = [guid]::NewGuid().ToString()
        MessageJson  = (@{ Cmdlet = $Cmdlet; Parameters = $Parameters } | ConvertTo-Json -Depth 10 -Compress)
        VisibleAt    = [datetimeoffset]::UtcNow.AddSeconds($DelaySeconds)
        DequeueCount = 0
        InsertedAt   = [datetimeoffset]::UtcNow
    }
    Add-AzDataTableEntity -Context $script:QueueContext -Entity $entity -ErrorAction Stop
}

function Receive-CippSqliteQueueMessage {
    <# Dequeue one visible message, returns entity or $null #>
    param([int]$MaxDequeueCount = 5)
    $cutoff = [datetimeoffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $msg = Get-AzDataTableEntity -Context $script:QueueContext `
        -Filter "PartitionKey eq 'msg' and VisibleAt le datetime'$cutoff'" `
        -Sort @('InsertedAt') -First 1
    if (-not $msg) { return $null }
    if ($msg.DequeueCount -ge $MaxDequeueCount) {
        # dead-letter
        $msg.PartitionKey = 'dead'
        Add-AzDataTableEntity -Context $script:QueueContext -Entity $msg -ErrorAction SilentlyContinue
        Remove-AzDataTableEntity -Context $script:QueueContext -Entity $msg -Force -ErrorAction SilentlyContinue
        Write-Warning "[queue] message $($msg.RowKey) exceeded $MaxDequeueCount attempts - dead-lettered"
        return $null
    }
    return $msg
}

function Complete-CippSqliteQueueMessage {
    param($Message)
    Remove-AzDataTableEntity -Context $script:QueueContext -Entity $Message -Force -ErrorAction SilentlyContinue
}

function Abandon-CippSqliteQueueMessage {
    param($Message)
    $Message.DequeueCount = [int]$Message.DequeueCount + 1
    $backoff = [math]::Min([math]::Pow(2, [int]$Message.DequeueCount) * 15, 900)
    $Message.VisibleAt = [datetimeoffset]::UtcNow.AddSeconds($backoff)
    Update-AzDataTableEntity -Context $script:QueueContext -Entity $Message -Force -ErrorAction SilentlyContinue
}

# ─────────────────────────────────────────────────────────────────────────────
# Azure Functions hosting shims
# ─────────────────────────────────────────────────────────────────────────────
# Push-OutputBinding: HTTP Response -> captured per invocation; QueueItem -> SQLite queue.
function global:Push-OutputBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Value,
        [switch]$Clobber
    )
    if ($Name -eq 'QueueItem') {
        $cmdlet = $Value.Cmdlet
        $parameters = $Value.Parameters
        if ($parameters -isnot [hashtable]) {
            $parameters = @{}
            foreach ($p in $Value.Parameters.PSObject.Properties) { $parameters[$p.Name] = $p.Value }
        }
        Add-CippSqliteQueueMessage -Cmdlet $cmdlet -Parameters $parameters | Out-Null
        return
    }
    if ($Name -eq 'Response') {
        $script:__CIPPResponse = $Value
        return
    }
    # other output bindings are ignored in direct-run mode
}

# Start-NewOrchestration (Durable SDK): replaced with queue-based execution.
# The worker's inline executor runs the orchestration body without the Durable framework.
function global:Start-NewOrchestration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FunctionName,
        [Parameter(Mandatory)][object]$InputObject,
        $InstanceStore,
        $Version,
        $InstanceId
    )
    if (-not $InstanceId) { $InstanceId = [guid]::NewGuid().ToString() }

    # Track instance status in the <sitename>Instances table (mirrors Durable behaviour;
    # Receive-CIPPTimerTrigger checks RuntimeStatus to skip already-running jobs).
    try {
        $InstancesTable = Get-CippTable -TableName ('{0}Instances' -f ($env:WEBSITE_SITE_NAME -replace '-', ''))
        Add-CIPPAzDataTableEntity @InstancesTable -Entity @{
            PartitionKey = $InstanceId
            RowKey       = $InstanceId
            RuntimeStatus = 'Pending'
            CreatedTime  = [datetimeoffset]::UtcNow
            Input        = ([string]$InputObject).Substring(0, [math]::Min(2000, ([string]$InputObject).Length))
        } -Force -ErrorAction SilentlyContinue
    } catch { Write-Warning "[orchestration] failed to track instance: $($_.Exception.Message)" }

    Add-CippSqliteQueueMessage -Cmdlet '__CIPP_DirectOrchestration' -Parameters @{
        InstanceId = $InstanceId
        Input      = [string]$InputObject
    } | Out-Null
    Write-Information "[orchestration] queued '$InstanceId' (input $( ([string]$InputObject).Length ) bytes)"
    return $InstanceId
}

# Inline orchestration executor — mirrors Receive-CippOrchestrationTrigger's
# sequential (NoScaling) branch, but activities run directly instead of via the
# Durable Task framework.
function Invoke-CippInlineOrchestration {
    param([string]$InstanceId, [string]$InputJson)

    $InstancesTable = $null
    try {
        $InstancesTable = Get-CippTable -TableName ('{0}Instances' -f ($env:WEBSITE_SITE_NAME -replace '-', ''))
        $instance = Get-CIPPAzDataTableEntity @InstancesTable -Filter "PartitionKey eq '$InstanceId'" -First 1
        if ($instance) {
            $instance.RuntimeStatus = 'Running'
            Update-AzDataTableEntity @InstancesTable -Entity $instance -Force -ErrorAction SilentlyContinue
        }
    } catch { $InstancesTable = $null }

    $results = @()
    try {
        $OrchestratorInput = if (Test-Json -Json $InputJson) { $InputJson | ConvertFrom-Json } else { $InputJson }
        Write-Information "[orchestration] running $($OrchestratorInput.OrchestratorName ?? 'unnamed') ($InstanceId)"

        $Batch = @()
        if ($OrchestratorInput.Batch) {
            $Batch = @($OrchestratorInput.Batch | Where-Object { $null -ne $_.FunctionName })
        } elseif ($OrchestratorInput.QueueFunction) {
            $built = Receive-CippActivityTrigger -Item $OrchestratorInput.QueueFunction
            $Batch = @($built | Where-Object { $null -ne $_.FunctionName })
        }

        if ($Batch.Count -gt 0) {
            Write-Information "[orchestration] batch count: $($Batch.Count)"
            foreach ($Item in $Batch) {
                try {
                    $out = Receive-CippActivityTrigger -Item $Item
                    if ($out) { $results += $out }
                } catch {
                    Write-Warning "[orchestration] activity '$($Item.FunctionName)' failed: $($_.Exception.Message)"
                }
            }
        } else {
            Write-Information '[orchestration] no activities to execute in batch'
        }

        if ($OrchestratorInput.PostExecution) {
            Write-Information "[orchestration] post execution: $($OrchestratorInput.PostExecution.FunctionName)"
            $PostExecParams = @{
                FunctionName = $OrchestratorInput.PostExecution.FunctionName
            }
            if ($results) { $PostExecParams['Results'] = @($results) }
            if ($OrchestratorInput.PostExecution.Parameters) { $PostExecParams['Parameters'] = $OrchestratorInput.PostExecution.Parameters }
            if ($null -ne $PostExecParams.FunctionName) {
                $null = Receive-CippActivityTrigger -Item ([PSCustomObject]$PostExecParams)
            }
        }
    } catch {
        Write-Information "[orchestration] error: $($_.Exception.Message)"
        if ($InstancesTable) {
            $instance = Get-CIPPAzDataTableEntity @InstancesTable -Filter "PartitionKey eq '$InstanceId'" -First 1
            if ($instance) {
                $instance.RuntimeStatus = 'Failed'
                $instance | Add-Member -MemberType NoteProperty -Name 'CustomStatus' -Value $_.Exception.Message -Force
                Update-AzDataTableEntity @InstancesTable -Entity $instance -Force -ErrorAction SilentlyContinue
            }
        }
        return
    }

    if ($InstancesTable) {
        $instance = Get-CIPPAzDataTableEntity @InstancesTable -Filter "PartitionKey eq '$InstanceId'" -First 1
        if ($instance) {
            $instance.RuntimeStatus = 'Completed'
            Update-AzDataTableEntity @InstancesTable -Entity $instance -Force -ErrorAction SilentlyContinue
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Worker mode: cron timers + queue poller
# ─────────────────────────────────────────────────────────────────────────────
if ($WorkerOnly) {
    $CronosPath = Join-Path $BackendRoot 'Shared' 'Cronos' 'Cronos.dll'
    if (-not ('Cronos.CronExpression' -as [type])) { $null = [System.Reflection.Assembly]::LoadFrom($CronosPath) }

    $TimerFunctions = @(Get-CIPPTimerFunctions | Where-Object { $_.Id -and $_.Command -and $_.Cron })
    $nextRun = @{}
    $now = [datetimeoffset]::UtcNow
    foreach ($fn in $TimerFunctions) {
        try {
            $expr = [Cronos.CronExpression]::Parse($fn.Cron, [Cronos.CronFormat]::IncludeSeconds)
            $nextRun["$($fn.Id)"] = $expr.GetNextOccurrence($now, [TimeZoneInfo]::Utc)
        } catch {
            Write-Warning "[timer] invalid cron '$($fn.Cron)' for $($fn.Command): $($_.Exception.Message)"
            $nextRun["$($fn.Id)"] = $null
        }
    }
    Write-Host "[cipp-worker] watching $($TimerFunctions.Count) timer functions + SQLite queue." -ForegroundColor Cyan

    while ($true) {
        $now = [datetimeoffset]::UtcNow

        # ── timers due ──
        $due = @()
        foreach ($fn in $TimerFunctions) {
            $next = $nextRun["$($fn.Id)"]
            if ($null -ne $next -and $next -le $now) {
                $due += $fn
                try {
                    $expr = [Cronos.CronExpression]::Parse($fn.Cron, [Cronos.CronFormat]::IncludeSeconds)
                    $nextRun["$($fn.Id)"] = $expr.GetNextOccurrence($now.AddSeconds(1), [TimeZoneInfo]::Utc)
                } catch { $nextRun["$($fn.Id)"] = $null }
            }
        }
        if ($due.Count -gt 0) {
            foreach ($fn in $due) {
                Write-Information "[timer] firing $($fn.Command) (cron: $($fn.Cron))"
                try {
                    $null = Receive-CIPPTimerTrigger -Timer @{ ScheduleStatus = @{
                        Period    = 'PT15M'
                        Status    = 'OK'
                        Previous  = $now.AddMinutes(-15).UtcDateTime
                        Next      = $now.AddMinutes(15).UtcDateTime
                        Last      = $now.AddMinutes(-15).UtcDateTime
                        IsPastDue = $false
                    } } -DueFunctions @($fn)
                } catch {
                    Write-Warning "[timer] $($fn.Command) failed: $($_.Exception.Message)"
                }
            }
        }

        # ── queue ──
        try {
            $msg = Receive-CippSqliteQueueMessage
            if ($msg) {
                $queueItem = $msg.MessageJson | ConvertFrom-Json
                if ($queueItem.Cmdlet -eq '__CIPP_DirectOrchestration') {
                    Invoke-CippInlineOrchestration -InputJson ([string]$queueItem.Parameters.Input) -InstanceId $queueItem.Parameters.InstanceId
                    Complete-CippSqliteQueueMessage -Message $msg
                } else {
                    Write-Information "[queue] executing $($queueItem.Cmdlet)"
                    Receive-CippQueueTrigger -QueueItem $queueItem -TriggerMetadata @{ Id = $msg.RowKey; DequeueCount = $msg.DequeueCount }
                    Complete-CippSqliteQueueMessage -Message $msg
                }
            }
        } catch {
            Write-Warning "[queue] processing failed: $($_.Exception.Message)"
            if ($msg) { Abandon-CippSqliteQueueMessage -Message $msg }
        }

        Start-Sleep -Seconds 15
    }
    return
}

# ─────────────────────────────────────────────────────────────────────────────
# API mode: HTTP listener
# ─────────────────────────────────────────────────────────────────────────────
$Prefix = "http://127.0.0.1:$Port/"
if ($env:CIPP_API_BIND -eq 'any') { $Prefix = "http://*:$Port/" }
$Listener = [System.Net.HttpListener]::new()
$Listener.Prefixes.Add($Prefix)
$Listener.Start()
Write-Host "[cipp-api] listening on $Prefix (Caddy/nginx should proxy /api/* here)" -ForegroundColor Green

function ConvertTo-ListenerRequest {
    param($HttpListenerContext)
    $req = $HttpListenerContext.Request
    $url = [uri]$req.Url

    # /api/{CIPPEndpoint}
    $route = $url.AbsolutePath
    if ($route.StartsWith('/api/')) { $route = $route.Substring(5) }
    elseif ($route -eq '/api') { $route = '' }
    else { return $null }

    # headers -> case-insensitive hashtable
    $headers = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $req.Headers.AllKeys) { $headers[$k] = $req.Headers[$k] }

    # query -> case-insensitive hashtable
    $query = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
    $parsedQuery = [System.Web.HttpUtility]::ParseQueryString($url.Query)
    foreach ($k in $parsedQuery.AllKeys) { if ($null -ne $k) { $query[$k] = $parsedQuery[$k] } }

    # body: JSON parsed where possible (matches Azure Functions worker behaviour)
    $bodyText = ''
    if ($req.HasEntityBody) {
        $reader = [System.IO.StreamReader]::new($req.InputStream, $req.ContentEncoding)
        try { $bodyText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    $body = $bodyText
    if ($bodyText) {
        try { $body = $bodyText | ConvertFrom-Json -Depth 100 } catch { $body = $bodyText }
    }

    [PSCustomObject]@{
        Method  = $req.HttpMethod
        Url     = $url.AbsoluteUri
        Headers = $headers
        Query   = $query
        Params  = @{ CIPPEndpoint = $route }
        Body    = $body
    }
}

function Send-ListenerResponse {
    param($HttpListenerContext, $Response)
    $res = $HttpListenerContext.Response
    $statusCode = if ($Response.StatusCode -is [System.Net.HttpStatusCode]) { [int]$Response.StatusCode } else { [int]($Response.StatusCode ?? 500) }
    $res.StatusCode = $statusCode

    $contentType = 'application/json; charset=utf-8'
    if ($Response.Headers) {
        foreach ($p in $Response.Headers.PSObject.Properties) {
            if ($p.Name -ieq 'Content-Type') {
                $contentType = "$($p.Value)"
                continue
            }
            try { $res.Headers[$p.Name] = "$($p.Value)" } catch { }
        }
    }

    $body = $Response.Body
    if ($body -is [string]) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    } else {
        $json = $body | ConvertTo-Json -Depth 20 -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    }
    $res.ContentType = $contentType
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.OutputStream.Close()
}

Write-Host "[cipp-api] CIPP API ready - http://127.0.0.1:$Port/api/" -ForegroundColor Green
while ($Listener.IsListening) {
    try { $ctx = $Listener.GetContext() } catch { break }

    try {
        $request = ConvertTo-ListenerRequest -HttpListenerContext $ctx
        if ($null -eq $request) {
            Send-ListenerResponse -HttpListenerContext $ctx -Response @{
                StatusCode = [System.Net.HttpStatusCode]::NotFound
                Body       = @{ error = @{ message = "Only /api/* routes are served here" } }
            }
            continue
        }

        Write-Host "[api] $($request.Method) /api/$($request.Params.CIPPEndpoint)" -ForegroundColor DarkGray
        $script:__CIPPResponse = $null
        $triggerMeta = @{ TriggerName = 'CIPPHttpTrigger'; Sys = 'direct-run' }

        $null = Receive-CippHttpTrigger -Request $request -TriggerMetadata $triggerMeta 2>&1

        $response = $script:__CIPPResponse
        if (-not $response) {
            $response = @{
                StatusCode = [System.Net.HttpStatusCode]::InternalServerError
                Body       = @{ error = @{ message = 'No response produced by the API' } }
            }
        }
        Send-ListenerResponse -HttpListenerContext $ctx -Response $response
    } catch {
        Write-Warning "[api] request failed: $($_.Exception.Message)"
        try {
            Send-ListenerResponse -HttpListenerContext $ctx -Response @{
                StatusCode = [System.Net.HttpStatusCode]::InternalServerError
                Body       = @{ error = @{ message = $_.Exception.Message } }
            }
        } catch { }
    }
}

try { $Listener.Stop(); $Listener.Close() } catch { }
