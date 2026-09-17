import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController {
    var onOverlayVisibilityChange: ((Bool) -> Void)?
    var onOverlayContentChange: ((String, String, Bool) -> Void)?
    var onOverlayClickThroughChange: ((Bool) -> Void)?
    var onOverlayAppearanceChange: ((Bool, Int) -> Void)? {
        didSet { onOverlayAppearanceChange?(model.isDark, model.accentIndex) }
    }

    private let model = NativeAppModel()
    private let service = RustServiceClient()
    private var speechSession: AnyObject?
    private var speechStartTask: Task<Void, Never>?
    private var partialTranslationTasks: [String: Task<Void, Never>] = [:]
    private var currentTranslationRequests: [String: String] = [:]
    private var lastProvisionalRequestAt: [String: Date] = [:]
    private var startedAt: Date?
    private var elapsedTimer: Timer?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 1_000, height: 680)
        window.title = "LinguaGlass"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.isMovableByWindowBackground = false
        self.init(window: window)

        let host = NSHostingView(rootView: NativeDashboardView(model: model))
        host.sizingOptions = [.minSize]
        window.contentView = host
        model.refreshAudioDevices()
        configureModelActions()
        configureService()
        applyAppearance(model.isDark)
    }

    private func configureModelActions() {
        model.onToggleSession = { [weak self] in self?.toggleSession() }
        model.onToggleOverlay = { [weak self] in self?.toggleOverlay() }
        model.onSaveKey = { [weak self] key in self?.saveKey(key) }
        model.onDeleteKey = { [weak self] in self?.deleteKey() }
        model.onClickThrough = { [weak self] enabled in self?.onOverlayClickThroughChange?(enabled) }
        model.onThemeChanged = { [weak self] dark in self?.applyAppearance(dark) }
        model.onAppearanceChanged = { [weak self] dark, accent in
            self?.onOverlayAppearanceChange?(dark, accent)
        }
        model.onExport = { [weak self] format in self?.exportTranscript(format: format) }
    }

    private func configureService() {
        service.onEvent = { [weak self] event in self?.handleService(event) }
        service.onExit = { [weak self] _ in
            self?.model.keyReady = false
            self?.model.notice = "翻译服务暂不可用"
        }
        do {
            try service.start()
            loadKeyAtStartup()
        } catch {
            model.notice = error.localizedDescription
        }
    }

    private func toggleSession() {
        switch model.sessionState {
        case .idle:
            requestPermissionAndStart()
        case .initializing, .listening:
            setState(.stopping)
            stopSpeechSession()
        case .stopping:
            break
        }
    }

    private func requestPermissionAndStart() {
        if model.inputMode == .system {
            beginSession()
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted { self.beginSession() }
                    else { self.model.notice = "麦克风权限未开启，请在系统设置中允许 LinguaGlass 使用麦克风。" }
                }
            }
        case .denied, .restricted:
            model.notice = "麦克风权限未开启，请在系统设置中允许 LinguaGlass 使用麦克风。"
        @unknown default:
            model.notice = "无法确认麦克风权限。"
        }
    }

    private func beginSession() {
        guard model.sessionState == .idle else { return }
        guard #available(macOS 26.0, *) else {
            presentError("Apple Speech 需要 macOS 26 或更高版本。")
            return
        }
        model.segments.removeAll()
        model.notice = ""
        partialTranslationTasks.values.forEach { $0.cancel() }
        partialTranslationTasks.removeAll()
        currentTranslationRequests.removeAll()
        lastProvisionalRequestAt.removeAll()
        publishOverlay()
        try? service.resetContext()
        setState(.initializing)

        let session = AppleSpeechSession(
            mode: model.inputMode,
            deviceUID: model.inputMode == .microphone
                ? (model.selectedInputDevice.isEmpty ? nil : model.selectedInputDevice)
                : (model.selectedOutputDevice.isEmpty ? nil : model.selectedOutputDevice),
            gain: model.inputGain
        )
        session.onEvent = { [weak self] event in self?.handleSpeech(event) }
        speechSession = session
        speechStartTask = Task { [weak self, weak session] in
            guard let self, let session else { return }
            do {
                try await session.start()
            } catch is CancellationError {
                await session.stop()
            } catch {
                await session.stop()
                if self.speechSession === session {
                    self.speechSession = nil
                    self.setState(.idle)
                    self.presentError(error.localizedDescription)
                }
            }
        }
    }

    private func stopSpeechSession() {
        speechStartTask?.cancel()
        speechStartTask = nil
        guard #available(macOS 26.0, *), let session = speechSession as? AppleSpeechSession else {
            speechSession = nil
            setState(.idle)
            return
        }
        Task { [weak self, weak session] in
            await session?.stop()
            guard let self else { return }
            if self.speechSession === session { self.speechSession = nil }
            self.setState(.idle)
        }
    }

    private func toggleOverlay() {
        model.overlayVisible.toggle()
        onOverlayVisibilityChange?(model.overlayVisible)
        publishOverlay()
    }

    private func handleSpeech(_ event: SpeechBridgeEvent) {
        switch event.type {
        case "ready":
            setState(.listening)
        case "level":
            model.level = min(1, max(0, (event.value ?? 0) * 5))
        case "asr_partial", "asr_final":
            guard let id = event.id, let text = event.text else { return }
            let isFinal = event.type == "asr_final"
            let segment = TranscriptSegment(
                id: id,
                start: event.start ?? 0,
                end: event.end ?? 0,
                english: text,
                isFinal: isFinal
            )
            if let index = model.segments.firstIndex(where: { $0.id == id }) {
                let translation = model.segments[index].chinese
                if !model.segments[index].isFinal || isFinal {
                    model.segments[index] = segment
                    model.segments[index].chinese = translation
                }
            } else {
                model.segments.append(segment)
            }
            publishOverlay()
            scheduleTranslation(id: id, text: text, isFinal: isFinal)
        case "warning":
            model.notice = event.message ?? "语音识别出现警告"
        case "error":
            setState(.idle)
            stopSpeechSession()
            presentError(event.message ?? "Apple Speech 启动失败")
        case "stopped":
            speechSession = nil
            setState(.idle)
        default:
            break
        }
    }

    private func scheduleTranslation(id: String, text: String, isFinal: Bool) {
        partialTranslationTasks[id]?.cancel()
        partialTranslationTasks[id] = nil
        if isFinal {
            lastProvisionalRequestAt[id] = nil
            requestTranslation(id: id, text: text, provisional: false)
            return
        }
        guard model.keyReady, text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5 else { return }
        let elapsed = model.segments.first(where: { $0.id == id }).map { max(0, $0.end - $0.start) } ?? 0
        let requestedDelay = model.asrSilenceSeconds * model.asrPatience
        let cadence = min(4.0, max(1.2, model.asrMaxSegmentSeconds / 8.0))
        let now = Date()
        let sinceLast = lastProvisionalRequestAt[id].map { now.timeIntervalSince($0) }
        if (sinceLast == nil && elapsed >= max(1.2, requestedDelay)) || (sinceLast ?? 0) >= cadence {
            lastProvisionalRequestAt[id] = now
            requestTranslation(id: id, text: text, provisional: true)
            return
        }
        let delay = UInt64(max(0.25, requestedDelay) * 1_000_000_000)
        partialTranslationTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            self?.lastProvisionalRequestAt[id] = Date()
            self?.requestTranslation(id: id, text: text, provisional: true)
        }
    }

    private func requestTranslation(id: String, text: String, provisional: Bool) {
        let models = ["deepseek-v4-flash", "deepseek-v4-pro"]
        let domains = ["General", "Computer Science", "Artificial Intelligence", "Mathematics", "Engineering", "Custom"]
        let contexts = [0, 2, 3, 4]
        let requestID = UUID().uuidString
        currentTranslationRequests[id] = requestID
        do {
            try service.translate(
                id: id,
                requestID: requestID,
                text: text,
                model: models[min(models.count - 1, max(0, model.translationModel))],
                domain: domains[min(domains.count - 1, max(0, model.domainIndex))],
                glossary: model.glossary,
                contextLength: contexts[min(contexts.count - 1, max(0, model.contextIndex))],
                provisional: provisional
            )
        } catch {
            setTranslation(id: id, text: "翻译服务不可用")
            model.notice = error.localizedDescription
        }
    }

    private func handleService(_ event: RustServiceEvent) {
        if event.type.hasPrefix("translation_"), let id = event.id,
           let requestID = event.requestID, currentTranslationRequests[id] != requestID {
            return
        }
        switch event.type {
        case "service_ready", "key_status":
            if let ready = event.keyReady {
                model.keyReady = ready
                UserDefaults.standard.set(ready, forKey: "native.deepseek.configured")
            }
        case "key_saved":
            model.keyReady = true
            UserDefaults.standard.set(true, forKey: "native.deepseek.configured")
            model.notice = "API Key 已安全保存到系统钥匙串"
        case "key_deleted":
            model.keyReady = false
            UserDefaults.standard.set(false, forKey: "native.deepseek.configured")
            model.notice = "API Key 已移除"
        case "translation_started":
            if let id = event.id { setTranslation(id: id, text: "正在翻译…") }
        case "translation_delta", "translation_done":
            if let id = event.id, let text = event.text { setTranslation(id: id, text: text) }
        case "translation_error":
            if let id = event.id { setTranslation(id: id, text: event.message ?? "翻译暂不可用") }
        case "service_error":
            presentError(event.message ?? "翻译服务操作失败")
        default:
            break
        }
    }

    private func setTranslation(id: String, text: String) {
        guard let index = model.segments.firstIndex(where: { $0.id == id }) else { return }
        model.segments[index].chinese = text
        publishOverlay()
    }

    private func saveKey(_ rawKey: String) {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            presentError("请输入 DeepSeek API Key。")
            return
        }
        do {
            try KeychainStore.save(key)
            try service.setRuntimeKey(key)
            model.keyReady = true
            UserDefaults.standard.set(true, forKey: "native.deepseek.configured")
            model.notice = "API Key 已安全保存；本次运行不会再次读取钥匙串"
        } catch { presentError(error.localizedDescription) }
    }

    private func deleteKey() {
        do {
            try KeychainStore.delete()
            try service.clearRuntimeKey()
            model.keyReady = false
            UserDefaults.standard.set(false, forKey: "native.deepseek.configured")
            model.notice = "API Key 已移除"
        } catch { presentError(error.localizedDescription) }
    }

    private func loadKeyAtStartup() {
        do {
            let key = try KeychainStore.read()
            model.keyReady = key != nil
            UserDefaults.standard.set(key != nil, forKey: "native.deepseek.configured")
            if let key { try service.setRuntimeKey(key) }
        } catch {
            model.keyReady = false
            model.notice = error.localizedDescription
        }
    }

    private func exportTranscript(format: Int) {
        guard !model.segments.isEmpty, let window else { return }
        let extensions = ["md", "txt", "json"]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "LinguaGlass-会话.\(extensions[min(2, max(0, format))])"
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let content: String
            switch format {
            case 1:
                content = self.model.segments.map { "[\(self.timecode($0.start))] \($0.english)\n\($0.chinese)" }.joined(separator: "\n\n")
            case 2:
                let rows: [[String: Any]] = self.model.segments.map { ["start": $0.start, "end": $0.end, "english": $0.english, "chinese": $0.chinese] }
                let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
                content = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            default:
                content = self.model.segments.map { "### \(self.timecode($0.start))\n\n\($0.english)\n\n\($0.chinese)" }.joined(separator: "\n\n---\n\n")
            }
            do { try content.write(to: url, atomically: true, encoding: .utf8) }
            catch { self.presentError("导出失败：\(error.localizedDescription)") }
        }
    }

    private func timecode(_ seconds: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func setState(_ state: SessionState) {
        model.sessionState = state
        if state == .listening {
            startedAt = Date()
            elapsedTimer?.invalidate()
            elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let startedAt = self.startedAt else { return }
                    self.model.elapsed = Int(Date().timeIntervalSince(startedAt))
                }
            }
        } else if state == .idle {
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            startedAt = nil
            model.elapsed = 0
            model.level = 0
        }
    }

    private func applyAppearance(_ dark: Bool) {
        window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }

    private func publishOverlay() {
        let latest = model.latest
        let chinese: String
        if let translated = latest?.chinese, !translated.isEmpty {
            chinese = translated
        } else if latest == nil {
            chinese = "中文翻译将在这里显示"
        } else if latest?.isFinal == true {
            chinese = model.keyReady ? "正在翻译…" : "请先配置 DeepSeek API Key"
        } else {
            chinese = "正在识别…"
        }
        onOverlayContentChange?(
            latest?.english ?? "Start listening in the main window",
            chinese,
            latest?.isFinal == false
        )
    }

    func overlayWasClosed() { model.overlayVisible = false }

    private func presentError(_ message: String) {
        model.notice = message
        let alert = NSAlert()
        alert.messageText = "LinguaGlass"
        alert.informativeText = message
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) }
    }

    func shutdown() {
        model.persist()
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        partialTranslationTasks.values.forEach { $0.cancel() }
        stopSpeechSession()
        service.terminate()
    }
}
