# LinguaGlass

跨平台实时学术翻译桌面应用 · Windows Release candidate。

**音频留在本地，只有最终英文文本发送到 DeepSeek。**

## 当前交付

- Tauri 2 + React + TypeScript 桌面工程；简约扁平主界面、大字号、明暗主题。
- Windows 系统音频（WASAPI Loopback）或麦克风采集，设备选择、增益、音量反馈。
- 字号、主题与识别设置自动保存；不可用的模型、设备和操作有明确提示。
- Python faster-whisper 常驻模型；16 kHz 重采样、Silero VAD、部分/最终英文字幕。
- Rust 异步翻译队列、DeepSeek 流式响应、上下文与课程术语表。
- 系统凭据管理器保存密钥，独立置顶透明字幕窗及鼠标穿透控制。
- 本地 JSONL 会话记录与 TXT / Markdown / JSON / SRT 完整会话导出。
- 有界缓冲和清晰的失败提示，断网/缺少密钥不停止英文识别。

Windows 首个公开版本使用 Distil-Whisper 本地识别；Windows AI Speech
实验接口不属于当前发行版。请参阅[验证记录](docs/validation.md)了解当前限制。

## Windows 启动

**开发目录启动方式。** 双击根目录
`Start-LinguaGlass.cmd` 可启动当前开发构建，界面资源已内置，不依赖 Vite 服务。
在偏好设置中填写 DeepSeek API Key 即可进行翻译联调。当前 CPU 大模型速度还需要优化。

如需继续开发，运行 `powershell -ExecutionPolicy Bypass -File scripts\desktop.ps1`；
该脚本会自动加载项目 `.tools` 下的编译环境。

### 其他电脑从源码安装

需要 Node.js 22+（含 npm）、Python 3.11、Rust stable MSVC、Visual Studio Build Tools
的 Desktop development with C++（含 Windows SDK）和 WebView2 Runtime。

```powershell
cd F:\Code\LinguaGlass
npm install
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1 -DownloadModel
npm run desktop
```

首次下载 distil-large-v3 需要网络和较大的磁盘空间。下载完成后，模型加载使用
`local_files_only=True`，开始聆听不会触发模型网络下载。CPU 默认为 INT8；速度不够时
先下载并在界面选择 `distil-small.en`。CUDA 需要兼容的 NVIDIA 运行库。

```powershell
.venv\Scripts\python.exe asr-sidecar\main.py --download-model --model distil-small.en
```

打开设置，输入 DeepSeek Key 并点击「安全保存」。选择系统音频或麦克风，然后开始聆听。
系统音频应选择课程实际播放的扬声器或耳机；当前一次选择一种音源，不混合双输入。
4K 屏幕可在顶部「文字大小」选择更大字号，浮动字幕同步放大。
没有密钥也可以识别英文。前端浏览器预览 `npm run dev` 不提供真实音频/翻译能力。

## 使用说明

### 1. 安装与首次启动

1. 从 [GitHub Releases](https://github.com/yranium2023/LinguaGlass/releases) 下载最新的 `.msi` 安装包。
2. 双击安装包完成安装，然后启动 LinguaGlass。
3. 首次启动会检查本地识别环境和已安装模型。安装包不包含 Distil 模型，需要用户自行选择下载。

### 2. 下载识别模型

打开「设置」中的「本地模型与计算环境」，按电脑配置选择：

- `distil-small.en`：体积和资源占用较小。
- `distil-medium.en`：速度与准确率均衡。
- `distil-large-v3`：准确率优先，需要更多磁盘空间和内存。

模型默认保存在：

```text
%APPDATA%\com.linguaglass.desktop\models
```

下载中断后可以重新下载。模型只保存在本机，不会上传到 DeepSeek 或 GitHub。

### 3. 配置 DeepSeek 翻译

1. 在设置中输入 DeepSeek API Key。
2. 点击「安全保存」。密钥保存在 Windows 凭据管理器中，不写入配置文件或日志。
3. 没有 API Key 时仍可使用英文识别，但不会生成中文翻译。

### 4. 开始实时字幕

1. 选择「系统音频」或「麦克风」。系统音频用于课程、会议和视频，麦克风用于现场讲话。
2. 选择具体设备并按需调整输入增益。
3. 点击「开始聆听」。状态变为「正在聆听」后，英文识别与中文翻译会逐段显示。
4. 点击「停止聆听」结束会话并保存已经完成的字幕。

### 5. 悬浮字幕与导出

- 点击「打开悬浮字幕」显示置顶字幕窗口。
- 可以切换鼠标穿透、拖动窗口、调整大小以及收起或展开。
- 顶部文字大小设置会同步影响主界面和悬浮字幕。
- 会话结束后可导出 TXT、Markdown、JSON 或 SRT。

### 6. 常见问题

- **提示模型未下载**：进入设置下载当前选择的模型。
- **无法启动识别**：重新检测环境，并尝试切换到 `distil-small.en`。
- **识别速度慢或丢字幕**：选择更小的模型，并关闭占用大量资源的程序。
- **没有中文翻译**：检查 DeepSeek API Key、网络连接和 API 额度。
- **清除本地数据**：退出应用后，可删除 `%APPDATA%\com.linguaglass.desktop\models` 或 `sessions` 目录。

## 构建 Windows 安装包

Release 安装包会携带 Python ASR 运行环境，但不携带任何 Distil 模型；模型在
首次使用时由用户选择并下载到应用数据目录。安装包生成在
`src-tauri/target/release/bundle/msi/`。

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-release.ps1
```

脚本最后会打印 MSI 的 SHA-256 校验值。干净 Windows 11 验收时只需要分发该
MSI，不需要 Node、Python、Rust 或开发工具。

## 验证

```powershell
.venv\Scripts\python.exe asr-sidecar\main.py --doctor
.venv\Scripts\python.exe -m unittest discover -s asr-sidecar\tests -v
npm test
npm run build
cargo test --manifest-path src-tauri\Cargo.toml
```

交付前运行 `powershell -ExecutionPolicy Bypass -File scripts\release-check.ps1`。
该检查会额外用项目 `test-assets` 中的官方公开英语音频按真实时间验证 GPU 识别、
渐进英文事件、最终文本时间戳和连续段落合并。

项目附带 pnpm 锁文件；也可以使用 `pnpm install --frozen-lockfile`。
当前环境仅自带 Node 可执行文件时，请安装完整 Node.js 或使用随环境提供的 pnpm。

## 数据与隐私

凭据进入 Windows Credential Manager / macOS Keychain / Linux Secret Service。
Key 不写入日志、localStorage、配置文件或 Python 进程。
会话写入系统应用数据目录的 `com.linguaglass.desktop/sessions`（本机位于 `%APPDATA%`）。导出按钮生成同名
文件并在界面显示绝对路径；导出期间继续到达的字幕需再次导出才会包含。
音频只存在于有界内存及本机进程管道，应用不保存原始音频。
术语表、最近 0–4 个最终英文片段与当前英文发送到 DeepSeek。

## 后续阶段

双输入混合、暂停恢复、模型下载管理、字幕透明度/
位置锁定、翻译重试、macOS ScreenCaptureKit、Linux PipeWire、Python sidecar 打包，
以及至少 2 小时的稳定性和真实课堂延迟测试。

架构与已核实的官方接口来源：[architecture.md](docs/architecture.md)。
