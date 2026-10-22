import Foundation

struct AnalysisRunner {
    func run(transcripts: [SegmentTranscript], checkpoints: [AnalysisCheckpoint], service: any MemoryAIService,
             onCheckpoint: (AnalysisCheckpoint) async throws -> Void) async throws -> AnalysisResult {
        let batches = try AnalysisBatch.make(transcripts)
        guard !batches.isEmpty else { throw AIError.emptyTranscript }
        var cache = Dictionary(checkpoints.map { ($0.id, $0.result) }, uniquingKeysWith: { _, last in last })
        let allSources = Set(transcripts.map { $0.id.uuidString })
        let config = service.configuration
        let prefix = "iphone-v2|\(config.effectiveAnalysisURL)|\(config.analysisModel)|\(config.structuredOutputs)"
        func process(input: String, sources: Set<String>, merging: Bool) async throws -> AnalysisResult {
            try Task.checkCancellation()
            let id = stableHash("\(prefix)|\(merging)|\(input)")
            if let cached = cache[id] { return cached }
            let result = try await service.analyze(input: input, sourceIDs: sources, merging: merging)
            try Task.checkCancellation()
            try await onCheckpoint(AnalysisCheckpoint(id: id, result: result))
            cache[id] = result
            return result
        }
        var results: [AnalysisResult] = []
        for batch in batches { results.append(try await process(input: batch.input, sources: batch.sourceIDs, merging: false)) }
        // Pairwise reduction keeps context bounded rather than concatenating an entire day's notes.
        while results.count > 1 {
            var next: [AnalysisResult] = []
            for index in stride(from: 0, to: results.count, by: 2) {
                guard index + 1 < results.count else { next.append(results[index]); continue }
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                let data = try encoder.encode([results[index], results[index + 1]])
                guard data.count <= 120_000 else { throw AIError.responseTooLarge }
                next.append(try await process(input: String(decoding: data, as: UTF8.self), sources: allSources, merging: true))
            }
            results = next
        }
        return results[0]
    }
}
