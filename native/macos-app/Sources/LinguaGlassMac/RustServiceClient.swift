import Foundation

struct RustServiceEvent {
    let type: String
    let id: String?
    let text: String?
    let message: String?
    let keyReady: Bool?
    let requestID: String?

    init?(data: Data) {
        guard
            let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = value["type"] as? String
        else { return nil }
        self.type = type
        id = value["id"] as? String
        text = value["text"] as? String
        message = value["message"] as? String
        keyReady = value["key_ready"] as? Bool
        requestID = value["request_id"] as? String
    }
}

enum RustServiceError: LocalizedError {
    case executableNotFound
    case unavailable

    var errorDescription: String? {
        switch self {
        case .executableNotFound: "找不到 LinguaGlass 本地翻译服务。请重新构建原生应用。"
        case .unavailable: "LinguaGlass 本地翻译服务尚未启动。"
        }
    }
}

@MainActor
final class RustServiceClient: @unchecked Sendable {
    var onEvent: ((RustServiceEvent) -> Void)?
    var onExit: ((Int32) -> Void)?

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputBuffer = Data()

    var isRunning: Bool { process?.isRunning == true }

    func start() throws {
        guard !isRunning else { return }
        guard let executable = Self.findExecutable() else { throw RustServiceError.executableNotFound }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.consume(data) }
        }
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.cleanUp()
                self?.onExit?(process.terminationStatus)
            }
        }
        try process.run()
        self.process = process
        inputPipe = input
    }

    func translate(
        id: String,
        requestID: String,
        text: String,
        model: String,
        domain: String = "General",
        glossary: String = "",
        contextLength: Int = 3,
        provisional: Bool = false
    ) throws {
        try send([
            "type": "translate", "id": id, "request_id": requestID, "text": text, "model": model,
            "domain": domain, "glossary": glossary, "context_length": contextLength,
            "provisional": provisional
        ])
    }

    func setRuntimeKey(_ key: String) throws { try send(["type": "set_runtime_key", "key": key, "request_id": UUID().uuidString]) }
    func clearRuntimeKey() throws { try send(["type": "clear_runtime_key", "request_id": UUID().uuidString]) }
    func requestKeyStatus() throws { try send(["type": "key_status", "request_id": UUID().uuidString]) }
    func resetContext() throws { try send(["type": "reset_context", "request_id": UUID().uuidString]) }

    func stop() {
        try? send(["type": "stop"])
        try? inputPipe?.fileHandleForWriting.close()
    }

    func terminate() {
        stop()
        if process?.isRunning == true { process?.terminate() }
        cleanUp()
    }

    private func send(_ object: [String: Any]) throws {
        guard isRunning, let inputPipe else { throw RustServiceError.unavailable }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard let event = RustServiceEvent(data: Data(line)) else { continue }
            onEvent?(event)
        }
    }

    private func cleanUp() {
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process = nil
        inputPipe = nil
        outputBuffer.removeAll(keepingCapacity: true)
    }

    private static func findExecutable() -> URL? {
        let fileManager = FileManager.default
        let source = URL(fileURLWithPath: #filePath)
        let repository = source
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["LINGUAGLASS_SERVICE"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        if let executable = Bundle.main.executableURL {
            candidates.append(executable.deletingLastPathComponent().appendingPathComponent("linguaglass-service"))
        }
        candidates.append(repository.appendingPathComponent("src-tauri/target/release/linguaglass-service"))
        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath)
            .appendingPathComponent("src-tauri/target/release/linguaglass-service"))
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
