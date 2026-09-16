# LinguaGlass Windows Release Roadmap

状态：生效（Windows AI Speech 已作 No-Go，不进入首个公开版）  
当前里程碑：GitHub Release `v0.1.0`  
当前最高优先级：Distil 后端产品化、模型管理器与 MSIX Release

## 发布完成的唯一标准

开发机可运行、`cargo tauri dev` 可运行、测试机上能生成 MSIX，都不代表 Windows
首个公开版本完成。只有满足下面这条完整用户路径，才允许发布 `v0.1.0`：

1. 一台没有 Node、Python、Rust、Visual Studio、Git 和 LinguaGlass 开发环境的
   Windows 11 电脑从 GitHub Releases 下载 LinguaGlass。
2. 用户完成安装和首次启动，全程不需要打开终端。
3. 应用检测本地 Distil 模型；没有模型时明确提示并允许用户按需下载。
4. 用户可以选择轻量、均衡或高精度 Distil 模型，并看到下载、校验和磁盘占用状态。
5. 用户输入 DeepSeek API Key，选择麦克风或系统音频后，可以获得连续的英文识别、
   学术中文翻译和悬浮字幕。
6. 安装、运行、停止、升级和卸载过程中不出现开发工具、CMD/PowerShell 黑窗、
   stack trace 或无法处理的错误状态。

## 优先级判断规则

后续的新功能与 Bug 按以下顺序排期：

1. 阻断当前 P0 验证的问题。
2. 阻断统一 ASR Backend、MSIX 或干净环境验收的问题。
3. 数据安全、密钥泄漏、崩溃、字幕丢失、无法恢复的音频问题。
4. 影响主要路径的识别、翻译和桌面体验问题。
5. 不阻断 `v0.1.0` 的增强功能和跨平台工作。

除非是安全问题或使当前验证无法继续，P0 期间不扩展新的 UI 功能，也不把实验性
Windows AI 代码直接耦合进主会话流程。

## 当前工程基线

已经具备：

- React + Tauri + Rust 桌面架构。
- Rust/CPAL 的麦克风和 Windows WASAPI Loopback 音频采集。
- Python/faster-whisper Distil Sidecar、可配置 VAD 与分段参数。
- DeepSeek 流式翻译、会话记录、悬浮字幕和基础模型管理。
- ASR、翻译和 UI 之间基于事件的通信基础。

当前发布阻塞项：

- Windows AI Speech Bridge 已完成隔离 PoC，但因模型创建失败和约 915 MB 的系统组件开销，
  明确不进入 `v0.1.0` 主流程。
- 当前 MSI 已可生成；仍需在干净 Windows 11 环境完成安装和端到端验收。
- 当前构建将 Python ASR 运行环境随安装包发布；Distil 模型仍按需下载。
- MSIX、签名、Release CI 和干净 Windows 验收仍待完成。
- 当前仓库没有可用的提交基线，现有文件全部显示为未跟踪。

## P0：Windows AI Speech WASAPI 流式 PoC

### P0.0 建立安全基线和工具链

目标：让 PoC 可编译、可复现、可回退。

- 审查并建立当前代码的首个 Git 基线；提交前检查密钥、日志和大型临时文件。
- 使用独立功能分支开发 PoC，不在实验验证前重写现有 Distil 流程。
- 安装并固定 .NET SDK 版本；优先选择受支持的 LTS SDK。
- 保留当前 Windows SDK `10.0.26100.0`，安装 Windows App SDK/C# 所需工作负载。
- 固定 Windows App SDK 与实验包版本，不使用浮动依赖。
- 记录当前系统构建号、CPU/NPU、音频设备和依赖版本，作为测试环境元数据。

2026-09-16 实测：稳定版 `Microsoft.WindowsAppSDK 2.4.0` 不包含
`Microsoft.Windows.AI.Speech`；当前 PoC 固定使用 `2.4.1-Experimental`。因此 P0 即使功能
通过，正式 Release 仍需单独决定是否等待 Speech 进入稳定通道。

当前机器检查结果：Windows 构建 `26200.7623`，Windows SDK
`10.0.26100.0` 已存在；只有 .NET 运行时，没有 .NET SDK。

### P0.1 打包身份与模型准备

在 `native/windows-ai-poc/` 建立隔离的最小 C# / Windows App SDK 工程：

- 工程必须以 MSIX 安装运行，不能只从 IDE 以无包身份启动。
- Manifest 声明 `systemAIModels`，配置正确的 Target Device Family、
  `MinVersion` 和 `MaxVersionTested`。
- 实现 `GetReadyState()` 状态显示。
- 只有得到用户确认后才调用 `EnsureReadyAsync()`。
- 将“不支持、需要下载、下载中、已就绪、权限被拒绝、下载失败”转换成明确状态。
- 先完成麦克风实时识别，输出 partial/final transcript 和时间戳。

P0.1 完成条件：安装后的 PoC 能在本机准备系统模型；麦克风识别可连续启动、停止、
再次启动，且能稳定输出 partial 和 final。

### P0.2 WASAPI Loopback 流式验证

复用现有 Rust/CPAL Loopback，不重复实现另一套系统音频捕获：

- 明确 Rust → Bridge 的音频契约：采样格式、采样率、声道数、起始时间和断点标记。
- Bridge 将连续 PCM 输入 Windows AI Speech，并输出统一 JSON Lines 事件。
- 第一版事件至少包含 `partial`、`final`、`error`、`backend-status` 和原始时间戳。
- 验证默认播放设备、指定播放设备、静音、设备切换、停止排空和重新开始。
- 如果 Windows AI 的流式输入接口仍为实验性，PoC 必须固定具体 SDK 版本，禁止在
  未验证兼容性的情况下进入主工程。

P0.2 完成条件：真实播放中的英文可以经
`WASAPI Loopback → PCM → Windows AI → partial/final` 连续输出，不依赖麦克风回录。

### P0.3 指标、稳定性和 Go/No-Go

使用相同素材同时记录 Windows AI 与 Distil 的结果：

- 首个 partial 延迟、speech end → final 延迟和连续字幕端到端延迟。
- CPU、NPU、内存、进程存活和音频丢块。
- 90 秒公开演讲的可比转写结果，以及至少 30 分钟真实系统音频连续运行。
- 三次完整的启动 → 识别 → 停止 → 重启循环。
- 模型未就绪、用户拒绝、权限不足、API 不支持和 Bridge 异常退出。
- 音频和 transcript 不被意外写入诊断日志。

在 `docs/validation/windows-ai-poc.md` 保存环境、步骤、原始指标摘要、已知限制和
结论。只有同时满足以下条件，才作出 Go 决策：

- 麦克风和 WASAPI Loopback 都能产生可用的 partial/final。
- 30 分钟运行无崩溃、无死锁、无持续增长的资源泄漏和不可解释的音频中断。
- 停止、重新开始和错误恢复可控。
- 系统模型准备流程可以转化为普通用户可理解的交互。
- Bridge 的分发和 API 版本风险有明确处理方案。

### P0 No-Go 结论（2026-09-16）

本机 Windows AI Speech 模型通过 Windows Update 按需下载，安装组件约 915 MB；最终
`GetReadyState()` 为 `Ready`，但 `TryCreateAsync()` 在已安装的模型上仍失败，返回
`COMException 0x8007007E`（模块无法加载）。执行提供程序初始化也只完成编译验证，未形成
稳定的可分发识别链路。基于磁盘占用、实验 API 风险和当前运行失败，Windows AI 不进入
`v0.1.0`，PoC 与证据保留在 `native/windows-ai-poc/` 和 `docs/validation/`，仅作未来重新评估
的隔离实验。

## P1：Distil ASR Backend 与模型管理

- 将现有 Distil 逻辑抽离为稳定的发布后端；首个公开版默认且唯一启用 `Distil-Whisper`。
- 本地没有 Distil 时才提示下载，不允许静默下载大型模型。
- 统一 ASR 状态机和事件协议，为未来重新接入 Windows AI 保留后端边界，但不在首个公开版
  暴露未验证的 Windows AI 选项。
- 为模型能力探测、下载、校验、取消、删除和状态转换增加测试。

完成条件：翻译和 UI 不需要通过条件分支理解后端的内部实现。

## P2：Windows AI Bridge（延期，不阻断 v0.1.0）

- 保留 React + Tauri + Rust 主架构。
- Rust 负责音频、Bridge 生命周期、超时、重启、日志和字幕事件。
- Windows Native Bridge 只负责 Windows AI 能力、模型准备和识别。
- 统一 `partial / final / error / backend-status` 事件及错误码。
- Sidecar 使用无控制台窗口方式启动，异常退出可以被检测并友好恢复。

完成条件：只有在 Windows AI API 进入稳定通道、模型创建和系统音频流式识别通过独立验收后，
才重新打开本阶段；不作为 `v0.1.0` 发布条件。

## P3：实时翻译 Pipeline

- 稳定 partial，避免文本来回替换和重复翻译。
- 将 ASR 确认、语义断句、翻译节流、上下文和字幕分页明确分层。
- 优化自然停顿、长句安全上限、术语一致性和学术语境。
- 实现 API 超时、有限重试、网络恢复和过载保护。
- 使用真实课堂、讲座和会议材料验证，而不是只验证短句。

完成条件：连续字幕不会因后端切换、partial 更新或网络波动而重复、丢失或乱序。

## P4：Distil 模型管理器

- 安装包不携带 Distil 模型。
- 展示模型大小、状态、磁盘位置、下载和校验进度。
- 支持按需下载、取消、删除、切换、断点/失败恢复和损坏校验。
- 用户可以只安装所选 Distil 模型；安装包本身不携带模型。

完成条件：全新用户不会因为缺少模型或半成品下载进入无法恢复状态。

## P5：Windows 桌面体验

- 完成浅色/深色、Accent Color、玻璃透明度和所有控件状态。
- 完成悬浮字幕、置顶、拖动、缩放、点击穿透和多显示器行为。
- 完成托盘、开机启动、快捷键和音频源切换。
- 启动和运行不显示 CMD/PowerShell/Sidecar 黑窗，不暴露开发工具。

完成条件：主路径可完全由普通桌面 UI 操作，并通过常用 DPI 和分辨率检查。

## P6：权限和异常处理

覆盖并自动测试或人工验证：

- 麦克风权限和系统 AI 权限。
- 旧 Windows、系统模型不可用和模型下载失败。
- DeepSeek Key 无效、限流、超时和网络断开。
- 音频设备拔出、默认设备改变和无可用输入。
- Distil 模型缺失、损坏和下载中断。
- Windows Bridge、Python Sidecar 和翻译任务异常退出。

完成条件：所有预期错误都提供原因、影响和下一步操作，不显示 stack trace。

## P7：MSIX 正式打包

- 建立可重复的 Release Pipeline。
- 打包 Tauri 主程序、前端资源、Windows Speech Bridge 和必要 Sidecar。
- 配置 `Identity / Publisher / systemAIModels / MinVersion / MaxVersionTested`。
- 开发阶段使用自签名证书验证安装、升级和卸载。
- 明确 GitHub 直发版本最终采用的可信签名方案。

完成条件：MSIX 在没有开发环境的 Windows 11 上能够安装、升级和卸载。

## P8：Release 安全整理

- DeepSeek API Key 不进入仓库、二进制、崩溃报告或日志。
- 日志默认脱敏；检查 HTTPS、下载 URL、文件哈希和重定向策略。
- 明确用户配置、模型、缓存、日志和会话目录。
- 检查卸载残留和用户主动保留数据的策略。
- 补齐 `LICENSE`、第三方依赖许可证和 Whisper/模型许可说明。

完成条件：安全检查形成可复核清单，没有发布级秘密和未知许可风险。

## P9：自动化测试与 Release CI

- GitHub Actions 运行前端测试、TypeScript 构建、Rust tests、Python ASR tests。
- 增加 Release build 和 MSIX 构建检查。
- Tag `vX.Y.Z` 自动生成 GitHub Release artifact 和校验信息。
- 签名方案允许时，在隔离的 Secret 环境自动签名。

完成条件：相同 tag 的产物可复现，失败的检查不能发布。

## P10：干净 Windows 验收

在无开发环境的 Windows 11 真机或 VM 上逐步验证：

1. 从 GitHub 下载并安装。
2. 首次启动并检测本地 Distil 模型。
3. 按需下载并校验所选 Distil 模型。
4. 保存 DeepSeek Key。
5. 使用麦克风和系统音频分别完成识别、翻译和悬浮字幕。
6. 验证重启、升级、卸载、网络中断和设备变化。

整个流程不允许用户打开终端或安装开发工具。

## P11：GitHub Release v0.1.0

- README 包含截图、功能、系统要求、安装、后端区别、API 配置、隐私和排错。
- 建立并维护 `CHANGELOG.md`。
- Release 提供安装包、版本说明和校验信息。
- 发布前重新执行 P10，并保存验收记录。

完成条件：发布页上的安装包满足本文开头的唯一发布标准。

## 当前立即执行的顺序

1. 在干净 Windows 11 环境安装 MSI，验证首次启动不需要开发工具。
2. 验证模型检测、按需下载、取消/失败恢复和应用数据目录权限。
3. 验证麦克风与 WASAPI Loopback 的英文识别、DeepSeek 翻译和悬浮字幕。
4. 补齐安装、升级、卸载、日志脱敏和异常提示验收记录。
5. 建立 GitHub Actions 的前端、Rust、Python 和 Windows Release 构建任务。
6. 明确签名方案后再生成 GitHub Release `v0.1.0`。
