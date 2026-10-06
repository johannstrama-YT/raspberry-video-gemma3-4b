# Raspberry Pi Private AI Server

[Deutsch](README.md) | **English**

`setup-ai-phone.sh` turns a Raspberry Pi into a private AI chat server you can reach from your phone or laptop.

```
Android / Laptop
      │  Tailscale HTTPS
      ▼
Open WebUI   127.0.0.1:8080
      │
      ▼
Ollama       127.0.0.1:11434
      │
      ▼
Local LLMs (e.g. gemma3:4b)
```

Both Ollama and Open WebUI listen on localhost only. Remote access goes exclusively through Tailscale Serve, so no router port forwarding is needed.

## Requirements

- A Raspberry Pi running Raspberry Pi OS / Debian (64-bit recommended) with internet access
- A normal user account with `sudo` rights
- At least 4 GB of free disk space (the script checks this)
- [Ollama](https://ollama.com) already installed, ideally with a model pulled
- A free [Tailscale](https://tailscale.com) account, with Tailscale also installed on your phone/laptop

## First-time Pi setup (Imager, SSH, Raspberry Pi Connect)

1. **Flash the SD card** with the [Raspberry Pi Imager](https://www.raspberrypi.com/software/): choose your device and Raspberry Pi OS (64-bit). Under "OS customisation" set:
   - Hostname (e.g. `raspberrypi`), username and password
   - Wi-Fi credentials and country (if not using Ethernet)
   - **Enable SSH** (password or public key)
   - **Enable Raspberry Pi Connect** if your Imager version offers it (otherwise see step 4)
2. Put the SD card in the Pi, plug in power, and wait 1–2 minutes.
3. **First SSH connection** from your laptop on the same network:

   ```bash
   ssh <user>@<hostname>.local
   ```

   If `.local` doesn't resolve, use the IP address from your router's device list: `ssh <user>@<ip-address>`. Answer `yes` to the fingerprint prompt, then enter the password.
4. **Raspberry Pi Connect** (if not already enabled in the Imager): turn it on and link it to your Raspberry Pi account:

   ```bash
   sudo apt install -y rpi-connect-lite   # Raspberry Pi OS Lite; with desktop: rpi-connect
   rpi-connect on
   rpi-connect signin
   ```

   `rpi-connect signin` prints a URL. Open it on your laptop/phone, sign in at [connect.raspberrypi.com](https://connect.raspberrypi.com) and approve the device. The Pi then shows up there and you can open a remote shell in the browser (screen sharing only with the desktop version).
5. **First things after logging in** (see "How to run" below): update the system, install `curl`/`git`, install Ollama, clone the repo, run the script.

## How to run

1. On a fresh Raspberry Pi OS, update the system and install the basics first:

   ```bash
   sudo apt update && sudo apt full-upgrade -y
   sudo apt install -y curl git ca-certificates zstd
   ```

2. Install Ollama and pull a model (skip if already done):

   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   ollama pull gemma3:4b
   ```

3. Get the script onto the Pi:

   ```bash
   git clone https://github.com/johannstrama-YT/raspberry-video-gemma3-4b.git
   cd raspberry-video-gemma3-4b
   ```

4. Run it as your **normal user** (not with `sudo`; the script calls `sudo` itself where needed):

   ```bash
   ./setup-ai-phone.sh
   ```

5. Follow the prompts:
   - If Tailscale isn't logged in yet, open the printed URL on your phone/laptop and approve the Pi.
   - The first time, you may need to open a second URL to approve Tailscale Serve/HTTPS. The script waits up to five minutes.

6. When it finishes, it prints your private HTTPS address (`https://<pi-name>.<tailnet>.ts.net`) and a QR code.

## Using it from your phone

1. Install Tailscale on Android and sign in to the same tailnet.
2. Scan the QR code (or open the URL) in your browser.
3. Create the Open WebUI admin account on first visit, pick your Ollama model, and chat.

## What the script does

1. Installs `curl`, `ca-certificates`, `openssl`, `qrencode`
2. Checks free disk space
3. Checks that Ollama is installed
4. Forces Ollama to listen on `127.0.0.1` only (systemd drop-in)
5. Installs and connects Tailscale
6. Installs `uv`
7. Creates a Python 3.11 virtualenv for Open WebUI
8. Installs Open WebUI (with retries for flaky downloads)
9. Creates and starts an `open-webui` systemd service
10. Publishes Open WebUI on your tailnet with `tailscale serve`

It is safe to re-run; it keeps your existing Open WebUI secret and data and upgrades Open WebUI.

## Useful commands

```bash
sudo systemctl status open-webui      # service status
sudo journalctl -u open-webui -f      # Open WebUI logs
sudo journalctl -u ollama -f          # Ollama logs
ollama list                           # installed models
ollama ps                             # loaded models
sudo tailscale serve status           # show your private URL
watch -n 1 'free -h; echo; ollama ps' # live memory/model monitor
```

## Security

Do **not** enable Tailscale Funnel unless you deliberately want to expose Open WebUI to the public internet.
