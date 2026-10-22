import Foundation
#if DEBUG

// Only reachable through explicit UI-test launch arguments in Debug builds.
// Synthetic files live in their own directory; no real recording or service key is used.
@MainActor
enum DebugHarness {
    nonisolated static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    static let recordingID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let segmentID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static func prepare(root: URL) throws -> URL {
        let isolated = root.deletingLastPathComponent().appendingPathComponent("WorkMemoryUITests", isDirectory: true)
        if ProcessInfo.processInfo.arguments.contains("--reset-ui-tests"), FileManager.default.fileExists(atPath: isolated.path) {
            try FileManager.default.removeItem(at: isolated)
        }
        let repo = try LocalRepository(root: isolated)
        if try repo.load().isEmpty {
            var recording = Recording(id: recordingID, title: "界面测试 · 客户需求验证", scene: .customer)
            recording.state = .saved
            recording.notes = "此记录和 AI 返回均为合成测试资料，不是真实录音。"
            try repo.save(recording)
            let segment = AudioSegment(id: segmentID, sequence: 0, filename: "synthetic.wav", startOffset: 0)
            var wave = Data()
            func ascii(_ text: String) { wave.append(Data(text.utf8)) }
            func number<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { wave.append(contentsOf: $0) } }
            let bytes = 32_000
            ascii("RIFF"); number(UInt32(36 + bytes)); ascii("WAVEfmt "); number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(UInt32(16_000)); number(UInt32(32_000)); number(UInt16(2)); number(UInt16(16)); ascii("data"); number(UInt32(bytes)); wave.append(Data(repeating: 0, count: bytes))
            let file = try repo.file(recordingID, name: segment.filename)
            try wave.write(to: file)
            recording.segments = [try repo.finalize(segment, recordingID: recordingID, duration: 1)]
            try repo.save(recording)
        }
        AppPreferences.defaults.set(true, forKey: "privacyAccepted")
        return isolated
    }
}
final class PreviewAIService: MemoryAIService {
    var configuration: ServiceConfiguration { var value = ServiceConfiguration(); value.baseURL = "https://ui-test.invalid/v1"; return value }
    func transcribe(file: URL) async throws -> String {
        try await Task.sleep(nanoseconds: 300_000_000)
        return "客户提出先用两周验证需求，暂不扩大投入。我们决定先做小范围试用，下周再讨论结果。负责人和具体截止日期还没确定。"
    }
    func analyze(input: String, sourceIDs: Set<String>, merging: Bool) async throws -> AnalysisResult {
        try await Task.sleep(nanoseconds: 300_000_000)
        let sources = sourceIDs.sorted()
        return AnalysisResult(summary: "先小规模验证需求，再决定是否扩大投入。", detailedSummary: "本次讨论确认先进行两周的需求验证，负责人及具体日期仍需跟进，尚无结果。", sections: SectionKind.allCases.map { kind in
            let item = MemoryItem(title: kind == .todos ? "确认试用负责人" : "先验证再投入", detail: kind == .todos ? "负责人未明确，具体截止日期未明确，需下次讨论确认。" : "客户建议先小范围试用。结果尚未确认。", sourceIDs: sources)
            return AnalysisSection(kind: kind, items: [item])
        }, ideas: [ContentIdea(title: "为什么我建议先做小范围试用", audience: "企业经营者", problem: "需求还没验证就扩大投入", viewpoint: "先验证真实需求，再决定投入规模", angle: "从客户沟通中的真实选择出发", sourceIDs: sources)])
    }
    func draft(idea: ContentIdea, evidence: String) async throws -> String {
        try await Task.sleep(nanoseconds: 300_000_000)
        return "今天和客户沟通时，我们做了一个选择：先小范围试用，再决定是否扩大投入。两周后会有什么结果，现在还不知道。但这次讨论让我重新提醒自己，先把需求验证清楚，再做下一步决定。这是一份基于合成测试资料的口播初稿。"
    }
}
#endif

enum AppPreferences {
    static var defaults: UserDefaults {
        #if DEBUG
        if DebugHarness.enabled { return UserDefaults(suiteName: "com.workmemory.ui-tests")! }
        #endif
        return .standard
    }
}
