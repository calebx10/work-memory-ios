import AVFoundation
import Combine

@MainActor
final class PlaybackController: NSObject, ObservableObject {
    @Published private(set) var recordingID: UUID?
    @Published private(set) var playing = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var errorMessage: String?
    private var player: AVAudioPlayer?
    private var segments: [(AudioSegment, URL)] = []
    private var currentIndex = 0
    private var timer: Timer?

    func load(_ recording: Recording, repository: LocalRepository) {
        guard recordingID != recording.id else { return }
        stop()
        do {
            segments = try recording.playableSegments.map { segment in
                try repository.verify(segment, recordingID: recording.id)
                return (segment, try repository.file(recording.id, name: segment.filename))
            }
            duration = segments.reduce(0) { $0 + $1.0.duration }
            recordingID = recording.id
        } catch { segments = []; errorMessage = "音频无法读取：\(error.localizedDescription)" }
    }
    func toggle() {
        if playing { pause() }
        else { seek(to: position, play: true) }
    }
    func pause() { player?.pause(); playing = false; timer?.invalidate(); timer = nil }
    func stop() {
        player?.delegate = nil
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        playing = false
        position = 0
        duration = 0
        recordingID = nil
        segments = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func seek(to offset: TimeInterval, play: Bool? = nil) {
        guard !segments.isEmpty else { return }
        let shouldPlay = play ?? playing
        var remaining = max(0, min(offset, duration))
        var index = 0
        while index < segments.count - 1, remaining >= segments[index].0.duration {
            remaining -= segments[index].0.duration
            index += 1
        }
        do {
            player?.delegate = nil
            player?.stop()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            let audio = try AVAudioPlayer(contentsOf: segments[index].1)
            audio.delegate = self
            audio.currentTime = remaining
            player = audio
            currentIndex = index
            position = max(0, min(offset, duration))
            playing = shouldPlay && audio.play()
            timer?.invalidate()
            if playing {
                timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.position = self.segments.prefix(self.currentIndex).reduce(0) { $0 + $1.0.duration } + (self.player?.currentTime ?? 0)
                    }
                }
            }
        } catch { pause(); errorMessage = "播放失败：\(error.localizedDescription)" }
    }
    fileprivate func finished(success: Bool) {
        guard success else { pause(); errorMessage = "音频播放中断，请尝试重新播放。"; return }
        if currentIndex + 1 < segments.count {
            let next = segments.prefix(currentIndex + 1).reduce(0) { $0 + $1.0.duration }
            seek(to: next, play: true)
        } else { pause(); position = 0 }
    }
}
extension PlaybackController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identity else { return }
            self.finished(success: flag)
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error?.localizedDescription ?? "音频文件无法解码。"
        Task { @MainActor [weak self] in self?.pause(); self?.errorMessage = message }
    }
}
