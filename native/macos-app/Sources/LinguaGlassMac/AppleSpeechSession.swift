import AVFoundation
import CoreMedia
import Foundation
import Speech

@available(macOS 26.0, *)
private final class ConverterInputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private let lock = NSLock()
    private var supplied = false

    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock(); defer { lock.unlock() }
        if supplied {
            status.pointee = .noDataNow
            return nil
        }
        supplied = true
        status.pointee = .haveData
        return buffer
    }
}

@available(macOS 26.0, *)
private final class SessionConverter: @unchecked Sendable {
    private let outputFormat: AVAudioFormat
    private let lock = NSLock()
    private var converter: AVAudioConverter?

    init(outputFormat: AVAudioFormat) { self.outputFormat = outputFormat }

    func convert(_ input: AVAudioPCMBuffer, gain: Float) throws -> AnalyzerInput? {
        lock.lock(); defer { lock.unlock() }
        if gain != 1 { applyGain(gain, to: input) }
        if converter == nil || converter?.inputFormat != input.format {
            guard let value = AVAudioConverter(from: input.format, to: outputFormat) else {
                throw DirectSpeechError("无法创建音频转换器")
            }
            value.primeMethod = .none
            converter = value
        }
        guard let converter else { return nil }
        let capacity = AVAudioFrameCount(max(1, ceil(Double(input.frameLength) * outputFormat.sampleRate / input.format.sampleRate) + 32))
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return nil }
        let provider = ConverterInputProvider(buffer: input)
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, state in
            provider.next(status: state)
        }
        if status == .error { throw conversionError ?? DirectSpeechError("音频转换失败") }
        return output.frameLength > 0 ? AnalyzerInput(buffer: output) : nil
    }

    private func applyGain(_ gain: Float, to buffer: AVAudioPCMBuffer) {
        guard gain != 1, buffer.format.commonFormat == .pcmFormatFloat32 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        for audioBuffer in buffers {
            guard let data = audioBuffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let count = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
            for index in 0..<count { samples[index] = max(-1, min(1, samples[index] * gain)) }
        }
    }
}

private struct DirectSpeechError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@available(macOS 26.0, *)
final class AppleSpeechSession: NSObject, @unchecked Sendable {
    var onEvent: (@MainActor (SpeechBridgeEvent) -> Void)?

    private let mode: AudioInputMode
    private let deviceUID: String?
    private let gain: Float
    private var analyzer: SpeechAnalyzer?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: SessionConverter?
    private var resultsTask: Task<Void, Never>?
    private var microphoneSession: AVCaptureSession?
    private var systemAudioTap: SystemAudioTap?
    private let microphoneQueue = DispatchQueue(label: "com.linguaglass.native.microphone")
    private let levelLock = NSLock()
    private var lastLevel: UInt64 = 0
    private var segment = 0
    private let started = ContinuousClock.now

    init(mode: AudioInputMode, deviceUID: String?, gain: Double) {
        self.mode = mode
        self.deviceUID = deviceUID
        self.gain = Float(gain)
    }

    func start() async throws {
        guard SpeechTranscriber.isAvailable else { throw DirectSpeechError("当前 Mac 不支持 Apple Speech") }
        let requested = Locale(identifier: "en-US")
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requested) else {
            throw DirectSpeechError("Apple Speech 暂不支持 English (US)")
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw DirectSpeechError("无法取得 Apple Speech 音频格式")
        }
        let (sequence, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.continuation = continuation
        self.converter = SessionConverter(outputFormat: format)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        try await analyzer.start(inputSequence: sequence)
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results { self?.emit(result) }
            } catch {
                if !Task.isCancelled { self?.send("error", message: "Apple Speech 识别中断：\(error.localizedDescription)") }
            }
        }
        if mode == .system { try startSystemAudio() } else { try startMicrophone() }
        send("ready")
    }

    func stop() async {
        microphoneSession?.stopRunning(); microphoneSession = nil
        systemAudioTap?.stop(); systemAudioTap = nil
        continuation?.finish()
        await analyzer?.cancelAndFinishNow()
        resultsTask?.cancel(); resultsTask = nil
        analyzer = nil; continuation = nil; converter = nil
        send("stopped")
    }

    private func startMicrophone() throws {
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
        let defaultDevice = AVCaptureDevice.default(for: .audio)
        let device = deviceUID.flatMap { uid in uid == defaultDevice?.uniqueID ? defaultDevice : discovery.devices.first { $0.uniqueID == uid } } ?? defaultDevice
        guard let device else { throw DirectSpeechError("没有可用的麦克风") }
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: microphoneQueue)
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else { session.commitConfiguration(); throw DirectSpeechError("无法连接所选麦克风") }
        session.addInput(input); session.addOutput(output); session.commitConfiguration(); session.startRunning()
        microphoneSession = session
    }

    private func startSystemAudio() throws {
        let outputUID = deviceUID ?? AudioDeviceCatalog.defaultOutputUID()
        guard let outputUID, !outputUID.isEmpty else { throw DirectSpeechError("没有可用的播放设备") }
        let tap = SystemAudioTap(deviceUID: outputUID)
        tap.onBuffer = { [weak self] buffer in self?.consume(buffer) }
        do {
            try tap.start()
            systemAudioTap = tap
        } catch {
            throw DirectSpeechError("系统音频捕获启动失败：\(error.localizedDescription)")
        }
    }

    private func consume(_ sampleBuffer: CMSampleBuffer) {
        guard sampleBuffer.isValid else { return }
        try? sampleBuffer.withAudioBufferList { list, _ in
            guard var description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
                  let format = AVAudioFormat(streamDescription: &description),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer, deallocator: nil)
            else { return }
            consume(buffer)
        }
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let continuation else { return }
        do {
            if let input = try converter.convert(buffer, gain: gain) {
                continuation.yield(input)
                emitLevel(input.buffer)
            }
        } catch { send("warning", message: "部分音频无法转换") }
    }

    private func emit(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let id = "apple-\(segment)"
        if result.isFinal { segment += 1 }
        let elapsed = Double(started.duration(to: .now).components.seconds)
        let rangeStart = CMTimeGetSeconds(result.range.start)
        let rangeEnd = CMTimeGetSeconds(CMTimeRangeGetEnd(result.range))
        let event = SpeechBridgeEvent(type: result.isFinal ? "asr_final" : "asr_partial", id: id, text: text, message: nil,
            start: rangeStart.isFinite ? max(0, rangeStart) : max(0, elapsed - 1), end: rangeEnd.isFinite ? max(0, rangeEnd) : elapsed, value: nil)
        deliver(event)
    }

    private func emitLevel(_ buffer: AVAudioPCMBuffer) {
        let now = DispatchTime.now().uptimeNanoseconds
        levelLock.lock(); let should = now &- lastLevel >= 100_000_000; if should { lastLevel = now }; levelLock.unlock()
        guard should else { return }
        var energy = 0.0; var count = 0
        for item in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            guard let data = item.mData, buffer.format.commonFormat == .pcmFormatFloat32 else { continue }
            let samples = data.assumingMemoryBound(to: Float.self)
            let length = Int(item.mDataByteSize) / MemoryLayout<Float>.size
            for index in 0..<length { let sample = Double(samples[index]); energy += sample * sample }
            count += length
        }
        deliver(SpeechBridgeEvent(type: "level", id: nil, text: nil, message: nil, start: nil, end: nil, value: count > 0 ? sqrt(energy / Double(count)) : 0))
    }

    private func send(_ type: String, message: String? = nil) {
        deliver(SpeechBridgeEvent(type: type, id: nil, text: nil, message: message, start: nil, end: nil, value: nil))
    }

    private func deliver(_ event: SpeechBridgeEvent) {
        Task { @MainActor [weak self] in self?.onEvent?(event) }
    }
}

@available(macOS 26.0, *)
extension AppleSpeechSession: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) { consume(sampleBuffer) }
}
