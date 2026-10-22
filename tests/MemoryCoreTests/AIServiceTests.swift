import XCTest
import Foundation
@testable import MemoryCore

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw AIError.malformedResponse }
            let (code, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class AIServiceTests: XCTestCase {
    func service(configuration: ServiceConfiguration = ServiceConfiguration()) throws -> HTTPMemoryAIService {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        return try HTTPMemoryAIService(configuration: configuration, key: "test-only-not-real", session: URLSession(configuration: config))
    }
    func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var output = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; output.append(bytes, count: count) }
        return output
    }
    func testTranscriptionMultipartAndChineseResponse() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).m4a")
        try Data("synthetic-test-audio".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-not-real")
            let body = String(decoding: self.body(request), as: UTF8.self)
            XCTAssertTrue(body.contains("gpt-transcribe"))
            XCTAssertTrue(body.contains("synthetic-test-audio"))
            XCTAssertFalse(body.contains("test-only-not-real"))
            return (200, Data("{\"text\":\"先验证需求，再扩大投入。\"}".utf8))
        }
        let result = try await service().transcribe(file: file)
        XCTAssertEqual(result, "先验证需求，再扩大投入。")
    }
    func testHTTPFailureDoesNotLeakServerBodyAndDoesNotRetry() async throws {
        var calls = 0
        MockURLProtocol.handler = { _ in calls += 1; return (401, Data("sensitive-server-error-key".utf8)) }
        do { _ = try await service().draft(idea: sampleIdea(), evidence: "测试依据"); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? AIError, .http(401)); XCTAssertFalse(error.localizedDescription.contains("sensitive-server")) }
        XCTAssertEqual(calls, 1)
    }
    func testAPIMartUsesChineseAudioAndDocumentedChatContract() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).m4a")
        try Data("synthetic-audio".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.apimart.ai/v1/audio/transcriptions")
            let multipart = String(decoding: self.body(request), as: UTF8.self)
            for value in ["whisper-1", "name=\"language\"\r\n\r\nzh", "name=\"response_format\"\r\n\r\njson"] { XCTAssertTrue(multipart.contains(value)) }
            return (200, Data("{\"text\":\"中文测试\"}".utf8))
        }
        let client = try service(configuration: .apimart)
        let text = try await client.transcribe(file: file)
        XCTAssertEqual(text, "中文测试")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.apimart.ai/v1/chat/completions")
            let body = try JSONSerialization.jsonObject(with: self.body(request)) as! [String: Any]
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertEqual(body["model"] as? String, "gpt-4o")
            XCTAssertNil(body["response_format"])
            let messages = body["messages"] as! [[String: String]]
            XCTAssertTrue(messages[0]["content"]!.contains("additionalProperties"))
            // Compatible transport must still reject incomplete/unverified AI results.
            return (200, Data("{\"choices\":[{\"message\":{\"content\":\"{}\"},\"finish_reason\":\"stop\"}]}".utf8))
        }
        do { _ = try await client.analyze(input: "测试", sourceIDs: [], merging: false); XCTFail("Expected invalid payload rejection") }
        catch { XCTAssertEqual(error as? AIError, .malformedResponse) }
    }
    func testStructuredOutputContractAndCitationValidation() async throws {
        let source = UUID().uuidString
        let payload: [String: Any] = ["summary": "先验证需求", "detailedSummary": "先进行小规模验证。", "sections": SectionKind.allCases.map { kind in ["kind": kind.rawValue, "items": kind == .keyPoints ? [["title": "需求验证", "detail": "先验证再投入", "sourceIDs": [source]]] : []] as [String: Any] }, "ideas": []]
        let content = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
        let envelope = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content], "finish_reason": "stop"]]])
        MockURLProtocol.handler = { request in
            let body = try JSONSerialization.jsonObject(with: self.body(request)) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "gpt-4.1-mini")
            XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_schema")
            return (200, envelope)
        }
        let result = try await service().analyze(input: "测试原文", sourceIDs: [source], merging: false)
        XCTAssertEqual(result.sections.count, 6)
        XCTAssertEqual(result.sections.first?.items.first?.sourceIDs, [source])
    }
    func testTruncatedModelOutputIsNotAccepted() async throws {
        MockURLProtocol.handler = { _ in
            (200, try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": "{\"summary\":\"不完整\"}"], "finish_reason": "length"]]]))
        }
        do { _ = try await service().analyze(input: "test", sourceIDs: [], merging: false); XCTFail("Expected failure") }
        catch { XCTAssertEqual(error as? AIError, .malformedResponse) }
    }
    func testSplitProvidersRouteEachCredentialOnlyToItsOwnHost() async throws {
        var configuration = ServiceConfiguration.apimart
        configuration.analysisBaseURL = "https://api.deepseek.com"
        configuration.analysisModel = "deepseek-flash"
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        let client = try HTTPMemoryAIService(configuration: configuration, key: "audio-only-test", analysisKey: "text-only-test", session: URLSession(configuration: config))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID()).m4a")
        try Data("synthetic-audio".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "api.apimart.ai")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer audio-only-test")
            return (200, Data("{\"text\":\"中文原文\"}".utf8))
        }
        let transcript = try await client.transcribe(file: file)
        XCTAssertEqual(transcript, "中文原文")
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer text-only-test")
            let body = try JSONSerialization.jsonObject(with: self.body(request)) as! [String: Any]
            XCTAssertEqual(body["model"] as? String, "deepseek-flash")
            XCTAssertEqual(body["max_tokens"] as? Int, 8192)
            XCTAssertEqual((body["thinking"] as? [String: String])?["type"], "disabled")
            XCTAssertFalse(String(decoding: self.body(request), as: UTF8.self).contains("audio-only-test"))
            return (200, Data("{\"choices\":[{\"message\":{\"content\":\"测试初稿\"},\"finish_reason\":\"stop\"}]}".utf8))
        }
        let draft = try await client.draft(idea: sampleIdea(), evidence: transcript)
        XCTAssertEqual(draft, "测试初稿")
        XCTAssertThrowsError(try HTTPMemoryAIService(configuration: configuration, key: "audio-key"))
        configuration.analysisBaseURL = "http://unsafe.example/v1"
        XCTAssertThrowsError(try configuration.validatedURL())
    }
    func testExistingConfigurationWithoutSplitProviderStillLoads() throws {
        let legacy = Data("{\"baseURL\":\"https://api.apimart.ai/v1\",\"transcriptionModel\":\"whisper-1\",\"analysisModel\":\"gpt-4o\",\"structuredOutputs\":false}".utf8)
        let config = try JSONDecoder().decode(ServiceConfiguration.self, from: legacy)
        XCTAssertNil(config.analysisBaseURL)
        XCTAssertEqual(config.effectiveAnalysisURL, config.baseURL)
    }
    func testMissingKeyRejectedWithoutNetwork() {
        XCTAssertThrowsError(try HTTPMemoryAIService(configuration: ServiceConfiguration(), key: ""))
    }
    func testRunnerResumesCheckpointsAndMergesBoundedInputs() async throws {
        let fake = FakeAIService()
        let id = UUID()
        let transcript = SegmentTranscript(id: id, sha256: "h", original: String(repeating: "甲", count: 10_000) + String(repeating: "乙", count: 10_000) + String(repeating: "丙", count: 10_000), provider: "test", model: "test")
        var saved: [AnalysisCheckpoint] = []
        fake.failAt = 2
        do { _ = try await AnalysisRunner().run(transcripts: [transcript], checkpoints: saved, service: fake) { saved.append($0) }; XCTFail("Expected failure") }
        catch { XCTAssertEqual(saved.count, 1) }
        let completedInput = fake.inputs[0]
        fake.failAt = nil
        let result = try await AnalysisRunner().run(transcripts: [transcript], checkpoints: saved, service: fake) { saved.append($0) }
        XCTAssertEqual(result.summary, "测试摘要")
        XCTAssertEqual(fake.inputs.filter { $0 == completedInput }.count, 1)
        XCTAssertTrue(fake.inputs.allSatisfy { $0.count < 32_000 })
        let count = fake.inputs.count
        _ = try await AnalysisRunner().run(transcripts: [transcript], checkpoints: saved, service: fake) { saved.append($0) }
        XCTAssertEqual(fake.inputs.count, count)
    }
    func testCancellationDoesNotMakeARequest() async throws {
        let fake = FakeAIService()
        let transcript = SegmentTranscript(id: UUID(), sha256: "h", original: "测试", provider: "test", model: "test")
        let task = Task {
            try await Task.sleep(nanoseconds: 10_000_000)
            return try await AnalysisRunner().run(transcripts: [transcript], checkpoints: [], service: fake) { _ in }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(fake.inputs.isEmpty)
    }
    private func sampleIdea() -> ContentIdea { ContentIdea(title: "测试选题", audience: "创业者", problem: "投入过早", viewpoint: "先验证", angle: "工作观察", sourceIDs: []) }
}
private final class FakeAIService: MemoryAIService {
    var configuration = ServiceConfiguration()
    var inputs: [String] = []
    var failAt: Int?
    func transcribe(file: URL) async throws -> String { "测试原文" }
    func analyze(input: String, sourceIDs: Set<String>, merging: Bool) async throws -> AnalysisResult {
        inputs.append(input)
        if inputs.count == failAt { throw AIError.http(429) }
        return AnalysisResult(summary: "测试摘要", detailedSummary: "测试正文", sections: SectionKind.allCases.map { AnalysisSection(kind: $0, items: []) }, ideas: [])
    }
    func draft(idea: ContentIdea, evidence: String) async throws -> String { "测试稿件" }
}
