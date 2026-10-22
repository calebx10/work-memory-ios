import Foundation

enum SceneType: String, Codable, CaseIterable, Identifiable {
    case meeting = "会议", customer = "客户沟通", brainstorm = "头脑风暴"
    case review = "工作复盘", inspiration = "灵感记录", learning = "培训学习", other = "其他"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .meeting: return "person.3"
        case .customer: return "bubble.left.and.bubble.right"
        case .brainstorm: return "sparkles"
        case .review: return "arrow.clockwise"
        case .inspiration: return "lightbulb"
        case .learning: return "book"
        case .other: return "waveform"
        }
    }
}

enum RecordingState: String, Codable {
    case recording, paused, interrupted, recovered, saved
    var label: String {
        switch self {
        case .recording: return "正在录音"
        case .paused: return "已暂停"
        case .interrupted: return "录音中断"
        case .recovered: return "待确认恢复"
        case .saved: return "保存在手机"
        }
    }
    var unfinished: Bool { self != .saved && self != .recovered }
}

enum SegmentState: String, Codable { case writing, ready, unreadable }
struct AudioSegment: Codable, Identifiable, Equatable {
    var id = UUID()
    var sequence: Int
    var filename: String
    var startedAt = Date()
    var endedAt: Date?
    var startOffset: TimeInterval
    var duration: TimeInterval = 0
    var byteCount: Int64 = 0
    var sha256: String?
    var state: SegmentState = .writing
    var error: String?
}
struct RecordingEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var message: String
}
struct Recording: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var scene: SceneType
    var tags = ""
    var notes = ""
    var createdAt = Date()
    var endedAt: Date?
    var updatedAt = Date()
    var state: RecordingState = .recording
    var segments: [AudioSegment] = []
    var events: [RecordingEvent] = []
    var duration: TimeInterval { segments.reduce(0) { $0 + $1.duration } }
    var byteCount: Int64 { segments.reduce(0) { $0 + $1.byteCount } }
    var playableSegments: [AudioSegment] { segments.filter { $0.state == .ready }.sorted { $0.sequence < $1.sequence } }

    static func defaultTitle(scene: SceneType, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\(formatter.string(from: date)) \(scene.rawValue)"
    }
    mutating func transition(to newState: RecordingState, at date: Date = Date()) throws {
        let allowed: Bool
        switch (state, newState) {
        case (.recording, .paused), (.recording, .interrupted), (.recording, .saved),
             (.paused, .recording), (.paused, .saved), (.paused, .interrupted),
             (.interrupted, .recording), (.interrupted, .saved),
             (.recovered, .saved): allowed = true
        default: allowed = false
        }
        guard allowed else { throw LocalError.invalidTransition }
        state = newState
        updatedAt = date
        if newState == .saved { endedAt = date }
    }
    func segment(at offset: TimeInterval) -> (AudioSegment, TimeInterval)? {
        let available = playableSegments
        var cursor: TimeInterval = 0
        for segment in available {
            if offset < cursor + segment.duration {
                return (segment, max(0, offset - cursor))
            }
            cursor += segment.duration
        }
        return available.last.map { ($0, $0.duration) }
    }
}

enum LocalError: LocalizedError {
    case invalidTransition, unsafePath, missingFile, insufficientSpace, corruptMetadata, integrityMismatch
    var errorDescription: String? {
        switch self {
        case .invalidTransition: return "当前状态不允许此操作。"
        case .unsafePath: return "文件路径无效，已拒绝访问。"
        case .missingFile: return "本地音频不存在，其他已保存分段仍会保留。"
        case .insufficientSpace: return "手机可用空间不足 100 MB。请释放空间后再录音。"
        case .corruptMetadata: return "录音信息损坏，已保留原始文件，请导出备份。"
        case .integrityMismatch: return "音频校验未通过，文件可能已被修改。"
        }
    }
}

func clockText(_ seconds: TimeInterval) -> String {
    let value = max(0, Int(seconds.isFinite ? seconds : 0))
    return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
}
