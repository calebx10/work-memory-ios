import Foundation
import CryptoKit

final class LocalRepository {
    let root: URL
    private let fm: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private(set) var warnings: [String] = []
    static let minimumFreeBytes: Int64 = 100 * 1_024 * 1_024

    init(root: URL, fileManager: FileManager = .default) throws {
        self.root = root
        fm = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try protect(root)
        var excluded = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
    }

    func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func file(_ recordingID: UUID, name: String) throws -> URL {
        guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent,
              !name.contains(".."), !name.contains("/"), !name.contains("\\") else { throw LocalError.unsafePath }
        return directory(recordingID).appendingPathComponent(name)
    }

    func save(_ recording: Recording) throws {
        let folder = directory(recording.id)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try protect(folder)
        let url = folder.appendingPathComponent("manifest.json")
        let backup = folder.appendingPathComponent("manifest.backup.json")
        if let previous = try? Data(contentsOf: url), (try? decoder.decode(Recording.self, from: previous)) != nil {
            try previous.write(to: backup, options: .atomic)
            try protect(backup)
        }
        try encoder.encode(recording).write(to: url, options: .atomic)
        try protect(url)
    }

    func load() throws -> [Recording] {
        warnings = []
        let folders = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        var recordings: [Recording] = []
        for folder in folders {
            guard let expectedID = UUID(uuidString: folder.lastPathComponent) else { continue }
            let primary = folder.appendingPathComponent("manifest.json")
            let backup = folder.appendingPathComponent("manifest.backup.json")
            var value: Recording?
            if let data = try? Data(contentsOf: primary), let parsed = try? decoder.decode(Recording.self, from: data), parsed.id == expectedID {
                value = parsed
            } else if let data = try? Data(contentsOf: backup), let parsed = try? decoder.decode(Recording.self, from: data), parsed.id == expectedID {
                value = parsed
                warnings.append("录音 \(expectedID.uuidString.prefix(8)) 的信息已从备份恢复，部分最近操作可能未保留。")
            } else {
                warnings.append("录音目录 \(expectedID.uuidString.prefix(8)) 信息无法读取，原始文件仍保留，请通过文件导出备份。")
            }
            if let value { recordings.append(value) }
        }
        return recordings.sorted { $0.createdAt > $1.createdAt }
    }

    func finalize(_ segment: AudioSegment, recordingID: UUID, duration: TimeInterval) throws -> AudioSegment {
        let url = try file(recordingID, name: segment.filename)
        guard fm.fileExists(atPath: url.path) else { throw LocalError.missingFile }
        let size = try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard let size, size.int64Value > 0, duration.isFinite, duration > 0 else { throw LocalError.missingFile }
        var result = segment
        result.duration = duration
        result.endedAt = Date()
        result.byteCount = size.int64Value
        result.sha256 = try digest(url)
        result.state = .ready
        result.error = nil
        try protect(url)
        return result
    }

    func verify(_ segment: AudioSegment, recordingID: UUID) throws {
        let url = try file(recordingID, name: segment.filename)
        let size = try fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard size?.int64Value == segment.byteCount, try digest(url) == segment.sha256 else { throw LocalError.integrityMismatch }
    }

    func recover(_ original: Recording, durationOfFile: (URL) throws -> TimeInterval) throws -> Recording {
        guard original.state.unfinished else { return original }
        var recovered = original
        var offset: TimeInterval = 0
        for index in recovered.segments.indices {
            var segment = recovered.segments[index]
            segment.startOffset = offset
            do {
                let url = try file(original.id, name: segment.filename)
                let duration = try durationOfFile(url)
                if segment.state == .ready { try verify(segment, recordingID: original.id) }
                segment = try finalize(segment, recordingID: original.id, duration: duration)
                offset += segment.duration
            } catch {
                segment.state = .unreadable
                segment.error = "上次录音未完整保存或文件校验失败；原始文件保留供导出。"
            }
            recovered.segments[index] = segment
        }
        recovered.state = .recovered
        recovered.updatedAt = Date()
        recovered.events.append(RecordingEvent(message: "检测到上次未结束的录音。已检查文件，请回听后确认保存。"))
        try save(recovered)
        return recovered
    }

    func delete(_ id: UUID) throws {
        try fm.removeItem(at: directory(id))
    }
    func freeBytes() throws -> Int64 {
        let values = try fm.attributesOfFileSystem(forPath: root.path)
        return (values[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }
    func checkSpace() throws {
        guard try freeBytes() >= Self.minimumFreeBytes else { throw LocalError.insufficientSpace }
    }
    func exportURLs(_ recording: Recording) throws -> [URL] {
        let manifest = try file(recording.id, name: "manifest.json")
        let memory = try file(recording.id, name: "memory.json")
        let memoryFiles = fm.fileExists(atPath: memory.path) ? [memory] : []
        return [manifest] + memoryFiles + (try recording.segments.sorted { $0.sequence < $1.sequence }.map {
            try file(recording.id, name: $0.filename)
        }).filter { fm.fileExists(atPath: $0.path) }
    }
    func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_024 * 1_024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func protect(_ url: URL) throws {
        #if os(iOS)
        try fm.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
}
