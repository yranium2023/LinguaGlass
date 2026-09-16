# LinguaGlass UI 重设计 Work Handoff

日期：2026-09-15  
工作目录：`F:\Code\LinguaGlass`

## 新 work 的目标

用户要求暂不考虑 macOS 移植，只优化现有 Windows 前端 UI，风格为“简约高级”，参考 macOS 的克制动效和玻璃质感。

必须完成：

1. 重做当前导航栏、滚动条和窗口控制按钮。关闭、最小化、最大化/全屏按钮由前端自绘，不能继续依赖当前默认观感。
2. 优化液态玻璃效果和布局留白。界面不能逼仄，允许加入轻量的淡入、悬停、按压和状态过渡动画。
3. 背景改为纯色或低对比度纯色透明层，去掉当前彩色渐变背景和大面积高斯模糊。
4. 修复悬浮字幕四周多出的透明边。悬浮窗内容应贴合窗口边缘，不出现明显黑/透明外圈。
5. 修复白天主题下悬浮字幕仍显示夜间样式的问题。悬浮窗应根据主界面主题切换明暗样式；白天主题使用浅色字幕卡，夜间主题使用深色字幕卡。
6. 悬浮字幕页面加入明确的关闭按钮。关闭动作只隐藏悬浮窗，不影响主窗口会话。
7. 首次打开主界面时不要立即看到页面滚动条。只有内容超过视口时才显示滚动条；滚动条样式需要自定义且低存在感。

## 当前已完成、不要回退

### 字幕与翻译逻辑

- Windows 系统音频已经通过 CPAL/WASAPI Loopback 接入，麦克风模式也可用。
- GPU 预热和 CUDA 环境修复已经完成。
- API HTTP 客户端使用连接复用，DeepSeek 流式翻译已经接通。
- 翻译时延已经在真实链路中记录：90 秒公开演讲测试中，首字中位约 529ms，完整译文中位约 627ms，队列最大等待约 360ms。
- 识别与预翻译节奏已经分离：ASR 保留约 6 秒声学上下文，滚动识别结果约每 2 秒发起预翻译；不能重新改回固定 2 秒硬切 ASR。
- `groupTranscript()` 用于主界面会话记录的语义分段，按自然标点、停顿和硬上限控制长度。
- `subtitlePages()` 用于悬浮窗分页。长语义段会分页，每页最多 3 个识别段；悬浮窗保留上一页和当前页，避免同一段过长时开头被覆盖。
- `protocol.ts` 已增加 `finalized` 保护：预翻译完成后，迟到的局部识别不能覆盖最终确认字幕；同一行的英文仍可以继续更新。
- 设置中已有“字幕短停顿合并”滑块：`0.5–4.0 秒`，默认 `2.2 秒`，保存到 `localStorage`，主界面和悬浮窗会读取。

### 真实测试素材与验证

- `test-assets/english-jfk.flac` 和 `english-jfk.wav`：faster-whisper 官方短音频。
- `test-assets/jfk-rice-90s.wav`：NASA 公版的肯尼迪莱斯大学太空演讲 90 秒片段，约 2.9MB。
- 临时测试视频源已删除，不要把大视频重新加入项目。
- `scripts/native-audio-regression.cjs`：真实 Tauri/WebView2/WASAPI/系统音频/悬浮窗/API 回归脚本。
- `scripts/long-native-check.ps1`：构建临时调试版、嵌入 90 秒音频、运行原生回归、清理测试音频和调试端口、恢复正常构建。
- 最新长测已验证：没有悬浮窗滚动条，字幕卡高度稳定，卡片中英文没有被行数限制裁掉；会话记录非末尾行不在逗号后断开。

## 重点文件

- `src/frontend/Dashboard.tsx`：主窗口布局、预览、设置对话框、悬浮窗开关。
- `src/frontend/Overlay.tsx`：悬浮字幕窗口组件。当前只有拖拽标题区域、收起按钮，没有独立关闭按钮。
- `src/frontend/flat.css`：当前所有主窗口和悬浮窗样式。这里有本轮 UI 重设计的主要工作。
- `src/frontend/preferences.ts`：主题、字号和 `subtitle_pause_seconds` 偏好。
- `src/frontend/transcript.ts`：`groupTranscript()` 与 `subtitlePages()`。
- `src/frontend/protocol.ts`：事件 reducer 和 `finalized` 字段。
- `src-tauri/src/lib.rs`：窗口命令和悬浮窗尺寸控制。用户本轮要求只改前端，除非编译或现有命令确实无法满足 UI 需求，不要修改这里。
- `src-tauri/tauri.conf.json`：当前 overlay 窗口尺寸和透明配置。用户要求本轮只改前端，暂时不要改配置；如果透明外圈只能由原生窗口配置解决，应在新 work 中先说明再决定。

## 当前 UI 已知问题

截图中可见的问题：

- Windows 默认标题栏仍在，主窗口和悬浮窗都没有真正统一的自绘窗口控制。
- 页面右侧滚动条在初始空状态直接可见，视觉上很重。
- 主窗口背景仍然存在蓝紫色渐变与大面积模糊，和用户要求的纯色透明层不符。
- 悬浮窗周围有明显透明/黑色边缘；当前 `.overlay-shell` 有 margin 和圆角，可能造成外圈。
- `Overlay.tsx` 当前悬浮窗固定使用深色文字和深色背景，没有读取 `appearance.theme`，导致白天主题仍像夜间字幕。
- 悬浮窗标题栏只有收起按钮，没有关闭按钮。
- 当前主界面间距和卡片高度仍偏紧，右侧记录区在空状态占据很大高度，初始视图显得拥挤。
- 当前 `.overlay-text` 和页面滚动行为需要继续保持固定高度，不能因文字流式更新而改变窗口尺寸。

## 推荐实现顺序

### 1. 主题状态同步

- 在 `Overlay.tsx` 读取 `loadPreferences().appearance.theme`，设置 `document.documentElement.dataset.theme`。
- 监听 `storage` 事件同步主题和字号。
- 悬浮窗样式使用 `[data-surface="overlay"][data-theme="light"]`、`[data-theme="dark"]` 两套变量。
- 不要继续在 `[data-surface="overlay"]` 里硬编码 `color-scheme: dark`、白色文字和深色背景。

### 2. 重做悬浮窗边缘和控制区

- 让 `.overlay-shell` 占满窗口，不使用外层 margin；如果需要内边距，用内部内容层实现。
- 保留圆角但避免透明外圈；边框和阴影应贴合窗口边界。
- 在 `Overlay.tsx` 标题栏加入关闭按钮，调用现有的 `set_overlay` 命令隐藏悬浮窗，并清除错误状态。
- 自绘三个窗口控制按钮时，优先使用现有 `@tauri-apps/api/window` 能力；不要修改 Rust，除非当前原生命令不可用。
- 按钮必须有 `aria-label`、`title`，并在悬浮窗 click-through 开启时仍保持可用策略不变。

### 3. 主窗口布局和滚动条

- 初始空状态尽量让主窗口内容在视口内完成，不让右侧滚动条立即出现。
- 只有 `.transcript-body` 在记录较多时滚动；主页面本身应尽量 `overflow-x: hidden`，避免横向滚动条。
- 使用 `scrollbar-width: thin` 和 WebKit scrollbar 伪元素，颜色低对比度，hover 时略增强。
- 增大 section 间距、卡片内边距和标题上下留白，减少控件挤在同一行的感觉。
- 保持 1440p 和 4K 下字号可读；英文和中文字号差距不要过大。

### 4. 纯色透明玻璃与轻量动效

- 删除 body 当前蓝紫色 radial-gradient/彩色背景。
- 使用单一背景色 + 低透明度表面层，例如 `rgba(255,255,255,.72)` 或深色对应值。
- 玻璃效果只保留在 header、panel、dialog、overlay card；不要让整个页面都模糊。
- 允许使用 `opacity`、`background-color`、`box-shadow` 和轻微 `transform` 的 120–220ms 过渡。
- 不要对字幕正文做闪烁、shimmer 或连续 transform；字幕更新不能引起布局抖动。
- 尊重 `prefers-reduced-motion`。

## 前端验证命令

在 `F:\Code\LinguaGlass` 执行：

```powershell
node node_modules\vitest\vitest.mjs run
node scripts\frontend.cjs build
. .\scripts\native-env.ps1
cargo fmt --manifest-path src-tauri\Cargo.toml -- --check
cargo test --manifest-path src-tauri\Cargo.toml
```

如果需要真实长音频验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\long-native-check.ps1
```

该脚本会运行约 90 秒，结束后应确认：

- 临时 `dist/test-audio.wav` 已删除；
- 9223 调试端口没有作为正式运行配置保留；
- `src-tauri/target/debug/linguaglass.exe` 是无调试端口的正常构建；
- 主窗口和悬浮窗截图位于 `artifacts/native-audio-main.png`、`artifacts/native-overlay-audio.png`。

## 交付前检查清单

- [ ] 只改了 `src/frontend`、必要的前端测试和文档；没有改后端逻辑。
- [ ] 主窗口不再使用彩色渐变背景。
- [ ] 初始空状态不显示页面滚动条。
- [ ] 自绘关闭、最小化、最大化/全屏按钮可用。
- [ ] 悬浮窗有关闭按钮，关闭后主窗口仍正常。
- [ ] 白天/夜间主题下悬浮窗颜色正确同步。
- [ ] 悬浮窗没有透明外圈，字幕更新不闪烁、不改变窗口高度。
- [ ] 长字幕完整分页，前文不会被覆盖。
- [ ] 短停顿合并设置立即生效且重启后保留。
- [ ] 前端单元测试、TypeScript 构建、Rust 格式和测试通过。

## 注意事项

- 用户明确要求本轮只修改前端，不要为了“窗口控制按钮”顺手改 Rust。
- 不要恢复“按两秒切 ASR 段”的实现；用户已经指出那会在句中断句。
- 不要用 `subtitleText(group).slice(-2)` 一类做法截断长字幕；应使用 `subtitlePages()` 分页。
- 不要把临时 90 秒视频或音频测试源加入项目大文件。
- 项目当前没有可依赖的远程提交历史，文件可能全部显示为未跟踪；以当前工作目录文件为准。
