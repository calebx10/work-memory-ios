import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var controller: RecordingController
    @AppStorage("privacyAccepted", store: AppPreferences.defaults) private var privacyAccepted = false
    @EnvironmentObject private var ai: AIController
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { CaptureView() }.tabItem { Label("录音", systemImage: "waveform") }.tag(0)
            NavigationStack { LibraryView() }.tabItem { Label("录音库", systemImage: "square.stack") }.tag(1)
            NavigationStack { CollectionsView() }.tabItem { Label("素材", systemImage: "lightbulb") }.tag(3)
            NavigationStack { SettingsView() }.tabItem { Label("设置", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .tint(Theme.accent)
        .sheet(isPresented: Binding(get: { !privacyAccepted }, set: { _ in })) {
            PrivacyView { privacyAccepted = true }.interactiveDismissDisabled()
        }
        .alert("操作提示", isPresented: Binding(get: { controller.errorMessage != nil || ai.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil; ai.errorMessage = nil } })) {
            if controller.errorMessage?.contains("权限") == true {
                Button("打开系统设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button("知道了", role: .cancel) { controller.errorMessage = nil; ai.errorMessage = nil }
        } message: { Text(ai.errorMessage ?? controller.errorMessage ?? "") }
        .onChange(of: controller.activeID) { _, id in if id != nil { tab = 0 } }
    }
}

struct CaptureView: View {
    @EnvironmentObject private var controller: RecordingController
    @State private var creating = false
    @State private var finished: Recording?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("WORK MEMORY", systemImage: "circle.hexagongrid.fill")
                        .font(.caption.weight(.bold)).tracking(2).foregroundStyle(Theme.accent)
                    Spacer()
                    Image(systemName: "iphone.gen3.radiowaves.left.and.right").foregroundStyle(Theme.muted)
                }
                if let active = controller.active {
                    ActiveRecordingView(recording: active) {
                        if let id = controller.finish() { finished = controller.lookup(id) }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("把工作现场，\n留给未来的自己。").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("从一次对话，积累一份工作记忆。")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    Panel {
                        VStack(spacing: 22) {
                            HStack { Label("准备好记录", systemImage: "circle.fill").font(.caption).foregroundStyle(Theme.mint); Spacer(); Text("本地优先").font(.caption).foregroundStyle(Theme.muted) }
                            Button { creating = true } label: {
                                Image(systemName: "mic.fill").font(.system(size: 42, weight: .medium))
                                    .foregroundStyle(Theme.background).frame(width: 118, height: 118)
                                    .background(Theme.accent, in: Circle())
                                    .padding(10).overlay(Circle().stroke(Theme.accent.opacity(0.2), lineWidth: 1))
                            }.accessibilityLabel("新建场景并开始录音")
                            VStack(spacing: 7) {
                                Text("开始一段新录音").font(.title3.bold())
                                Text("会议 · 客户沟通 · 灵感记录").font(.caption).foregroundStyle(Theme.muted)
                            }
                            HStack { Label("离线可录", systemImage: "wifi.slash"); Spacer(); Label("手动开启", systemImage: "hand.tap"); Spacer(); Label("分段保存", systemImage: "square.stack.3d.up") }
                                .font(.caption2).foregroundStyle(Theme.muted)
                        }.frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive").foregroundStyle(Theme.mint)
                    Text("手机可用空间 \(ByteCountFormatter.string(fromByteCount: controller.freeBytes, countStyle: .file))")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                if !controller.storageWarnings.isEmpty {
                    Panel { ForEach(controller.storageWarnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(.yellow) } }
                }
                HStack { Text("最近录音").font(.title3.bold()); Spacer(); Text("\(controller.recordings.count) 段记忆").font(.caption).foregroundStyle(Theme.muted) }
                if controller.recordings.isEmpty {
                    Panel {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("你的第一段工作记忆，从这里开始。").font(.subheadline)
                            Text("录音只会在你点击开始后采集。结束时先保存到手机。").font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(controller.recordings.prefix(4)) { item in
                            NavigationLink { RecordingDetailView(id: item.id) } label: { RecordingRow(recording: item) }
                            if item.id != controller.recordings.prefix(4).last?.id { Divider().overlay(.white.opacity(0.04)) }
                        }
                    }
                }
                Text("iPhone 独立版 · 录音、分析、工作记忆").font(.caption2).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.bottom, 16)
            }.padding(22)
        }.background(Theme.background).toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $creating) { NewRecordingView() }
            .sheet(item: $finished) { recording in SavedRecordingView(recording: recording) }
    }
}

struct ActiveRecordingView: View {
    @EnvironmentObject private var controller: RecordingController
    let recording: Recording
    let onFinish: () -> Void
    @State private var confirmEnd = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(recording.title).font(.title2.bold())
            HStack { StatusPill(state: recording.state); Text(recording.scene.rawValue).font(.caption).foregroundStyle(Theme.muted) }
            Panel {
                VStack(spacing: 24) {
                    Text(clockText(controller.elapsed)).font(.system(size: 48, weight: .light, design: .monospaced)).minimumScaleFactor(0.5).lineLimit(1)
                        .accessibilityLabel("已录制 \(clockText(controller.elapsed))")
                    HStack(alignment: .center, spacing: 5) {
                        ForEach(0..<27, id: \.self) { index in
                            Capsule().fill(controller.isRecording ? Theme.accent : Theme.muted.opacity(0.35))
                                .frame(width: 5, height: CGFloat(8 + (controller.isRecording ? Double(controller.level) * Double(15 + (index * 17) % 54) : 0)))
                        }
                    }.frame(height: 72).frame(maxWidth: .infinity).accessibilityHidden(true)
                    Text(controller.isRecording ? "正在采集 · 音频仅写入手机" : "当前未采集音频")
                        .font(.caption).foregroundStyle(controller.isRecording ? Theme.accent : Theme.muted)
                    HStack(spacing: 14) {
                        Button { controller.isRecording ? controller.pause() : controller.resume() } label: {
                            Label(controller.isRecording ? "暂停" : "继续录音", systemImage: controller.isRecording ? "pause.fill" : "mic.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                        }.buttonStyle(.bordered).tint(Theme.accent)
                        Button { confirmEnd = true } label: {
                            Label("结束", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 14)
                        }.buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.background)
                    }
                }
            }
            Label("已关闭保存 \(recording.playableSegments.count) 个分段", systemImage: "checkmark.shield")
                .font(.footnote).foregroundStyle(Theme.mint)
            if controller.pauseReminder {
                Label("已暂停超过 5 分钟，请确认是否需要继续。", systemImage: "clock.badge.exclamationmark").font(.footnote).foregroundStyle(.yellow)
            }
            if let message = recording.events.last?.message { Text(message).font(.footnote).foregroundStyle(Theme.muted) }
        }
        .confirmationDialog("结束这次录音？", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("结束并保存到手机", action: onFinish)
            Button("返回录音", role: .cancel) {}
        } message: { Text("将先关闭并保存当前音频文件。不会上传音频。") }
    }
}

struct SavedRecordingView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 62)).foregroundStyle(Theme.mint)
                Text("已保存到手机").font(.title.bold())
                Text(recording.title).multilineTextAlignment(.center)
                Text("\(clockText(recording.duration)) · \(recording.playableSegments.count) 个可用分段").foregroundStyle(Theme.muted)
                PrimaryButton(title: "完成", symbol: "checkmark") { dismiss() }
                NavigationLink { MemoryDetailView(id: recording.id) } label: {
                    Label("查看并分析这段录音", systemImage: "sparkles").font(.headline)
                }.buttonStyle(.bordered).tint(Theme.accent)
                Text("录音已经保存在手机。分析前会确认接收服务，联网后可直接在手机完成，无需 Mac。").font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
        }.presentationDetents([.medium, .large])
    }
}
