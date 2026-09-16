import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit
import Speech

private struct Options {
    var doctor = false
    var prepare = false
    var mode = "microphone"
    var locale = "en-US"

    init(_ arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--doctor": doctor = true
            case "--prepare": prepare = true
            case "--mode": mode = iterator.next() ?? mode
            case "--locale": locale = iterator.next() ?? locale
            default: break
            }
        }
    }
}

private final class JSONEmitter: @unchecked Sendable {
    private let lock = NSLock()
    func send(_ type: String, _ fields: [String: Any] = [:]) {
        var payload = fields
        payload["type"] = type
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        lock.lock()
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        lock.unlock()
    }
}

@available(macOS 26.0, *)
private final class SpeechSession: NSObject, @unchecked Sendable {
    private let emitter: JSONEmitter
    private let mode: String
    private let locale: Locale
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AnalyzerInputConverter?
    private var resultTask: Task<Void, Never>?
    private let microphone = AVAudioEngine()
    private var screenStream: SCStream?
    private let screenQueue = DispatchQueue(label: "com.linguaglass.speech.system-audio")
    private let started = ContinuousClock.now
    private var segment = 0
    private let stateLock = NSLock()

    init(emitter: JSONEmitter, mode: String, locale: Locale) {
        self.emitter = emitter
        self.mode = mode
        self.locale = locale
    }

    static func supportedLocale(_ locale: Locale) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: locale)
    }

    func prepareAssets() async throws {
        guard SpeechTranscriber.isAvailable else { throw BridgeError("当前 Mac 不支持 Apple SpeechTranscriber") }
        guard let supported = await Self.supportedLocale(locale) else { throw BridgeError("不支持所选语言") }
        let module = SpeechTranscriber(locale: supported, preset: .progressiveLiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            emitter.send("model_status", ["state": "downloading", "locale": supported.identifier])
            try await request.downloadAndInstall()
        }
        emitter.send("model_status", ["state": "ready", "locale": supported.identifier])
    }

    func start() async throws {
        guard let supported = await Self.supportedLocale(locale) else { throw BridgeError("不支持所选语言") }
        let transcriber = SpeechTranscriber(
            locale: supported,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            emitter.send("model_status", ["state": "downloading", "locale": supported.identifier])
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw BridgeError("无法取得 Apple Speech 音频格式")
        }
        let (sequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        self.inputContinuation = continuation
        self.converter = AnalyzerInputConverter(analyzerFormat: format)
        try await analyzer.start(inputSequence: sequence)

        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results { self?.emit(result) }
            } catch {
                self?.emitter.send("error", ["message": "Apple 本地语音识别意外停止"])
            }
        }
        if mode == "system" { try await startSystemAudio() } else { try startMicrophone() }
        emitter.send("ready", ["backend": "apple_speech", "locale": supported.identifier])
    }

    private func emit(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stateLock.lock()
        let id = "apple-\(segment)"
        if result.isFinal { segment += 1 }
        stateLock.unlock()
        let end = Double(started.duration(to: .now).components.seconds)
        emitter.send(result.isFinal ? "asr_final" : "asr_partial", [
            "id": id, "text": text, "start": max(0, end - 1), "end": end
        ])
    }

    private func startMicrophone() throws {
        let input = microphone.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in self?.consume(buffer) }
        microphone.prepare()
        try microphone.start()
    }

    private func startSystemAudio() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw BridgeError("没有可捕获的显示器") }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: screenQueue)
        try await stream.startCapture()
        screenStream = stream
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let continuation = inputContinuation else { return }
        do {
            for input in try converter.convert(buffer, at: nil) { continuation.yield(input) }
            if let data = buffer.floatChannelData {
                let count = Int(buffer.frameLength)
                let rms = count == 0 ? 0 : sqrt((0..<count).reduce(Float(0)) { $0 + data[0][$1] * data[0][$1] } / Float(count))
                emitter.send("level", ["value": rms])
            }
        } catch { emitter.send("warning", ["message": "部分音频无法转换，识别继续运行"]) }
    }

    func stop() async {
        microphone.inputNode.removeTap(onBus: 0)
        microphone.stop()
        if let stream = screenStream { try? await stream.stopCapture() }
        if let converter, let continuation = inputContinuation {
            if let remaining = try? converter.flush() { for input in remaining { continuation.yield(input) } }
            continuation.finish()
        }
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultTask?.cancel()
        emitter.send("stopped")
    }
}

@available(macOS 26.0, *)
extension SpeechSession: SCStreamDelegate, SCStreamOutput {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        emitter.send("error", ["message": "系统音频捕获已停止，请检查屏幕与系统音频录制权限"])
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        try? sampleBuffer.withAudioBufferList { audioBufferList, _ in
            guard let description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                  let format = AVAudioFormat(standardFormatWithSampleRate: description.mSampleRate,
                                             channels: description.mChannelsPerFrame),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                bufferListNoCopy: audioBufferList.unsafePointer)
            else { return }
            consume(buffer)
        }
    }
}

private struct BridgeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@main private struct LinguaGlassSpeechBridge {
    static func main() async {
        let options = Options(CommandLine.arguments)
        let emitter = JSONEmitter()
        guard #available(macOS 26.0, *) else {
            emitter.send("error", ["message": "Apple Speech 后端需要 macOS 26 或更高版本"])
            return
        }
        let locale = Locale(identifier: options.locale)
        guard SpeechTranscriber.isAvailable, let supported = await SpeechSession.supportedLocale(locale) else {
            emitter.send("doctor", ["available": false, "locale": options.locale])
            return
        }
        if options.doctor {
            let installed = await SpeechTranscriber.installedLocales
            emitter.send("doctor", ["available": true, "locale": supported.identifier,
                                     "installed": installed.contains { $0.identifier == supported.identifier }])
            return
        }
        let session = SpeechSession(emitter: emitter, mode: options.mode, locale: supported)
        do {
            if options.prepare { try await session.prepareAssets(); return }
            try await session.start()
            _ = readLine()
            await session.stop()
        } catch {
            emitter.send("error", ["message": (error as? LocalizedError)?.errorDescription ?? "Apple Speech 启动失败"])
            await session.stop()
        }
    }
}
