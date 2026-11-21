#!/usr/bin/env bash
# voice-input 安装脚本（幂等）
# Linux: venv + systemd user unit + GNOME 快捷键
# macOS: uv venv + LaunchAgent
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

if [ "$(uname)" = "Darwin" ]; then
    if ! command -v uv >/dev/null; then
        echo "error: 需要 uv，请先 brew install uv" >&2
        exit 1
    fi

    SV=${VOICE_INPUT_SENSEVOICE:-~/.cache/asr_models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17}
    VAD=${VOICE_INPUT_VAD:-~/.cache/asr_models/silero_vad.onnx}
    if [ ! -f "$SV/model.int8.onnx" ]; then
        cat >&2 <<EOF
error: SenseVoice 模型缺失: $SV/model.int8.onnx
下载并解压到 ~/.cache/asr_models/：
  curl -L -o /tmp/sensevoice.tar.bz2 \\
    https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17.tar.bz2
  tar -xjf /tmp/sensevoice.tar.bz2 -C ~/.cache/asr_models/
EOF
        exit 1
    fi

    # 1. venv：系统 python 版本过新可能无 sherpa-onnx wheel，固定 3.12
    if [ ! -x venv/bin/python ]; then
        uv venv --python 3.12 venv
    fi
    uv pip install --python venv/bin/python --quiet \
        'sherpa-onnx==2.0.2' numpy sounddevice \
        pyobjc-core pyobjc-framework-Quartz pyobjc-framework-Cocoa \
        pyobjc-framework-ApplicationServices

    # 2. Silero VAD（v4 int8，缺失才下载）
    if [ ! -f "$VAD" ]; then
        mkdir -p "$(dirname "$VAD")"
        curl -L -o "$VAD" \
            https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.int8.onnx
    fi

    # 3. LaunchAgent
    PLIST=~/Library/LaunchAgents/com.local.voice-input.plist
    mkdir -p ~/Library/LaunchAgents
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.voice-input</string>
    <key>ProgramArguments</key>
    <array>
        <string>$PWD/voice-input</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/voice-input.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/voice-input.log</string>
</dict>
</plist>
EOF
    launchctl bootout "gui/$(id -u)/com.local.voice-input" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"

    PYBIN=$(readlink -f venv/bin/python)
    cat <<EOF
installed. Cmd+Z 开始/结束听写，Esc 取消。
注意：需给 venv python 真实二进制授权（系统设置 > 隐私与安全性）：
  辅助功能 + 输入监控 + 麦克风: $PYBIN
日志: tail -f ~/Library/Logs/voice-input.log
EOF
    exit 0
fi

# ---- Linux ----

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
