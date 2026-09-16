# LinguaGlass 跨平台实时学术翻译软件
## Work Mode Handoff / Project Specification

**文档状态：** v0.1  
**目标平台：** Windows / macOS / Linux  
**核心场景：** 大学课程、学术讲座、技术会议、线上课程、面对面英语交流  
**核心语言方向：** English Speech → English Transcript → Simplified Chinese Translation

---

# 1. 产品目标

设计并实现一款轻量级跨平台实时翻译桌面软件。

软件同时支持：

- 系统音频实时识别，例如 Zoom、Teams、浏览器、YouTube、播放器和网课；
- 麦克风实时识别，例如线下课程、老师讲话、会议和面对面交流；
- 系统音频与麦克风同时监听；
- 本地英文 Speech-to-Text；
- 将英文文本发送至 DeepSeek API；
- 返回准确、自然、符合学术表达的简体中文翻译；
- 中英双语实时字幕；
- Always-on-top 悬浮字幕；
- 保存完整 transcript 与翻译记录。

最重要的架构原则：

```text
Audio stays local
        │
        ▼
Local Speech Recognition
        │
        ▼
English Text
        │
        ▼
DeepSeek API
        │
        ▼
Chinese Translation
```

**音频本身不得发送给 DeepSeek。**

云端只处理文本，从而同时降低费用、减少网络带宽和提高隐私性。

---

# 2. MVP 非目标

第一版暂时不做：

- Speech-to-Speech 语音翻译；
- 中文/日语等多语言 ASR；
- 本地 LLM 翻译；
- 多人 Speaker Diarization；
- 会议机器人自动加入 Zoom/Teams；
- 浏览器插件；
- 手机 App；
- 云端账户同步；
- 自动课程总结。

架构应保留扩展能力，但 MVP 必须首先解决：

**英语实时识别 + 学术中文实时翻译 + 悬浮字幕。**

---

# 3. 推荐技术栈

## Desktop Framework

采用：

**Tauri 2 + React + TypeScript + Rust**

不优先使用 Electron。

原因：

- Tauri 桌面包体与常驻资源占用较小；
- Rust 非常适合音频采集、并发与本地系统 API；
- React 方便快速构建现代 UI；
- Tauri 原生支持 always-on-top 等窗口属性，适合实现独立字幕悬浮窗。citeturn122733search6

建议：

```text
Frontend
React
TypeScript
Vite

Desktop
Tauri 2

Native Backend
Rust

ASR
Python Sidecar
faster-whisper

Translation
DeepSeek API
```

---

# 4. 总体系统架构

```text
┌─────────────────────────────────────────────┐
│                 LinguaGlass                 │
├─────────────────────────────────────────────┤
│                                             │
│ System Audio                    Microphone  │
│      │                              │       │
│      └──────────────┬───────────────┘       │
│                     ▼                       │
│                Audio Engine                 │
│                     │                       │
│                     ▼                       │
│                  VAD                        │
│                     │                       │
│                     ▼                       │
│          Local ASR / faster-whisper        │
│                     │                       │
│              Partial / Final               │
│                     │                       │
│        ┌────────────┴────────────┐          │
│        ▼                         ▼          │
│ English Overlay          Translation Queue │
│                                  │          │
│                                  ▼          │
│                           DeepSeek API      │
│                                  │          │
│                                  ▼          │
│                        Chinese Translation  │
│                                  │          │
│                                  ▼          │
│                           Overlay Update    │
│                                             │
└─────────────────────────────────────────────┘
```

三个模块必须彼此异步：

```text
Audio Capture
ASR
Translation
```

任何一个模块变慢，不得阻塞另外两个模块。

---

# 5. 跨平台音频采集

建立统一 Rust Trait：

```text
AudioCaptureBackend
├── WindowsAudioBackend
├── MacOSAudioBackend
└── LinuxAudioBackend
```

## Windows

系统音频：

```text
WASAPI Loopback Capture
```

麦克风：

```text
WASAPI Capture
```

目标：

无需 VB-CABLE 等第三方虚拟声卡即可采集系统输出。

## macOS

系统音频优先：

```text
ScreenCaptureKit
```

麦克风：

```text
CoreAudio
```

需要处理 macOS：

```text
Microphone Permission
Screen Recording / System Audio Permission
```

## Linux

优先：

```text
PipeWire
```

兼容：

```text
PulseAudio Monitor
```

---

# 6. Audio Engine

统一转换：

```text
16 kHz
Mono
PCM Float32 / Int16
```

内部维护 ring buffer。

音频链路：

```text
Raw Audio
   ↓
Resample
   ↓
16 kHz Mono
   ↓
VAD
   ↓
ASR Segment
```

需要支持 Input Mode：

```text
System Audio
Microphone
System + Microphone
```

系统音频和麦克风需要独立音量控制。

---

# 7. VAD

优先使用：

**Silero VAD**

faster-whisper 本身已经集成 Silero VAD，并允许配置 silence duration。citeturn122733search0

建议 MVP：

```text
min_silence_duration_ms:
500–700 ms
```

状态：

```text
SILENCE
   ↓
SPEECH_STARTED
   ↓
SPEECH_ACTIVE
   ↓
SPEECH_END
```

关键原则：

**Partial ASR 可以实时显示，但只有 Final Segment 才允许发送给 DeepSeek。**

避免：

```text
The convolution...
The convolution layer...
The convolution layer extracts...
```

连续调用三次 API。

应该只发送最终：

```text
The convolution layer extracts spatial features from the input.
```

---

# 8. Local ASR

第一版默认：

**faster-whisper + Distil-Whisper**

推荐模型：

```text
Accuracy
distil-large-v3

Balanced
distil-medium.en

Performance
distil-small.en
```

Distil-Whisper 专门针对英文 ASR，官方给出的 distil-large-v3 为 756M 参数，相比 large-v3 更小且显著更快，并推荐作为默认高性能英文模型。citeturn122733search1

faster-whisper 官方明确兼容 `distil-large-v3`，同时支持 INT8、CUDA 和 VAD。citeturn122733search0

默认：

```text
language = "en"

condition_on_previous_text = false

beam_size = 5

vad_filter = true
```

---

# 9. ASR Sidecar 架构

第一阶段不要尝试把 Whisper 完全写进 Rust。

采用：

```text
Tauri / Rust
     │
     │ IPC
     ▼
Python ASR Sidecar
     │
     ▼
faster-whisper
```

Sidecar 启动后模型常驻内存。

禁止：

```text
每句话重新启动 Python
每句话重新加载模型
```

通信建议：

```text
Local WebSocket

or

stdin/stdout JSON IPC
```

事件格式：

```json
{
  "type": "asr_final",
  "start": 124.31,
  "end": 128.72,
  "text": "Gradient descent minimizes the loss function."
}
```

---

# 10. DeepSeek Translation Engine

DeepSeek API 当前提供 OpenAI/Anthropic 兼容 API，可直接通过 OpenAI-compatible 调用方式集成。citeturn122733search2turn122733search3

默认翻译模型：

```text
deepseek-v4-flash
```

高精度模式：

```text
deepseek-v4-pro
```

普通实时字幕优先：

**Flash**

用户可手动切换：

```text
Fast
Balanced
Academic Accuracy
```

需要使用 Streaming：

```text
stream = true
```

DeepSeek Chat Completions API 支持流式响应。citeturn122733search3turn122733search4

这样中文可以逐渐显示，而不必等待完整 response。

---

# 11. Academic Translation Prompt

翻译不得使用普通聊天式 Prompt。

默认 System Prompt：

```text
You are a professional academic interpreter translating spoken English
into Simplified Chinese.

The content may involve computer science, engineering, mathematics,
artificial intelligence, telecommunications, networking, machine
learning and university lectures.

Requirements:

1. Translate accurately and faithfully.
2. Preserve technical terminology.
3. Do not summarize, simplify, explain, or omit information.
4. Preserve equations, symbols, variable names, acronyms and model names.
5. Prefer standard Chinese academic terminology.
6. Use previous context to resolve pronouns and ambiguous terminology.
7. Spoken fragments may be incomplete. Translate conservatively and do
   not invent missing information.
8. Keep proper nouns, software names, APIs, algorithms and model names
   unchanged when appropriate.
9. Output only the Chinese translation.
```

---

# 12. Context-Aware Translation

不能逐句完全独立翻译。

维护：

```text
TranslationContext
```

结构：

```text
Previous finalized segment 1
Previous finalized segment 2
Previous finalized segment 3

Current segment
```

例如：

```text
Context:

Previous:
We first compute the gradient of the loss function.
Then we propagate it backward through each layer.

Current:
This gives us the update direction.
```

DeepSeek 应理解：

```text
This
```

指的是之前讨论的 gradient / backpropagation process。

建议保持最近：

```text
2–4 segments
```

而不是整个 transcript。

---

# 13. Course Glossary

支持用户设置课程领域：

```text
General
Computer Science
Artificial Intelligence
Networking
Electrical Engineering
Mathematics
Custom
```

同时支持用户自定义 Glossary：

```text
backpropagation = 反向传播
gradient descent = 梯度下降
channel gain = 信道增益
path loss = 路径损耗
policy iteration = 策略迭代
```

Prompt 中动态加入：

```text
Preferred terminology:
...
```

这是提高大学课程翻译准确率的重要功能。

---

# 14. Translation Queue

必须单独设计异步 Queue：

```text
ASR Final
   │
   ▼
Translation Queue
   │
   ▼
DeepSeek Worker
   │
   ▼
Translation Result
```

如果网络短暂变慢：

ASR 仍然继续。

英文字幕仍然继续。

中文翻译进入队列。

禁止：

```text
等待 DeepSeek 返回
↓
才继续做 ASR
```

---

# 15. UI 设计方向

设计关键词：

**Minimal / Liquid Glass / Focused / Academic**

不要做成传统工程工具。

参考视觉：

```text
Glass
Soft Blur
Thin Border
Low Contrast
Large Radius
Subtle Shadow
Minimal Iconography
```

应用默认：

```text
Dark / Auto
```

支持：

```text
Light
Dark
System
```

视觉风格根据平台自适应：

```text
macOS
Vibrancy / native glass

Windows
Mica / Acrylic-inspired glass

Linux
Blur when compositor supports it
Fallback translucent surface
```

不能为了完全一致而破坏平台体验。

---

# 16. 主界面

主界面只显示最核心的状态：

```text
┌─────────────────────────────────┐
│ LinguaGlass                  ⚙  │
│                                 │
│ Input                           │
│ ● System Audio                  │
│ ○ Microphone                    │
│ ○ Both                          │
│                                 │
│ ASR                             │
│ Distil Large V3        Ready ✓  │
│                                 │
│ Translation                     │
│ DeepSeek Flash         Ready ✓  │
│                                 │
│      ┌─────────────────┐        │
│      │ Start Listening │        │
│      └─────────────────┘        │
│                                 │
└─────────────────────────────────┘
```

Listening 后：

```text
Listening ●

System Audio █████░
Microphone   ███░░░

00:34:27
```

---

# 17. 悬浮字幕窗口

悬浮窗与主窗口必须是两个独立 Tauri Window。

Subtitle Overlay：

```text
┌────────────────────────────────────────┐
│ The convolution layer extracts        │
│ spatial features from the input.      │
│                                        │
│ 卷积层从输入中提取空间特征。            │
└────────────────────────────────────────┘
```

默认：

```text
English
14–16 px
60–70% opacity

Chinese
20–24 px
100% opacity
```

支持：

```text
Always on top
Drag
Resize
Opacity
Font size
English show/hide
Chinese show/hide
Click-through
Lock position
Bottom / Top preset
Single / Dual subtitle
```

悬浮窗收起时：

```text
● EN → 中
```

点击恢复。

---

# 18. 字幕生命周期

每个字幕单元：

```text
PARTIAL
FINAL
TRANSLATING
TRANSLATED
```

UI：

```text
PARTIAL
灰色英语

FINAL
白色英语

TRANSLATING
中文区域轻微 shimmer

TRANSLATED
正式中文
```

不得使用显眼 loading spinner。

---

# 19. Transcript

实时记录：

```text
00:02:14

EN
Today we're going to discuss convolutional neural networks.

ZH
今天我们将讨论卷积神经网络。
```

支持导出：

```text
.txt
.md
.json
.srt
```

未来可加入：

```text
AI lecture summary
Key concepts
Vocabulary
```

但不属于 MVP。

---

# 20. 设置界面

设置分成：

```text
General

Audio

Speech Recognition

Translation

Subtitle

Privacy

Advanced
```

核心设置：

```text
Audio Device

ASR Model

Compute Device
Auto / CPU / CUDA / Metal

DeepSeek API Key

DeepSeek Model

Academic Domain

Glossary

Translation Context Length

Overlay Position

Font Size

Opacity
```

---

# 21. API Key Security

API Key 不允许：

```text
localStorage
plaintext config
日志
```

优先使用：

```text
Windows Credential Manager
macOS Keychain
Linux Secret Service
```

Rust 统一封装：

```text
SecretStore
```

日志必须自动 redact：

```text
sk-********
```

---

# 22. Privacy

软件 UI 必须明确显示：

```text
Audio Processing
Local

Speech Recognition
Local

Translation
DeepSeek Cloud

Data sent to cloud
Text only
```

这是产品卖点之一。

---

# 23. 性能目标

目标而非绝对保证：

```text
Audio → Partial English
< 500–800 ms

Speech End → Final English
< 1 s

Final English → Chinese begins
< 1 s typical network

Speech End → usable Chinese
< 2 s preferred
```

ASR 要求：

```text
Real Time Factor < 0.5
```

即处理 10 秒音频最好不超过 5 秒。

正常情况下应该明显快于实时。

---

# 24. Error Handling

必须优雅处理：

```text
No microphone permission

No system audio permission

ASR model missing

CUDA unavailable

DeepSeek API key invalid

DeepSeek rate limit

Network offline

Translation timeout

Audio device disconnected
```

例如 DeepSeek 不可用时：

```text
English transcription continues normally.

Chinese translation:
Connection unavailable.
```

不能停止整个 Session。

---

# 25. Session State

建议核心状态：

```text
IDLE
INITIALIZING
LISTENING
PAUSED
STOPPING
ERROR
```

Listening 内部状态：

```text
Audio Capture
ASR
Translation
Overlay
Transcript
```

全部分别维护健康状态。

---

# 26. 项目目录建议

```text
linguaglass/

apps/
  desktop/

src/
  frontend/
    components/
    pages/
    overlay/
    stores/
    services/

src-tauri/
  src/
    audio/
      mod.rs
      windows.rs
      macos.rs
      linux.rs

    asr/
      mod.rs
      sidecar.rs

    translation/
      deepseek.rs
      queue.rs
      context.rs

    session/
    storage/
    secrets/

asr-sidecar/
  main.py
  engine.py
  vad.py
  protocol.py

shared/
  protocol/

docs/
  architecture.md
  ui.md
  translation.md
```

---

# 27. 推荐开发阶段

## Phase 1 — Functional Prototype

只做：

```text
Microphone
↓
faster-whisper
↓
English transcript
↓
DeepSeek
↓
Chinese text
```

无复杂 UI。

目标：

验证整个核心 pipeline。

---

## Phase 2 — Streaming

实现：

```text
VAD

Partial ASR

Final ASR

Translation Queue

Streaming DeepSeek
```

验证实时体验。

---

## Phase 3 — Desktop UI

建立：

```text
Tauri
React
Main Window
Settings
Transcript
```

---

## Phase 4 — Overlay

实现：

```text
Always-on-top

Transparent

Resizable

Click-through

Dual subtitle
```

---

## Phase 5 — System Audio

依次完成：

```text
Windows WASAPI Loopback

macOS ScreenCaptureKit

Linux PipeWire
```

建议首先完成 Windows。

---

## Phase 6 — Academic Translation

加入：

```text
Context Window

Domain Prompt

Glossary

Translation Correction
```

使用真实 NUS lecture 音频测试。

---

## Phase 7 — Packaging

生成：

```text
Windows
.msi / .exe

macOS
.dmg

Linux
.AppImage / .deb
```

---

# 28. MVP 验收标准

MVP 完成需要满足：

```text
✓ Windows 能选择麦克风
✓ Windows 能捕获系统音频
✓ 本地完成英文 ASR
✓ 音频不会上传 DeepSeek
✓ DeepSeek 实时翻译为中文
✓ English + Chinese 双语显示
✓ 支持 always-on-top overlay
✓ 网络断开不影响 English ASR
✓ API Key 安全保存
✓ Transcript 可以导出
✓ 可以运行至少 2 小时而不明显累积内存
✓ 技术课程术语翻译稳定
```

---

# 29. Work 模式首先需要完成的任务

进入 Work 后不要立刻开发完整应用。

首先完成以下顺序：

```text
1. 创建项目 repository 与目录结构

2. 编写 architecture.md

3. 建立 Tauri 2 + React + TypeScript 项目

4. 创建 Python faster-whisper sidecar

5. 实现：
   Microphone → ASR

6. 实现 DeepSeekTranslationService

7. 打通：
   Microphone
      ↓
   Local ASR
      ↓
   English
      ↓
   DeepSeek
      ↓
   Chinese

8. 加入 VAD + Translation Queue

9. 创建 Liquid Glass UI

10. 创建独立 Overlay Window

11. 实现 Windows WASAPI Loopback

12. 最后再实现 macOS / Linux 音频采集
```

---

# 30. 第一版开发原则

任何设计决定都优先遵循：

```text
Accuracy
   >
Low latency
   >
Stability
   >
Low resource usage
   >
Visual effects
```

但 UI 必须保持简洁。

本项目不是 AI Demo。

目标是：

**一款能够真正持续运行一整节大学课程的实时学术翻译工具。**

最终用户体验应该接近：

```text
Open LinguaGlass
        ↓
Select System Audio
        ↓
Start
        ↓

老师开始讲话

English appears immediately

中文稍后约数百毫秒～1 秒出现

整个过程无需用户继续操作
```

---

# 31. 当前已经确定，不需要再次讨论的技术决策

```text
Desktop:
Tauri 2

Frontend:
React + TypeScript

Native Core:
Rust

ASR:
Local

Primary ASR:
faster-whisper

Primary Model:
distil-large-v3

Language:
English only for MVP

Translation:
DeepSeek API

Default translation model:
deepseek-v4-flash

Cloud data:
Text only

UI:
Minimal Liquid Glass

Overlay:
Independent always-on-top window

Translation:
Context-aware academic translation

Development priority:
Windows → macOS → Linux
```

后续除非发现明确的技术阻碍，否则 Work 模式应按照上述技术路线继续实施，而不是重新进行框架选型。