# 下一里程碑：Windows AI Speech 流式 PoC

正式路线与发布验收标准见
[`windows-release-roadmap.md`](windows-release-roadmap.md)。该文档是后续功能与 Bug
优先级的依据。

当前 P0 只做以下工作：

1. 建立可回退的 Git 基线，并补齐 .NET SDK / Windows App SDK 工具链。
2. 创建隔离的 packaged C# PoC，验证 `systemAIModels`、模型状态、
   `EnsureReadyAsync()` 和麦克风 partial/final。
3. 复用现有 Rust/CPAL WASAPI Loopback，将连续 PCM 输入 Windows AI。
4. 记录 90 秒识别对比和至少 30 分钟稳定性数据。
5. 形成书面 Go/No-Go 结论；通过后才建立统一 ASR Backend。

始终保留：音频本地处理；只有确认文本进入正式翻译；采集、识别和翻译独立排队；
实验性 Windows AI 代码在通过 P0 前不得替换现有 Distil 链路。
