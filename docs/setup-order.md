# Complete Setup Order & Reference

> **What this builds:** A private, fully local smart home brain and AI model server running 24/7 on the Minisforum AI X1 Pro-370 — replacing Home Assistant Yellow, replacing Alexa, and running open-source AI models entirely on your network.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│              Minisforum AI X1 Pro-370 (bare metal)       │
│                    Proxmox VE 9.x                        │
│  ┌──────────────────────┐  ┌──────────────────────────┐ │
│  │   VM 100: HAOS       │  │  LXC 101: Ubuntu 24.04   │ │
│  │   Home Assistant OS  │  │  Ollama + Open WebUI     │ │
│  │   4 vCPU / 8 GB RAM  │  │  10–12 vCPU / 48 GB RAM │ │
│  │   64 GB disk         │  │  200 GB disk             │ │
│  └──────────────────────┘  └──────────────────────────┘ │
│       USB passthrough: Sonoff Zigbee dongle              │
│       Thread border router: Apple TV 4K (on LAN)         │
└─────────────────────────────────────────────────────────┘
```

## Recommended Setup Order

The parts in this guide are numbered in the order you should follow them. Parts 6 and 7 (Zigbee and Matter) are intentionally placed after the AI stack so you have a local assistant available during the most variable setup steps.

| Part | Section | Why |
|------|---------|-----|
| Part 1  | Proxmox | Foundation everything else runs on |
| Part 2  | Home Assistant OS | Get HA running and your Yellow backup restored |
| Part 3  | AI Stack (LXC + Ollama + Open WebUI) | Get the AI online early — before Zigbee and Matter |
| Part 4  | Wire Ollama to HA | Connect the two so the AI knows your HA entities |
| Part 5  | Voice Assistant | Voice pipeline needs both HA and Ollama running |
| **Part 6**  | **Zigbee** | AI is now running — use Open WebUI to debug dongle issues |
| **Part 7**  | **Matter & Thread** | AI helps interpret commissioning errors in real time |
| Part 8  | Open WebUI ↔ HA | Two-way chat control |
| Part 9  | Remote Access & VPN | Lock down external access |
| Part 10 | Siri Passthrough | Needs Tailscale (Part 9) to be in place first |
| Part 11 | Add-ons & Extensions | Polish |


> **Why are Parts 6 and 7 (Zigbee and Matter) placed after the AI stack?** Once Ollama is wired to HA (Part 4), you have a local AI that knows your HA setup and can help you work through integration errors, interpret logs, and suggest config values in real time. Zigbee and Matter setup have the most variability and the most opportunity to need that help. Neither depends on the AI stack, and the AI stack doesn't depend on them — so there's no cost to the reorder.

---

## IP Address Plan

| Service | Default IP | Port |
|---------|-----------|------|
| Proxmox management | `192.168.1.10` | `8006` |
| Home Assistant | `192.168.1.100` | `8123` |
| Ollama API | `192.168.1.101` | `11434` |
| Open WebUI | `192.168.1.101` | `3000` |
| WireGuard VPN LXC (if used) | `192.168.1.102` | `51820` UDP |

---

## Before You Start

### Buy these before Day 1
- **Sonoff Zigbee 3.0 USB Dongle Plus-E** (~$20) — replaces the Yellow's built-in Zigbee radio
- **USB flash drive** (8 GB+) — for the Proxmox installer
- **Ethernet cable** — wire the Minisforum directly to your router

> **You already have what you need for Matter/Thread.** Your Apple TV 4K (2nd gen or 3rd gen Wi-Fi + Ethernet model) acts as the Thread border router — no additional hardware required. See Part 7 for the full setup.

### Back up HA Yellow first
Do this before touching anything else. Keep the Yellow running in parallel until the new setup is confirmed stable.

1. In Home Assistant on your Yellow → **Settings → System → Backups**
2. **Create Backup** → "Full backup" → wait for it to complete
3. Click the backup → **Download** → save the `.tar` file to your laptop or cloud storage
4. Note your **backup encryption key** (Settings → System → Backups → key icon) — you cannot restore without it

---

## Part 1 — Install Proxmox on the Minisforum

### Step 1 — Flash the installer USB
1. Download the **Proxmox VE ISO** from [proxmox.com/downloads](https://www.proxmox.com/en/downloads) (latest stable, currently 9.x)
2. Flash it using **balenaEtcher** or **Rufus**

### Step 2 — BIOS setup
1. Plug in USB, monitor, and keyboard; power on the Minisforum
2. Press **Delete** (or F7) on boot to enter BIOS
3. Confirm or change these settings:
   - **Virtualization (AMD-V / SVM):** Enabled (usually on by default)
   - **Secure Boot:** Disabled ← most common install failure if missed
   - **Boot order:** USB first
   - **Power on after AC loss:** Power On ← ensures auto-restart after any power cut
4. Save and exit

### Step 3 — Install Proxmox (graphical wizard)
1. Boot from USB → select **"Install Proxmox VE (Graphical)"**
2. Accept the EULA
3. **Target disk:** Select the 1 TB NVMe (will be wiped)
4. **Location/timezone:** Set to your region
5. **Admin password + email:** Set a strong root password — this is your Proxmox login
6. **Network config:** Set a static IP, e.g., `192.168.1.10` — gateway and DNS match your router (usually `192.168.1.1`)
7. Confirm and install (~5–10 minutes)
8. Remove USB when prompted, let the machine reboot

### Step 4 — Access the Proxmox web UI

> **This is the last step that requires a monitor and keyboard directly connected to the Minisforum.** Once the machine reboots into Proxmox, everything from here on — all remaining shell commands, VM/LXC creation, HA setup, and configuration — is done through a browser on any device connected to your home network. Disconnect the monitor and keyboard after this reboot if you like, then continue from your Mac, iPad, or any other device.
>
> Once you complete Part 9 (Remote Access), you can manage everything over Tailscale from anywhere — not just your home network.

From any device on your network:
```
https://192.168.1.10:8006
```
You'll get a self-signed cert warning — click through it. Log in with `root` and the password you set.

### Step 5 — Post-install housekeeping
> **Script available:** `scripts/01-proxmox-post-install.sh` — run this in the Proxmox Shell to automate steps below.

Run in **Node → Shell**:
```bash
# Disable the enterprise (paid) repo nag
sed -i 's/^deb https:\/\/enterprise.proxmox.com\/debian\/pve/#&/' /etc/apt/sources.list.d/pve-enterprise.list

# Enable the free community repo
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
  >> /etc/apt/sources.list.d/pve-community.list

# Update and upgrade
apt-get update && apt-get dist-upgrade -y
```

Then reboot: **Node → Reboot** in the Proxmox UI (or run `reboot` in the shell).

---

## Part 2 — Install Home Assistant OS as a VM

### Step 1 — Run the HAOS community auto-install script
In **Node → Shell**:
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/vm/haos-vm.sh)"
```

When the wizard asks, choose:
- **Default or Advanced?** → Advanced
- **HAOS Version:** Stable
- **VM ID:** Accept default (100)
- **RAM:** `8192` (8 GB)
- **CPU cores:** `4`
- **Disk size:** `64` GB
- **Machine type:** Default (i440fx)
- Confirm → script downloads and installs HAOS automatically

### Step 2 — Start the HAOS VM
1. In the Proxmox left sidebar, find VM 100
2. Click it → **Start**
3. Click **Console** to watch it boot (first boot: 2–3 minutes)

### Step 3 — Access Home Assistant
From any device on your network:
```
http://homeassistant.local:8123
```
If mDNS doesn't resolve, check your router's DHCP list for a device named `homeassistant` and use its IP directly.

### Step 4 — Restore your HA Yellow backup
**Do not create a new account.** On the Welcome screen:
1. Click **"Restore from backup"**
2. Upload the `.tar` file from your Yellow
3. Enter your encryption key if prompted
4. Select **"Full restore"** → Confirm
5. HA restores and restarts (5–20 minutes depending on setup size)
6. Log in with your existing Yellow credentials — all devices, automations, dashboards, and add-ons should be restored

### Step 5 — Assign a static IP to Home Assistant
In your **router's admin panel**, find the new `homeassistant` device in the DHCP list and assign it a static lease, e.g., `192.168.1.100`. This keeps your HA URL stable permanently.

---

## Part 3 — Install Ollama + Open WebUI (AI Stack)

> **Follow the [Recommended Setup Order](#recommended-setup-order) and do this before Parts 6 and 7.** Once the AI stack is live and wired to HA (Part 4), you'll have a local assistant you can actively use during the Zigbee and Matter setup steps.

This runs in a separate Ubuntu LXC container, isolating AI inference from HAOS.

### Step 1 — Download the Ubuntu 24.04 template
> **Script available:** `scripts/02-download-ubuntu-template.sh` — automates this step.

In **Node → Shell**:
```bash
pveam update
pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst
```

### Step 2 — Create the Ubuntu LXC container
In Proxmox UI → **Datacenter → Node → Create CT**:

| Setting | Value |
|---------|-------|
| CT ID | `101` |
| Hostname | `ai-stack` |
| Password | Set a strong root password |
| Template | `ubuntu-24.04-standard_24.04-2_amd64.tar.zst` |
| Disk | `200 GB` (models are large — one 14B model is ~9–10 GB) |
| CPU | `10–12 cores` |
| RAM | `48000 MB` (48 GB) |
| Network | DHCP |
| Features tab | Enable **"Nesting"** (required for Docker inside LXC) |

Start the container after creating it.

### Step 3 — Install Docker + deploy the AI stack
> **Script available:** `scripts/03-setup-ai-stack.sh` — automates Steps 3 and 4 entirely. Run it inside CT 101's shell.

Or manually — access CT 101 → Shell and run:

```bash
# Update system
apt update && apt upgrade -y
apt install -y curl ca-certificates gnupg lsb-release

# Add Docker's official GPG key and repo
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
systemctl enable docker
```

Then create and start the stack:

```bash
mkdir ~/ai-stack && cd ~/ai-stack
cat > docker-compose.yml << 'EOF'
services:
  ollama:
    image: ollama/ollama
    container_name: ollama
    restart: always
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    container_name: open-webui
    restart: always
    ports:
      - "3000:8080"
    environment:
      - OLLAMA_BASE_URL=http://ollama:11434
    volumes:
      - open_webui_data:/app/backend/data
    depends_on:
      - ollama

volumes:
  ollama_data:
  open_webui_data:
EOF

docker compose up -d
```

Open WebUI is now accessible at `http://192.168.1.101:3000`. The first account you create is the admin.

### Step 4 — Pull your AI models
> **Script available:** `scripts/04-pull-models.sh` — pulls both models by default. Run it inside CT 101's shell.

Or manually:
```bash
# Voice assistant model (used by HA Assist / voice pipeline)
docker exec -it ollama ollama pull qwen3:4b

# Chat + MCP agent model (used by Open WebUI)
docker exec -it ollama ollama pull qwen3:14b
```

Both models sit in memory simultaneously. Combined they use ~11 GB of your 48 GB allocation — well within headroom. There's no manual switching needed: HA's voice pipeline is wired to `qwen3:4b` and Open WebUI defaults to `qwen3:14b` automatically.

**Model reference for your 48 GB container:**

| Model | RAM Used | Speed | Role in this setup |
|-------|----------|-------|--------------------|
| `qwen3:4b` | ~4 GB | Fast | **HA voice pipeline** — fast enough for voice, handles device commands perfectly |
| `qwen3:14b` | ~10 GB | Medium | **Open WebUI + MCP agents** — better quality for deliberate tasks |
| `qwen3:30b-a3b` (MoE) | ~20 GB | Medium | Optional: near-GPT-4 quality if you want to experiment |
| `llama3.1:70b` (Q4) | ~40 GB | Slow | Optional: maximum capability, leaves little headroom |

### Step 5 — Assign a static IP to the AI container
In your **router's admin panel**, assign a static DHCP lease for `ai-stack` (e.g., `192.168.1.101`).

### A note on GPU acceleration (Radeon 890M)
The Radeon 890M uses `gfx1150`, which as of early 2026 is not fully supported by Ollama's ROCm backend. Ollama defaults to **CPU inference** — still ~15–25 tokens/second for 7B models on this chip, which is perfectly usable for a home voice assistant.

To experiment with GPU acceleration later, add this to the `ollama` service in `docker-compose.yml`:
```yaml
environment:
  - HSA_OVERRIDE_GFX_VERSION=11.0.0
```
Results vary. Check [github.com/ollama/ollama/issues/9999](https://github.com/ollama/ollama/issues/9999) for current `gfx1150` status.

---

## Part 4 — Connect Ollama to Home Assistant

### Step 1 — Add the Ollama integration
1. **Settings → Devices & Services → Add Integration**
2. Search for **"Ollama"** → select it
3. Enter the URL: `http://192.168.1.101:11434`
4. Submit

### Step 2 — Create a conversation agent
1. Open the Ollama integration card → cogwheel → **Add conversation agent**
2. Select your model: **`qwen3:4b`** — this is the voice-optimised model; fast response times matter here
3. Check the **"Assist"** checkbox — this grants the LLM access to your HA entities so it can control devices

### Step 3 — Expose devices to the AI
1. **Settings → Voice Assistants → Expose**
2. Toggle on the entities you want the AI to see and control
3. Start with lights in one room, then expand once confirmed working

### Step 4 — Test
Press `e` in Home Assistant to open Assist. Switch the conversation agent dropdown to Ollama. Try:
- *"What's the temperature in the living room?"*
- *"Turn off all the lights in the kitchen"*

> **AI stack is now live. This is the point to go back and complete Parts 6 and 7** if you deferred them. You can use Open WebUI at `http://192.168.1.101:3000` as an active assistant while you work through Zigbee and Matter setup:
>
> - **Paste HA log output** directly into Open WebUI and ask what it means
> - **Describe what you're seeing** in the Proxmox or HA UI and ask what to do next
> - **Ask for config values** — e.g. "what's the correct ZHA path for a Sonoff Zigbee dongle on a Proxmox USB passthrough?"
> - **Interpret commissioning errors** — Matter errors are often cryptic; paste them and ask
>
> Open a browser tab with Open WebUI alongside your HA tab. The `qwen3:14b` model running locally is the equivalent of having a knowledgeable assistant sitting next to you during setup — and nothing you type leaves your network.

---

## Part 5 — Local Voice Assistant (Alexa Replacement)

This builds a fully offline voice pipeline — no audio leaves your house.

### Step 1 — Install speech add-ons in HAOS
**Settings → Add-ons → Add-on Store** — install and start all three:

| Add-on | Purpose | Config |
|--------|---------|--------|
| **Faster Whisper** | Speech-to-text | Language: `en`, model size: `small` or `medium` |
| **Piper** | Text-to-speech | Voice: `en_US-lessac-medium` (natural-sounding default) |
| **openWakeWord** | Wake word detection | Wake word: `hey_jarvis` or `ok_nabu` |

Use Faster Whisper (not standard Whisper) — it's significantly faster on CPU.

### Step 2 — Wyoming integration
HA will auto-discover the Wyoming protocol services from these add-ons. Go to **Settings → Devices & Services** and click **Add** on any Wyoming notifications that appear.

### Step 3 — Build the voice pipeline
1. **Settings → Voice Assistants → Add Assistant**
2. Name it (e.g., "Home AI")
3. Configure:
   - **Wake word engine:** openWakeWord
   - **Wake word:** your chosen phrase
   - **Speech-to-text:** Faster Whisper
   - **Conversation agent:** Ollama (`qwen3:4b`) — the fast model, configured separately from Open WebUI
   - **Text-to-speech:** Piper
4. Save

### Step 4 — Connect the Home Assistant Voice Preview Edition
1. Power on the Voice PE box — it discovers your HA instance automatically via its onboarding wizard
2. In HA → **Settings → Devices & Services** → find the new Voice PE device
3. Assign it to your "Home AI" pipeline
4. Say your wake word — LED ring lights up, you speak, response plays through the built-in speaker

You can place multiple Voice Preview boxes in different rooms — each connects to the same pipeline.

---

## Part 6 — Pass Through the Zigbee USB Dongle

> **This part is intentionally placed here** — after the AI stack (Parts 3–5) is running. Zigbee setup doesn't require the AI, but once Ollama is wired to HA you can paste dongle errors or Zigbee2MQTT logs directly into Open WebUI and get contextual help. See the [Recommended Setup Order](#recommended-setup-order) table above.

Plug the Sonoff Zigbee dongle into a USB port on the Minisforum.

### Step 1 — Find the dongle's USB ID
In **Node → Shell**:
```bash
lsusb
```
Look for a line like:
```
Bus 001 Device 003: ID 10c4:ea60 Silicon Labs CP210x UART Bridge
```
Note the `ID` value (e.g., `10c4:ea60`).

### Step 2 — Add the USB device to the HAOS VM
1. In Proxmox, click your HAOS VM → **Hardware** tab → **Add** → **USB Device**
2. Select **"Use USB Vendor/Device ID"** (not port — this survives unplug/replug)
3. Select your Sonoff dongle from the list → **Add**

### Step 3 — Restart the HAOS VM
Proxmox UI → HAOS VM → **Reboot**

### Step 4 — Configure the Zigbee integration in HA
1. **Settings → Devices & Services**
2. If ZHA or Zigbee2MQTT doesn't auto-discover, add manually:
   - ZHA: Settings → Add Integration → "Zigbee Home Automation" → select dongle path (usually `/dev/ttyUSB0` or `/dev/serial/by-id/...`)
3. Zigbee devices should reconnect within minutes — if any don't reconnect overnight, power-cycle them

> **Thread/Matter:** The Yellow's built-in Thread radio does not transfer to USB. Your Apple TV 4K is already acting as a Thread border router on your network — no USB radio needed. **Proceed to Part 7** to connect your Matter devices to Home Assistant via the Apple TV.

---

## Part 7 — Matter & Thread (Apple TV 4K as Border Router)

> **This part is intentionally placed here** — after the AI stack (Parts 3–5) is running. Matter commissioning has more moving parts than Zigbee (IPv6, multicast, Thread credentials, multi-fabric), and errors often show up as silent failures. Having Open WebUI running with `qwen3:14b` means you can paste your HA logs or describe what you're seeing and get actionable help without leaving your desk. See the [Recommended Setup Order](#recommended-setup-order) table above.

### Background: Thread vs. Matter vs. Zigbee

These three terms often get conflated. Here's what each one actually is:

| Protocol | What it is | Analogy |
|----------|-----------|--------|
| **Zigbee** | A radio protocol for low-power devices | Like Wi-Fi, but for sensors and switches |
| **Thread** | A radio/mesh networking protocol | Like Wi-Fi, but for Matter devices |
| **Matter** | A smart home control standard | The language devices speak — can run over Wi-Fi or Thread |

Your Apple TV 4K is a **Thread border router** — it bridges your Thread radio mesh to your regular IP network so Home Assistant (and other controllers) can talk to Thread-based Matter devices. The Apple TV handles the radio; HA handles the control.

Critically: your Zigbee setup (via the Sonoff dongle from Part 6) and your Matter/Thread setup are completely independent. One doesn't affect the other.

### Apple TV 4K model check — Thread support

Not all Apple TV 4K models support Thread. Before proceeding:

| Model | Thread? |
|-------|---------|
| Apple TV 4K 3rd gen (2022) — **Wi-Fi + Ethernet** | ✓ Yes |
| Apple TV 4K 3rd gen (2022) — **Wi-Fi only (64 GB)** | ✗ No |
| Apple TV 4K 2nd gen (2021) | ✓ Yes |
| Apple TV 4K 1st gen (2017) | ✗ No |

To confirm: **Apple TV → Settings → General → About → Model**

If your Apple TV does not support Thread, you can still add Matter-over-Wi-Fi devices directly — you just can't use Thread-based devices. For a Thread-capable radio without the Apple TV, a HomePod Mini or HomePod 2nd gen also works as a border router.

> **Script available:** `scripts/07-matter-prereq-check.sh` — run this in the Proxmox Shell before continuing. It verifies that IPv6 is enabled, multicast traffic is not being blocked on the Proxmox bridge, and the HA VM is reachable. Matter silently fails without these conditions.

To run the script, copy it from the repo to the Proxmox host:

```bash
# In the Proxmox Shell — download and run the prerequisite check
curl -fsSL https://raw.githubusercontent.com/conchan/ha-local-ai-setup/main/scripts/07-matter-prereq-check.sh | bash
```

> Since the repo is private, you can alternatively copy-paste the script contents directly from the GitHub file view into the Proxmox Shell, or `scp` it from your Mac.

Fix any failures the script reports before continuing.

### Step 1 — Confirm IPv6 and multicast on the Proxmox bridge

The script checks this automatically. If it flagged multicast snooping as enabled, fix it now — this is the most common reason Matter devices fail to commission:

```bash
# Disable multicast snooping immediately (no reboot needed)
echo 0 > /sys/class/net/vmbr0/bridge/multicast_snooping

# Make it permanent — add this line to /etc/network/interfaces
# under the 'iface vmbr0 inet static' block:
#   bridge-multicast-snooping 0
```

Also confirm IPv6 is not disabled:
```bash
sysctl net.ipv6.conf.all.disable_ipv6
# Should return: net.ipv6.conf.all.disable_ipv6 = 0
# If it returns 1, run:
sysctl -w net.ipv6.conf.all.disable_ipv6=0
echo 'net.ipv6.conf.all.disable_ipv6=0' >> /etc/sysctl.conf
```

### Step 2 — Confirm your Apple TV is signed into Apple Home

The Apple TV needs to be set up as a Home hub before it can route Thread traffic:

1. On your iPhone → **Home app** → tap the **house icon** (top left) → **Home Settings**
2. Scroll down to your Apple TV — it should show **"Connected"** as a home hub
3. If it shows "Not Responding" or isn't listed, open **Settings on the Apple TV → Users and Accounts** and sign in with your Apple ID

### Step 3 — Install the Matter integration in Home Assistant

In Home Assistant:
1. **Settings → Devices & Services → Add Integration**
2. Search for **"Matter"** → select it
3. When prompted: **"Select the connection method"** → leave the checkbox checked → **Submit**
   - This installs the official Matter Server app automatically on HAOS
4. Wait for the Matter Server app to start (~1 minute)
5. The Matter integration card appears in Devices & Services — it's ready

> No manual configuration needed. HAOS handles the Matter Server installation automatically.

### Step 4 — Share Apple's Thread credentials with Home Assistant

For HA to communicate with your Thread-based Matter devices over the Apple TV's network, HA needs the Thread network credentials. You transfer these from your iPhone:

1. Install the **Home Assistant Companion app** on your iPhone (if not already)
2. Open the Companion app → **Settings → Devices & Services**
3. Tap the **Thread** integration → **Configure**
4. You should see your Apple Thread network listed (named something like `MyHome1234`)
5. Tap **"Send credentials to Home Assistant"** → tap **Allow** when iOS asks for permission
6. Back in the HA web UI → **Settings → Devices & Services → Thread** → you should see the Apple network listed as a known Thread network
7. Tap **Configure** → tap **"Make preferred network"** on the Apple network

> If the Apple network doesn't appear, make sure your iPhone is:
> - Logged in with the **same Apple ID** as the Apple TV
> - Connected to the **same Wi-Fi network** as your Apple TV and Home Assistant
> - Running the HA Companion app with **Location permission set to "Always"** (required for Thread credential transfer)

### Step 5 — Add Matter devices to Home Assistant

There are two methods. Use whichever fits your situation:

#### Method A — Add a new device directly to HA (recommended for new devices)

Use this when the Matter device hasn't been paired to anything yet:

1. Open the **Home Assistant Companion app** on your iPhone
2. Tap **...** (top right) → **Add to Home Assistant** → **Add device** → **Add Matter device**
3. Tap **"No, it's new"**
4. Scan the QR code on the device (or tap **"More options"** to enter the numeric code)
5. HA commissions the device — takes 1–3 minutes
6. The device appears in HA under its entity name

Your Apple TV bridges the Thread signal. HA is the controller — the device lives on the HA fabric.

#### Method B — Share a device already in Apple Home to HA (for existing Apple Home devices)

Use this when the device is already paired to Apple Home and you want to add HA as a second controller without factory-resetting it:

1. Open the **Apple Home app** on your iPhone
2. Tap and hold the device → **Settings** (gear icon) → scroll down → **Turn On Pairing Mode**
   - This generates a one-time share code
   - Alternative on some devices: tap the device → gear icon → **Share Access** → the code appears
3. Copy the code or note the numeric string
4. Open the **HA Companion app** → **...** → **Add to Home Assistant** → **Add device** → **Add Matter device**
5. Tap **"Yes, it's already in use"** → select **Apple Home**
6. Enter the share code when prompted
7. HA is now a second controller — you can control the device from both Apple Home and HA simultaneously

Matter's multi-fabric feature means both controllers see live state updates — there's no sync delay.

#### Which method should I use?

| Situation | Method |
|-----------|--------|
| Brand new device, not yet paired anywhere | A |
| Device already in Apple Home, want to keep it there too | B |
| Device already in Apple Home, want HA only | Factory reset → A |

### Step 6 — Verify the device in Home Assistant

1. **Settings → Devices & Services** → find your new Matter device
2. Click the device → confirm you can toggle it on/off from HA
3. Check that state changes in Apple Home are reflected in HA (and vice versa) — this confirms the multi-fabric setup is working

### Known limitations with Apple Thread border routers

- **OTA firmware updates for Matter devices do not work** through Apple border routers. The Apple TV doesn't forward the mDNS packets HA needs to push updates. If you want to run Matter OTA updates from HA, you'd need an additional non-Apple Thread border router (e.g., an SLZB-06M or Home Assistant Connect ZBT-1 configured for Thread). Updates can still be pushed from the Apple Home app.
- **Keep Apple TV and Home Assistant on the same flat network** (same VLAN/subnet). If you have VLANs, mDNS won't cross them without a reflector, and Matter commissioning will silently fail.
- **Thread 1.4** (which would unify multi-brand Thread networks automatically) is coming to Apple TV via tvOS 26 — expected fall 2026. For now, your Apple Thread network and any future HA-native Thread network are separate.

---

## Part 8 — Open WebUI ↔ Home Assistant (Two-Way Control)

This lets you type natural language commands to your smart home from the Open WebUI chat interface.

### Step 1 — Generate a Long-Lived Access Token in HA
1. In HA, click your **profile name** (bottom left) → **Security**
2. Scroll to **Long-Lived Access Tokens** → **Create Token**
3. Name it "Open WebUI" → copy and save the token — **it's shown only once**

### Step 2 — Connect in Open WebUI
1. Open `http://192.168.1.101:3000` → **Workspace → Tools**
2. Search for the **Home Assistant** community tool (or import it from the community URL)
3. Configure with:
   - HA URL: `http://192.168.1.100:8123`
   - Access token: the token from Step 1
4. In a new chat, click the tools toggle → enable Home Assistant
5. You can now type "lock the front door" or "set the living room to 72°F" directly in the chat

---

## Part 9 — Remote Access & VPN

> **Never forward port 8123 (or any service port) directly to the internet.** Use a VPN so devices must authenticate before reaching anything on your home network.

### Tailscale vs. WireGuard

| | Tailscale | Self-hosted WireGuard |
|--|-----------|----------------------|
| Setup time | ~10 minutes | ~30–45 minutes |
| Works behind CGNAT | Yes, automatically | Needs VPS or DDNS workaround |
| Third-party dependency | Tailscale coordination servers (metadata only — traffic is E2E encrypted) | None — you own everything |
| Key management | Automatic | Manual |
| Performance | Slightly more overhead | Near-native WireGuard throughput |
| Best for | Simplicity, works everywhere | Maximum privacy, zero external trust |

**Recommendation:** Start with Tailscale. Add WireGuard later if privacy requirements evolve.

---

### Option A — Tailscale (Recommended)

Tailscale creates a private encrypted mesh network. Every device gets a stable `100.x.x.x` IP. No ports opened on your router — outbound connections only.

#### Step 1 — Sign up for Tailscale
1. Create a free account at [tailscale.com](https://tailscale.com) (Google, GitHub, or email)
2. Note your **tailnet name** from the admin console — e.g., `tail1a2b3c.ts.net`

#### Step 2 — Install Tailscale on the Proxmox host
> **Script available:** `scripts/05-tailscale-proxmox.sh` — automates Steps 2 and 3 (IP forwarding + install + bring-up).

Run in **Node → Shell**:
```bash
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --advertise-routes=192.168.1.0/24 --accept-dns=false
```
This prints an auth URL — open it and log in. The `--advertise-routes` flag exposes your entire home subnet (not just the Minisforum) to Tailscale clients.

In the **Tailscale admin console** at [login.tailscale.com/admin/machines](https://login.tailscale.com/admin/machines):
- Find your Minisforum node → **...** → **Edit route settings** → approve `192.168.1.0/24`
  
  ⚠️ Without this approval, other devices won't see your home network through the VPN.

#### Step 3 — Install Tailscale on Home Assistant
1. **Settings → Add-ons → Add-on Store** → search "Tailscale"
2. Install → Start
3. Open the add-on logs → click the authentication link → log in with the **same Tailscale account**

HA now has its own Tailscale IP and is also reachable via the Proxmox subnet route — two independent paths.

#### Step 4 — Install Tailscale on your client devices
- **iPhone/iPad:** App Store → Tailscale → log in
- **Mac:** [tailscale.com/download](https://tailscale.com/download) → install → log in

From anywhere, reach HA at: `http://homeassistant.tail1234.ts.net:8123`

#### Step 5 — Enable HTTPS for Open WebUI
Required for microphone access in the browser voice UI. Run in CT 101's shell:
```bash
tailscale serve --bg --https=443 http://localhost:3000
```
Open WebUI is now at `https://ai-stack.tail1234.ts.net` with a valid HTTPS certificate — no Cloudflare or Let's Encrypt needed.

#### Step 6 — Tighten access with Tailscale ACLs
In the Tailscale admin console → **Access controls**, paste and edit `config/tailscale-acl-example.json` from this repo. Replace `your-email@example.com` with your login email:
```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["your-email@example.com"],
      "dst": ["homeassistant:8123", "ai-stack:443"]
    }
  ]
}
```
This prevents any other device — even one accidentally added to your tailnet — from reaching your services.

---

### Option B — Self-Hosted WireGuard (Maximum Privacy)

No third party involved at any step. Your devices connect directly, with no coordination service.

#### Prerequisites — Dynamic DNS
WireGuard clients need a stable address to reach your home's public IP (which your ISP may change):
1. Sign up at [duckdns.org](https://www.duckdns.org) (free) or [no-ip.com](https://www.noip.com)
2. Create a hostname, e.g., `myhome.duckdns.org`
3. Install the DuckDNS add-on in Home Assistant (official add-on store) to keep the hostname updated

> **CGNAT check:** If your router's WAN IP starts with `100.64.x.x` or `10.x.x.x`, you're behind Carrier-Grade NAT and cannot receive inbound connections. WireGuard won't work without calling your ISP to request a real public IP, or using a cheap relay VPS (~$5/mo on Hetzner/DigitalOcean). If in doubt, use Tailscale — it handles CGNAT automatically.

#### Step 1 — Create the WireGuard LXC container
In **Node → Shell**:
```bash
bash -c "$(wget -qLO - https://github.com/community-scripts/ProxmoxVE/raw/main/ct/wireguard.sh)"
```
Accept defaults — this creates a minimal Debian LXC with WireGuard + WGDashboard installed. Note the container's LAN IP (e.g., `192.168.1.102`).

#### Step 2 — Enable the TUN device in the LXC
Run in **Node → Shell** (not inside the container):
```bash
# Replace 102 with your WireGuard container's actual ID
echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> /etc/pve/lxc/102.conf
echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file' >> /etc/pve/lxc/102.conf
```
Then reboot the container: Proxmox UI → CT 102 → **Reboot**

#### Step 3 — Enable IP forwarding and firewall rules
> **Script available:** `scripts/06-wireguard-lxc-harden.sh` — automates this entire step. Run it inside CT 102's shell.

Or manually in CT 102's shell:
```bash
# Enable IP forwarding permanently
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
sysctl -p

# Allow forwarding and NAT (check your NIC name with: ip link)
iptables -A FORWARD -i wg0 -j ACCEPT
iptables -A FORWARD -o wg0 -j ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Persist rules across reboots
apt install iptables-persistent -y
netfilter-persistent save
```

#### Step 4 — Configure WireGuard via WGDashboard
1. Open `http://192.168.1.102:10086` in your browser
2. Default login: `admin` / `admin` — **change this immediately** in Settings
3. Create a new WireGuard interface:
   - **Interface name:** `wg0`
   - **Listen port:** `51820`
   - **VPN subnet:** `10.10.0.0/24`
4. Click **Save** → interface starts

#### Step 5 — Open port 51820 on your router
In your router's admin panel:
- Port forwarding rule: External **UDP 51820** → Internal `192.168.1.102` port `51820`
- This is the **only port** you need to open for the entire setup

#### Step 6 — Add client peers in WGDashboard
For each device (iPhone, MacBook, etc.):
1. **Add Peer** → give it a name (e.g., "iPhone") → assign a VPN IP (e.g., `10.10.0.2`)
2. **Allowed IPs:** `192.168.1.0/24, 10.10.0.0/24` — routes all home network traffic through VPN
3. Click **Generate** → WGDashboard shows a QR code
4. **iPhone:** Install WireGuard (App Store) → tap **+** → **Scan QR code**
5. **Mac:** Install WireGuard (App Store or [wireguard.com](https://www.wireguard.com)) → import the `.conf` file

#### Step 7 — Set the DDNS endpoint
In each generated client config, confirm the `[Peer]` section reads:
```ini
Endpoint = myhome.duckdns.org:51820
```
Using the DDNS hostname (not a raw IP) means your config never breaks when your ISP changes your IP.

#### Step 8 — Test the VPN
1. Turn off Wi-Fi on your iPhone (use cellular only)
2. Connect to the WireGuard VPN → tap the toggle
3. Navigate to `http://192.168.1.100:8123` — Home Assistant should load
4. Navigate to `http://192.168.1.101:3000` — Open WebUI should load

---

### Security hardening (applies to both VPN options)

**Proxmox firewall:**
- Enable the firewall at the datacenter level (Datacenter → Firewall → Enable)
- Block all inbound traffic to port `8006` from outside your home network — only access Proxmox while on VPN

**Home Assistant:**
- Keep MFA enabled (Settings → Profile → Security)
- Use a long randomly generated password stored in a password manager
- Regularly check **Settings → System → Logs** for unusual login attempts

**Open WebUI:**
- Disable "Enable New Sign Ups" after creating your account (Settings → General)
- Consider enabling Open WebUI's built-in OAuth/SSO to reuse existing credentials

**General:**
- Keep Proxmox, HAOS, Docker images, and Minisforum firmware updated
- Your VPN is only as strong as your client devices — use Face ID and FileVault on Mac

---

## Part 10 — Siri → Local AI Passthrough ("Hey Siri, Ask Jarvis…")

This wires Siri on any Apple device into your Ollama conversation agent. Saying *"Hey Siri, ask Jarvis"* sends your voice to your local HA server, runs it through the LLM, and reads the response back via Piper — all locally, nothing leaving your network.

Works on iPhone, iPad, Mac, HomePod, and Apple Watch (via phone relay).

### Prerequisites
Before building the Shortcut, confirm these are already in place:
- Ollama integration added in HA with a conversation agent (Part 4)
- Piper TTS add-on installed and running (Part 5)
- Tailscale installed so the Shortcut works both at home and remotely (Part 9)
- A **Long-Lived Access Token** from HA: Profile → Security → Long-Lived Access Tokens → Create Token (copy it — shown only once)

### Step 1 — Find your Ollama agent ID
1. In HA → hamburger menu → **Developer Tools** → **States**
2. Filter by `conversation`
3. Find an entity like `conversation.ollama_qwen3_4b` — copy the full entity ID
   (The voice pipeline uses `qwen3:4b`; Open WebUI uses `qwen3:14b` separately)

### Step 2 — Find your Piper voice ID
1. **Settings → Add-ons → Piper** → note the voice name you configured (e.g., `en_US-lessac-medium`)
2. Remove `.onnx.json` from the end if present — use just `en_US-lessac-medium`

### Step 3 — Build the "Ask Jarvis" Shortcut
Open **Shortcuts** on your iPhone and create a new shortcut with these actions in order:

**Action 1 — Variables dictionary** (fill in once)

Add a **Dictionary** action with:
| Key | Value |
|-----|-------|
| `haURL` | `http://homeassistant.tail1234.ts.net:8123` (your Tailscale HA URL) |
| `token` | your Long-Lived Access Token |
| `agentID` | `conversation.ollama_qwen3_4b` (from Step 1 — the voice agent, not the chat agent) |
| `piperVoice` | `en_US-lessac-medium` (from Step 2) |

**Action 2 — Capture voice**

Add **Dictate Text** → Language: English

**Action 3 — Send to HA conversation API**

Add **Get Contents of URL**:
- URL: `[haURL]/api/conversation/process`
- Method: **POST**
- Headers: `Authorization: Bearer [token]`, `Content-Type: application/json`
- Body (JSON):
```json
{
  "text": "[Dictated Text]",
  "agent_id": "[agentID]",
  "language": "en"
}
```
(Use the Shortcuts variable picker for `[Dictated Text]` and dictionary values)

**Action 4 — Extract response text**

Add **Get Dictionary Value** from the URL result — key path: `response → speech → plain → speech`

**Action 5 — Speak via Piper TTS**

Add another **Get Contents of URL**:
- URL: `[haURL]/api/tts_get_url`
- Method: POST, JSON body:
```json
{
  "platform": "tts.piper",
  "message": "[response from Action 4]",
  "language": "en-US",
  "options": { "voice": "[piperVoice]" }
}
```
Then **Get Dictionary Value** → key: `url`
Then **Play Sound** → use the extracted URL

**Action 6 — Save**

Rename the shortcut to **"Ask Jarvis"** (or any phrase you want to say to Siri) → Done.

Say *"Hey Siri, Ask Jarvis"* — Siri hands off, you speak your question, Piper reads the response.

### Shortcut: use the community pre-built version
If building manually feels tedious, the HA community has a ready-made shortcut set (**Assist A + Assist B**) with smart voice/text switching:
- Voice mode automatically when phone is face-down or connected to Bluetooth/CarPlay
- Text input popup when face-up

Install from: [community.home-assistant.io/t/talk-to-your-ha-voice-assistant-via-siri/905997](https://community.home-assistant.io/t/talk-to-your-ha-voice-assistant-via-siri/905997)

Setup:
1. Download and install **Assist A** and **Assist B** from the iCloud links in the post
2. Edit **Assist B**: replace `AGENTID`, `URL`, and `TOKEN` with your values
3. Run **Assist A** once to grant permissions
4. Add **Assist A** to your iPhone **Action Button** (Settings → Action Button → Shortcut → Assist A)

### Using this on HomePod
To make *"Hey Siri"* on a HomePod trigger your local AI:
1. **Settings → Automations → New Automation** in HA
2. Trigger: **Webhook** (note the webhook ID)
3. Action: **Media Player: Play Media** → target your HomePod entity → URL: Piper TTS URL from your Shortcut
4. In your Shortcut, add a final step that calls this webhook — HA plays the audio through HomePod instead of your iPhone speaker

---

## Part 11 — Recommended Add-ons and Extensions

### Install HACS (Home Assistant Community Store)
HACS is the community package manager for HA — like npm for custom integrations and UI cards.

1. **Settings → Add-ons → Add-on Store** → ⋮ → **Repositories** → add `https://github.com/hacs/integration`
2. Install HACS → restart → **Settings → Devices & Services → Add HACS** → authorize via GitHub

### Essential add-ons

| Add-on | Purpose |
|--------|---------|
| **Mosquitto Broker** | MQTT broker for Zigbee2MQTT, Tasmota, and other IoT devices |
| **Zigbee2MQTT** | Alternative Zigbee stack with broader device support than ZHA |
| **Node-RED** | Visual flow-based automation builder — like n8n for your home |
| **Studio Code Server** | VS Code in the browser for editing YAML configs |
| **Nginx Proxy Manager** | (Optional) Manage HTTPS reverse proxy for internal services |

---

## Migration Checklist

Work through this in order. The sequence follows the [Recommended Setup Order](#recommended-setup-order) — AI stack comes before Zigbee and Matter so you have a local assistant available during the integration steps.

### Preparation
- [ ] Buy Sonoff Zigbee 3.0 USB Dongle Plus-E
- [ ] Buy 8 GB+ USB flash drive for Proxmox installer
- [ ] Create full backup on HA Yellow → download `.tar` file
- [ ] Note backup encryption key

### Step 1 — Part 1: Proxmox
- [ ] Download Proxmox VE ISO → flash to USB
- [ ] BIOS: disable Secure Boot, enable AMD-V/SVM, USB boot first, power-on-after-AC-loss
- [ ] Install Proxmox on 1 TB NVMe, set static IP `192.168.1.10`
- [ ] Access web UI at `https://192.168.1.10:8006` ← **monitor/keyboard no longer needed after this point**
- [ ] Run `scripts/01-proxmox-post-install.sh` in Proxmox Shell → reboot

### Step 2 — Part 2: Home Assistant OS
- [ ] Run HAOS community auto-install script in Proxmox Shell (Advanced: 8 GB RAM, 4 vCPU, 64 GB disk)
- [ ] Start VM 100 → access `http://homeassistant.local:8123`
- [ ] Restore HA Yellow backup → confirm all devices and automations are back
- [ ] Assign static DHCP lease `192.168.1.100` to HA in router

### Step 3 — Part 3: AI Stack
- [ ] Run `scripts/02-download-ubuntu-template.sh` in Proxmox Shell
- [ ] Create LXC CT 101 (`ai-stack`) in Proxmox UI: 10–12 cores, 48 GB RAM, 200 GB disk, Nesting enabled
- [ ] Run `scripts/03-setup-ai-stack.sh` inside CT 101 shell
- [ ] Confirm Open WebUI loads at `http://192.168.1.101:3000`
- [ ] Create admin account in Open WebUI → disable new sign-ups
- [ ] Assign static DHCP lease `192.168.1.101` to `ai-stack` in router

### Step 4 — Part 4: Wire Ollama to HA
- [ ] Add Ollama integration in HA → URL: `http://192.168.1.101:11434`
- [ ] Create conversation agent with `qwen3:4b` (voice model)
- [ ] Confirm Open WebUI defaults to `qwen3:14b` (set via `DEFAULT_MODELS` env var in docker-compose)
- [ ] Expose entities → test via Assist (`e` key in HA)
- [ ] **AI assistant is now available** — open `http://192.168.1.101:3000` alongside HA for the steps below

### Step 5 — Part 5: Voice Assistant
- [ ] Install Faster Whisper, Piper, openWakeWord add-ons in HA
- [ ] Confirm Wyoming integration auto-discovered
- [ ] Create voice pipeline "Home AI" in HA
- [ ] Onboard Home Assistant Voice Preview Edition

### Step 6 — Part 6: Zigbee *(use Open WebUI to help debug if needed)*
- [ ] Plug Sonoff dongle into Minisforum USB
- [ ] Find dongle USB ID with `lsusb` in Proxmox Shell
- [ ] Add USB device to HAOS VM via Proxmox UI (Hardware → Add → USB Device)
- [ ] Reboot HAOS VM
- [ ] Configure ZHA or Zigbee2MQTT in HA → confirm devices reconnect

### Step 7 — Part 7: Matter & Thread *(use Open WebUI to help debug if needed)*
- [ ] Confirm Apple TV 4K model supports Thread (Settings → General → About → Model)
- [ ] Confirm Apple TV is connected as a home hub in the iPhone Home app
- [ ] Run `scripts/07-matter-prereq-check.sh` in Proxmox Shell → fix any failures
- [ ] Disable multicast snooping on `vmbr0` if flagged by script
- [ ] Confirm IPv6 enabled on Proxmox host if flagged by script
- [ ] Install Matter integration in HA (Settings → Integrations → Add → Matter)
- [ ] Transfer Apple Thread credentials to HA via iPhone Companion app
- [ ] Set Apple Thread network as preferred in HA Thread integration
- [ ] Add each Matter device using Method A (new) or Method B (already in Apple Home)
- [ ] Verify device control works from both HA and Apple Home

### Step 8 — Part 8: Open WebUI ↔ HA
- [ ] Generate Long-Lived Access Token in HA (Profile → Security)
- [ ] Connect HA tool in Open WebUI with token and HA URL
- [ ] Test: type "turn on the living room lights" in Open WebUI chat

### Step 9 — Part 9: Remote Access
- [ ] **Tailscale (recommended):** Run `scripts/05-tailscale-proxmox.sh` → approve subnet route in admin console → install HA add-on → install on iPhone + Mac
- [ ] OR **WireGuard:** Run community LXC installer → run `scripts/06-wireguard-lxc-harden.sh` → configure WGDashboard → open UDP 51820 in router
- [ ] Test remote access: turn off Wi-Fi on iPhone → confirm HA loads

### Step 10 — Part 10: Siri Passthrough
- [ ] Find Ollama agent entity ID in Developer Tools
- [ ] Build "Ask Jarvis" Shortcut (or install community Assist A/B)
- [ ] Test: "Hey Siri, Ask Jarvis" → confirm local AI responds

### Step 11 — Part 11: Polish
- [ ] Install HACS → add Node-RED, Mosquitto, Studio Code Server
- [ ] Run HA Yellow in parallel for 1 week → decommission after confirmed stable

---

## Resource Allocation Reference

| Component | vCPU | RAM | Disk |
|-----------|------|-----|------|
| Proxmox host OS | — | ~2 GB reserved | System NVMe |
| HAOS VM (VM 100) | 4 cores | 8 GB | 64 GB |
| Ubuntu AI LXC (CT 101) | 10–12 cores | 48 GB | 200 GB |
| Headroom / buffer | — | ~6 GB | — |
| **Total** | | **64 GB** | |

Allocations can be adjusted in Proxmox at any time without reinstalling anything.

---

## Script Quick Reference

| Script | Where to run | Replaces |
|--------|-------------|---------|
| `scripts/01-proxmox-post-install.sh` | Proxmox Shell | Part 1, Step 5 |
| `scripts/02-download-ubuntu-template.sh` | Proxmox Shell | Part 3, Step 1 |
| `scripts/03-setup-ai-stack.sh` | Inside CT 101 shell | Part 3, Steps 3–4 |
| `scripts/04-pull-models.sh` | Inside CT 101 shell | Part 3, Step 4 (model management) |
| `scripts/05-tailscale-proxmox.sh` | Proxmox Shell | Part 9, Option A Steps 2–3 |
| `scripts/06-wireguard-lxc-harden.sh` | Inside WireGuard LXC shell | Part 9, Option B Steps 3–4 |
| `scripts/07-matter-prereq-check.sh` | Proxmox Shell | Part 7, pre-flight check |
