#!/usr/bin/env bash
# M365-MTM one-shot installer
# Requires: Linux + PowerShell 7 (pwsh). Everything else is bundled:
#   - Storage: SQLite (AzTablesShim), no Azurite / Docker
#   - API: cipp-server.ps1 (PowerShell direct-run host, port 7071)
#   - Worker: cipp-server.ps1 -WorkerOnly (cron timers + SQLite queue)
#   - Web: Caddy serves frontend-dist/ and proxies /api/*
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="$REPO_ROOT/backend"
DATA_DIR="$BACKEND/data"
SYSTEMD_DIR=/etc/systemd/system
INSTALL_ROOT="${M365_MTM_INSTALL_ROOT:-/opt/M365-MTM}"
RUN_CADDY="${M365_MTM_RUN_CADDY:-auto}"   # auto|yes|no
DOMAIN="${M365_MTM_DOMAIN:-}"

log()  { printf '\033[1;36m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*"; exit 1; }

log "M365-MTM installer - repo: $REPO_ROOT"

# ── 1. PowerShell 7 ──────────────────────────────────────────────────────────
if ! command -v pwsh >/dev/null 2>&1; then
    log "pwsh not found - installing PowerShell 7"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq wget apt-transport-https software-properties-common
        wget -q https://packages.microsoft.com/config/ubuntu/$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
        dpkg -i /tmp/packages-microsoft-prod.deb && apt-get update -qq && apt-get install -y -qq powershell
    else
        fail "pwsh missing and automatic install supports apt only. Install PowerShell 7 manually: https://aka.ms/powershell"
    fi
fi
PWASH_VER=$(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()')
log "PowerShell $PWASH_VER OK"

# ── 2. Layout: move/copy repo to INSTALL_ROOT if needed ─────────────────────
if [ "$(realpath "$REPO_ROOT")" != "$INSTALL_ROOT" ]; then
    if [ ! -d "$INSTALL_ROOT" ]; then
        log "Installing to $INSTALL_ROOT"
        mkdir -p "$(dirname "$INSTALL_ROOT")"
        cp -a "$REPO_ROOT" "$INSTALL_ROOT"
        REPO_ROOT="$INSTALL_ROOT"
        BACKEND="$REPO_ROOT/backend"
        DATA_DIR="$BACKEND/data"
    else
        log "Using existing $INSTALL_ROOT (repo copy skipped)"
        REPO_ROOT="$INSTALL_ROOT"; BACKEND="$REPO_ROOT/backend"; DATA_DIR="$BACKEND/data"
    fi
fi

# ── 3. SQLite initialisation + module smoke test ─────────────────────────────
log "Initialising SQLite storage ($DATA_DIR/cipp.db)"
mkdir -p "$DATA_DIR"
pwsh -NoProfile -File "$REPO_ROOT/cipp-server.ps1" -Port 7079 > /tmp/cipp-install-smoke.log 2>&1 &
SMOKE_PID=$!
sleep 45
if kill -0 "$SMOKE_PID" 2>/dev/null; then
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:7079/api/ListTenants" || true)
    kill "$SMOKE_PID" 2>/dev/null || true
    wait "$SMOKE_PID" 2>/dev/null || true
    if [ "$HTTP_CODE" != "000" ] && [ -n "$HTTP_CODE" ]; then
        log "API smoke test OK (HTTP $HTTP_CODE)"
    else
        warn "API smoke test returned no response - check /tmp/cipp-install-smoke.log"
    fi
else
    warn "API smoke process exited early - check /tmp/cipp-install-smoke.log"
fi

# ── 4. systemd units ─────────────────────────────────────────────────────────
if [ -d /etc/systemd/system ]; then
    log "Installing systemd units (cipp-api, cipp-worker)"
    sed -e "s#/opt/M365-MTM#$REPO_ROOT#g" "$REPO_ROOT/deploy/systemd/cipp-api.service"    > "$SYSTEMD_DIR/cipp-api.service"
    sed -e "s#/opt/M365-MTM#$REPO_ROOT#g" "$REPO_ROOT/deploy/systemd/cipp-worker.service" > "$SYSTEMD_DIR/cipp-worker.service"
    sed -i "s#User=root#User=$(whoami)#" "$SYSTEMD_DIR/cipp-api.service" "$SYSTEMD_DIR/cipp-worker.service"
    systemctl daemon-reload
    systemctl enable --now cipp-api.service cipp-worker.service
    sleep 3
    systemctl --no-pager --lines 3 status cipp-api.service || warn "cipp-api not healthy yet (journalctl -u cipp-api)"
else
    warn "systemd not available - start manually:"
    warn "  pwsh -File $REPO_ROOT/cipp-server.ps1 &"
    warn "  pwsh -File $REPO_ROOT/cipp-server.ps1 -WorkerOnly &"
fi

# ── 5. Caddy (web tier) ──────────────────────────────────────────────────────
if [ "$RUN_CADDY" != "no" ] && ! command -v caddy >/dev/null 2>&1; then
    log "Installing Caddy"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/deb/gpg.key' | gpg --batch --yes --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
        curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/deb/debian.data' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
        apt-get update -qq && apt-get install -y -qq caddy
    else
        warn "Caddy not installed automatically - install from https://caddyserver.com"
    fi
fi
if command -v caddy >/dev/null 2>&1 && [ "$RUN_CADDY" != "no" ]; then
    log "Configuring Caddy"
    mkdir -p "$REPO_ROOT/frontend-dist"
    [ -f "$REPO_ROOT/frontend-dist/index.html" ] || warn "frontend-dist/ is empty - the web UI will 404 until a frontend build is copied there"
    export M365_MTM_CADDY_CONFIG="$REPO_ROOT/deploy/Caddyfile"
    if [ -n "$DOMAIN" ]; then
        printf 'DOMAIN=%s\n' "$DOMAIN" > /etc/caddy/cipp.env 2>/dev/null || printf 'DOMAIN=%s\n' "$DOMAIN" > "$REPO_ROOT/deploy/caddy.env"
    fi
    (cd "$REPO_ROOT" && caddy validate --config "$REPO_ROOT/deploy/Caddyfile" --adapter caddyfile 2>/dev/null) \
        && log "Caddyfile valid" \
        || warn "Caddyfile validation failed - adjust $REPO_ROOT/deploy/Caddyfile (DOMAIN / rate_limit plugin)"
    if [ -d /etc/caddy ]; then
        cp "$REPO_ROOT/deploy/Caddyfile" /etc/caddy/Caddyfile
        systemctl restart caddy 2>/dev/null || warn "caddy restart failed"
    else
        warn "Start Caddy manually: caddy run --config $REPO_ROOT/deploy/Caddyfile"
    fi
fi

# ── 6. Done ──────────────────────────────────────────────────────────────────
log "Installation complete."
log "  API:    http://127.0.0.1:7071/api/  (systemd: cipp-api)"
log "  Worker: cron timers + SQLite queue   (systemd: cipp-worker)"
log "  Web:    Caddy -> http(s)://<host>/   (frontend-dist/)"
log "Next steps:"
log "  1. Open https://<your-domain> and register the first local account."
log "  2. Add tenants (scripts/Add-DirectTenant.ps1 or the web UI)."
[ -n "$DOMAIN" ] && log "  Set M365_MTM_DOMAIN and CADDY_EMAIL env vars for automatic HTTPS."
