# Home Assistant + Local AI — Setup Scripts

Automation scripts for setting up a self-hosted Home Assistant + Ollama AI stack on the **Minisforum AI X1 Pro-370** running Proxmox VE.

> These scripts automate the shell-side steps from the setup guide. Steps that require BIOS interaction, Proxmox UI clicks, router configuration, or HA UI are documented as manual steps in [`docs/setup-order.md`](docs/setup-order.md).

## Hardware Target

| Component | Spec |
|-----------|------|
| Machine | Minisforum AI X1 Pro-370 |
| CPU | AMD Ryzen AI 9 HX 370 |
| RAM | 64 GB |
| Storage | 1 TB NVMe |
| Hypervisor | Proxmox VE 9.x |

## Architecture

```
┌─────────────────────────────────────────────────┐
│           Minisforum AI X1 Pro-370               │
│                 Proxmox VE                       │
│  ┌─────────────────┐  ┌───────────────────────┐ │
│  │  VM: HAOS       │  │  LXC: Ubuntu 24.04    │ │
│  │  Home Assistant │  │  Ollama + Open WebUI  │ │
│  │  4 vCPU / 8 GB  │  │  10–12 vCPU / 48 GB  │ │
│  └─────────────────┘  └───────────────────────┘ │
│  USB passthrough: Sonoff Zigbee dongle           │
└─────────────────────────────────────────────────┘
```

## Scripts

| Script | Runs in | Purpose |
|--------|---------|---------|
| [`01-proxmox-post-install.sh`](scripts/01-proxmox-post-install.sh) | Proxmox Shell | Disable enterprise repo, enable free community repo, full upgrade |
| [`02-download-ubuntu-template.sh`](scripts/02-download-ubuntu-template.sh) | Proxmox Shell | Download Ubuntu 24.04 LXC template for the AI container |
| [`03-setup-ai-stack.sh`](scripts/03-setup-ai-stack.sh) | Inside AI LXC (CT 101) | Install Docker, deploy Ollama + Open WebUI, pull starter models |
| [`04-pull-models.sh`](scripts/04-pull-models.sh) | Inside AI LXC (CT 101) | Pull or update Ollama models (edit the list inside the script) |
| [`05-tailscale-proxmox.sh`](scripts/05-tailscale-proxmox.sh) | Proxmox Shell | Install Tailscale, enable subnet routing for home LAN |
| [`06-wireguard-lxc-harden.sh`](scripts/06-wireguard-lxc-harden.sh) | Inside WireGuard LXC | Enable IP forwarding, set up iptables NAT, persist rules |
| [`07-matter-prereq-check.sh`](scripts/07-matter-prereq-check.sh) | Proxmox Shell | IPv6 / multicast / HA reachability preflight before Matter setup |

## Usage

### Prerequisites
- Proxmox VE installed on the Minisforum NVMe
- Proxmox configured with a static IP (e.g. `192.168.1.10`)
- Access to the Proxmox Shell via the web UI (`https://192.168.1.10:8006`)

### Recommended order

```bash
# 1. In Proxmox Shell — immediately after first boot:
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/ha-local-ai-setup/main/scripts/01-proxmox-post-install.sh)
# Then reboot

# 2. In Proxmox Shell — download Ubuntu template for LXC:
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/ha-local-ai-setup/main/scripts/02-download-ubuntu-template.sh)
# Then create CT 101 (ai-stack) in the Proxmox UI — see docs/setup-order.md

# 3. Inside CT 101 Shell — set up Docker + Ollama + Open WebUI:
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/ha-local-ai-setup/main/scripts/03-setup-ai-stack.sh)

# 4. Later — pull or update Ollama models as needed:
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/ha-local-ai-setup/main/scripts/04-pull-models.sh)

# 5a. In Proxmox Shell — set up Tailscale VPN (recommended):
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/ha-local-ai-setup/main/scripts/05-tailscale-proxmox.sh)

# 5b. Inside WireGuard LXC Shell — harden WireGuard (alternative to Tailscale):
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/ha-local-ai-setup/main/scripts/06-wireguard-lxc-harden.sh)

# 7. In Proxmox Shell — run Matter/Thread preflight check before Part 7:
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/ha-local-ai-setup/main/scripts/07-matter-prereq-check.sh)
```

Replace `YOUR_USERNAME` with your GitHub username after pushing this repo.

## What Can't Be Automated

These steps require physical access, UI interaction, or account credentials:

- **BIOS setup** — Disable Secure Boot, enable AMD-V/SVM, set boot order, enable "power on after AC loss"
- **Proxmox installation** — graphical wizard on the physical machine
- **HAOS VM creation** — use the [community auto-install script](https://github.com/community-scripts/ProxmoxVE)
- **HA backup restore** — upload via the HA web UI
- **Zigbee dongle passthrough** — assign via Proxmox UI → VM Hardware → Add USB Device
- **Router DHCP reservations** — assign static IPs to HAOS VM and AI LXC
- **Tailscale subnet route approval** — approve in the [Tailscale admin console](https://login.tailscale.com/admin/machines)
- **HA integrations** — Ollama, Wyoming (voice), HACS — configured via HA Settings UI

Full step-by-step guide with context is in [`docs/setup-order.md`](docs/setup-order.md).

## Config Reference

| File | Purpose |
|------|---------|
| [`config/docker-compose.yml`](config/docker-compose.yml) | AI stack compose file with GPU acceleration notes |
| [`config/tailscale-acl-example.json`](config/tailscale-acl-example.json) | Tailscale ACL policy — paste into admin console |

## IP Address Plan (defaults)

| Service | Default IP | Port |
|---------|-----------|------|
| Proxmox | `192.168.1.10` | `8006` |
| Home Assistant | `192.168.1.100` | `8123` |
| AI Stack (Ollama) | `192.168.1.101` | `11434` |
| AI Stack (Open WebUI) | `192.168.1.101` | `3000` |
| WireGuard VPN LXC | `192.168.1.102` | `51820` (UDP) |

Adjust these in your router's DHCP reservation settings and update script variables as needed.

## Security Notes

- Never expose HA port 8123 or Proxmox port 8006 directly to the internet
- Use Tailscale (or WireGuard) as your only remote access method
- Change WGDashboard's default `admin/admin` credentials immediately
- Disable new sign-ups in Open WebUI after creating your admin account
- Enable MFA on your HA account (Settings → Profile → Security)
