#!/usr/bin/env bash
# =============================================================================
# 07-matter-prereq-check.sh
# Run this in the Proxmox Shell BEFORE setting up Matter in Home Assistant.
#
# What it does:
#   - Confirms IPv6 is enabled and routable on the Proxmox host
#   - Confirms the HAOS VM is reachable on the network
#   - Checks that multicast traffic is not being blocked by the Linux bridge
#   - Prints a summary of what passed/failed and what to fix before proceeding
#
# Why this matters:
#   Matter (and Thread) rely on IPv6 multicast to discover and communicate with
#   devices. If IPv6 is disabled or multicast is filtered on your network bridge,
#   Matter commissioning will silently fail. This script catches those issues
#   before you spend time troubleshooting in the HA UI.
#
# Prerequisites:
#   - Run AFTER Part 2 (HAOS VM is up and has a network address)
#   - Run in the Proxmox Shell (Node → Shell)
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${GREEN}[PASS]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()    { echo -e "${RED}[FAIL]${NC}  $*"; FAILURES=$((FAILURES+1)); }
section() { echo -e "\n${CYAN}── $* ──${NC}"; }

FAILURES=0

# --- Configurable -----------------------------------------------------------
HA_IP="${HA_IP:-192.168.1.100}"   # Your Home Assistant IP — set as env var to override
BRIDGE="${BRIDGE:-vmbr0}"         # Proxmox bridge interface name

# =============================================================================
section "Check 1: IPv6 enabled on Proxmox host"
# =============================================================================
if sysctl net.ipv6.conf.all.disable_ipv6 2>/dev/null | grep -q "= 0"; then
  info "IPv6 is enabled on this host."
else
  fail "IPv6 is disabled on this host."
  echo "     Fix: Run: sysctl -w net.ipv6.conf.all.disable_ipv6=0"
  echo "     To persist: add 'net.ipv6.conf.all.disable_ipv6=0' to /etc/sysctl.conf"
fi

# =============================================================================
section "Check 2: IPv6 link-local address on the bridge"
# =============================================================================
IPV6_ADDR=$(ip -6 addr show dev "$BRIDGE" scope link 2>/dev/null | awk '/inet6/{print $2}' | head -1)
if [[ -n "$IPV6_ADDR" ]]; then
  info "Bridge $BRIDGE has IPv6 link-local address: $IPV6_ADDR"
else
  fail "Bridge $BRIDGE has no IPv6 link-local address."
  echo "     Fix: Ensure IPv6 is not disabled for $BRIDGE specifically."
  echo "     Run: sysctl -w net.ipv6.conf.${BRIDGE}.disable_ipv6=0"
fi

# =============================================================================
section "Check 3: Multicast snooping on the bridge"
# =============================================================================
# Matter uses IPv6 multicast (ff02::/16). If multicast_snooping is enabled on
# the Proxmox bridge, it can silently drop Thread/Matter multicast unless the
# bridge has an IGMP/MLD querier. Disabling it is the safest option for a
# single-subnet home network.
SNOOP_FILE="/sys/class/net/${BRIDGE}/bridge/multicast_snooping"
if [[ -f "$SNOOP_FILE" ]]; then
  SNOOP_VAL=$(cat "$SNOOP_FILE")
  if [[ "$SNOOP_VAL" == "0" ]]; then
    info "Multicast snooping is disabled on $BRIDGE — multicast will flow freely."
  else
    warn "Multicast snooping is ENABLED on $BRIDGE (value: $SNOOP_VAL)."
    echo "     This can silently block Matter/Thread multicast discovery."
    echo "     Fix (immediate, no reboot): echo 0 > $SNOOP_FILE"
    echo "     Fix (permanent): add to /etc/network/interfaces under 'iface $BRIDGE':"
    echo "       bridge-multicast-snooping 0"
  fi
else
  warn "Could not read multicast_snooping for $BRIDGE — check manually."
fi

# =============================================================================
section "Check 4: Home Assistant reachable at $HA_IP"
# =============================================================================
if ping -c 2 -W 2 "$HA_IP" &>/dev/null; then
  info "Home Assistant is reachable at $HA_IP."
else
  fail "Home Assistant at $HA_IP is not responding to ping."
  echo "     Fix: Confirm the HAOS VM is running and has a DHCP lease."
  echo "     Check your router's DHCP table for a 'homeassistant' device."
  echo "     Then set HA_IP= to the correct IP and re-run this script."
fi

# =============================================================================
section "Check 5: HA web UI port reachable"
# =============================================================================
if curl -s --max-time 4 "http://${HA_IP}:8123" -o /dev/null; then
  info "Home Assistant web UI is accessible at http://${HA_IP}:8123."
else
  fail "Home Assistant web UI at http://${HA_IP}:8123 is not responding."
  echo "     Fix: Confirm HAOS VM is fully booted (first boot can take 2–3 min)."
fi

# =============================================================================
section "Check 6: Apple TV 4K model (Thread Border Router compatibility)"
# =============================================================================
echo "  This check is informational — it cannot be automated."
echo ""
echo "  Thread Border Router support on Apple TV 4K:"
echo "    Apple TV 4K (3rd gen, 2022) Wi-Fi + Ethernet  →  ✓  Supports Thread"
echo "    Apple TV 4K (3rd gen, 2022) Wi-Fi only        →  ✗  No Thread support"
echo "    Apple TV 4K (2nd gen, 2021)                   →  ✓  Supports Thread"
echo "    Apple TV 4K (1st gen, 2017)                   →  ✗  No Thread support"
echo ""
echo "  To confirm your model:"
echo "    Apple TV → Settings → General → About → Model"
echo "    MN873xx / MN893xx (2nd gen) or MC7T3xx / MC7U3xx / MNEH3xx (3rd gen Eth) = Thread capable"
echo "    If you have the Wi-Fi-only 3rd gen (64 GB, model MC8Q3xx) = no Thread"
echo ""
echo "  If your Apple TV does not support Thread, you have two options:"
echo "    A) Add a HomePod Mini or HomePod 2nd gen as your Thread border router"
echo "    B) Use a SLZB-06M or Home Assistant Connect ZBT-1 USB dongle for Thread"

# =============================================================================
section "Summary"
# =============================================================================
echo ""
if [[ $FAILURES -eq 0 ]]; then
  echo -e "${GREEN}All automated checks passed.${NC}"
  echo ""
  echo "Your Proxmox host is ready for Matter setup. Proceed to Part 3.5 in"
  echo "docs/setup-order.md — install the Matter integration in Home Assistant."
else
  echo -e "${RED}${FAILURES} check(s) failed.${NC} Fix the issues above before proceeding."
  echo ""
  echo "Re-run this script after making changes to confirm everything is resolved."
fi
echo ""
