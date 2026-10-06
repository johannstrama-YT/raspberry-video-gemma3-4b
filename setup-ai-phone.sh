#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Raspberry Pi Private AI Server
#
# Android / Laptop
#       │
#       │ Tailscale HTTPS
#       ▼
# Open WebUI
# 127.0.0.1:8080
#       │
#       ▼
# Ollama
# 127.0.0.1:11434
#       │
#       ▼
# Local LLMs
#
# Safe to re-run.
# ============================================================


# ============================================================
# CONFIGURATION
# ============================================================

OLLAMA_PORT="11434"
WEBUI_PORT="8080"

USER_NAME="$(id -un)"
USER_GROUP="$(id -gn)"
USER_HOME="$HOME"

OPENWEBUI_ROOT="${USER_HOME}/.local/share/open-webui"
OPENWEBUI_VENV="${OPENWEBUI_ROOT}/venv"
OPENWEBUI_DATA="${OPENWEBUI_ROOT}/data"

CONFIG_DIR="${USER_HOME}/.config/open-webui"
ENV_FILE="${CONFIG_DIR}/open-webui.env"

OLLAMA_URL="http://127.0.0.1:${OLLAMA_PORT}"
WEBUI_URL="http://127.0.0.1:${WEBUI_PORT}"


# ============================================================
# UV NETWORK SETTINGS
#
# Longer timeouts + serial downloads because this Pi/network
# previously stalled on large packages such as pyarrow.
# ============================================================

export UV_HTTP_TIMEOUT=300
export UV_HTTP_RETRIES=10
export UV_CONCURRENT_DOWNLOADS=1
export UV_CONCURRENT_INSTALLS=1
export UV_CONCURRENT_BUILDS=1


# ============================================================
# HELPERS
# ============================================================

section() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
    echo
}


fail() {
    echo
    echo "ERROR:"
    echo "$1"
    echo
    exit 1
}


trap '
echo
echo "============================================================"
echo "SETUP STOPPED"
echo "An error occurred around line $LINENO."
echo "============================================================"
echo
' ERR


section "Raspberry Pi Private AI Setup"


# ============================================================
# DON'T RUN ENTIRE SCRIPT AS ROOT
# ============================================================

if [ "$EUID" -eq 0 ]; then
    fail "Run this script as your normal user:

    ~/setup-ai-phone.sh

Do NOT run the complete script using sudo."
fi


# ============================================================
# 1. REQUIRED PACKAGES
# ============================================================

section "[1/10] Installing required packages"

sudo apt-get update

sudo apt-get install -y \
    curl \
    ca-certificates \
    openssl \
    qrencode

echo
echo "Required packages installed."


# ============================================================
# 2. DISK SPACE
# ============================================================

section "[2/10] Checking disk space"

AVAILABLE_KB="$(
    df --output=avail "$USER_HOME" |
    tail -1 |
    tr -d ' '
)"

AVAILABLE_GB=$(( AVAILABLE_KB / 1024 / 1024 ))

echo "Available disk space: ~${AVAILABLE_GB} GB"

if [ "$AVAILABLE_GB" -lt 4 ]; then
    fail "Less than 4 GB free disk space."
fi


# ============================================================
# 3. CHECK OLLAMA
# ============================================================

section "[3/10] Checking Ollama"

if ! command -v ollama >/dev/null 2>&1; then
    fail "Ollama is not installed."
fi

ollama --version

echo
echo "Installed models:"
echo

ollama list || true


# ============================================================
# 4. FORCE OLLAMA TO LOCALHOST
# ============================================================

section "[4/10] Securing Ollama"

echo "Ollama will listen only on:"
echo
echo "    127.0.0.1:${OLLAMA_PORT}"
echo


sudo mkdir -p \
    /etc/systemd/system/ollama.service.d


sudo tee \
    /etc/systemd/system/ollama.service.d/99-local-only.conf \
    >/dev/null <<EOF
[Service]
Environment="OLLAMA_HOST=127.0.0.1:${OLLAMA_PORT}"
EOF


sudo systemctl daemon-reload
sudo systemctl enable ollama.service >/dev/null 2>&1 || true
sudo systemctl restart ollama.service


echo "Waiting for Ollama..."


OLLAMA_READY=0

for i in $(seq 1 30); do

    if curl -fsS \
        "${OLLAMA_URL}/api/tags" \
        >/dev/null 2>&1
    then
        OLLAMA_READY=1
        break
    fi

    sleep 1
done


if [ "$OLLAMA_READY" -ne 1 ]; then

    sudo journalctl \
        -u ollama.service \
        -n 60 \
        --no-pager || true

    fail "Ollama did not start correctly."
fi


echo
echo "Ollama API works:"
echo
echo "    ${OLLAMA_URL}"


# ============================================================
# 5. TAILSCALE
# ============================================================

section "[5/10] Installing/checking Tailscale"


if ! command -v tailscale >/dev/null 2>&1; then

    echo "Installing Tailscale..."
    echo

    curl -fsSL \
        https://tailscale.com/install.sh \
        | sh

fi


sudo systemctl enable --now tailscaled


echo "Tailscale version:"
echo

tailscale version


echo
echo "Checking Tailnet connection..."
echo


if tailscale ip -4 >/dev/null 2>&1; then

    echo "Pi is already connected to Tailscale."

else

    echo "Tailscale authentication is required."
    echo
    echo "A URL will be displayed."
    echo
    echo "Open that URL on your phone/laptop and approve the Pi."
    echo

    sudo tailscale up

fi


echo
echo "Tailscale IPv4:"
echo

tailscale ip -4 || true


echo
echo "Tailscale status:"
echo

tailscale status || true


# ============================================================
# 6. INSTALL UV
# ============================================================

section "[6/10] Installing/checking uv"


export PATH="${USER_HOME}/.local/bin:${PATH}"


if ! command -v uv >/dev/null 2>&1; then

    echo "Installing uv..."
    echo

    curl -LsSf \
        https://astral.sh/uv/install.sh \
        | sh

    export PATH="${USER_HOME}/.local/bin:${PATH}"

fi


UV_BIN="$(command -v uv || true)"


if [ -z "$UV_BIN" ]; then
    fail "uv could not be found."
fi


"$UV_BIN" --version


echo
echo "Download reliability settings:"
echo
echo "    HTTP timeout:         ${UV_HTTP_TIMEOUT}s"
echo "    HTTP retries:         ${UV_HTTP_RETRIES}"
echo "    Concurrent downloads: ${UV_CONCURRENT_DOWNLOADS}"


# ============================================================
# 7. PYTHON 3.11 ENVIRONMENT
# ============================================================

section "[7/10] Creating Open WebUI Python environment"


mkdir -p \
    "$OPENWEBUI_ROOT" \
    "$OPENWEBUI_DATA" \
    "$CONFIG_DIR"


if [ ! -x "${OPENWEBUI_VENV}/bin/python" ]; then

    echo "Creating Python 3.11 environment..."
    echo

    "$UV_BIN" venv \
        --python 3.11 \
        "$OPENWEBUI_VENV"

else

    echo "Existing Python environment found."

fi


echo
"${OPENWEBUI_VENV}/bin/python" --version


# ============================================================
# 8. INSTALL OPEN WEBUI
# ============================================================

section "[8/10] Installing/updating Open WebUI"


install_open_webui() {

    local attempt

    for attempt in 1 2 3 4; do

        echo
        echo "------------------------------------------------------------"
        echo "Open WebUI install attempt ${attempt}/4"
        echo "------------------------------------------------------------"
        echo


        if "$UV_BIN" pip install \
            --python "${OPENWEBUI_VENV}/bin/python" \
            --upgrade \
            open-webui
        then

            echo
            echo "Open WebUI installation succeeded."

            return 0
        fi


        echo
        echo "Attempt ${attempt} failed."


        # We previously experienced a corrupted/timed-out
        # pyarrow download. Clean only that cache after
        # two failed attempts.
        if [ "$attempt" -eq 2 ]; then

            echo
            echo "Clearing cached pyarrow package..."

            "$UV_BIN" cache clean pyarrow || true

        fi


        if [ "$attempt" -lt 4 ]; then

            echo
            echo "Waiting 10 seconds before retrying..."

            sleep 10

        fi

    done

    return 1
}


if ! install_open_webui; then
    fail "Open WebUI failed to install after four attempts."
fi


OPEN_WEBUI_BIN="${OPENWEBUI_VENV}/bin/open-webui"


if [ ! -x "$OPEN_WEBUI_BIN" ]; then
    fail "Open WebUI executable was not found."
fi


echo
echo "Open WebUI executable:"
echo
echo "    ${OPEN_WEBUI_BIN}"


# ============================================================
# OPEN WEBUI CONFIG
# ============================================================

section "Configuring Open WebUI"


if [ -f "$ENV_FILE" ] &&
   grep -q '^WEBUI_SECRET_KEY=' "$ENV_FILE"
then

    WEBUI_SECRET_KEY="$(
        grep '^WEBUI_SECRET_KEY=' "$ENV_FILE" |
        head -1 |
        cut -d= -f2-
    )"

    echo "Keeping existing WebUI secret."

else

    WEBUI_SECRET_KEY="$(
        openssl rand -hex 32
    )"

    echo "Generated new WebUI secret."

fi


cat > "$ENV_FILE" <<EOF
DATA_DIR=${OPENWEBUI_DATA}
OLLAMA_BASE_URL=${OLLAMA_URL}
WEBUI_SECRET_KEY=${WEBUI_SECRET_KEY}
EOF


chmod 600 "$ENV_FILE"


# ============================================================
# 9. OPEN WEBUI SYSTEMD SERVICE
# ============================================================

section "[9/10] Installing Open WebUI service"


sudo tee \
    /etc/systemd/system/open-webui.service \
    >/dev/null <<EOF
[Unit]
Description=Open WebUI
After=network-online.target ollama.service tailscaled.service
Wants=network-online.target
Requires=ollama.service

[Service]
Type=simple

User=${USER_NAME}
Group=${USER_GROUP}

WorkingDirectory=${OPENWEBUI_ROOT}

EnvironmentFile=${ENV_FILE}

ExecStart=${OPEN_WEBUI_BIN} serve --host 127.0.0.1 --port ${WEBUI_PORT}

Restart=on-failure
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF


sudo systemctl daemon-reload

sudo systemctl enable \
    open-webui.service \
    >/dev/null

sudo systemctl restart \
    open-webui.service


echo "Waiting for Open WebUI..."


WEBUI_READY=0


for i in $(seq 1 450); do

    if curl -fsS \
        "${WEBUI_URL}/" \
        >/dev/null 2>&1
    then

        WEBUI_READY=1
        break

    fi


    if [ $((i % 5)) -eq 0 ]; then
        echo "Still starting..."
    fi


    sleep 2

done


if [ "$WEBUI_READY" -ne 1 ]; then

    echo
    echo "Service status:"
    echo

    sudo systemctl status \
        open-webui.service \
        --no-pager || true


    echo
    echo "Recent logs:"
    echo

    sudo journalctl \
        -u open-webui.service \
        -n 100 \
        --no-pager || true


    fail "Open WebUI failed to start."
fi


echo
echo "Open WebUI works locally:"
echo
echo "    ${WEBUI_URL}"


# ============================================================
# SECURITY CHECK
# ============================================================

echo
echo "Listening sockets:"
echo

ss -ltn |
grep -E ":(${OLLAMA_PORT}|${WEBUI_PORT})" || true

echo
echo "Expected:"
echo
echo "    127.0.0.1:${OLLAMA_PORT}    Ollama"
echo "    127.0.0.1:${WEBUI_PORT}     Open WebUI"


# ============================================================
# 10. TAILSCALE SERVE
# ============================================================

section "[10/10] Configuring private Tailscale access"


enable_tailscale_serve() {

    local output
    local result
    local enable_url
    local attempt


    # --------------------------------------------------------
    # FIRST ATTEMPT
    # --------------------------------------------------------

    set +e

    output="$(
        sudo tailscale serve \
            --bg \
            "${WEBUI_PORT}" \
            2>&1
    )"

    result=$?

    set -e


    echo "$output"


    # --------------------------------------------------------
    # SUCCESS
    # --------------------------------------------------------

    if [ "$result" -eq 0 ]; then

        echo
        echo "Tailscale Serve configured."

        return 0
    fi


    # --------------------------------------------------------
    # LOOK FOR ONE-TIME SERVE APPROVAL URL
    # --------------------------------------------------------

    enable_url="$(
        printf '%s\n' "$output" |
        grep -Eo \
            'https://login\.tailscale\.com/f/serve[^[:space:]]*' |
        head -1 \
        || true
    )"


    if [ -z "$enable_url" ]; then

        echo
        echo "Unexpected Tailscale error:"
        echo
        echo "$output"

        return 1
    fi


    # --------------------------------------------------------
    # SERVE NEEDS ONE-TIME APPROVAL
    # --------------------------------------------------------

    echo
    echo "============================================================"
    echo "TAILSCALE APPROVAL REQUIRED"
    echo "============================================================"
    echo
    echo "Tailscale Serve/HTTPS must be enabled once."
    echo
    echo "Open this URL on your phone or computer:"
    echo
    echo "    ${enable_url}"
    echo
    echo "Approve Tailscale Serve."
    echo


    # Try opening it automatically if Pi has GUI.
    if command -v xdg-open >/dev/null 2>&1 &&
       { [ -n "${DISPLAY:-}" ] ||
         [ -n "${WAYLAND_DISPLAY:-}" ]; }
    then

        echo "Opening the approval page..."

        xdg-open \
            "$enable_url" \
            >/dev/null 2>&1 &

    fi


    echo
    echo "Waiting for approval..."
    echo


    # --------------------------------------------------------
    # WAIT UP TO FIVE MINUTES
    # --------------------------------------------------------

    for attempt in $(seq 1 60); do

        sleep 5

        printf \
            "Waiting for approval... %d/60\r" \
            "$attempt"


        set +e

        output="$(
            sudo tailscale serve \
                --bg \
                "${WEBUI_PORT}" \
                2>&1
        )"

        result=$?

        set -e


        if [ "$result" -eq 0 ]; then

            echo
            echo
            echo "Tailscale Serve enabled!"

            return 0

        fi

    done


    echo
    echo
    echo "Approval was not completed within five minutes."
    echo
    echo "Approval URL:"
    echo
    echo "    ${enable_url}"

    return 1
}


if ! enable_tailscale_serve; then

    echo
    echo "Open WebUI itself is working."
    echo
    echo "You can retry Tailscale later with:"
    echo
    echo "    sudo tailscale serve --bg ${WEBUI_PORT}"

    exit 1

fi


# ============================================================
# VERIFY SERVE CONFIGURATION
# ============================================================

echo
echo "Checking Tailscale Serve..."
echo


SERVE_STATUS="$(
    sudo tailscale serve status 2>&1
)"


echo "$SERVE_STATUS"


if echo "$SERVE_STATUS" |
   grep -q "No serve config"
then

    fail "Tailscale reports no Serve configuration."

fi


# ============================================================
# EXTRACT HTTPS URL
# ============================================================

TAILSCALE_URL="$(
    printf '%s\n' "$SERVE_STATUS" |
    grep -Eo \
        'https://[^[:space:]]+\.ts\.net/?' |
    head -1 \
    || true
)"


# ============================================================
# FINAL STATUS
# ============================================================

section "SETUP COMPLETE"


echo "Services:"
echo

printf "%-20s " "Ollama:"
systemctl is-active ollama.service || true

printf "%-20s " "Open WebUI:"
systemctl is-active open-webui.service || true

printf "%-20s " "Tailscale:"
systemctl is-active tailscaled.service || true


echo
echo "Ollama:"
echo
echo "    ${OLLAMA_URL}"

echo
echo "Open WebUI:"
echo
echo "    ${WEBUI_URL}"


# ============================================================
# DISPLAY URL + TERMINAL QR CODE
# ============================================================

echo
echo "============================================================"
echo "PRIVATE AI ADDRESS"
echo "============================================================"
echo


if [ -n "$TAILSCALE_URL" ]; then

    echo "Open WebUI is available inside your Tailnet at:"
    echo
    echo "    ${TAILSCALE_URL}"
    echo


    echo "============================================================"
    echo "SCAN THIS QR CODE"
    echo "============================================================"
    echo


    if command -v qrencode >/dev/null 2>&1; then

        qrencode \
            -t ANSIUTF8 \
            -m 2 \
            "${TAILSCALE_URL}"

    else

        echo "qrencode was not found."

    fi


    echo
    echo "============================================================"
    echo
    echo "URL:"
    echo
    echo "    ${TAILSCALE_URL}"
    echo

else

    echo "Tailscale Serve is running, but the URL"
    echo "could not be extracted."
    echo
    echo "Run:"
    echo
    echo "    sudo tailscale serve status"

fi


# ============================================================
# ANDROID INSTRUCTIONS
# ============================================================

echo
echo "============================================================"
echo "ANDROID"
echo "============================================================"
echo
echo "1. Open Tailscale on Android."
echo "2. Connect to the same Tailnet."
echo "3. Scan the QR code above."
echo "4. Open the HTTPS address."
echo "5. Sign into Open WebUI."
echo "6. Select your Ollama model."
echo "7. Chat."
echo


# ============================================================
# MODELS
# ============================================================

echo "============================================================"
echo "OLLAMA MODELS"
echo "============================================================"
echo

ollama list || true


# ============================================================
# USEFUL COMMANDS
# ============================================================

echo
echo "============================================================"
echo "USEFUL COMMANDS"
echo "============================================================"
echo
echo "Open WebUI status:"
echo
echo "    sudo systemctl status open-webui"
echo
echo "Open WebUI logs:"
echo
echo "    sudo journalctl -u open-webui -f"
echo
echo "Ollama logs:"
echo
echo "    sudo journalctl -u ollama -f"
echo
echo "Loaded Ollama models:"
echo
echo "    ollama ps"
echo
echo "Available models:"
echo
echo "    ollama list"
echo
echo "Tailscale URL:"
echo
echo "    sudo tailscale serve status"
echo
echo "Memory usage:"
echo
echo "    free -h"
echo
echo "Live memory/model monitor:"
echo
echo "    watch -n 1 'free -h; echo; ollama ps'"
echo


# ============================================================
# SECURITY REMINDER
# ============================================================

echo "============================================================"
echo "SECURITY"
echo "============================================================"
echo
echo "Ollama:"
echo "    127.0.0.1:${OLLAMA_PORT}"
echo
echo "Open WebUI:"
echo "    127.0.0.1:${WEBUI_PORT}"
echo
echo "Remote access:"
echo "    Tailscale Serve only"
echo
echo "No router port forwarding is required."
echo
echo "Do NOT use Tailscale Funnel unless you deliberately"
echo "want to expose Open WebUI to the public Internet."
echo


echo "============================================================"
echo "DONE"
echo "============================================================"
