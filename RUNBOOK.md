# CIPP Linux GDAP Deployment — Runbook

## Overview

This runbook documents the complete deployment and configuration of CIPP (CyberDrain Improved Partner Portal) on Linux with GDAP (Granular Delegated Admin Privileges) mode.

**Environment:**
- Server: Ubuntu 22.04 arm64
- Domain: `mtm.cxty.de` (Cloudflare proxy)
- CIPP-SAM AppId: `98779b37-04c7-4714-887a-0c3bae41cb82`
- CIPP-Linux: `/opt/M365-MTM/CIPP-Linux/`
- CIPP-API: `/opt/M365-MTM/CIPP-API/`

---

## Architecture

```
Client → Cloudflare (HTTPS) → nginx (:443) → CIPP-Linux frontend
                                              ↓ API proxy
                                         cipp-server.ps1 (:7071)
                                              ↓
                                         Azurite (Table/Blob/Queue :10000-10002)
                                              ↓
                                         Microsoft Graph / Exchange Online
```

**Key limitation:** The orchestrator (`AzureWebJobs_CIPPOrchestrator`) is disabled on Linux. Queue-based tasks (DB cache sync, scheduled jobs) do NOT auto-execute. Must call `Set-CIPPDBCache*` functions directly via PowerShell.

---

## Critical: AsApp Parameter for GDAP Mode

**Root cause of most EXO failures:** CIPP's `New-ExoRequest` function defaults to delegated (refresh_token) auth mode. In GDAP mode on Linux, there is no valid refresh_token — only client_credentials (app-only) works.

**Fix:** Every `New-ExoRequest` call MUST include `AsApp = $true` (splatting) or `-AsApp` (inline).

### Files that were patched (103 total):

**DBCache functions (20 files):**
- `Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheMailboxes.ps1` — splatting style
- `Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheCASMailboxes.ps1` — inline style
- + 18 other EXO-related cache functions

**HTTP functions (83 files):**
- All `Email-Exchange/*` endpoints
- All `Security/Safe-Links-Policy/*` endpoints
- All `Identity/Administration/*` endpoints
- `CIPP/Settings/Invoke-ExecExchangeRoleRepair.ps1`

### How to find missing AsApp in future:

```bash
# Find all files with New-ExoRequest but no AsApp
cd /opt/M365-MTM/CIPP-API
grep -rl "New-ExoRequest" Modules/ | while read f; do
    grep -qL "AsApp" "$f" && echo "MISSING: $f"
done
```

### Bulk fix script:

```python
import os, re

for root, dirs, files in os.walk("Modules/"):
    for fname in files:
        if not fname.endswith(".ps1"):
            continue
        fpath = os.path.join(root, fname)
        with open(fpath, 'r') as f:
            content = f.read()
        if "New-ExoRequest" not in content or "AsApp" in content:
            continue
        # Fix splatting: add AsApp = $true to hashtable
        for var in re.findall(r'New-ExoRequest\s+@(\w+)', content):
            pat = rf'(\${var}\s*=\s*@{{)([^}}]*?)(\s*}})'
            content = re.sub(pat, lambda m: m.group(1)+m.group(2)+'\n            AsApp     = $true'+m.group(3), content, flags=re.DOTALL)
        # Fix inline: add -AsApp to New-ExoRequest calls
        content = re.sub(r"(New-ExoRequest\s+[^|\n]*?)(\s*\||\s*$)",
            lambda m: m.group(1)+" -AsApp"+m.group(2) if "-AsApp" not in m.group(0) else m.group(0),
            content, flags=re.MULTILINE)
        with open(fpath, 'w') as f:
            f.write(content)
        print(f"Fixed: {fpath}")
```

---

## Tenant Onboarding Checklist

For each new tenant:

### 1. Add tenant to CIPP via GDAP relationship
- Create GDAP relationship in Partner Center
- Assign security groups for required roles
- Wait for relationship to activate

### 2. Assign Exchange Administrator role to CIPP-SAM

```powershell
# See scripts/Onboard-CIPPTenant.ps1 for full automation
$SpId = (Get service principal for CIPP-SAM in customer tenant).id
$DirRoleId = (Get Exchange Administrator directory role).id
# Add CIPP-SAM as member of Exchange Administrator role
```

Required directory roles for full functionality:
- **Exchange Administrator** — for all EXO management (mailbox, transport, spam, etc.)
- **User Administrator** — for user/group management (if needed)
- **Intune Administrator** — for device management (if needed)

### 3. CPV Admin Consent
Open in browser (as Global Admin of customer tenant):
```
https://login.microsoftonline.com/{TENANT_ID}/adminconsent?client_id=98779b37-04c7-4714-887a-0c3bae41cb82&redirect_uri=https://mtm.cxty.de/authredirect
```

### 4. Set tenant to GDAP mode
In Azurite table storage, set `delegatedPrivilegeStatus` to `granularDelegatedAdminPrivileges` for the tenant.

### 5. Sync mailbox cache (Linux only — orchestrator disabled)
```powershell
# Direct call — NOT via API (queue won't process)
$env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNoBnZf6KgBVU4=;...'
$env:CIPPRootPath = '/opt/M365-MTM/CIPP-API'
$env:DisableCIPPRestMethod = 'true'
Import-Module /opt/M365-MTM/CIPP-API/Modules/CIPPDB -Force
Import-Module /opt/M365-MTM/CIPP-API/Modules/CIPPCore -Force
Set-CIPPDBCacheMailboxes -TenantFilter 'contoso.onmicrosoft.com'
```

Or use the automated script:
```bash
cd /opt/M365-MTM/scripts
pwsh ./Onboard-CIPPTenant.ps1 -TenantDomain 'contoso.onmicrosoft.com'
```

### 6. Verify
```bash
curl -s "http://localhost:7071/api/ListMailboxes?TenantFilter=contoso.onmicrosoft.com&UseReportDB=true"
```

---

## Environment Variables

Set in `/opt/M365-MTM/CIPP-Linux/.env`:
```bash
APPLICATIONSECRET=***
DisableCIPPRestMethod=true   # CRITICAL: avoids .NET HttpClient compression issue
```

Set in `cipp-server.ps1`:
```powershell
$env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM02xNoBnZf6KgBVU4=;...'
$env:AzureWebJobs_CIPPOrchestrator_Disabled = 'true'
$env:NonLocalHostAzurite = 'true'
```

---

## Known Issues & Workarounds

| Issue | Cause | Workaround |
|-------|-------|------------|
| `AADSTS65001` on EXO calls | Missing `AsApp` parameter | Add `AsApp = $true` to all `New-ExoRequest` calls |
| `unsupported compression method` | .NET HttpClient compression | Set `DisableCIPPRestMethod=true` |
| Queue stuck at "Queued" | Orchestrator disabled on Linux | Call `Set-CIPPDBCache*` directly |
| `403 Forbidden` on contacts/other EXO | Missing Exchange Administrator role | Assign role via Graph API |
| `No mailbox data in reporting database` | Cache never synced | Run direct sync (see step 5 above) |

---

## CIPP API Server Management

### Start
```bash
cd /opt/M365-MTM/CIPP-API && DisableCIPPRestMethod=true pwsh -File ./cipp-server.ps1
```

### Restart
```bash
pkill -f "cipp-server.ps1"
sleep 2
cd /opt/M365-MTM/CIPP-API && DisableCIPPRestMethod=true pwsh -File ./cipp-server.ps1
```

### Check status
```bash
pgrep -f "cipp-server.ps1"
curl -s -w "%{http_code}" "http://localhost:7071/api/ListTenants"
```

### View logs
```bash
# Check process output via /proc/PID/fd/1
# Or check /tmp/cipp-server.log if started with redirection
```

---

## Frontend Build (if needed)

```bash
cd /opt/M365-MTM/CIPP-Linux
npm run build
cp -r out/* /opt/M365-MTM/CIPP-Linux/frontend-dist/
docker restart cipp-nginx
```

---

## Useful API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/ListTenants` | List all tenants |
| `GET /api/ListMailboxes?TenantFilter=X&UseReportDB=true` | Mailboxes from report DB |
| `GET /api/ListMailboxes?TenantFilter=X` | Mailboxes live from EXO |
| `POST /api/ExecCIPPDBCache?Name=Mailboxes&TenantFilter=X` | Trigger mailbox cache sync |
| `GET /api/ListCippQueue` | Check queue status |
| `GET /api/ListUsers?TenantFilter=X` | List users |
| `GET /api/ListGroups?TenantFilter=X` | List groups |
