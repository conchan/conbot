#!/usr/bin/env bash
# =============================================================================
# 01-proxmox-post-install.sh
# Run this in the Proxmox Shell (Node → Shell) immediately after first boot.
# What it does:
#   - Disables the enterprise (paid) repo nag
#   - Enables the free community (no-subscription) repo
#   - Runs a full system upgrade
#   - Optionally installs useful CLI tools
# =============================================================================
set -euo pipefail

# --- Colors for output -------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Root check --------------------------------------------------------------
[[ $EUID -ne 0 ]] && error "Run this script as root (you should be in the Proxmox shell already)."

# --- 1. Disable enterprise repo ----------------------------------------------
info "Disabling enterprise (subscription) repository..."
ENTERPRISE_LIST="/etc/apt/sources.list.d/pve-enterprise.list"
if [[ -f "$ENTERPRISE_LIST" ]]; then
  sed -i 's|^deb https://enterprise.proxmox.com|#deb https://enterprise.proxmox.com|g' "$ENTERPRISE_LIST"
  info "Enterprise repo commented out."
else
  warn "Enterprise list not found — skipping."
fi

# Also disable Ceph enterprise repo if present
CEPH_LIST="/etc/apt/sources.list.d/ceph.list"
if [[ -f "$CEPH_LIST" ]]; then
  sed -i 's|^deb https://enterprise.proxmox.com|#deb https://enterprise.proxmox.com|g' "$CEPH_LIST"
fi

# --- 2. Enable community (no-subscription) repo ------------------------------
info "Adding community (no-subscription) repository..."
COMMUNITY_LIST="/etc/apt/sources.list.d/pve-community.list"
if ! grep -q "pve-no-subscription" "$COMMUNITY_LIST" 2>/dev/null; then
  echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
    > "$COMMUNITY_LIST"
  info "Community repo added."
else
  info "Community repo already present — skipping."
fi

# --- 3. Update & upgrade -----------------------------------------------------
info "Running apt update + dist-upgrade (this may take a few minutes)..."
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -q
info "System fully upgraded."

# --- 4. Install handy CLI tools ----------------------------------------------
info "Installing optional but useful CLI tools..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
  curl wget git htop iotop net-tools lsb-release \
  ca-certificates gnupg unzip jq

info "Done. Review the output above, then reboot the node:"
echo ""
echo "  Node → Reboot   (in the Proxmox web UI)"
echo "  — or —"
echo "  reboot          (from this shell)"
echo ""
info "After reboot, proceed to: 02-create-ai-lxc.sh (run inside a new Ubuntu LXC container)"
