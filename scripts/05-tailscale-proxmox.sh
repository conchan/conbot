#!/usr/bin/env bash
# =============================================================================
# 04-tailscale-proxmox.sh
# Run this in the Proxmox Shell to install Tailscale on the HOST node.
# This makes your entire home subnet (192.168.1.0/24) reachable via Tailscale
# from anywhere — no ports opened on your router.
#
# Prerequisites:
#   - A Tailscale account (free at https://tailscale.com)
#   - Know your home subnet (default: 192.168.1.0/24)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}══════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════${NC}"; }

[[ $EUID -ne 0 ]] && error "Run as root in the Proxmox shell."

# --- Configurable -----------------------------------------------------------
# Your home LAN subnet. Change this if your router uses a different range.
HOME_SUBNET="${HOME_SUBNET:-192.168.1.0/24}"

# =============================================================================
section "Step 1: Install Tailscale"
# =============================================================================
if command -v tailscale &>/dev/null; then
  info "Tailscale already installed ($(tailscale version | head -1)) — skipping install."
else
  info "Downloading and running Tailscale installer..."
  curl -fsSL https://tailscale.com/install.sh | sh
  info "Tailscale installed."
fi

# =============================================================================
section "Step 2: Enable IP Forwarding (required for subnet routing)"
# =============================================================================
info "Enabling IPv4 forwarding..."
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
if ! grep -q "^net.ipv6.conf.all.forwarding=1" /etc/sysctl.conf; then
  echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
fi
sysctl -p -q
info "IP forwarding enabled."

# =============================================================================
section "Step 3: Bring Tailscale Up"
# =============================================================================
info "Starting Tailscale and advertising your home subnet ($HOME_SUBNET)..."
info "You will be given an authentication URL — open it in any browser and log in."
echo ""

tailscale up \
  --advertise-routes="$HOME_SUBNET" \
  --accept-dns=false

# =============================================================================
section "Step 4: Post-Connect Instructions"
# =============================================================================
TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
echo ""
info "Tailscale is connected. Proxmox Tailscale IP: ${TS_IP}"
echo ""
echo "  ⚠  IMPORTANT — complete these steps in the Tailscale admin console:"
echo "  https://login.tailscale.com/admin/machines"
echo ""
echo "  1. Find this machine (Proxmox host)"
echo "  2. Click '...' → 'Edit route settings'"
echo "  3. Approve the advertised route: $HOME_SUBNET"
echo "     Without this, your other devices won't see your home network."
echo ""
echo "  4. On each client device (iPhone, Mac), install Tailscale:"
echo "     iPhone/iPad: App Store → Tailscale"
echo "     Mac:         https://tailscale.com/download"
echo "     Log in with the same account."
echo ""
echo "  5. Install the Tailscale add-on inside Home Assistant:"
echo "     Settings → Add-ons → Add-on Store → search 'Tailscale' → Install → Start"
echo "     Open the add-on logs and click the authentication link."
echo ""
echo "  After setup, reach Home Assistant from anywhere via your Tailscale hostname:"
echo "  e.g. http://homeassistant.tail1234.ts.net:8123"
echo ""
echo "  To enable HTTPS for Open WebUI (required for browser microphone access),"
echo "  run inside the AI LXC container shell:"
echo "  tailscale serve --bg --https=443 http://localhost:3000"
echo ""
