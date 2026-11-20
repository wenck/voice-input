# voice-input

GNOME Wayland 下的本地离线中文语音输入。按 Super+Z 开始听写，说话过程中每次停顿都会把识别文本上屏到当前焦点应用；再按一次 Super+Z 结束，Esc 取消。

实现方式：一个常驻服务进程在运行时向 ibus-daemon 注册独立的 IBus 引擎 `voice-input`（不修改、不依赖任何已安装的输入法），按 Super+Z 时切换全局引擎到它并开始录音，结束时自动切回之前的引擎。识别链路完全本地：sherpa-onnx + SenseVoice（ASR）+ Silero VAD（分段），CPU int8 推理。

## 使用

- Super+Z：开始 / 结束听写
- Esc：取消本次听写（丢弃在途语音）
- 说话中每次自然停顿，已识别的句子会立即输入

## 依赖

- GNOME（Wayland）+ IBus（ibus-daemon 由会话启动即可）
- PipeWire / PulseAudio 麦克风（经 PortAudio 采集）
- Python 3 + `gi`（GIRepository，含 IBus-1.0 typelib，随 `ibus` 包提供）

## 模型

模型不随仓库分发，目录结构如下（默认根目录 `~/src/sub-live-v2/models`，可用环境变量 `VOICE_INPUT_MODELS` 覆盖）：

```
$VOICE_INPUT_MODELS/
  sensevoice/
    model.int8.onnx
    tokens.txt
  silero-vad/
    silero_vad.onnx
```

下载：

```bash
MODELS=${VOICE_INPUT_MODELS:-~/src/sub-live-v2/models}
mkdir -p "$MODELS/sensevoice" "$MODELS/silero-vad"
curl -L -o "$MODELS/sensevoice/model.int8.onnx" \
  https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx
curl -L -o "$MODELS/sensevoice/tokens.txt" \
  https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt
curl -L -o "$MODELS/silero-vad/silero_vad.onnx" \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.int8.onnx
```

注意：Silero VAD 需使用 sherpa-onnx 官方导出的 v4 int8 版（即上面的 `silero_vad.int8.onnx`）；onnx-community 的 v5 导出在 sherpa 中长时间运行会漂移失聪。

## 安装

```bash
./install.sh
```

幂等执行：创建 `venv`（`--system-site-packages`，需要系统 `gi`），安装 `sherpa-onnx`/`numpy`/`sounddevice`，写入并启用 `~/.config/systemd/user/voice-input.service`，并把 GNOME 自定义快捷键 `<Super>z` → `systemctl --user kill -s USR1 voice-input.service` 追加到 media-keys 列表（不会覆盖已有绑定）。

## 环境变量

- `VOICE_INPUT_MODELS`：模型根目录（默认 `~/src/sub-live-v2/models`）
- `VOICE_INPUT_LANG`：SenseVoice 语言（默认 `zh`，支持 `en`/`ja`/`ko`/`yue`/`auto`）
- `VOICE_INPUT_DEBUG=1`：把识别文本写入日志（默认只记状态与耗时）
- `VOICE_INPUT_TEST_WAV=文件.wav`：服务模式不占用麦克风，按实时节奏喂该 16k 单声道 wav（随后持续喂静音），用于无麦集成测试

## 自检

```bash
./voice-input --selftest 某文件.wav   # 不连 IBus，跑完整 VAD+ASR 分段并打印识别结果
systemctl --user kill -s USR1 voice-input.service   # 等价于按 Super+Z
```

## 排障

```bash
journalctl --user -u voice-input -f   # 实时日志：状态切换、分段时长、识别耗时
ibus engine                           # 查看当前全局引擎（结束时应为之前的引擎）
```

- 按 Super+Z 无反应：确认 `systemctl --user status voice-input` 为 active，且 gsettings 中
  `org.gnome.settings-daemon.plugins.media-keys custom-keybindings` 包含 `voice-input` 路径。
- 文本不上屏：听写期间目标应用必须保持键盘焦点；辅助文本（"正在听…"）由 GNOME Shell 的 IBus 弹窗显示。
- `ibus list-engine` 看不到 `voice-input` 是正常现象：运行时注册的组件不出现在该列表，但引擎切换与输入均正常。
- `ibus restart` 后服务会检测断线并退出，由 systemd 自动拉起重新注册。
