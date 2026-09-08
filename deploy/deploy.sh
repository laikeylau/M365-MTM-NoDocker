#!/bin/bash
# ============================================
# CIPP Linux Deployment Script
# ============================================
# Deploys CIPP on a Linux VM using Docker Compose
#
# Prerequisites:
# - Docker & Docker Compose installed
# - CIPP repo cloned: git clone https://github.com/laikeylau/CIPP
# - CIPP-Linux placed at: CIPP/CIPP-Linux/
# - .env configured with your credentials
#
# Directory structure expected:
#   CIPP/
#   ├── CIPP-API/
#   ├── CIPP-Frontend/
#   └── CIPP-Linux/       ← you are here
# ============================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CIPP_API_DIR="$PROJECT_ROOT/CIPP-API"
CIPP_FRONTEND_DIR="$PROJECT_ROOT/CIPP-Frontend"

echo "============================================"
echo "  CIPP Linux Deployment"
echo "============================================"
echo ""

# ============================================
# Step 1: Verify prerequisites
# ============================================
echo "[1/6] Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker not found. Install it first:"
    echo "  curl -fsSL https://get.docker.com | sh"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "ERROR: Docker Compose not found."
    exit 1
fi

echo "  ✓ Docker and Docker Compose installed"

# ============================================
# Step 2: Verify directory structure
# ============================================
echo "[2/6] Verifying directory structure..."

if [ ! -d "$CIPP_API_DIR" ]; then
    echo "ERROR: CIPP-API not found at $CIPP_API_DIR"
    echo "Expected structure:"
    echo "  CIPP/"
    echo "  ├── CIPP-API/"
    echo "  ├── CIPP-Frontend/"
    echo "  └── CIPP-Linux/"
    exit 1
fi

if [ ! -d "$CIPP_FRONTEND_DIR" ]; then
    echo "ERROR: CIPP-Frontend not found at $CIPP_FRONTEND_DIR"
    exit 1
fi

echo "  ✓ CIPP-API: $CIPP_API_DIR"
echo "  ✓ CIPP-Frontend: $CIPP_FRONTEND_DIR"

# ============================================
# Step 3: Check .env file
# ============================================
echo "[3/6] Checking .env file..."

if [ ! -f "$SCRIPT_DIR/.env" ]; then
    if [ -f "$SCRIPT_DIR/.env.example" ]; then
        echo "  ⚠ .env not found. Copying from .env.example..."
        cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
        echo "  ⚠ IMPORTANT: Edit .env with your actual credentials before continuing!"
        echo "  Then re-run this script."
        exit 1
    else
        echo "  ERROR: No .env or .env.example found!"
        exit 1
    fi
fi

# Source .env to check required vars
source "$SCRIPT_DIR/.env"
if [ -z "$APPLICATIONID" ] || [ -z "$APPLICATIONSECRET" ] || [ -z "$REFRESHTOKEN" ]; then
    echo "  ⚠ .env is missing required credentials."
    echo "  Required: APPLICATIONID, APPLICATIONSECRET, REFRESHTOKEN"
    echo "  Edit $SCRIPT_DIR/.env and try again."
    exit 1
fi

echo "  ✓ .env configured"

# ============================================
# Step 4: Apply patches (local auth)
# ============================================
echo "[4/6] Applying local authentication patches..."

if [ -f "$SCRIPT_DIR/apply-patches.sh" ]; then
    bash "$SCRIPT_DIR/apply-patches.sh"
else
    echo "  ⚠ apply-patches.sh not found, skipping"
fi

# ============================================
# Step 5: Build frontend
# ============================================
echo "[5/6] Building frontend..."

if [ -d "$CIPP_FRONTEND_DIR" ]; then
    cd "$CIPP_FRONTEND_DIR"
    if [ ! -d "node_modules" ]; then
        echo "  Installing dependencies..."
        npm install --legacy-peer-deps 2>&1 | tail -3
    fi
    echo "  Building..."
    npm run build 2>&1 | tail -5
    echo "  ✓ Frontend built"
    cd "$SCRIPT_DIR"
else
    echo "  ⚠ CIPP-Frontend not found, skipping build"
fi

# Copy frontend build output
if [ -d "$CIPP_FRONTEND_DIR/out" ]; then
    mkdir -p "$SCRIPT_DIR/frontend-dist"
    cp -r "$CIPP_FRONTEND_DIR/out/"* "$SCRIPT_DIR/frontend-dist/"
    echo "  ✓ Frontend assets copied to frontend-dist/"
fi

# ============================================
# Step 6: Deploy with Docker Compose
# ============================================
echo "[6/6] Starting Docker Compose..."

cd "$SCRIPT_DIR"

# Check if Dockerfile exists for CIPP-API
if [ ! -f "$CIPP_API_DIR/Dockerfile" ]; then
    echo "  ⚠ CIPP-API/Dockerfile not found!"
    echo "  You may need to create one. See MIGRATION-GUIDE.md for details."
    echo "  Attempting to continue..."
fi

docker compose up -d --build

echo ""
echo "============================================"
echo "  Deployment Complete!"
echo "============================================"
echo ""
echo "  Services starting..."
echo "  Wait 1-2 minutes for the API to initialize."
echo ""
echo "  Access CIPP at: http://localhost"
echo ""
echo "  First-time setup:"
echo "  1. Open http://localhost"
echo "  2. Go to Register tab → create your admin account"
echo "  3. First user automatically gets admin role"
echo ""
echo "  Useful commands:"
echo "  docker compose logs -f          # View logs"
echo "  docker compose restart cippapi  # Restart API"
echo "  docker compose down             # Stop all"
echo ""
echo "============================================"
