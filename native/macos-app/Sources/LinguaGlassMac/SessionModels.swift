import Foundation

enum SessionState: Equatable {
    case idle
    case initializing
    case listening
    case stopping

    var title: String {
        switch self {
        case .idle: "准备就绪"
        case .initializing: "正在加载语音模型"
        case .listening: "正在聆听"
        case .stopping: "正在结束"
        }
    }
}

struct TranscriptSegment: Identifiable, Equatable {
    let id: String
    var start: TimeInterval
    var end: TimeInterval
    var english: String
    var chinese: String = ""
    var isFinal: Bool
}

enum AudioInputMode: String {
    case system
    case microphone

    var bridgeArgument: String { rawValue }
}

struct SpeechBridgeEvent {
    let type: String
    let id: String?
    let text: String?
    let message: String?
    let start: TimeInterval?
    let end: TimeInterval?
    let value: Double?

    init(type: String, id: String?, text: String?, message: String?, start: TimeInterval?, end: TimeInterval?, value: Double?) {
        self.type = type; self.id = id; self.text = text; self.message = message
        self.start = start; self.end = end; self.value = value
    }

    init?(data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = object["type"] as? String
        else { return nil }
        self.type = type
        id = object["id"] as? String
        text = object["text"] as? String
        message = object["message"] as? String
        start = object["start"] as? TimeInterval
        end = object["end"] as? TimeInterval
        value = object["value"] as? Double
    }
}
