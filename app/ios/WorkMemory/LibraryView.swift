import SwiftUI
import UIKit

struct LibraryView: View {
    @EnvironmentObject private var controller: RecordingController
    @EnvironmentObject private var ai: AIController
    @State private var query = ""
    @State private var scene: SceneType?
    private var filtered: [Recording] {
        controller.recordings.filter {
            (scene == nil || $0.scene == scene) && (query.isEmpty || "\($0.title) \($0.scene.rawValue) \($0.tags) \($0.notes) \(ai.document($0.id).searchText)".localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("\(filtered.count) 条录音 · 均保存在手机").font(.caption).foregroundStyle(Theme.muted)
                    Spacer()
                    Menu {
                        Button("全部场景") { scene = nil }
                        ForEach(SceneType.allCases) { item in Button(item.rawValue) { scene = item } }
                    } label: { Label(scene?.rawValue ?? "全部", systemImage: "line.3.horizontal.decrease.circle").font(.caption) }
                }
                if filtered.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "还没有录音" : "没有找到录音", systemImage: "waveform", description: Text(query.isEmpty ? "从“录音”页开启一段新的工作记忆。" : "试试其他标题、场景或标签。"))
                } else {
                    ForEach(filtered) { recording in
                        NavigationLink { RecordingDetailView(id: recording.id) } label: {
                            Panel { RecordingRow(recording: recording) }
                        }.buttonStyle(.plain).accessibilityIdentifier("recording-\(recording.id.uuidString)")
                    }
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle("录音库")
            .searchable(text: $query, prompt: "搜索标题、原文、观点或标签")
    }
}

struct RecordingDetailView: View {
    @EnvironmentObject private var controller: RecordingController
    @EnvironmentObject private var playback: PlaybackController
    @EnvironmentObject private var ai: AIController
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    @State private var editing = false
    @State private var deleting = false
    @State private var exporting = false
    @State private var exportFiles: [URL] = []
    @State private var sliderValue: Double = 0
    @State private var scrubbing = false
    var body: some View {
        Group {
            if let recording = controller.lookup(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Text(recording.title).font(.title2.bold())
                        HStack { StatusPill(state: recording.state); Spacer(); Text(recording.scene.rawValue).font(.subheadline).foregroundStyle(Theme.muted) }
                        Text(recording.createdAt.formatted(date: .long, time: .shortened)).font(.caption).foregroundStyle(Theme.muted)
                        if recording.id == controller.activeID {
                            Label("此录音仍在进行，请回“录音”页操作。", systemImage: "mic.fill").foregroundStyle(Theme.accent)
                        } else if !recording.playableSegments.isEmpty {
                            Panel {
                                VStack(spacing: 16) {
                                    HStack {
                                        Text("原始录音").font(.headline)
                                        Spacer()
                                        Text(clockText(recording.playableSegments.reduce(0) { $0 + $1.duration })).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.muted)
                                    }
                                    Slider(value: Binding(get: { scrubbing ? sliderValue : (playback.recordingID == id ? playback.position : 0) }, set: { sliderValue = $0 }), in: 0...max(1, recording.playableSegments.reduce(0) { $0 + $1.duration }), onEditingChanged: { editing in
                                        if editing { sliderValue = playback.recordingID == id ? playback.position : 0; scrubbing = true }
                                        else { scrubbing = false; playback.load(recording, repository: controller.repository); playback.seek(to: sliderValue) }
                                    }).disabled(controller.activeID != nil).accessibilityLabel("回放位置")
                                    HStack {
                                        Text(clockText(playback.recordingID == id ? playback.position : 0)).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.muted)
                                        Spacer()
                                        Button {
                                            playback.load(recording, repository: controller.repository)
                                            playback.toggle()
                                        } label: {
                                            Image(systemName: playback.recordingID == id && playback.playing ? "pause.fill" : "play.fill").font(.title2).frame(width: 60, height: 50)
                                        }.buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.background)
                                            .disabled(controller.activeID != nil)
                                            .accessibilityLabel(playback.playing ? "暂停回放" : "播放录音")
                                        Spacer()
                                        Text("\(recording.playableSegments.count) 段").font(.caption).foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                        }
                        if recording.state == .recovered {
                            Panel {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label("上次录音意外结束", systemImage: "exclamationmark.triangle").foregroundStyle(.yellow)
                                    Text("请回听可用分段。未完成封装的末段可能无法恢复，原文件仍保留。").font(.footnote).foregroundStyle(Theme.muted)
                                    Button("我已检查，确认保存") { controller.confirmRecovery(id) }.buttonStyle(.bordered)
                                }
                            }
                        }
                        if !recording.tags.isEmpty { Label(recording.tags, systemImage: "tag").font(.subheadline).foregroundStyle(Theme.accent) }
                        if !recording.notes.isEmpty { Panel { Text(recording.notes).font(.subheadline).textSelection(.enabled) } }
                        HStack { Text("音频分段").font(.headline); Spacer(); Text(ByteCountFormatter.string(fromByteCount: recording.byteCount, countStyle: .file)).font(.caption).foregroundStyle(Theme.muted) }
                        ForEach(recording.segments.sorted { $0.sequence < $1.sequence }) { segment in
                            Panel {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: segment.state == .ready ? "waveform" : "exclamationmark.triangle").foregroundStyle(segment.state == .ready ? Theme.mint : .yellow)
                                        Text("分段 \(segment.sequence + 1)").font(.subheadline.bold())
                                        Spacer()
                                        Text(clockText(segment.duration)).font(.system(.caption, design: .monospaced))
                                    }
                                    if segment.state == .ready {
                                        Text("已保存 · SHA-256 已记录").font(.caption2).foregroundStyle(Theme.muted)
                                        Button("从此段播放") {
                                            playback.load(recording, repository: controller.repository)
                                            let offset = recording.playableSegments.filter { $0.sequence < segment.sequence }.reduce(0) { $0 + $1.duration }
                                            playback.seek(to: offset, play: true)
                                        }.font(.caption).disabled(controller.activeID != nil)
                                    } else {
                                        Text(segment.error ?? "分段仍在录制中，结束后可回放。").font(.footnote).foregroundStyle(.yellow)
                                    }
                                }
                            }
                        }
                        if !recording.events.isEmpty {
                            Text("录音事件").font(.headline)
                            ForEach(recording.events) { event in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(event.date.formatted(date: .omitted, time: .standard)).font(.system(.caption2, design: .monospaced)).foregroundStyle(Theme.muted)
                                    Text(event.message).font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        NavigationLink { MemoryDetailView(id: id) } label: {
                            Panel {
                                HStack {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Label(ai.document(id).analysis == nil ? "文字与重点分析" : "查看工作记忆", systemImage: "sparkles").font(.headline)
                                        Text(ai.document(id).state.label).font(.footnote).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }
                            }
                        }.buttonStyle(.plain).foregroundStyle(Theme.accent).accessibilityIdentifier("openMemory")
                        Button(role: .destructive) { deleting = true } label: {
                            Label("删除手机上的这条录音", systemImage: "trash").frame(maxWidth: .infinity).padding()
                        }.disabled(controller.activeID == id || ai.activeID == id)
                    }.padding(22)
                }
                .sheet(isPresented: $editing) { RecordingEditor(recording: recording, save: controller.update) }
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { editing = true } label: { Image(systemName: "pencil") }.accessibilityLabel("编辑信息").disabled(controller.activeID == id || ai.activeID == id)
                        Button { exportFiles = controller.exports(recording); exporting = !exportFiles.isEmpty } label: { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("导出全部分段和信息").disabled(controller.activeID == id || ai.activeID == id)
                    }
                }
            } else { ContentUnavailableView("录音不存在", systemImage: "waveform") }
        }.background(Theme.background).navigationTitle("录音详情").navigationBarTitleDisplayMode(.inline)
            .onDisappear { playback.pause() }
            .sheet(isPresented: $exporting) { ShareSheet(items: exportFiles) }
            .confirmationDialog("删除手机上的录音？", isPresented: $deleting, titleVisibility: .visible) {
                Button("永久删除手机文件", role: .destructive) { controller.delete(id); if controller.lookup(id) == nil { ai.forget(id); dismiss() } }
                Button("取消", role: .cancel) {}
            } message: { Text("将删除本条录音的全部手机音频、文字、分析、选题和稿件，无法撤销。不会删除你已导出的副本或服务商可能留存的数据。") }
            .alert("回放提示", isPresented: Binding(get: { playback.errorMessage != nil }, set: { if !$0 { playback.errorMessage = nil } })) {
                Button("知道了", role: .cancel) { playback.errorMessage = nil }
            } message: { Text(playback.errorMessage ?? "") }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
