# Setup Order & Script Reference

Follow these steps in order. Each script maps to a phase in the main guide.

## Phase 1 — Proxmox Host (manual + script)

| Step | What | Where to run |
|------|------|--------------|
| Manual | Flash Proxmox USB, install on NVMe, set static IP | Physical machine |
| **Script** | `scripts/01-proxmox-post-install.sh` | Proxmox Shell |
| Reboot | `reboot` or Proxmox UI → Node → Reboot | Proxmox Shell |

## Phase 2 — Home Assistant OS VM (mostly automated by community script)

| Step | What | Where to run |
|------|------|--------------|
| Run HAOS installer | `bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/vm/haos-vm.sh)"` | Proxmox Shell |
| Configure | RAM: 8192, CPU: 4, Disk: 64 GB | Proxmox wizard |
| Restore backup | HA web UI → Restore from backup | Browser |
| Assign static IP | Router admin → DHCP reservation for `homeassistant` | Router |

## Phase 3 — AI Stack LXC

| Step | What | Where to run |
|------|------|--------------|
| **Script** | `scripts/02-download-ubuntu-template.sh` | Proxmox Shell |
| Manual | Create LXC CT via Proxmox UI (CT 101, 10 cores, 48 GB RAM, 200 GB disk, Nesting enabled) | Proxmox UI |
| **Script** | `scripts/03-setup-ai-stack.sh` | Inside CT 101 shell |
| Optional | `scripts/06-pull-models.sh` (add more models later) | Inside CT 101 shell |

## Phase 4 — Remote Access

### Option A: Tailscale (recommended)
| Step | What | Where to run |
|------|------|--------------|
| **Script** | `scripts/04-tailscale-proxmox.sh` | Proxmox Shell |
| Manual | Approve subnet route in Tailscale admin console | Browser |
| Manual | Install Tailscale add-on in HAOS | HA UI |
| Optional | `tailscale serve --bg --https=443 http://localhost:3000` | Inside CT 101 shell |

### Option B: WireGuard (self-hosted)
| Step | What | Where to run |
|------|------|--------------|
| Install | `bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/ct/wireguard.sh)"` | Proxmox Shell |
| **Script** | `scripts/05-wireguard-lxc-harden.sh` | Inside WireGuard LXC shell |
| Manual | Add TUN device entries to `/etc/pve/lxc/<CT_ID>.conf` | Proxmox Shell |
| Manual | Open UDP 51820 in router → port forward to WireGuard LXC IP | Router |

## Phase 5 — Connect Everything

All done via UI — no scripts needed:
- HA → Settings → Integrations → Add → Ollama → URL: `http://192.168.1.101:11434`
- Install Whisper + Piper + openWakeWord add-ons in HA
- Create voice pipeline in HA → Voice Assistants
- Connect Open WebUI to HA via Long-Lived Access Token

## Config Files

| File | Purpose |
|------|---------|
| `config/docker-compose.yml` | Reference copy of the AI stack compose file |
| `config/tailscale-acl-example.json` | ACL policy template for Tailscale admin console |
