#!/usr/bin/env bash
# =============================================================================
# 05-wireguard-lxc-harden.sh
# Run this INSIDE the WireGuard LXC container (created via the Proxmox
# community script: bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/ct/wireguard.sh)")
#
# What it does:
#   - Enables IP forwarding permanently
#   - Sets up iptables NAT/forwarding rules for WireGuard
#   - Persists iptables rules across reboots
#   - Prints reminder for the Proxmox TUN device config and router port forward
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}══════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════${NC}"; }

[[ $EUID -ne 0 ]] && error "Run as root inside the WireGuard LXC container."

# --- Auto-detect the outbound NIC (usually eth0) ----------------------------
OUTBOUND_NIC=$(ip route | awk '/^default/ {print $5; exit}')
[[ -z "$OUTBOUND_NIC" ]] && error "Could not detect outbound network interface. Set OUTBOUND_NIC manually."
info "Detected outbound NIC: $OUTBOUND_NIC"

WG_INTERFACE="${WG_INTERFACE:-wg0}"

# =============================================================================
section "Step 1: Enable IP Forwarding"
# =============================================================================
info "Enabling IPv4 forwarding..."
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi
sysctl -p -q
info "IP forwarding active."

# =============================================================================
section "Step 2: Configure iptables Rules"
# =============================================================================
info "Adding iptables forwarding and NAT rules for $WG_INTERFACE → $OUTBOUND_NIC..."

# Avoid duplicate rules
iptables -C FORWARD -i "$WG_INTERFACE" -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -i "$WG_INTERFACE" -j ACCEPT

iptables -C FORWARD -o "$WG_INTERFACE" -j ACCEPT 2>/dev/null || \
  iptables -A FORWARD -o "$WG_INTERFACE" -j ACCEPT

iptables -t nat -C POSTROUTING -o "$OUTBOUND_NIC" -j MASQUERADE 2>/dev/null || \
  iptables -t nat -A POSTROUTING -o "$OUTBOUND_NIC" -j MASQUERADE

info "iptables rules applied."

# =============================================================================
section "Step 3: Persist iptables Rules"
# =============================================================================
info "Installing iptables-persistent to survive reboots..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -q iptables-persistent
netfilter-persistent save
info "Rules saved."

# =============================================================================
section "Setup Complete — Remaining Manual Steps"
# =============================================================================
CONTAINER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo -e "${GREEN}WireGuard LXC is hardened.${NC}"
echo ""
echo "  ⚠  IMPORTANT — two manual steps remain:"
echo ""
echo "  ── A. Enable TUN device in Proxmox (run in Proxmox Shell, not here) ──"
echo "  Replace '102' below with your actual WireGuard container ID:"
echo ""
echo "    CT_ID=102"
echo "    echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> /etc/pve/lxc/\${CT_ID}.conf"
echo "    echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file' >> /etc/pve/lxc/\${CT_ID}.conf"
echo "    pct reboot \${CT_ID}"
echo ""
echo "  ── B. Open port 51820 UDP on your router ────────────────────────────"
echo "  Create a port forwarding rule:"
echo "    External: UDP 51820  →  Internal: ${CONTAINER_IP}:51820"
echo "  This is the ONLY port you need to open for the entire setup."
echo ""
echo "  ── C. Configure WireGuard via WGDashboard ───────────────────────────"
echo "  Open: http://${CONTAINER_IP}:10086"
echo "  Default login: admin / admin  ← CHANGE THIS IMMEDIATELY"
echo "  Create interface wg0, listen port 51820, VPN subnet 10.10.0.0/24"
echo ""
echo "  ── D. Add clients ───────────────────────────────────────────────────"
echo "  For each device: Add Peer → set Allowed IPs to 192.168.1.0/24,10.10.0.0/24"
echo "  Scan the QR code with the WireGuard app on iPhone/Android"
echo "  Mac: import the .conf file via the WireGuard app"
echo ""
echo "  ── E. Set DDNS hostname as endpoint ─────────────────────────────────"
echo "  In each client config, ensure [Peer] Endpoint = myhome.duckdns.org:51820"
echo "  (use DuckDNS or no-ip.com to keep hostname pointing at your dynamic IP)"
echo ""
