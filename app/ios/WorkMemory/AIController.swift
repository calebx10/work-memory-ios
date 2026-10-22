import Foundation
import Combine
import UIKit

@MainActor
final class AIController: ObservableObject {
    @Published private(set) var documents: [UUID: MemoryDocument] = [:]
    @Published private(set) var activeID: UUID?
    @Published private(set) var draftID: UUID?
    @Published var errorMessage: String?
    let settings: AISettings
    private let recordings: RecordingController
    private var task: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var damagedIDs = Set<UUID>()
    private var generation = UUID()
    var busy: Bool { task != nil }

    init(recordings: RecordingController, settings: AISettings) {
        self.recordings = recordings; self.settings = settings
        for item in recordings.recordings {
            do { documents[item.id] = try recordings.repository.loadMemory(item.id) }
            catch { damagedIDs.insert(item.id); errorMessage = "“\(item.title)”的分析文件无法读取。原始文件保留，请先导出备份。" }
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.cancel() }
        })
    }
    func document(_ id: UUID) -> MemoryDocument { documents[id] ?? MemoryDocument(recordingID: id) }
    private func persist(_ doc: MemoryDocument) throws {
        guard !damagedIDs.contains(doc.recordingID) else { throw LocalError.corruptMetadata }
        try recordings.repository.saveMemory(doc)
        documents[doc.recordingID] = doc
    }
    private func mutate(_ id: UUID, _ body: (inout MemoryDocument) -> Void) throws {
        var value = document(id); body(&value); try persist(value)
    }
    func start(_ recording: Recording, force: Bool = false) {
        guard !busy else { errorMessage = "已有任务正在处理，请等待完成或先暂停。"; return }
        guard recordings.activeID == nil else { errorMessage = "请先结束录音，再发送和分析。"; return }
        guard recording.state == .saved, !recording.playableSegments.isEmpty,
              recording.segments.allSatisfy({ $0.state == .ready }) else {
            errorMessage = "请先确认恢复并检查所有音频分段。有损坏分段时请先导出备份，当前不会发送不完整录音。"; return
        }
        let old = document(recording.id)
        if !force, old.analysis != nil, old.analysisFingerprint == old.fingerprint, old.state == .completed {
            errorMessage = "这条录音已有分析结果。需要重做时请在详情中选择“重新生成分析”。"; return
        }
        do {
            let service = try settings.service()
            var value = old
            value.state = .transcribing; value.message = "准备发送音频，已完成的分段会跳过。"
            value.provider = service.configuration.effectiveAnalysisURL; value.model = service.configuration.analysisModel
            if force { value.checkpoints = [] }
            try persist(value)
            activeID = recording.id
            let token = UUID(); generation = token
            task = Task { [weak self] in
                guard let self else { return }
                defer { if self.generation == token { self.activeID = nil; self.draftID = nil; self.task = nil } }
                do {
                    for (index, segment) in recording.segments.sorted(by: { $0.sequence < $1.sequence }).enumerated() {
                        try Task.checkCancellation()
                        if self.document(recording.id).transcripts.contains(where: { $0.id == segment.id && $0.sha256 == segment.sha256 }) { continue }
                        try self.recordings.repository.verify(segment, recordingID: recording.id)
                        try self.mutate(recording.id) { $0.message = "正在转写第 \(index + 1)/\(recording.segments.count) 段…" }
                        let file = try self.recordings.repository.file(recording.id, name: segment.filename)
                        let text = try await service.transcribe(file: file)
                        try Task.checkCancellation()
                        let transcript = SegmentTranscript(id: segment.id, sha256: segment.sha256 ?? "", original: text, provider: service.configuration.baseURL, model: service.configuration.transcriptionModel)
                        try self.mutate(recording.id) { doc in
                            doc.transcripts.removeAll { $0.id == segment.id }
                            doc.transcripts.append(transcript)
                            let positions = Dictionary(uniqueKeysWithValues: recording.segments.map { ($0.id, $0.sequence) })
                            doc.transcripts.sort { (positions[$0.id] ?? 0) < (positions[$1.id] ?? 0) }
                        }
                    }
                    let snapshot = self.document(recording.id)
                    try self.mutate(recording.id) { $0.state = .analyzing; $0.message = "正在整理重点、待办和选题。长录音会分批处理。" }
                    let result = try await AnalysisRunner().run(transcripts: snapshot.transcripts, checkpoints: snapshot.checkpoints, service: service) { checkpoint in
                        try self.mutate(recording.id) { doc in
                            doc.checkpoints.removeAll { $0.id == checkpoint.id }
                            doc.checkpoints.append(checkpoint)
                            doc.message = "已保存 \(doc.checkpoints.count) 个分析步骤，正在继续…"
                        }
                    }
                    try Task.checkCancellation()
                    try self.mutate(recording.id) {
                        $0.analysis = result; $0.originalAnalysis = result
                        $0.analysisFingerprint = snapshot.fingerprint
                        $0.state = .completed; $0.message = "结果已保存在手机，请核对原文。"
                    }
                } catch {
                    let paused = Task.isCancelled || (error as? URLError)?.code == .cancelled
                    do {
                        try self.mutate(recording.id) {
                            $0.state = paused ? .paused : .failed
                            $0.message = paused ? "处理已暂停。已保存结果仍保留，点击重试继续；服务端可能已处理未收到结果的请求，重试可能重复计费。" : self.friendly(error)
                        }
                    } catch { self.errorMessage = "结果保存失败，请释放手机空间后重试。原始录音仍保留。" }
                }
            }
        } catch { errorMessage = friendly(error) }
    }
    func cancel() {
        guard let task else { return }
        task.cancel()
        // Keep activeID until cancellation unwinds, preventing a concurrent restart or deletion.
    }
    func editTranscript(recordingID: UUID, segmentID: UUID, text: String) {
        guard activeID != recordingID else { return }
        do { try mutate(recordingID) { doc in
            if let index = doc.transcripts.firstIndex(where: { $0.id == segmentID }) {
                doc.transcripts[index].edited = text == doc.transcripts[index].original ? nil : text
                doc.message = "原文已修改，已有分析可能需要重新生成。"
            }
        } } catch { errorMessage = friendly(error) }
    }
    func editAnalysis(_ id: UUID, result: AnalysisResult) {
        guard activeID != id else { return }
        do { try mutate(id) { $0.analysis = result } } catch { errorMessage = friendly(error) }
    }
    func clearTranscript(_ id: UUID) {
        guard activeID != id else { return }
        do { try mutate(id) {
            $0.transcripts = []; $0.checkpoints = []; $0.analysis = nil; $0.originalAnalysis = nil
            $0.analysisFingerprint = nil; $0.state = .idle; $0.message = "转写和分析已清除，手机音频仍保留。再次发送将重新产生服务请求。"
        } } catch { errorMessage = friendly(error) }
    }
    func forget(_ id: UUID) { guard activeID != id else { return }; documents.removeValue(forKey: id); damagedIDs.remove(id) }
    func generateDraft(recording: Recording, idea: ContentIdea) {
        guard !busy, recordings.activeID == nil else { errorMessage = "请先结束录音或等待当前任务。"; return }
        let doc = document(recording.id)
        let evidence = doc.validSources(idea.sourceIDs).map(\.text).joined(separator: "\n")
        guard !evidence.isEmpty else { errorMessage = "没有可核对的原文依据，无法生成初稿。"; return }
        guard evidence.count < 24_000 else { errorMessage = "原文依据过长，请先精简选题关联来源。"; return }
        do {
            let service = try settings.service()
            try mutate(recording.id) { $0.draftError = nil }
            activeID = recording.id; draftID = idea.id
            task = Task { [weak self] in
                guard let self else { return }
                defer { self.activeID = nil; self.draftID = nil; self.task = nil }
                do {
                    let text = try await service.draft(idea: idea, evidence: evidence)
                    try Task.checkCancellation()
                    try self.mutate(recording.id) { doc in
                        if let index = doc.analysis?.ideas.firstIndex(where: { $0.id == idea.id }) {
                            doc.analysis?.ideas[index].draft = text
                            doc.analysis?.ideas[index].status = .drafted
                        }
                    }
                } catch {
                    let message = Task.isCancelled ? "初稿生成已暂停。重试可能重复计费。" : self.friendly(error)
                    try? self.mutate(recording.id) { $0.draftError = message }
                    self.errorMessage = message
                }
            }
        } catch { errorMessage = friendly(error) }
    }
    private func friendly(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost:
                return "网络未连接或服务暂时不可达。已保存成功结果，请联网后手动重试；未收到结果的请求可能已计费。"
            default: return "无法安全连接 AI 服务，请检查网络和 HTTPS 服务地址。"
            }
        }
        return error.localizedDescription
    }
}
