import SwiftUI

struct MemoryDetailView: View {
    @EnvironmentObject private var controller: RecordingController
    @EnvironmentObject private var ai: AIController
    let id: UUID
    @State private var tab = 0
    @State private var consent = false
    @State private var force = false
    @State private var source: SegmentTranscript?
    @State private var editor: TextEditRequest?
    @State private var clearing = false
    @State private var exportFiles: [URL] = []
    @State private var exporting = false
    private var doc: MemoryDocument { ai.document(id) }
    private var locked: Bool { ai.activeID == id }
    var body: some View {
        Group {
            if let recording = controller.lookup(id) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(recording.title).font(.title2.bold())
                        processingPanel(recording)
                        Picker("内容", selection: $tab) {
                            Text("重点").tag(0); Text("原文").tag(1); Text("选题").tag(2)
                        }.pickerStyle(.segmented)
                        if tab == 0 { analysisView(recording) }
                        else if tab == 1 { transcriptView(recording) }
                        else { ideasView(recording) }
                    }.padding(22)
                }
                .sheet(isPresented: $consent) { AIConsentView(recording: recording, force: force) }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("导出 Markdown 和文字", systemImage: "square.and.arrow.up") {
                                do { exportFiles = try controller.repository.exportMemory(doc, recording: recording); exporting = true }
                                catch { ai.errorMessage = error.localizedDescription }
                            }.disabled(locked || doc.transcripts.isEmpty)
                            Button("重新生成分析", systemImage: "arrow.clockwise") { force = true; consent = true }.disabled(locked || doc.analysis == nil || controller.activeID != nil)
                            Button("清除转写和分析", systemImage: "trash", role: .destructive) { clearing = true }.disabled(locked || doc.transcripts.isEmpty)
                        } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("分析操作")
                    }
                }
            } else { ContentUnavailableView("录音不存在", systemImage: "waveform") }
        }.background(Theme.background).navigationTitle("工作记忆").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $source) { transcript in if let recording = controller.lookup(id) { SourceView(recording: recording, transcript: transcript) } }
            .sheet(item: $editor) { request in TextEditorSheet(request: request) }
            .sheet(isPresented: $exporting) { ShareSheet(items: exportFiles) }
            .confirmationDialog("清除本条转写和分析？", isPresented: $clearing, titleVisibility: .visible) {
                Button("清除转写、分析、选题和稿件", role: .destructive) { ai.clearTranscript(id) }
                Button("取消", role: .cancel) {}
            } message: { Text("手机原始音频会保留。此操作无法撤销，再次分析会重新发送音频并可能计费。请先导出备份。") }
    }
    private func processingPanel(_ recording: Recording) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(doc.state.label, systemImage: doc.state == .completed ? "checkmark.circle" : "sparkles").font(.headline).foregroundStyle(Theme.accent)
                    Spacer()
                    if locked { ProgressView() }
                }
                if !doc.message.isEmpty { Text(doc.message).font(.footnote).foregroundStyle(Theme.muted) }
                if doc.needsAnalysisUpdate { Label("原文已修改，分析待更新", systemImage: "arrow.clockwise").font(.footnote).foregroundStyle(.yellow) }
                if locked {
                    Button("暂停处理") { ai.cancel() }.buttonStyle(.bordered)
                } else if doc.analysis == nil || doc.needsAnalysisUpdate || doc.state == .failed || doc.state == .paused {
                    PrimaryButton(title: doc.state == .failed || doc.state == .paused ? "重试未完成的步骤" : "发送并分析", symbol: "sparkles") {
                        force = false; consent = true
                    }.disabled(ai.busy || controller.activeID != nil || recording.state != .saved)
                }
                if recording.state != .saved { Text("请先在录音详情确认恢复或结束录音。").font(.caption).foregroundStyle(.yellow) }
                Text("已转写 \(doc.transcripts.count)/\(recording.segments.count) 段 · 结果保存在手机").font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }
    @ViewBuilder private func analysisView(_ recording: Recording) -> some View {
        if let result = doc.analysis {
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("一句话摘要").font(.caption).foregroundStyle(Theme.accent); Spacer(); editButton { editSummary(result, detailed: false) } }
                    Text(result.summary).font(.title3.bold()).textSelection(.enabled)
                    Divider()
                    HStack { Text("内容摘要").font(.headline); Spacer(); editButton { editSummary(result, detailed: true) } }
                    Text(result.detailedSummary).font(.subheadline).textSelection(.enabled)
                }
            }
            ForEach(result.sections) { section in
                Text(section.kind.title).font(.title3.bold())
                if section.items.isEmpty { Text("原文中没有足够依据，暂未提取。").font(.footnote).foregroundStyle(Theme.muted) }
                ForEach(section.items) { item in
                    Panel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                Text(item.title).font(.headline)
                                Spacer()
                                Button { updateItem(item.id, kind: section.kind) { $0.favorite.toggle() } } label: { Image(systemName: item.favorite ? "star.fill" : "star") }
                                    .foregroundStyle(Theme.accent).disabled(locked).accessibilityLabel(item.favorite ? "取消收藏" : "收藏重点")
                                editButton { editItem(item, kind: section.kind) }
                            }
                            Text(item.detail).font(.subheadline).foregroundStyle(item.done ? Theme.muted : .white).textSelection(.enabled)
                            sourceButtons(item.sourceIDs)
                            if section.kind == .todos {
                                Button { updateItem(item.id, kind: section.kind) { $0.done.toggle() } } label: { Label(item.done ? "已完成" : "标记完成", systemImage: item.done ? "checkmark.circle.fill" : "circle") }.font(.caption).disabled(locked)
                            }
                        }
                    }
                }
            }
            Text("AI 内容是待审核草稿。来源链接指向实际转写分段，不代表每一条结论都正确。").font(.caption).foregroundStyle(Theme.muted)
        } else { ContentUnavailableView("让对话变成可用的记忆", systemImage: "sparkles", description: Text("分析后，这里会显示摘要、观点、决策、待办和经验。")) }
    }
    @ViewBuilder private func transcriptView(_ recording: Recording) -> some View {
        if doc.transcripts.isEmpty { ContentUnavailableView("还没有转写", systemImage: "text.alignleft", description: Text("点击“发送并分析”开始。录音文件仍在手机。")) }
        ForEach(doc.transcripts) { transcript in
            Panel {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        let segment = recording.segments.first { $0.id == transcript.id }
                        Text("\(clockText(segment?.startOffset ?? 0)) · 分段起点").font(.caption).foregroundStyle(Theme.accent)
                        Spacer()
                        editButton {
                            editor = TextEditRequest(title: "修订转写", text: transcript.text) { ai.editTranscript(recordingID: id, segmentID: transcript.id, text: $0) }
                        }
                    }
                    Text(transcript.text).font(.subheadline).textSelection(.enabled)
                    if transcript.edited != nil {
                        DisclosureGroup("查看原始 AI 转写") { Text(transcript.original).font(.footnote).foregroundStyle(Theme.muted).textSelection(.enabled) }
                    }
                    Button { source = transcript } label: { Label("回听原始分段", systemImage: "play.circle") }.font(.caption)
                }
            }
        }
    }
    @ViewBuilder private func ideasView(_ recording: Recording) -> some View {
        if let result = doc.analysis {
            if result.ideas.isEmpty { ContentUnavailableView("本次没有足够有价值的选题", systemImage: "lightbulb", description: Text("保留真实内容，不为了数量强行生成。")) }
            ForEach(result.ideas) { idea in
                IdeaCard(recording: recording, idea: idea, sourceAction: { source = $0 }, editAction: {
                    editor = TextEditRequest(title: "编辑选题标题", text: idea.title) { text in updateIdea(idea.id) { $0.title = text } }
                }, editDraft: {
                    editor = TextEditRequest(title: "编辑口播稿", text: idea.draft) { text in updateIdea(idea.id) { $0.draft = text; $0.status = .drafted } }
                }, update: { updated in updateIdea(idea.id) { $0 = updated } })
            }
        } else { ContentUnavailableView("从真实经验里发现选题", systemImage: "lightbulb", description: Text("先完成分析，再挑选你想讲的观点。")) }
    }
    private func sourceButtons(_ ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(doc.validSources(ids)) { transcript in
                Button { source = transcript } label: { Label("查看原文与录音", systemImage: "quote.bubble") }.font(.caption)
            }
        }
    }
    private func editButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "pencil").font(.caption).padding(5) }.disabled(locked).accessibilityLabel("编辑内容")
    }
    private func editSummary(_ result: AnalysisResult, detailed: Bool) {
        editor = TextEditRequest(title: detailed ? "编辑内容摘要" : "编辑一句话摘要", text: detailed ? result.detailedSummary : result.summary) { text in
            guard var current = ai.document(id).analysis else { return }
            if detailed { current.detailedSummary = text } else { current.summary = text }
            ai.editAnalysis(id, result: current)
        }
    }
    private func editItem(_ item: MemoryItem, kind: SectionKind) {
        editor = TextEditRequest(title: "编辑\(kind.title)", text: item.detail) { text in updateItem(item.id, kind: kind) { $0.detail = text } }
    }
    private func updateItem(_ itemID: UUID, kind: SectionKind, _ update: (inout MemoryItem) -> Void) {
        guard var result = doc.analysis, let sectionIndex = result.sections.firstIndex(where: { $0.kind == kind }), let index = result.sections[sectionIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
        update(&result.sections[sectionIndex].items[index]); ai.editAnalysis(id, result: result)
    }
    private func updateIdea(_ ideaID: UUID, _ update: (inout ContentIdea) -> Void) {
        guard var result = doc.analysis, let index = result.ideas.firstIndex(where: { $0.id == ideaID }) else { return }
        update(&result.ideas[index]); ai.editAnalysis(id, result: result)
    }
}

struct IdeaCard: View {
    @EnvironmentObject private var ai: AIController
    let recording: Recording
    let idea: ContentIdea
    let sourceAction: (SegmentTranscript) -> Void
    let editAction: () -> Void
    let editDraft: () -> Void
    let update: (ContentIdea) -> Void
    @State private var consent = false
    @State private var editing: TextEditRequest?
    private var locked: Bool { ai.activeID == recording.id }
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) { Text(idea.title).font(.title3.bold()); Spacer(); Button(action: editAction) { Image(systemName: "pencil") }.disabled(locked).accessibilityLabel("编辑选题标题") }
                Menu {
                    ForEach(IdeaStatus.allCases) { status in Button(status.rawValue) { var value = idea; value.status = status; update(value) } }
                } label: { Label(idea.status.rawValue, systemImage: idea.status == .favorite ? "star.fill" : "tag").font(.caption) }.disabled(locked)
                ideaField("受众", value: idea.audience) { $0.audience = $1 }
                ideaField("核心问题", value: idea.problem) { $0.problem = $1 }
                ideaField("核心观点", value: idea.viewpoint) { $0.viewpoint = $1 }
                ideaField("表达角度", value: idea.angle) { $0.angle = $1 }
                ForEach(ai.document(recording.id).validSources(idea.sourceIDs)) { source in
                    Button { sourceAction(source) } label: { Label("查看原文依据", systemImage: "quote.bubble") }.font(.caption)
                }
                if !idea.draft.isEmpty {
                    Divider()
                    HStack { Text("口播初稿").font(.headline); Spacer(); Button(action: editDraft) { Image(systemName: "pencil") }.disabled(locked).accessibilityLabel("编辑口播稿") }
                    Text(idea.draft).font(.subheadline).textSelection(.enabled)
                    ShareLink(item: idea.draft) { Label("复制或分享稿件", systemImage: "square.and.arrow.up") }.font(.caption)
                }
                if ai.draftID == idea.id { ProgressView("正在生成初稿…"); Button("暂停") { ai.cancel() } }
                else { Button { consent = true } label: { Label(idea.draft.isEmpty ? "生成口播初稿" : "重新生成初稿", systemImage: "wand.and.stars") }.buttonStyle(.bordered).disabled(ai.busy) }
                if let error = ai.document(recording.id).draftError { Text(error).font(.caption).foregroundStyle(.yellow) }
                Text("只生成草稿，不会自动发布。").font(.caption2).foregroundStyle(Theme.muted)
            }
        }.sheet(isPresented: $consent) { AIConsentView(recording: recording, draftIdea: idea) }
            .sheet(item: $editing) { request in TextEditorSheet(request: request) }
    }
    private func ideaField(_ title: String, value: String, setter: @escaping (inout ContentIdea, String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.caption).foregroundStyle(Theme.accent); Spacer(); Button { editing = TextEditRequest(title: "编辑\(title)", text: value) { text in var copy = idea; setter(&copy, text); update(copy) } } label: { Image(systemName: "pencil").font(.caption2) }.disabled(locked).accessibilityLabel("编辑\(title)") }
            Text(value).font(.subheadline).textSelection(.enabled)
        }
    }
}

struct SourceView: View {
    @EnvironmentObject private var controller: RecordingController
    @EnvironmentObject private var playback: PlaybackController
    @Environment(\.dismiss) private var dismiss
    let recording: Recording
    let transcript: SegmentTranscript
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("\(clockText(recording.segments.first { $0.id == transcript.id }?.startOffset ?? 0)) · 音频分段起点").font(.caption).foregroundStyle(Theme.accent)
                    Text("当前转写没有精确句级时间戳，播放会从对应分段开头开始。").font(.footnote).foregroundStyle(Theme.muted)
                    PrimaryButton(title: playback.playing ? "暂停回放" : "播放来源分段", symbol: playback.playing ? "pause.fill" : "play.fill") {
                        if playback.playing { playback.pause() }
                        else {
                            playback.load(recording, repository: controller.repository)
                            let offset = recording.playableSegments.prefix { $0.id != transcript.id }.reduce(0) { $0 + $1.duration }
                            playback.seek(to: offset, play: true)
                        }
                    }.disabled(controller.activeID != nil)
                    Text(transcript.text).textSelection(.enabled)
                    if transcript.edited != nil { DisclosureGroup("原始 AI 转写") { Text(transcript.original).font(.footnote).textSelection(.enabled) } }
                }.padding(24)
            }.background(Theme.background).navigationTitle("原文依据").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }.onDisappear { playback.pause() }
    }
}

struct TextEditRequest: Identifiable {
    let id = UUID()
    var title: String
    var text: String
    var save: (String) -> Void
}
struct TextEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: TextEditRequest
    @State private var text = ""
    var body: some View {
        NavigationStack {
            TextEditor(text: $text).padding(16).scrollContentBackground(.hidden).background(Theme.background)
                .navigationTitle(request.title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { request.save(text); dismiss() } }
                }.onAppear { text = request.text }
        }.tint(Theme.accent)
    }
}

struct CollectionsView: View {
    @EnvironmentObject private var controller: RecordingController
    @EnvironmentObject private var ai: AIController
    @State private var filter = "全部选题"
    @State private var query = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("内容筛选", selection: $filter) {
                    Text("全部选题").tag("全部选题"); Text("已收藏").tag("已收藏"); Text("收藏重点").tag("收藏重点")
                }.pickerStyle(.segmented)
                if entries.isEmpty { ContentUnavailableView("素材从真实对话中生长", systemImage: "lightbulb", description: Text("完成录音分析后，可在这里查找选题与收藏的重点。")) }
                ForEach(entries) { entry in
                    NavigationLink { MemoryDetailView(id: entry.recordingID) } label: {
                        Panel {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(entry.title).font(.headline).foregroundStyle(.white)
                                Text(entry.detail).font(.subheadline).lineLimit(3).foregroundStyle(Theme.muted)
                                Label(entry.source, systemImage: "waveform").font(.caption).foregroundStyle(Theme.accent)
                            }
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(22)
        }.background(Theme.background).navigationTitle("素材库").searchable(text: $query, prompt: "搜索选题、观点和稿件")
    }
    private var entries: [CollectionEntry] {
        controller.recordings.flatMap { recording -> [CollectionEntry] in
            guard let result = ai.document(recording.id).analysis else { return [] }
            if filter == "收藏重点" {
                return result.sections.flatMap(\.items).filter(\.favorite).map { CollectionEntry(id: $0.id, recordingID: recording.id, title: $0.title, detail: $0.detail, source: recording.title) }
            }
            return result.ideas.filter { filter != "已收藏" || $0.status == .favorite }.map { CollectionEntry(id: $0.id, recordingID: recording.id, title: $0.title, detail: "\($0.viewpoint) \($0.draft)", source: recording.title) }
        }.filter { query.isEmpty || "\($0.title) \($0.detail) \($0.source)".localizedCaseInsensitiveContains(query) }
    }
}
private struct CollectionEntry: Identifiable { var id: UUID; var recordingID: UUID; var title: String; var detail: String; var source: String }
