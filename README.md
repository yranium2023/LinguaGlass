# LinguaGlass

跨平台实时学术翻译桌面应用 · 第一阶段开发原型。

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

这是原型代码，**尚未通过真实麦克风到中文的端到端验收**。请参阅
[验证记录](docs/validation.md)，不要把界面示例误认为真实识别结果。

## Windows 启动

**此工作目录已经装好开发依赖并下载默认模型。** 双击根目录
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
以及至少 2 小时的稳定性和真实课堂延迟测试。当前不生成安装包。

架构与已核实的官方接口来源：[architecture.md](docs/architecture.md)。
