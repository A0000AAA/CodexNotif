# 资源来源与许可

## CodexNotif 图标

- 主文件：`mobile/assets/branding/codexnotif_icon_master.png`；
- Android 与 iOS 各尺寸图标由该主图缩放生成；
- 图形为本项目原创生成资源，不包含 OpenAI、ChatGPT、Codex、手机厂商或其他第三方商标/Logo；
- 许可：`AGPL-3.0-only`，与项目自有资源一致。

## 内置铃声

以下五个文件由仓库中的 `tools/generate_tones.py` 使用数学波形、包络和确定性参数合成，不是从手机系统、主题商店、网络音乐或第三方应用中提取：

- `mobile/android/app/src/main/res/raw/tone_alert.wav`；
- `mobile/android/app/src/main/res/raw/tone_chime.wav`；
- `mobile/android/app/src/main/res/raw/tone_hajimi.wav`；
- `mobile/android/app/src/main/res/raw/tone_phone.wav`；
- `mobile/android/app/src/main/res/raw/tone_soft.wav`。

格式为 44.1 kHz、单声道、16-bit PCM WAV。可从仓库根目录重新生成：

```powershell
python tools/generate_tones.py --output mobile/android/app/src/main/res/raw
```

重新执行脚本应生成内容相同的文件。脚本和生成的 WAV 均使用 `AGPL-3.0-only`。

## iOS 启动图

`mobile/ios/Runner/Assets.xcassets/LaunchImage.imageset/` 中的文件为 1×1 透明/空白启动占位资源，不包含第三方视觉作品，并按项目自有资源使用 `AGPL-3.0-only`。

## 新增资源时的要求

后续加入图片、字体、声音或模板时，应在本文件记录：作者、原始来源、取得日期、原始许可证、是否修改以及仓库中的目标路径。无法确认来源或不允许再分发的资源不得加入公开仓库。
