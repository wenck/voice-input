#!/usr/bin/env bash
# voice-input 安装脚本（幂等）：venv + systemd user unit + GNOME 快捷键
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

# 1. venv：必须 --system-site-packages 才有 gi / IBus typelib
if [ ! -x venv/bin/python ]; then
    python3 -m venv --system-site-packages venv
fi
venv/bin/pip install --quiet --upgrade 'sherpa-onnx==2.0.2' numpy sounddevice

# 2. systemd user unit
UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/voice-input.service" <<EOF
[Unit]
Description=Local offline Chinese voice input (IBus engine)
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=$PWD/voice-input
Restart=always
RestartSec=2

[Install]
WantedBy=graphical-session.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now voice-input.service

# 3. GNOME 快捷键 <Super>z -> 给服务发 SIGUSR1（幂等追加，绝不覆盖已有列表）
KB=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding
PATH_BASE=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
KB_PATH=$PATH_BASE/voice-input/
LIST=$(gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings)
if [[ "$LIST" != *"$KB_PATH"* ]]; then
    if [[ "$LIST" == "@as []" || "$LIST" == "[]" ]]; then
        NEW="['$KB_PATH']"
    else
        NEW="${LIST%]}, '$KB_PATH']"
    fi
    gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings "$NEW"
fi
gsettings set $KB:$KB_PATH name 'Voice input'
gsettings set $KB:$KB_PATH command 'systemctl --user kill -s USR1 voice-input.service'
gsettings set $KB:$KB_PATH binding '<Super>z'

echo "installed. models dir: ${VOICE_INPUT_MODELS:-~/src/sub-live-v2/models}"
