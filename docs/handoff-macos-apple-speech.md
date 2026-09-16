# LinguaGlass macOS Apple Speech 开发交接

更新时间：2026-09-16  
目标设备：Apple Silicon（当前测试机为 M1 Pro / 16 GB）  
目标系统：macOS 26 及以上  
当前分支：`feat/macos-apple-speech`

## 1. 本阶段目标

在保留现有 React + Tauri + Rust 前端与桌面框架的前提下，为 macOS 增加 Apple 原生语音识别：

- 麦克风：`AVAudioEngine → SpeechAnalyzer`
- 系统音频：`ScreenCaptureKit → PCM → SpeechAnalyzer`
- 输出统一的 `partial / final / error / backend-status` 事件
- 不依赖 Python 或 Distil-Whisper 即可在支持的 Mac 上生成本地英文字幕
- 最终产出可直接安装测试的 `.dmg`

当前版本是 **Apple Speech 技术验证版**，不是公开 Release。首要任务是在真实的 macOS 26 + Xcode 26 环境中完成编译，并修正 Apple SDK 的实际 API/并发约束。

## 2. 仓库与当前状态

仓库：<https://github.com/yranium2023/LinguaGlass.git>  
开发分支：<https://github.com/yranium2023/LinguaGlass/tree/feat/macos-apple-speech>

关键提交：

- `e9c45f6 feat: add macOS 26 Apple Speech test build`
- `71d22fd build: require Xcode 26 for Apple Speech`

Windows 上已经通过：

- 前端测试：20 项通过
- 前端生产构建
- Rust 测试：4 项通过
- Python ASR 测试：12 项通过

Windows 无法编译或验证 Swift、Apple Speech、ScreenCaptureKit 和 DMG。因此，当前 macOS 原生实现应视为“代码已接入、真机尚未验证”。

## 3. 已实现内容

### Apple Speech Bridge

目录：`native/macos-speech-bridge/`

- 使用 Swift Package Manager，要求 Swift 6.2、macOS 26 SDK。
- 使用 `SpeechAnalyzer`、`SpeechTranscriber`、`AssetInventory`。
- `--doctor`：检查系统、语言和 Apple Speech 模型状态。
- `--prepare`：请求准备系统管理的语音模型资源。
- `--mode microphone`：通过默认麦克风识别。
- `--mode system`：通过 ScreenCaptureKit 捕获系统音频并识别。
- 通过 stdout 输出逐行 JSON，供 Rust 读取。
- stdin 收到一行输入后停止，便于 Rust 管理生命周期。

### Tauri / Rust 集成

- macOS 环境报告 `backend: "apple_speech"`。
- 会话层在 macOS 分流到 Apple Speech Bridge。
- 设置页可展示 Apple Speech 状态并触发模型准备。
- macOS 的麦克风和系统音频入口复用现有前端模板。
- 开发环境从 Swift `.build/release` 查找 Bridge；打包后从 App 的 `Contents/MacOS` 查找 Bridge。

### macOS 打包配置

- `src-tauri/tauri.macos.conf.json`：DMG、外部 Bridge、最低 macOS 26。
- `src-tauri/Info.macos.plist`：麦克风、语音识别、屏幕/系统音频权限说明。
- `src-tauri/Entitlements.plist`：音频输入 entitlement。
- `scripts/build-macos.sh`：检查工具链、编译 Bridge、复制 sidecar、生成未签名 DMG。
- macOS 打包不携带 `.venv`、Python ASR sidecar 或 Distil 模型。

## 4. 当前隐私边界

这版只验证 **Apple 本地英文 ASR → LinguaGlass 字幕 UI**。

Apple Speech 产生的文本目前不会发送给 DeepSeek，因此 macOS 技术验证版不会生成中文翻译。接入翻译前，需要明确在产品界面告知用户：识别在本地进行，但开启翻译后，识别文本将发送到用户配置的 DeepSeek 服务。应在用户明确选择开启在线翻译后再启用该链路，不要在 Bridge 中直接加入隐式网络传输。

## 5. Mac 环境准备

Xcode Command Line Tools 单独更新后，不一定会自动切换到完整 Xcode。建议安装 Xcode 26，并执行：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

确认环境：

```bash
sw_vers
xcodebuild -version
xcrun swift --version
xcrun --sdk macosx --show-sdk-version
uname -m
```

最低预期：

- macOS：26.x
- Xcode：26.x
- Swift：6.2 或更新
- macOS SDK：26.x
- 架构：`arm64`

如果仍显示 Swift 6.0.3，说明活动开发目录仍指向旧 Command Line Tools。重新执行 `xcode-select`，然后用 `xcode-select -p` 确认结果为 `/Applications/Xcode.app/Contents/Developer`。

## 6. 获取代码和安装依赖

全新克隆：

```bash
git clone --branch feat/macos-apple-speech https://github.com/yranium2023/LinguaGlass.git
cd LinguaGlass
```

已有仓库：

```bash
git fetch origin
git switch feat/macos-apple-speech
git pull --ff-only origin feat/macos-apple-speech
```

安装前端和 Rust 工具链：

```bash
corepack enable
pnpm install --frozen-lockfile
curl https://sh.rustup.rs -sSf | sh
source "$HOME/.cargo/env"
```

## 7. 首次编译顺序

不要一开始就构建完整 DMG。先单独编译 Bridge，这样 Apple SDK 错误更容易定位。

```bash
swift build --package-path native/macos-speech-bridge -c release
```

编译成功后依次运行：

```bash
native/macos-speech-bridge/.build/release/LinguaGlassSpeechBridge --doctor --locale en-US
native/macos-speech-bridge/.build/release/LinguaGlassSpeechBridge --prepare --locale en-US
native/macos-speech-bridge/.build/release/LinguaGlassSpeechBridge --mode microphone --locale en-US
```

麦克风测试时说一段英文，观察终端是否持续输出 JSON。按 Return 让 Bridge 正常停止。

随后测试系统音频：

```bash
native/macos-speech-bridge/.build/release/LinguaGlassSpeechBridge --mode system --locale en-US
```

播放英文视频，授予“屏幕与系统音频录制”权限。如果系统提示重启应用，退出 Bridge 后重新运行。

## 8. 运行完整应用

Bridge 单独测试通过后，可以运行开发版：

```bash
pnpm tauri dev --config src-tauri/tauri.macos.conf.json
```

构建测试 DMG：

```bash
chmod +x scripts/build-macos.sh
./scripts/build-macos.sh
```

输出目录：

```text
src-tauri/target/release/bundle/dmg/
```

当前脚本使用 `--no-sign`，只适合本机开发测试。如果 Gatekeeper 阻止打开，可在 Finder 中按住 Control 点击应用并选择“打开”。公开发布前必须完成 Developer ID 签名、公证和 staple。

## 9. 建议测试顺序与验收标准

### P0：编译与诊断

- Swift Bridge 在 Xcode 26 环境成功编译。
- `--doctor` 返回可理解的 JSON 状态，不崩溃。
- `--prepare` 能准备 Apple 管理的模型，或给出可处理的失败原因。

### P1：麦克风

- 首次启动弹出正确的麦克风权限提示。
- 英文讲话能产生 partial 和 final 文本。
- partial 会被 final 正确替换，不重复堆叠。
- 连续停止/启动至少 3 次不崩溃、不失去音频输入。

### P2：系统音频

- 请求的是屏幕与系统音频录制权限。
- 只处理音频，不保存或显示屏幕画面。
- 英文视频能产生 partial 和 final 文本。
- 切换麦克风/系统音频后能正常恢复识别。

### P3：完整应用

- 设置页显示 Apple Speech，而不是要求下载 Distil。
- “准备模型”状态和错误能正确同步到前端。
- 主界面、悬浮字幕、停止与重启流程正常。
- 启动 App 不出现额外终端窗口。

### P4：DMG

- DMG 可以安装并启动。
- App 内存在 `LinguaGlassSpeechBridge`，并有可执行权限。
- App 不携带 `.venv`、Python、Distil 模型或 Windows sidecar。
- 安装后麦克风和系统音频均能识别。
- 连续运行系统音频 30 分钟，记录延迟、CPU、内存和稳定性。

## 10. 已知风险和待核对项

1. **Swift 6.2 严格并发**：ScreenCaptureKit 回调、`AsyncStream.Continuation`、`SpeechTranscriber.Result` 或音频转换对象可能触发 Sendable/actor 隔离错误。
2. **macOS 26 API 差异**：当前代码依据公开的 SpeechAnalyzer API 编写，实际 Xcode 26 SDK 的签名可能需要小幅调整。
3. **系统音频格式**：ScreenCaptureKit 的 CMSampleBuffer 到 AVAudioPCMBuffer 转换需要在真机验证采样格式、声道数和长期内存行为。
4. **sidecar 位置**：确认打包后的 Bridge 位于 `LinguaGlass.app/Contents/MacOS/LinguaGlassSpeechBridge`，且 Rust 能找到它。
5. **权限恢复**：用户拒绝权限、之后在系统设置重新开启、设备改变和 App 重启等路径尚未验证。
6. **设备选择**：当前 PoC 只使用默认麦克风和系统音频，设置页设备项仍是兼容现有 UI 的占位映射。
7. **时间戳**：partial/final 当前主要按事件时间输出，尚未完整映射 SpeechAnalyzer 的音频时间范围。
8. **模型占用**：Apple 资源由系统管理，实际首次准备耗时和磁盘增量需要记录，不能假定为零。
9. **本地语言**：当前只测试 `en-US`；其他语言和自动检测不在本阶段范围内。
10. **在线翻译**：尚未连接 DeepSeek，这是有意保留的隐私边界，不是遗漏的静默功能。

## 11. 出错时需要保留的信息

请保存以下命令的完整输出：

```bash
sw_vers
xcode-select -p
xcodebuild -version
xcrun swift --version
xcrun --sdk macosx --show-sdk-version
rustc -vV
pnpm --version
native/macos-speech-bridge/.build/release/LinguaGlassSpeechBridge --doctor --locale en-US
```

如果编译失败，附上从第一个 `error:` 开始的完整错误块和对应文件/行号。如果运行失败，附上终端 JSON 错误和界面截图。不要上传 DeepSeek API Key、私密录音或真实会议字幕。

权限异常可在“系统设置 → 隐私与安全性”中检查：

- 麦克风
- 语音识别
- 屏幕与系统音频录制

必要时可用下列命令重置开发阶段权限，然后重新触发授权：

```bash
tccutil reset Microphone
tccutil reset SpeechRecognition
tccutil reset ScreenCapture
```

## 12. 检查 DMG 内容和体积

构建后找到 `.app`，检查主要内容：

```bash
find src-tauri/target/release/bundle/macos/LinguaGlass.app/Contents -maxdepth 3 -type f -print
du -sh src-tauri/target/release/bundle/macos/LinguaGlass.app
du -sh src-tauri/target/release/bundle/dmg/*
```

重点确认没有 `.venv`、`site-packages`、Whisper 模型和 Windows 可执行文件。

## 13. 后续开发优先级

1. 修复 Xcode 26 下所有 Swift 编译问题，并提交最小改动。
2. 单独跑通麦克风 partial/final。
3. 单独跑通 ScreenCaptureKit 系统音频 partial/final。
4. 验证 Rust 生命周期、停止、重启和音频源切换。
5. 生成并检查未签名测试 DMG。
6. 根据真机数据优化分段、partial 抖动、CPU/内存和长时间稳定性。
7. 在明确的 UI 告知和用户选择下，把 final 文本接入现有 DeepSeek 翻译 pipeline。
8. 完成签名、公证、隐私说明和 macOS 公开 Release。

不要在上述 P0–P4 通过前合并到 `main`，也不要覆盖现有 Windows Distil Release 路径。

## 14. 建议 Git 工作流

```bash
git status
git add <本次修改的文件>
git commit -m "fix: make Apple Speech bridge build on macOS 26"
git push origin feat/macos-apple-speech
```

每解决一个独立问题就提交一次，避免把 Swift API 修复、UI 调整和打包变更混在同一提交中。真机测试通过后，再整理合并请求并更新 README 中的 macOS 状态。

## 15. Apple 官方参考

- Speech framework：<https://developer.apple.com/documentation/speech/>
- WWDC25 SpeechAnalyzer：<https://developer.apple.com/videos/play/wwdc2025/277/>
- ScreenCaptureKit：<https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos>
- Xcode 系统要求：<https://developer.apple.com/xcode/system-requirements/>

