import XCTest
@testable import MemoryCore

final class MemoryCoreTests: XCTestCase {
    var root: URL!
    var repo: LocalRepository!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MemoryCoreTests-\(UUID())")
        repo = try LocalRepository(root: root)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testRecordingRoundTripAndOnlyOwnDirectoryDeleted() throws {
        let first = Recording(title: "客户会议", scene: .customer)
        let second = Recording(title: "灵感", scene: .inspiration)
        try repo.save(first); try repo.save(second)
        XCTAssertEqual(Set(try repo.load().map(\.id)), Set([first.id, second.id]))
        try repo.delete(first.id)
        XCTAssertEqual(try repo.load().map(\.id), [second.id])
    }
    func testBackupRestoresMetadataWithoutDeletingAudio() throws {
        var recording = Recording(title: "原始标题", scene: .meeting)
        try repo.save(recording)
        recording.title = "新标题"; try repo.save(recording)
        let url = try repo.file(recording.id, name: "manifest.json")
        try Data("broken".utf8).write(to: url)
        XCTAssertEqual(try repo.load().first?.title, "原始标题")
        XCTAssertEqual(repo.warnings.count, 1)
    }
    func testCorruptMetadataDoesNotDisappearSilently() throws {
        let item = Recording(title: "示例", scene: .meeting)
        try repo.save(item)
        try Data("broken".utf8).write(to: repo.file(item.id, name: "manifest.json"))
        XCTAssertEqual(try repo.load().count, 0)
        XCTAssertFalse(repo.warnings.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.directory(item.id).path))
    }
    func testUnsafePathsRejected() throws {
        for name in ["../secret", "a/b", "a\\b", "", "/tmp/secret"] {
            XCTAssertThrowsError(try repo.file(UUID(), name: name))
        }
    }
    func testHashDetectsAudioChanges() throws {
        let recording = Recording(title: "示例", scene: .meeting)
        try repo.save(recording)
        let segment = AudioSegment(sequence: 0, filename: "audio.m4a", startOffset: 0)
        let url = try repo.file(recording.id, name: segment.filename)
        try Data("audio".utf8).write(to: url)
        let finalized = try repo.finalize(segment, recordingID: recording.id, duration: 10)
        try repo.verify(finalized, recordingID: recording.id)
        try Data("other".utf8).write(to: url)
        XCTAssertThrowsError(try repo.verify(finalized, recordingID: recording.id))
    }
    func testRecoveryKeepsValidAndUnreadableSegments() throws {
        var recording = Recording(title: "恢复", scene: .meeting)
        recording.segments = [AudioSegment(sequence: 0, filename: "good.m4a", startOffset: 0), AudioSegment(sequence: 1, filename: "bad.m4a", startOffset: 20)]
        try repo.save(recording)
        try Data("saved".utf8).write(to: repo.file(recording.id, name: "good.m4a"))
        try Data("partial".utf8).write(to: repo.file(recording.id, name: "bad.m4a"))
        let recovered = try repo.recover(recording) { url in
            if url.lastPathComponent == "bad.m4a" { throw LocalError.missingFile }
            return 20
        }
        XCTAssertEqual(recovered.state, .recovered)
        XCTAssertEqual(recovered.playableSegments.count, 1)
        XCTAssertEqual(recovered.segments[1].state, .unreadable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try repo.file(recording.id, name: "bad.m4a").path))
    }
    func testStateTransitionsAndDefaultTitle() throws {
        var value = Recording(title: "测试", scene: .customer)
        try value.transition(to: .paused); try value.transition(to: .recording); try value.transition(to: .interrupted); try value.transition(to: .saved)
        XCTAssertNotNil(value.endedAt)
        XCTAssertThrowsError(try value.transition(to: .recording))
        XCTAssertTrue(Recording.defaultTitle(scene: .customer).hasSuffix("客户沟通"))
    }
    func testPlaybackOffsetsExcludePause() {
        var value = Recording(title: "测试", scene: .meeting)
        value.segments = [AudioSegment(sequence: 0, filename: "a", startOffset: 0, duration: 10, state: .ready), AudioSegment(sequence: 1, filename: "b", startOffset: 10, duration: 20, state: .ready)]
        XCTAssertEqual(value.segment(at: 12)?.0.filename, "b")
        XCTAssertEqual(value.segment(at: 12)?.1, 2)
        XCTAssertEqual(clockText(3661), "01:01:01")
    }
    func testMemoryPersistenceRecoveryAndNoCredentialsInExport() throws {
        let recording = Recording(title: "项目会议", scene: .meeting)
        try repo.save(recording)
        var doc = MemoryDocument(recordingID: recording.id)
        doc.state = .transcribing
        doc.transcripts = [SegmentTranscript(id: UUID(), sha256: "hash", original: "下周验证客户需求", provider: "https://example.com/v1", model: "model")]
        try repo.saveMemory(doc)
        let recovered = try repo.loadMemory(recording.id)
        XCTAssertEqual(recovered.state, .paused)
        XCTAssertEqual(recovered.transcripts.count, 1)
        XCTAssertTrue(recovered.searchText.contains("客户需求"))
        let urls = try repo.exportMemory(recovered, recording: recording)
        XCTAssertEqual(urls.count, 2)
        let exported = try String(contentsOf: urls[0])
        XCTAssertTrue(exported.contains("下周验证客户需求"))
        XCTAssertFalse(exported.contains("Authorization"))
    }
    func testEditedTranscriptMakesAnalysisStaleAndPreservesOriginal() {
        var doc = MemoryDocument(recordingID: UUID())
        doc.transcripts = [SegmentTranscript(id: UUID(), sha256: "hash", original: "原文", provider: "local", model: "test")]
        doc.analysis = .init(summary: "摘要", detailedSummary: "正文", sections: [], ideas: [])
        doc.analysisFingerprint = doc.fingerprint
        XCTAssertFalse(doc.needsAnalysisUpdate)
        doc.transcripts[0].edited = "人工修改"
        XCTAssertTrue(doc.needsAnalysisUpdate)
        XCTAssertEqual(doc.transcripts[0].original, "原文")
    }
    func testMemoryBackupAndCorruptionAreNotOverwritten() throws {
        let recording = Recording(title: "会议", scene: .meeting); try repo.save(recording)
        var doc = MemoryDocument(recordingID: recording.id)
        try repo.saveMemory(doc)
        doc.message = "第二版"; try repo.saveMemory(doc)
        try Data("corrupt".utf8).write(to: repo.file(recording.id, name: "memory.json"))
        XCTAssertEqual(try repo.loadMemory(recording.id).message, "")
        try Data("corrupt".utf8).write(to: repo.file(recording.id, name: "memory.backup.json"))
        XCTAssertThrowsError(try repo.loadMemory(recording.id))
    }
    func testUnknownCitationRejectedAndRealCitationResolved() throws {
        let id = UUID()
        let json: [String: Any] = ["summary": "摘要", "detailedSummary": "正文", "sections": SectionKind.allCases.map { kind in ["kind": kind.rawValue, "items": kind == .keyPoints ? [["title": "重点", "detail": "依据", "sourceIDs": [id.uuidString]]] : []] as [String: Any] }, "ideas": []]
        let payload = try JSONDecoder().decode(AnalysisPayload.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try payload.result(sourceIDs: []))
        let result = try payload.result(sourceIDs: [id.uuidString])
        XCTAssertEqual(result.sections.first?.items.first?.sourceIDs, [id.uuidString])
        var doc = MemoryDocument(recordingID: UUID())
        doc.transcripts = [SegmentTranscript(id: id, sha256: "hash", original: "依据", provider: "test", model: "test")]
        XCTAssertEqual(doc.validSources([id.uuidString, "fake", id.uuidString]).count, 1)
    }
    func testLongTranscriptsAreBatchedWithoutDroppingText() throws {
        let text = String(repeating: "中文原文", count: 8000)
        let transcript = SegmentTranscript(id: UUID(), sha256: "h", original: text, provider: "test", model: "test")
        let batches = try AnalysisBatch.make([transcript])
        XCTAssertGreaterThan(batches.count, 1)
        let pieces = try batches.flatMap { batch -> [[String: String]] in
            try JSONDecoder().decode([[String: String]].self, from: Data(batch.input.utf8))
        }
        XCTAssertEqual(pieces.compactMap { $0["text"] }.joined(), text)
        XCTAssertTrue(batches.allSatisfy { $0.sourceIDs == [transcript.id.uuidString] })
    }
    func testEndpointValidation() throws {
        for bad in ["http://example.com/v1", "https://user:pass@example.com/v1", "https://example.com/v1?key=secret", "https://example.com/#key", "invalid"] {
            var config = ServiceConfiguration(); config.baseURL = bad
            XCTAssertThrowsError(try config.validatedURL())
        }
        XCTAssertNoThrow(try ServiceConfiguration().validatedURL())
    }
}
