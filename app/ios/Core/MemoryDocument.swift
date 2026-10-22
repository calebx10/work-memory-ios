import Foundation
import CryptoKit

enum ProcessingState: String, Codable {
    case idle, transcribing, analyzing, paused, failed, completed
    var label: String {
        switch self {
        case .idle: return "尚未分析"
        case .transcribing: return "正在转文字"
        case .analyzing: return "正在提炼重点"
        case .paused: return "已暂停处理"
        case .failed: return "处理未完成"
        case .completed: return "分析完成"
        }
    }
    var busy: Bool { self == .transcribing || self == .analyzing }
}
struct SegmentTranscript: Codable, Identifiable, Equatable {
    var id: UUID // Original audio segment ID; never invented by AI.
    var sha256: String
    var original: String
    var edited: String?
    var provider: String
    var model: String
    var text: String { edited ?? original }
}
enum SectionKind: String, Codable, CaseIterable, Identifiable {
    case keyPoints, reasoning, cases, decisions, todos, followups
    var id: String { rawValue }
    var title: String {
        switch self {
        case .keyPoints: return "关键观点"
        case .reasoning: return "判断与方法"
        case .cases: return "案例与经验"
        case .decisions: return "决策与理由"
        case .todos: return "待办事项"
        case .followups: return "待跟进问题"
        }
    }
}
struct MemoryItem: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var detail: String
    var sourceIDs: [String]
    var favorite: Bool
    var done: Bool
    init(title: String, detail: String, sourceIDs: [String]) {
        id = UUID(); self.title = title; self.detail = detail; self.sourceIDs = sourceIDs
        favorite = false; done = false
    }
}
struct AnalysisSection: Codable, Identifiable, Equatable {
    var kind: SectionKind
    var items: [MemoryItem]
    var id: String { kind.rawValue }
}
enum IdeaStatus: String, Codable, CaseIterable, Identifiable {
    case review = "待审核", favorite = "已收藏", drafted = "已成稿", discarded = "已放弃"
    var id: String { rawValue }
}
struct ContentIdea: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var audience: String
    var problem: String
    var viewpoint: String
    var angle: String
    var sourceIDs: [String]
    var status: IdeaStatus = .review
    var draft: String = ""
}
struct AnalysisResult: Codable, Equatable {
    var summary: String
    var detailedSummary: String
    var sections: [AnalysisSection]
    var ideas: [ContentIdea]
}
struct AnalysisCheckpoint: Codable, Identifiable, Equatable {
    var id: String // Hash of exact batch input + configuration + prompt version.
    var result: AnalysisResult
}
struct MemoryDocument: Codable, Equatable {
    var recordingID: UUID
    var state: ProcessingState = .idle
    var message = ""
    var transcripts: [SegmentTranscript] = []
    var checkpoints: [AnalysisCheckpoint] = []
    var analysis: AnalysisResult?
    var originalAnalysis: AnalysisResult?
    var analysisFingerprint: String?
    var provider = ""
    var model = ""
    var updatedAt = Date()
    var promptVersion = "iphone-v1"
    var draftError: String?
    var fingerprint: String {
        stableHash(transcripts.map { "\($0.id.uuidString):\($0.text)" }.joined(separator: "\n"))
    }
    var needsAnalysisUpdate: Bool { analysis != nil && analysisFingerprint != fingerprint }
    var searchText: String {
        let analysisText = analysis.map { result in
            [result.summary, result.detailedSummary] + result.sections.flatMap { $0.items.map { "\($0.title) \($0.detail)" } } + result.ideas.map { "\($0.title) \($0.viewpoint) \($0.draft)" }
        } ?? []
        return (transcripts.map(\.text) + analysisText).joined(separator: "\n")
    }
    func validSources(_ ids: [String]) -> [SegmentTranscript] {
        var seen = Set<UUID>()
        return ids.compactMap { raw in
            guard let id = UUID(uuidString: raw), seen.insert(id).inserted else { return nil }
            return transcripts.first { $0.id == id }
        }
    }
    func markdown(recording: Recording) -> String {
        var lines = ["# \(recording.title)", "", "场景：\(recording.scene.rawValue)", "日期：\(recording.createdAt.formatted())", "标签：\(recording.tags)", "备注：\(recording.notes)", "", "AI 生成内容为草稿，请核对原文。来源时间为音频分段起点。", ""]
        if let result = analysis {
            lines += ["## 一句话摘要", result.summary, "", "## 内容摘要", result.detailedSummary, ""]
            for section in result.sections {
                lines += ["## \(section.kind.title)"]
                for item in section.items {
                    lines += ["### \(item.done ? "[已完成] " : "")\(item.title)", item.detail, sourceText(item.sourceIDs, recording: recording), ""]
                }
            }
            lines += ["## 自媒体选题"]
            for idea in result.ideas {
                lines += ["### \(idea.title)", "状态：\(idea.status.rawValue)", "受众：\(idea.audience)", "问题：\(idea.problem)", "观点：\(idea.viewpoint)", "表达角度：\(idea.angle)", sourceText(idea.sourceIDs, recording: recording), "", idea.draft, ""]
            }
        }
        lines += ["## 原始转写"]
        for transcript in transcripts {
            let segment = recording.segments.first { $0.id == transcript.id }
            lines += ["### \(clockText(segment?.startOffset ?? 0))（分段起点）", transcript.original, ""]
            if let edited = transcript.edited { lines += ["人工修订：", edited, ""] }
        }
        return lines.joined(separator: "\n")
    }
    private func sourceText(_ ids: [String], recording: Recording) -> String {
        validSources(ids).map { source in
            let offset = recording.segments.first { $0.id == source.id }?.startOffset ?? 0
            return "来源：\(source.id.uuidString) · \(clockText(offset))（分段起点）"
        }.joined(separator: "\n")
    }
}
func stableHash(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

extension LocalRepository {
    func loadMemory(_ id: UUID) throws -> MemoryDocument {
        let main = try file(id, name: "memory.json")
        let backup = try file(id, name: "memory.backup.json")
        let decoder = JSONDecoder()
        if !FileManager.default.fileExists(atPath: main.path), !FileManager.default.fileExists(atPath: backup.path) {
            return MemoryDocument(recordingID: id)
        }
        for url in [main, backup] {
            if let data = try? Data(contentsOf: url), var doc = try? decoder.decode(MemoryDocument.self, from: data), doc.recordingID == id {
                if doc.state.busy {
                    doc.state = .paused
                    doc.message = "上次处理已中断。已保存的结果仍保留，点击重试继续；未收到结果的请求重试可能重复计费。"
                }
                return doc
            }
        }
        throw LocalError.corruptMetadata
    }
    func saveMemory(_ original: MemoryDocument) throws {
        var doc = original
        doc.updatedAt = Date()
        let main = try file(doc.recordingID, name: "memory.json")
        let backup = try file(doc.recordingID, name: "memory.backup.json")
        if let previous = try? Data(contentsOf: main), (try? JSONDecoder().decode(MemoryDocument.self, from: previous)) != nil {
            try previous.write(to: backup, options: .atomic)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(doc).write(to: main, options: .atomic)
        #if os(iOS)
        for url in [main, backup] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        }
        #endif
    }
    func exportMemory(_ doc: MemoryDocument, recording: Recording) throws -> [URL] {
        let md = try file(recording.id, name: "工作记忆.md")
        let txt = try file(recording.id, name: "转写.txt")
        try doc.markdown(recording: recording).write(to: md, atomically: true, encoding: .utf8)
        try doc.transcripts.map(\.text).joined(separator: "\n\n").write(to: txt, atomically: true, encoding: .utf8)
        return [md, txt]
    }
}
