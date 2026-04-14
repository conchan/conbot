#!/usr/bin/env bash
# =============================================================================
# 02-download-ubuntu-template.sh
# Run this in the Proxmox Shell BEFORE creating the AI LXC container.
# Downloads the Ubuntu 24.04 LTS container template to local storage.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Run as root in the Proxmox shell."

TEMPLATE="ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
STORAGE="local"

info "Checking if template already exists..."
if pveam list "$STORAGE" 2>/dev/null | grep -q "$TEMPLATE"; then
  info "Template already downloaded — nothing to do."
  exit 0
fi

info "Updating available templates list..."
pveam update

info "Downloading Ubuntu 24.04 LTS template to '$STORAGE'..."
pveam download "$STORAGE" "$TEMPLATE"

info "Template downloaded. You can now create the AI LXC container in the Proxmox UI:"
echo ""
echo "  Datacenter → Node → Create CT"
echo "  CT ID:      101"
echo "  Hostname:   ai-stack"
echo "  Template:   $TEMPLATE"
echo "  Disk:       200 GB"
echo "  CPU:        10–12 cores"
echo "  RAM:        48000 MB"
echo "  Network:    DHCP"
echo "  Features:   Enable 'Nesting' (required for Docker)"
echo ""
echo "After creating and starting the container, run 03-setup-ai-stack.sh inside it."
