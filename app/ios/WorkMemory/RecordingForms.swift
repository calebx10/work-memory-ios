import SwiftUI

struct NewRecordingView: View {
    @EnvironmentObject private var controller: RecordingController
    @EnvironmentObject private var ai: AIController
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultScene", store: AppPreferences.defaults) private var defaultScene = SceneType.meeting.rawValue
    @AppStorage("segmentMinutes", store: AppPreferences.defaults) private var segmentMinutes = 10
    @State private var title = ""
    @State private var scene = SceneType.meeting
    @State private var tags = ""
    @State private var notes = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("这次记录什么") {
                    TextField(Recording.defaultTitle(scene: scene), text: $title)
                    Picker("场景", selection: $scene) { ForEach(SceneType.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                    TextField("关联项目 / 标签（可选）", text: $tags)
                    TextField("备注（可选）", text: $notes, axis: .vertical).lineLimit(3...6)
                }
                Section {
                    Label("每 \(segmentMinutes) 分钟自动保存一个分段", systemImage: "square.stack.3d.up")
                    Label("可锁屏录音，系统中断时暂停并提示", systemImage: "lock.iphone")
                    Label("录音期间不上传音频", systemImage: "wifi.slash")
                }.font(.footnote).foregroundStyle(Theme.muted)
                Section {
                    PrimaryButton(title: controller.starting ? "正在申请麦克风…" : "开始录音", symbol: "mic.fill") {
                        Task {
                            await controller.start(title: title, scene: scene, tags: tags, notes: notes, segmentMinutes: segmentMinutes)
                            if controller.activeID != nil { dismiss() }
                        }
                    }.disabled(controller.starting || ai.busy)
                }.listRowBackground(Color.clear)
                if ai.busy { Section { Text("正在进行 AI 处理，请先等待完成或在工作记忆页面暂停处理，再开始新录音。").font(.footnote).foregroundStyle(.yellow) } }
                Section { Text("录制他人声音前，请先告知并取得必要同意。录音文件只保存在本机，卸载 App 会删除这些文件。").font(.footnote).foregroundStyle(Theme.muted) }
                if let error = controller.errorMessage {
                    Section("未能开始录音") {
                        Text(error).foregroundStyle(.yellow)
                        Button("打开系统设置") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(Theme.background)
                .navigationTitle("新建录音场景").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(controller.starting) } }
                .onAppear { scene = SceneType(rawValue: defaultScene) ?? .meeting }
                .interactiveDismissDisabled(controller.starting)
        }.tint(Theme.accent)
    }
}

struct RecordingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var recording: Recording
    let save: (Recording) -> Void
    var body: some View {
        NavigationStack {
            Form {
                Section("场景信息") {
                    TextField("标题", text: $recording.title)
                    Picker("场景", selection: $recording.scene) { ForEach(SceneType.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("关联项目 / 标签", text: $recording.tags)
                    TextField("备注", text: $recording.notes, axis: .vertical).lineLimit(4...10)
                }
            }.navigationTitle("编辑录音").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { save(recording); dismiss() } }
                }
        }.tint(Theme.accent)
    }
}
