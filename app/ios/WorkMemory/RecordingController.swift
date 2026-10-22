import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class RecordingController: NSObject, ObservableObject {
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var activeID: UUID?
    @Published private(set) var starting = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var freeBytes: Int64 = 0
    @Published var errorMessage: String?
    @Published private(set) var storageWarnings: [String] = []
    @Published private(set) var pausedAt: Date?
    @Published private(set) var now = Date()
    let repository: LocalRepository
    let playback = PlaybackController()
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var ticks = 0
    private var stoppedAt: Date?
    private var segmentSeconds: TimeInterval = 600
    var active: Recording? { recordings.first { $0.id == activeID } }
    var isRecording: Bool { active?.state == .recording && recorder?.isRecording == true }
    var pauseReminder: Bool { pausedAt.map { now.timeIntervalSince($0) > 300 } ?? false }

    init(repository: LocalRepository) {
        self.repository = repository
        super.init()
        reloadAndRecover()
        observeAudioSession()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }
    private func reloadAndRecover() {
        do {
            recordings = try repository.load()
            storageWarnings = repository.warnings
            for index in recordings.indices where recordings[index].state.unfinished {
                do {
                    recordings[index] = try repository.recover(recordings[index]) { url in
                        let audio = try AVAudioPlayer(contentsOf: url)
                        guard audio.duration > 0 else { throw LocalError.missingFile }
                        return audio.duration
                    }
                } catch { storageWarnings.append("恢复录音失败：\(error.localizedDescription)") }
            }
            freeBytes = try repository.freeBytes()
        } catch { errorMessage = "读取本地录音失败：\(error.localizedDescription)" }
    }

    func start(title: String, scene: SceneType, tags: String, notes: String, segmentMinutes: Int) async {
        guard activeID == nil, !starting else { return }
        starting = true
        defer { starting = false }
        let allowed = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard allowed else { errorMessage = "麦克风权限未开启。请在 iPhone 设置中允许“工作记忆”访问麦克风。"; return }
        do {
            playback.stop()
            try repository.checkSpace()
            try activateSession()
            var recording = Recording(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Recording.defaultTitle(scene: scene) : title, scene: scene)
            recording.tags = tags
            recording.notes = notes
            recording.events.append(RecordingEvent(message: "用户开始录音；音频仅保存在手机。"))
            try repository.save(recording)
            recordings.insert(recording, at: 0)
            activeID = recording.id
            segmentSeconds = TimeInterval([5, 10, 15].contains(segmentMinutes) ? segmentMinutes * 60 : 600)
            try openSegment()
        } catch { fail(error) }
    }

    private func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
    }
    private func deactivateSession() {
        do { try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        catch { errorMessage = "音频会话释放失败：\(error.localizedDescription)" }
    }
    private func openSegment() throws {
        guard let current = active else { return }
        try repository.checkSpace()
        let segmentID = UUID()
        var segment = AudioSegment(sequence: current.segments.count, filename: "\(segmentID.uuidString).m4a", startOffset: current.duration)
        segment.id = segmentID
        try changeActive { $0.segments.append(segment) }
        let url = try repository.file(current.id, name: segment.filename)
        let audio = try AVAudioRecorder(url: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ])
        audio.delegate = self
        audio.isMeteringEnabled = true
        recorder = audio
        guard audio.prepareToRecord(), audio.record(forDuration: segmentSeconds) else {
            audio.delegate = nil
            recorder = nil
            throw RecordingFailure.cannotStart
        }
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        pausedAt = nil
        stoppedAt = nil
        elapsed = current.duration
    }

    private func closeSegment() throws {
        guard let audio = recorder, let current = active, let segment = current.segments.last else { return }
        recorder = nil
        audio.delegate = nil
        let capturedDuration = audio.currentTime
        audio.stop()
        let url = try repository.file(current.id, name: segment.filename)
        do {
            let duration = (try? AVAudioPlayer(contentsOf: url).duration) ?? capturedDuration
            let completed = try repository.finalize(segment, recordingID: current.id, duration: duration)
            try changeActive { $0.segments[$0.segments.count - 1] = completed }
        } catch {
            let message = error.localizedDescription
            // Retain both the audio file and its manifest entry even when finalization fails.
            if let index = recordings.firstIndex(where: { $0.id == activeID }), !recordings[index].segments.isEmpty {
                let last = recordings[index].segments.count - 1
                recordings[index].segments[last].state = .unreadable
                recordings[index].segments[last].error = message
                try? repository.save(recordings[index])
            }
            throw error
        }
        elapsed = active?.duration ?? 0
        level = 0
    }

    func pause() {
        guard active?.state == .recording else { return }
        do {
            try closeSegment()
            try changeActive {
                try $0.transition(to: .paused)
                $0.events.append(RecordingEvent(message: "用户暂停，当前分段已关闭保存。"))
            }
            pausedAt = Date()
            deactivateSession()
        } catch { fail(error) }
    }
    func resume() {
        guard let state = active?.state, state == .paused || state == .interrupted else { return }
        do {
            try repository.checkSpace()
            try activateSession()
            try changeActive {
                try $0.transition(to: .recording)
                $0.events.append(RecordingEvent(message: "用户继续录音，创建新分段。"))
            }
            try openSegment()
        } catch { fail(error) }
    }
    @discardableResult
    func finish() -> UUID? {
        guard let id = activeID else { return nil }
        do {
            try closeSegment()
            try changeActive {
                try $0.transition(to: .saved)
                $0.events.append(RecordingEvent(message: "用户结束录音；已保存到手机，未上传。"))
            }
            activeID = nil
            pausedAt = nil
            level = 0
            deactivateSession()
            return id
        } catch { fail(error); return nil }
    }
    private func changeActive(_ update: (inout Recording) throws -> Void) throws {
        guard let index = recordings.firstIndex(where: { $0.id == activeID }) else { return }
        var value = recordings[index]
        try update(&value)
        value.updatedAt = Date()
        try repository.save(value)
        recordings[index] = value
    }
    private func fail(_ error: Error) {
        let message = error.localizedDescription
        // Closing a live recorder is necessary even when a metadata write failed.
        do { try closeSegment() } catch { /* The file and in-memory manifest are retained. */ }
        if activeID != nil {
            do {
                try changeActive {
                    if $0.state == .recording || $0.state == .paused { try $0.transition(to: .interrupted) }
                    $0.events.append(RecordingEvent(message: "异常停止：\(message)"))
                }
            } catch { storageWarnings.append("录音信息写入失败，请保留本机数据并释放空间后重试。") }
        }
        pausedAt = Date()
        level = 0
        errorMessage = message
        deactivateSession()
    }
    private func interrupt(_ message: String) {
        guard activeID != nil else { playback.stop(); return }
        if active?.state == .recording {
            do {
                try closeSegment()
                try changeActive {
                    try $0.transition(to: .interrupted)
                    $0.events.append(RecordingEvent(message: message))
                }
                pausedAt = Date()
                errorMessage = message + " 已保存可用分段，请在条件允许时手动继续。"
                deactivateSession()
            } catch { fail(error) }
        }
    }
    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            Task { @MainActor [weak self] in
                if raw == AVAudioSession.InterruptionType.began.rawValue { self?.interrupt("系统音频中断，录音已暂停。") }
                else if self?.active?.state == .interrupted { self?.errorMessage = "音频中断已结束。点击“继续录音”后才会重新采集。" }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                if raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.interrupt("耳机或输入设备已断开。") }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.interrupt("系统音频服务已重置。") }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        })
    }
    private func tick() {
        now = Date()
        if let audio = recorder {
            elapsed = (active?.duration ?? 0) + audio.currentTime
            audio.updateMeters()
            level = audio.isRecording ? max(0, min(1, (audio.averagePower(forChannel: 0) + 55) / 55)) : 0
            if active?.state == .recording, !audio.isRecording {
                if let stopped = stoppedAt, now.timeIntervalSince(stopped) > 2 {
                    interrupt("录音设备意外停止。")
                } else if stoppedAt == nil { stoppedAt = now }
            } else { stoppedAt = nil }

        }
        ticks += 1
        if ticks % 20 == 0 {
            do {
                freeBytes = try repository.freeBytes()
                if active?.state == .recording, freeBytes < LocalRepository.minimumFreeBytes { fail(LocalError.insufficientSpace) }
            } catch { errorMessage = "无法检查存储空间：\(error.localizedDescription)" }
        }
    }

    func update(_ recording: Recording) {
        guard recording.id != activeID, let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        do {
            var value = recording
            if value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { value.title = Recording.defaultTitle(scene: value.scene, date: value.createdAt) }
            value.updatedAt = Date()
            try repository.save(value)
            recordings[index] = value
        } catch { errorMessage = "保存修改失败：\(error.localizedDescription)" }
    }
    func confirmRecovery(_ id: UUID) {
        guard var item = recordings.first(where: { $0.id == id }), item.state == .recovered else { return }
        do { try item.transition(to: .saved); update(item) }
        catch { errorMessage = error.localizedDescription }
    }
    func delete(_ id: UUID) {
        guard id != activeID else { errorMessage = "请先结束录音，再删除手机文件。"; return }
        do {
            playback.stop()
            try repository.delete(id)
            recordings.removeAll { $0.id == id }
        } catch { errorMessage = "删除失败：\(error.localizedDescription)" }
    }
    func lookup(_ id: UUID) -> Recording? { recordings.first { $0.id == id } }
    func exports(_ recording: Recording) -> [URL] {
        do { return try repository.exportURLs(recording) }
        catch { errorMessage = "导出失败：\(error.localizedDescription)"; return [] }
    }
}

extension RecordingController: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let audio = self.recorder, ObjectIdentifier(audio) == identity else { return }
            guard flag else { self.fail(RecordingFailure.writeFailed); return }
            do {
                try self.closeSegment()
                guard self.active?.state == .recording else { return }
                try self.changeActive { $0.events.append(RecordingEvent(message: "分段已保存，开始下一段（切换可能有短暂间隙）。")) }
                try self.openSegment()
            } catch { self.fail(error) }
        }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let identity = ObjectIdentifier(recorder)
        let message = error?.localizedDescription ?? "音频编码错误。"
        Task { @MainActor [weak self] in
            guard let self, let audio = self.recorder, ObjectIdentifier(audio) == identity else { return }
            self.fail(RecordingFailure.encoding(message))
        }
    }
}

enum RecordingFailure: LocalizedError {
    case cannotStart, writeFailed, encoding(String)
    var errorDescription: String? {
        switch self {
        case .cannotStart: return "录音设备无法启动，请检查麦克风权限和其他 App 的音频占用。"
        case .writeFailed: return "音频分段写入失败，已保留此前完成的文件。"
        case .encoding(let message): return message
        }
    }
}
