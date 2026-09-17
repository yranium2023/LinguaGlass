import AppKit
import Combine
import CoreAudio
import SwiftUI

struct BrandMark: View {
    let size: CGFloat
    let accent: Color

    var body: some View {
        LinearGradient(
            colors: [
                accent.opacity(0.68),
                accent,
                accent.opacity(0.82)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        .overlay(
            Image(systemName: "waveform")
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .stroke(Color.white.opacity(0.20), lineWidth: 0.7)
        )
        .shadow(color: accent.opacity(0.25), radius: size * 0.3, y: size * 0.12)
    }
}

@MainActor
final class NativeAppModel: ObservableObject {
    @Published var page = 0
    @Published var sessionState = SessionState.idle
    @Published var segments: [TranscriptSegment] = []
    @Published var level = 0.0
    @Published var elapsed = 0
    @Published var overlayVisible = false
    @Published var keyReady = UserDefaults.standard.bool(forKey: "native.deepseek.configured")
    @Published var notice = ""
    @Published var inputMode = AudioInputMode(rawValue: UserDefaults.standard.string(forKey: "native.input.mode") ?? "system") ?? .system
    @Published var isDark = UserDefaults.standard.bool(forKey: "native.theme.dark")
    @Published var accentIndex = max(1, UserDefaults.standard.integer(forKey: "native.accent.index"))
    @Published var sizeIndex = UserDefaults.standard.integer(forKey: "native.size.index")
    @Published var translationModel = UserDefaults.standard.integer(forKey: "native.translation.model")
    @Published var domainIndex = UserDefaults.standard.integer(forKey: "native.translation.domain")
    @Published var contextIndex = UserDefaults.standard.object(forKey: "native.translation.context") == nil
        ? 2 : UserDefaults.standard.integer(forKey: "native.translation.context")
    @Published var glossary = UserDefaults.standard.string(forKey: "native.glossary") ?? ""
    @Published var pauseSeconds = UserDefaults.standard.object(forKey: "native.subtitle.pause") == nil
        ? 2.2 : UserDefaults.standard.double(forKey: "native.subtitle.pause")
    @Published var inputGain = UserDefaults.standard.object(forKey: "native.input.gain") == nil
        ? 1.0 : UserDefaults.standard.double(forKey: "native.input.gain")
    @Published var asrSilenceSeconds = UserDefaults.standard.object(forKey: "native.asr.silence") == nil
        ? 0.7 : UserDefaults.standard.double(forKey: "native.asr.silence")
    @Published var asrMaxSegmentSeconds = UserDefaults.standard.object(forKey: "native.asr.maxSegment") == nil
        ? 20.0 : UserDefaults.standard.double(forKey: "native.asr.maxSegment")
    @Published var asrPatience = UserDefaults.standard.object(forKey: "native.asr.patience") == nil
        ? 1.2 : UserDefaults.standard.double(forKey: "native.asr.patience")
    @Published var clickThrough = false
    @Published var inputDevices: [AudioDeviceOption] = []
    @Published var outputDevices: [AudioDeviceOption] = []
    @Published var selectedInputDevice = UserDefaults.standard.string(forKey: "native.input.device") ?? ""
    @Published var selectedOutputDevice = UserDefaults.standard.string(forKey: "native.output.device") ?? ""
    @Published var exportFormat = 0
    @Published var followLatest = UserDefaults.standard.object(forKey: "native.transcript.followLatest") == nil
        ? true : UserDefaults.standard.bool(forKey: "native.transcript.followLatest")

    var onToggleSession: (() -> Void)?
    var onToggleOverlay: (() -> Void)?
    var onSaveKey: ((String) -> Void)?
    var onDeleteKey: (() -> Void)?
    var onClickThrough: ((Bool) -> Void)?
    var onThemeChanged: ((Bool) -> Void)?
    var onAppearanceChanged: ((Bool, Int) -> Void)?
    var onExport: ((Int) -> Void)?

    var accent: Color {
        switch accentIndex {
        case 2: Color(red: 0.65, green: 0.30, blue: 0.73)
        case 3: Color(red: 0.96, green: 0.25, blue: 0.57)
        case 4: Color(red: 1.00, green: 0.29, blue: 0.31)
        case 5: Color(red: 1.00, green: 0.46, blue: 0.08)
        case 6: Color(red: 1.00, green: 0.72, blue: 0.00)
        case 7: Color(red: 0.32, green: 0.72, blue: 0.22)
        case 8: Color(red: 0.52, green: 0.54, blue: 0.58)
        default: Color(red: 0.03, green: 0.45, blue: 0.95)
        }
    }

    var scale: CGFloat { [1.0, 1.08, 1.16][min(2, max(0, sizeIndex))] }
    var active: Bool { sessionState != .idle }
    var latest: TranscriptSegment? { segments.last }

    func refreshAudioDevices() {
        inputDevices = AudioDeviceCatalog.inputs()
        outputDevices = AudioDeviceCatalog.outputs()
        if !inputDevices.contains(where: { $0.id == selectedInputDevice }) {
            selectedInputDevice = inputDevices.first(where: \.isDefault)?.id ?? inputDevices.first?.id ?? ""
        }
        if !outputDevices.contains(where: { $0.id == selectedOutputDevice }) {
            selectedOutputDevice = outputDevices.first(where: \.isDefault)?.id ?? outputDevices.first?.id ?? ""
        }
    }

    func persist() {
        let defaults = UserDefaults.standard
        defaults.set(isDark, forKey: "native.theme.dark")
        defaults.set(accentIndex, forKey: "native.accent.index")
        defaults.set(sizeIndex, forKey: "native.size.index")
        defaults.set(translationModel, forKey: "native.translation.model")
        defaults.set(domainIndex, forKey: "native.translation.domain")
        defaults.set(contextIndex, forKey: "native.translation.context")
        defaults.set(glossary, forKey: "native.glossary")
        defaults.set(pauseSeconds, forKey: "native.subtitle.pause")
        defaults.set(inputMode.rawValue, forKey: "native.input.mode")
        defaults.set(selectedInputDevice, forKey: "native.input.device")
        defaults.set(selectedOutputDevice, forKey: "native.output.device")
        defaults.set(inputGain, forKey: "native.input.gain")
        defaults.set(asrSilenceSeconds, forKey: "native.asr.silence")
        defaults.set(asrMaxSegmentSeconds, forKey: "native.asr.maxSegment")
        defaults.set(asrPatience, forKey: "native.asr.patience")
        defaults.set(followLatest, forKey: "native.transcript.followLatest")
    }
}

struct NativeDashboardView: View {
    @ObservedObject var model: NativeAppModel
    @State private var apiKey = ""

    private var background: Color { model.isDark ? Color(red: 0.055, green: 0.07, blue: 0.095) : Color(red: 0.945, green: 0.957, blue: 0.978) }
    private var surface: Color { model.isDark ? Color.white.opacity(0.065) : Color.white.opacity(0.72) }
    private var line: Color { model.isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07) }
    private var secondary: Color { model.isDark ? Color.white.opacity(0.58) : Color.black.opacity(0.52) }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            Circle().fill(model.accent.opacity(model.isDark ? 0.09 : 0.055)).frame(width: 520).blur(radius: 70).offset(x: 520, y: -380)
            VStack(spacing: 0) {
                appHeader
                if model.page == 0 { dashboard } else { settings }
            }
        }
        .preferredColorScheme(model.isDark ? .dark : .light)
        .environment(\.colorScheme, model.isDark ? .dark : .light)
        .font(.system(size: 13 * model.scale))
    }

    private var appHeader: some View {
        HStack(spacing: 12) {
            BrandMark(size: 38, accent: model.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("LinguaGlass").font(.system(size: 16, weight: .semibold))
                Text("Academic Live Interpreter").font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
            }
            Spacer()
            topButton("waveform", "实时会话", active: model.page == 0) { model.page = 0 }
            topButton("slider.horizontal.3", "设置", active: model.page == 1) { model.page = 1 }
            Button {
                model.isDark.toggle(); model.persist(); model.onThemeChanged?(model.isDark)
                model.onAppearanceChanged?(model.isDark, model.accentIndex)
            } label: {
                Image(systemName: model.isDark ? "sun.max" : "moon").frame(width: 32, height: 30).contentShape(Rectangle())
            }.buttonStyle(GlassButtonStyle(surface: surface, line: line))
        }
        .padding(.leading, 28).padding(.trailing, 24).frame(height: 70)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(line).frame(height: 1) }
    }

    private func topButton(_ icon: String, _ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 12, weight: .medium)).padding(.horizontal, 3)
        }
        .buttonStyle(GlassButtonStyle(surface: active ? model.accent.opacity(0.12) : surface, line: active ? model.accent.opacity(0.20) : line, foreground: active ? model.accent : nil))
    }

    private var dashboard: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIVE INTERPRETATION").font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(model.accent)
                    Text("实时翻译").font(.system(size: 27 * model.scale, weight: .semibold))
                }
                Spacer()
                statusPill
            }
            HStack(alignment: .top, spacing: 18) {
                controlPanel.frame(width: 326)
                VStack(spacing: 16) {
                    subtitlePanel.frame(height: 185)
                    transcriptPanel
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 24)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle().fill(model.sessionState == .listening ? Color.green : secondary).frame(width: 7, height: 7)
            Text(model.sessionState.title)
            if model.sessionState == .listening { Text(String(format: "%02d:%02d", model.elapsed / 60, model.elapsed % 60)).monospacedDigit() }
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(secondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(surface, in: Capsule()).overlay(Capsule().stroke(line))
    }

    private var controlPanel: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("声音来源").font(.system(size: 16, weight: .semibold))
                HStack(spacing: 4) {
                    sourceButton("display", "系统音频", .system)
                    sourceButton("mic", "麦克风", .microphone)
                }.padding(4).background(line.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
                Text(model.inputMode == .system ? "识别课程、视频或会议声音" : "识别你和周围人的讲话")
                    .font(.system(size: 11)).foregroundStyle(secondary)
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.inputMode == .system ? "播放设备" : "输入设备").font(.system(size: 11, weight: .medium)).foregroundStyle(secondary)
                    devicePicker
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.sessionState == .listening ? "输入电平" : "音量监测").font(.system(size: 11, weight: .medium)).foregroundStyle(secondary)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(line)
                            Capsule().fill(Color.green).frame(width: max(0, proxy.size.width * model.level))
                        }
                    }.frame(height: 6)
                }
                Button(action: { model.onToggleSession?() }) {
                    HStack { Image(systemName: model.active ? "stop.fill" : "play.fill"); Text(primaryTitle) }
                        .frame(maxWidth: .infinity).padding(.vertical, 11).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.white).font(.system(size: 13, weight: .semibold))
                .background(LinearGradient(colors: primaryColors, startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: primaryColors.last!.opacity(0.22), radius: 12, y: 5)
                if !model.notice.isEmpty {
                    Label(model.notice, systemImage: "info.circle.fill")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(model.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().opacity(0.7)
                engineRow("英文识别", "Apple Speech")
                engineRow("中文翻译", model.keyReady ? "DeepSeek 已就绪" : "未配置密钥")
                Label("音频始终留在本机", systemImage: "lock.fill").font(.system(size: 10)).foregroundStyle(secondary)
            }
        }
    }

    private func sourceButton(_ icon: String, _ title: String, _ mode: AudioInputMode) -> some View {
        Button { if !model.active { model.inputMode = mode; model.persist() } } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity).padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).font(.system(size: 12, weight: .medium))
            .foregroundStyle(model.inputMode == mode ? model.accent : secondary)
            .background(model.inputMode == mode ? surface : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.inputMode == mode ? line : .clear))
            .disabled(model.active)
    }

    private var devicePicker: some View {
        let devices = model.inputMode == .system ? model.outputDevices : model.inputDevices
        let selection = Binding<String>(
            get: { model.inputMode == .system ? model.selectedOutputDevice : model.selectedInputDevice },
            set: { value in
                if model.inputMode == .system { model.selectedOutputDevice = value }
                else { model.selectedInputDevice = value }
                if model.inputMode == .system { _ = AudioDeviceCatalog.setDefaultOutput(uid: value) }
                model.persist()
            }
        )
        return GlassDropdown(
            selection: selection,
            options: devices.map { ($0.name + ($0.isDefault ? " · 默认" : ""), $0.id) },
            placeholder: "未检测到可用设备",
            surface: surface,
            line: line,
            accent: model.accent
        )
        .disabled(model.active || devices.isEmpty)
    }

    private var subtitlePanel: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("实时字幕", systemImage: "captions.bubble").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Button(model.overlayVisible ? "关闭悬浮字幕" : "打开悬浮字幕") { model.onToggleOverlay?() }
                        .buttonStyle(GlassButtonStyle(surface: surface, line: line))
                }
                Text(model.latest?.english ?? "Your English transcript will appear here.")
                    .font(.system(size: 14)).foregroundStyle(secondary).lineLimit(2)
                Text(subtitleChinese).font(.system(size: 18, weight: .medium)).lineLimit(2)
                Spacer(minLength: 0)
            }
        }
    }

    private var transcriptPanel: some View {
        card {
            VStack(spacing: 0) {
                HStack {
                    Text("会话记录").font(.system(size: 16, weight: .semibold))
                    Text("\(model.segments.filter(\.isFinal).count)").foregroundStyle(secondary)
                    Spacer()
                    GlassDropdown(
                        selection: $model.exportFormat,
                        options: [("MD", 0), ("TXT", 1), ("JSON", 2)],
                        placeholder: "MD",
                        surface: surface,
                        line: line,
                        accent: model.accent
                    ).frame(width: 86)
                    Button(action: { model.onExport?(model.exportFormat) }) {
                        Image(systemName: "square.and.arrow.down").frame(width: 18, height: 18).contentShape(Rectangle())
                    }.buttonStyle(GlassButtonStyle(surface: surface, line: line)).disabled(model.segments.isEmpty)
                }.padding(.bottom, 12)
                Divider().opacity(0.65)
                if model.segments.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "text.book.closed").font(.system(size: 30, weight: .light)).foregroundStyle(model.accent)
                        Text("准备好，就开始吧").font(.system(size: 15, weight: .medium))
                        Text("英文原文与中文翻译会整理在这里").font(.system(size: 11)).foregroundStyle(secondary)
                    }
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(model.segments) { segment in
                                    transcriptRow(segment).padding(.vertical, 12)
                                    Divider().opacity(0.55)
                                }
                                Color.clear.frame(height: 1).id("transcript-bottom")
                            }
                        }
                        .onChange(of: model.segments) {
                            guard model.followLatest else { return }
                            withAnimation(.easeOut(duration: 0.18)) {
                                proxy.scrollTo("transcript-bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                HStack {
                    Text("本次会话保存在本机").font(.system(size: 10)).foregroundStyle(secondary)
                    Spacer()
                    Toggle("跟随最新", isOn: $model.followLatest).toggleStyle(.checkbox).font(.system(size: 10))
                        .onChange(of: model.followLatest) { model.persist() }
                }.padding(.top, 10)
            }
        }
    }

    private func transcriptRow(_ segment: TranscriptSegment) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(timecode(segment.start)).font(.system(size: 10, design: .monospaced)).foregroundStyle(secondary).frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(segment.english).font(.system(size: 13)).foregroundStyle(segment.isFinal ? Color.primary : secondary)
                Text(segment.chinese.isEmpty ? (segment.isFinal ? "正在翻译…" : "正在识别…") : segment.chinese).font(.system(size: 14, weight: .medium))
            }
            Spacer()
        }
    }

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置").font(.system(size: 27 * model.scale, weight: .semibold))
                    Text("翻译、识别与界面偏好").font(.system(size: 12)).foregroundStyle(secondary)
                }
                HStack(alignment: .top, spacing: 18) {
                    translationSettings
                    localSettings
                }
            }.padding(.horizontal, 28).padding(.vertical, 24)
        }
    }

    private var translationSettings: some View {
        card {
            VStack(alignment: .leading, spacing: 13) {
                Label("DeepSeek 翻译", systemImage: "sparkles").font(.system(size: 16, weight: .semibold))
                Label(model.keyReady ? "密钥已安全保存" : "尚未配置 API Key", systemImage: model.keyReady ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(model.keyReady ? Color.green : secondary)
                HStack(spacing: 8) {
                    SecureField("DeepSeek API Key", text: $apiKey).textFieldStyle(.plain).padding(10).background(surface, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(line))
                    Button("保存") { model.onSaveKey?(apiKey); apiKey = "" }.buttonStyle(GlassButtonStyle(surface: surface, line: line))
                    Button("移除") { model.onDeleteKey?() }.buttonStyle(GlassButtonStyle(surface: surface, line: line))
                }
                settingsRow("翻译模型") { dropdown($model.translationModel, [("V4 Flash", 0), ("V4 Pro", 1)], width: 150) }
                HStack(spacing: 16) {
                    settingsRow("领域") { dropdown($model.domainIndex, [("通用", 0), ("计算机科学", 1), ("人工智能", 2), ("数学", 3), ("工程", 4), ("自定义", 5)], width: 135) }
                    settingsRow("上下文") { dropdown($model.contextIndex, [("无", 0), ("2 段", 1), ("3 段", 2), ("4 段", 3)], width: 95) }
                }
                Text("课程术语表").font(.system(size: 11, weight: .medium)).foregroundStyle(secondary)
                TextEditor(text: $model.glossary).font(.system(size: 12)).scrollContentBackground(.hidden).padding(8).frame(height: 88).background(surface, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(line))
                Label("密钥启动时读取一次；识别中的英文也会增量翻译", systemImage: "lock.fill").font(.system(size: 10)).foregroundStyle(secondary)
            }
        }
        .onChange(of: model.translationModel) { model.persist() }
        .onChange(of: model.domainIndex) { model.persist() }
        .onChange(of: model.contextIndex) { model.persist() }
        .onChange(of: model.glossary) { model.persist() }
    }

    private var localSettings: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Label("本地识别与字幕", systemImage: "waveform.badge.mic").font(.system(size: 16, weight: .semibold))
                settingsRow("识别引擎") { Text("Apple Speech · English (US)").foregroundStyle(secondary) }
                parameterSlider("输入增益", value: $model.inputGain, range: 0...2, step: 0.05) {
                    "\(Int($0 * 100))%"
                }
                parameterSlider("增量翻译等待", value: $model.asrSilenceSeconds, range: 0.4...2, step: 0.1) {
                    String(format: "%.1f 秒", $0)
                }
                parameterSlider("连续语音最长片段", value: $model.asrMaxSegmentSeconds, range: 8...30, step: 1) {
                    "\(Int($0)) 秒"
                }
                parameterSlider("定稿耐心", value: $model.asrPatience, range: 1...2, step: 0.1) {
                    String(format: "%.1f×", $0)
                }
                VStack(alignment: .leading, spacing: 7) {
                    HStack { Text("字幕停顿合并"); Spacer(); Text(String(format: "%.1f 秒", model.pauseSeconds)).foregroundStyle(secondary) }
                    Slider(value: $model.pauseSeconds, in: 0.5...4, step: 0.1).tint(model.accent)
                }.font(.system(size: 11, weight: .medium))
                Toggle("悬浮字幕鼠标穿透", isOn: $model.clickThrough).toggleStyle(.switch).tint(model.accent)
                    .onChange(of: model.clickThrough) { _, enabled in model.onClickThrough?(enabled) }
                Divider().opacity(0.7)
                Label("界面", systemImage: "paintpalette").font(.system(size: 15, weight: .semibold))
                accentPalette
                settingsRow("界面字号") { dropdown($model.sizeIndex, [("标准", 0), ("大", 1), ("特大", 2)], width: 100) }
                Label("Apple Speech 在本机识别，音频不会上传", systemImage: "hand.raised.fill").font(.system(size: 10)).foregroundStyle(secondary)
            }
        }
        .onChange(of: model.pauseSeconds) { model.persist() }
        .onChange(of: model.inputGain) { model.persist() }
        .onChange(of: model.asrSilenceSeconds) { model.persist() }
        .onChange(of: model.asrMaxSegmentSeconds) { model.persist() }
        .onChange(of: model.asrPatience) { model.persist() }
        .onChange(of: model.accentIndex) { _, accent in
            model.persist(); model.onAppearanceChanged?(model.isDark, accent)
        }
        .onChange(of: model.sizeIndex) { model.persist() }
    }

    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack { Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(secondary); Spacer(); content() }
    }

    private func parameterSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue)).foregroundStyle(secondary).monospacedDigit()
            }
            Slider(value: value, in: range, step: step).tint(model.accent)
        }
        .font(.system(size: 11, weight: .medium))
    }

    private var accentPalette: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("强调色").font(.system(size: 11, weight: .medium)).foregroundStyle(secondary)
            HStack(spacing: 12) {
                ForEach(1..<9, id: \.self) { index in
                    Button {
                        model.accentIndex = index
                        model.persist()
                        model.onAppearanceChanged?(model.isDark, index)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(accentSwatch(index))
                                .frame(width: 20, height: 20)
                            if model.accentIndex == index {
                                Circle().stroke(model.isDark ? Color.white : Color.black, lineWidth: 2)
                                    .frame(width: 26, height: 26)
                                Circle().stroke(Color.white.opacity(0.9), lineWidth: 1)
                                    .frame(width: 23, height: 23)
                            }
                        }
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(["", "蓝色", "紫色", "粉色", "红色", "橙色", "黄色", "绿色", "灰色"][index])
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func accentSwatch(_ index: Int) -> AnyShapeStyle {
        let colors: [Color] = [
            .clear,
            Color(red: 0.03, green: 0.45, blue: 0.95),
            Color(red: 0.65, green: 0.30, blue: 0.73),
            Color(red: 0.96, green: 0.25, blue: 0.57),
            Color(red: 1.00, green: 0.29, blue: 0.31),
            Color(red: 1.00, green: 0.46, blue: 0.08),
            Color(red: 1.00, green: 0.72, blue: 0.00),
            Color(red: 0.32, green: 0.72, blue: 0.22),
            Color(red: 0.52, green: 0.54, blue: 0.58)
        ]
        return AnyShapeStyle(colors[index])
    }

    private func dropdown<Value: Hashable>(_ selection: Binding<Value>, _ options: [(String, Value)], width: CGFloat) -> some View {
        GlassDropdown(selection: selection, options: options, placeholder: "—", surface: surface, line: line, accent: model.accent)
            .frame(width: width)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(model.isDark ? Color.white.opacity(0.055) : Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(line))
            .shadow(color: Color.black.opacity(model.isDark ? 0.18 : 0.045), radius: 22, y: 10)
    }

    private func glassField<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().font(.system(size: 11, weight: .medium)).foregroundStyle(secondary).padding(.horizontal, 11).frame(height: 34).background(surface, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(line))
    }

    private func engineRow(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(secondary); Spacer(); Text(value).fontWeight(.medium) }.font(.system(size: 10))
    }

    private var primaryTitle: String {
        switch model.sessionState { case .idle: "开始聆听"; case .initializing: "取消加载"; case .listening: "结束聆听"; case .stopping: "正在结束…" }
    }
    private var primaryColors: [Color] {
        switch model.sessionState { case .idle: [model.accent.opacity(0.78), model.accent]; case .initializing: [.orange.opacity(0.8), .orange]; case .listening, .stopping: [.red.opacity(0.78), .red] }
    }
    private var subtitleChinese: String {
        guard let latest = model.latest else { return "开始聆听后，中文翻译会显示在这里。" }
        if !latest.chinese.isEmpty { return latest.chinese }
        return latest.isFinal ? (model.keyReady ? "正在翻译…" : "配置 DeepSeek 密钥后显示中文") : "正在识别英文…"
    }
    private func timecode(_ seconds: TimeInterval) -> String { String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}

struct GlassDropdown<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(String, Value)]
    let placeholder: String
    let surface: Color
    let line: Color
    let accent: Color
    @State private var presented = false

    private var selectedTitle: String { options.first(where: { $0.1 == selection })?.0 ?? placeholder }

    var body: some View {
        Button { presented.toggle() } label: {
            HStack(spacing: 8) {
                Text(selectedTitle).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 11).frame(maxWidth: .infinity, minHeight: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(presented ? accent.opacity(0.45) : line))
        .popover(isPresented: $presented, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        selection = option.1
                        presented = false
                    } label: {
                        HStack {
                            Text(option.0)
                            Spacer()
                            if option.1 == selection { Image(systemName: "checkmark").foregroundStyle(accent) }
                        }
                        .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(option.1 == selection ? accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(8).frame(minWidth: 180)
            .background(.ultraThinMaterial)
        }
    }
}

struct GlassButtonStyle: ButtonStyle {
    let surface: Color
    let line: Color
    var foreground: Color? = nil
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .medium)).foregroundStyle(foreground ?? .primary)
            .padding(.horizontal, 11).frame(height: 32)
            .contentShape(Rectangle())
            .background(surface.opacity(configuration.isPressed ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(line))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
