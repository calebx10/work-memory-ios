import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var controller: RecordingController
    @EnvironmentObject private var settings: AISettings
    @AppStorage("segmentMinutes", store: AppPreferences.defaults) private var segmentMinutes = 10
    @AppStorage("defaultScene", store: AppPreferences.defaults) private var defaultScene = SceneType.meeting.rawValue
    @State private var privacy = false
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "waveform.circle.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("工作记忆").font(.title3.bold())
                        Text("录下现场，留下经验。iPhone 独立使用。")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }.padding(.vertical, 8)
            }
            Section("AI 分析") {
                NavigationLink { ServiceSettingsView() } label: {
                    HStack {
                        Label("AI 服务", systemImage: "sparkles")
                        Spacer()
                        Text(settings.hasKey ? "已保存凭证" : "尚未配置").font(.caption).foregroundStyle(settings.hasKey ? Theme.mint : Theme.accent)
                    }
                }.accessibilityIdentifier("openAISettings")
                Text("录音不需要网络。只有你确认发送后，手机才会连接所选服务进行转写和分析。无需 Mac 开机。").font(.footnote).foregroundStyle(Theme.muted)
            }
            Section("录音偏好") {
                Picker("自动分段", selection: $segmentMinutes) { ForEach([5, 10, 15], id: \.self) { Text("\($0) 分钟").tag($0) } }
                Picker("默认场景", selection: $defaultScene) { ForEach(SceneType.allCases) { Text($0.rawValue).tag($0.rawValue) } }
                Text("暂停或音频中断时也会保存一段；继续时新建分段。分段切换可能有短暂间隙。").font(.footnote).foregroundStyle(Theme.muted)
            }
            Section("手机存储") {
                LabeledContent("录音文件", value: ByteCountFormatter.string(fromByteCount: controller.recordings.reduce(0) { $0 + $1.byteCount }, countStyle: .file))
                LabeledContent("剩余空间", value: ByteCountFormatter.string(fromByteCount: controller.freeBytes, countStyle: .file))
                Text("默认不自动删除录音。请在录音详情导出备份；卸载 App 会删除手机上的全部录音和笔记。").font(.footnote).foregroundStyle(Theme.muted)
            }
            Section {
                Button { privacy = true } label: { Label("隐私与数据说明", systemImage: "hand.raised") }
                Text("Mac 同步将在后续版本考虑，当前全部整理工作可在手机完成。").font(.footnote).foregroundStyle(Theme.muted)
            }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("设置")
            .sheet(isPresented: $privacy) { PrivacyView { privacy = false } }
    }
}

struct ServiceSettingsView: View {
    @EnvironmentObject private var settings: AISettings
    @EnvironmentObject private var ai: AIController
    @State private var configuration = ServiceConfiguration()
    @State private var newKey = ""
    @State private var newAnalysisKey = ""
    @State private var saved = false
    @State private var error: String?
    @State private var removeKey = false
    var body: some View {
        Form {
            Section("连接你的 AI 服务") {
                Text("第一次使用需要服务商的 API 凭证和可用额度。这是服务专用凭证，不是聊天软件的登录密码，也不包含在本 App 中。").font(.footnote)
                Button {
                    configuration = .apimart
                    configuration.analysisBaseURL = "https://api.deepseek.com"
                    configuration.analysisModel = "deepseek-flash"
                    saved = false
                } label: { Label("使用 APIMart 转写 + DeepSeek 提炼", systemImage: "sparkles") }
                    .accessibilityIdentifier("useDeepSeekCombo").disabled(ai.busy)
                Button {
                    configuration = .apimart
                    saved = false
                } label: { Label("使用 APIMart 推荐配置", systemImage: "wand.and.stars") }
                    .accessibilityIdentifier("useAPIMart").disabled(ai.busy)
                LabeledContent("录音转文字", value: configuration.hostLabel)
                LabeledContent("重点和选题", value: configuration.analysisHostLabel)
                if configuration.isAPIMart {
                    Text(configuration.analysisBaseURL == nil ? "APIMart 完成转写和分析，只需一份凭证。" : "APIMart 接收录音，DeepSeek 接收转写文字。两份凭证分开保存；App 会自动衔接。").font(.footnote).foregroundStyle(Theme.mint)
                }
                if configuration.analysisBaseURL != nil { Text("APIMart 凭证").font(.caption).foregroundStyle(Theme.muted) }
                SecureField(settings.hasKey && configuration.baseURL == settings.configuration.baseURL ? "已保存；留空保留现有凭证" : "粘贴服务商提供的 API 凭证", text: $newKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("serviceKey")
                if configuration.analysisBaseURL != nil {
                    Text("DeepSeek 官方凭证").font(.caption).foregroundStyle(Theme.muted)
                    SecureField("粘贴 DeepSeek 凭证；留空保留已存凭证", text: $newAnalysisKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("analysisKey")
                    Text("日常提炼使用 DeepSeek 低价模型并关闭深度思考。只在你确认分析或生成初稿时调用；具体费用以服务商账单为准。").font(.caption).foregroundStyle(Theme.muted)
                }
                Text("凭证只存入此 iPhone 的系统钥匙串，不显示完整内容，不随录音导出。").font(.caption).foregroundStyle(Theme.muted)
            }
            Section {
                DisclosureGroup("服务地址和模型（高级设置）") {
                    TextField("HTTPS 服务地址（含 /v1）", text: $configuration.baseURL).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    TextField("语音转写模型", text: $configuration.transcriptionModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("内容分析模型", text: $configuration.analysisModel).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("严格结构化结果", isOn: $configuration.structuredOutputs)
                    Text("APIMart 可用上方按钮一键填写。其他服务需兼容音频转写和聊天接口；不支持严格结构化结果时可关闭该选项。更换服务地址不会自动沿用旧服务凭证。").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Section {
                PrimaryButton(title: "保存设置", symbol: "checkmark") {
                    do { try settings.save(configuration: configuration, newKey: newKey, newAnalysisKey: newAnalysisKey); newKey = ""; newAnalysisKey = ""; configuration = settings.configuration; saved = true }
                    catch { self.error = error.localizedDescription }
                }.disabled(ai.busy)
                Text("保存设置不会发送录音，也不会产生 AI 请求。分析前会再次显示发送目标；服务商可能按用量收费，数据保留取决于其政策。").font(.footnote).foregroundStyle(Theme.muted)
            }.listRowBackground(Color.clear)
            Section {
                Button("移除此服务的凭证", role: .destructive) { removeKey = true }.disabled(!settings.hasKey || ai.busy)
            }
        }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("AI 服务").navigationBarTitleDisplayMode(.inline)
            .onAppear { configuration = settings.configuration }
            .alert("设置已保存", isPresented: $saved) { Button("好", role: .cancel) {} } message: { Text(settings.hasKey ? "可以在录音详情中选择“发送并分析”。" : "录音仍可使用；分析前还需要填写服务凭证。") }
            .alert("保存未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("好", role: .cancel) { error = nil } } message: { Text(error ?? "") }
            .confirmationDialog("移除 AI 服务凭证？", isPresented: $removeKey, titleVisibility: .visible) {
                Button("移除凭证", role: .destructive) { do { try settings.removeKey() } catch { self.error = error.localizedDescription } }
            } message: { Text("录音和分析结果会保留。下次分析前需要重新填写凭证。") }
    }
}

struct PrivacyView: View {
    let done: () -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "hand.raised.circle.fill").font(.system(size: 56)).foregroundStyle(Theme.mint)
                    Text("你的录音，由你决定。").font(.largeTitle.bold())
                    privacyItem("主动录音", "只有你点击开始才采集声音。录制他人前请先告知并取得必要同意。", "mic")
                    privacyItem("先保存在手机", "音频、转写、分析和选题存于本机。录音期间不上传。App 不自动清理，也不自动同步到 Mac。", "iphone")
                    privacyItem("确认后才分析", "在线分析会将所需音频发给你选择的转写服务，并把文字发给分析服务；对方的数据保留由其政策决定。可能产生按量费用。", "sparkles")
                    privacyItem("随时核对与备份", "AI 内容是可编辑的草稿，重要事实请回听原文。删除本机内容不代表删除服务商留存；卸载前请导出备份。", "square.and.arrow.up")
                    PrimaryButton(title: "我知道了", symbol: "checkmark", action: done)
                }.padding(26)
            }.background(Theme.background).navigationBarTitleDisplayMode(.inline)
        }.tint(Theme.accent).preferredColorScheme(.dark)
    }
    private func privacyItem(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 7) { Text(title).font(.headline); Text(detail).font(.subheadline).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct AIConsentView: View {
    @EnvironmentObject private var ai: AIController
    @EnvironmentObject private var settings: AISettings
    @Environment(\.dismiss) private var dismiss
    let recording: Recording
    var force = false
    var draftIdea: ContentIdea?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(draftIdea == nil ? "发送并分析" : "生成口播初稿", systemImage: "sparkles").font(.title2.bold())
                    Text(recording.title)
                }
                Section("本次会发送什么") {
                    if draftIdea == nil {
                        Text("尚未转写的音频分段会发送给转写服务；原文或人工修订文字会发送给分析服务。已保存的转写会复用。")
                    } else { Text("仅发送此选题及其关联原文文字，用于生成口播初稿。") }
                    LabeledContent("音频接收服务", value: settings.configuration.hostLabel)
                    LabeledContent("文字接收服务", value: settings.configuration.analysisHostLabel)
                    LabeledContent("转写模型", value: settings.configuration.transcriptionModel)
                    LabeledContent("分析模型", value: settings.configuration.analysisModel)
                }
                Section {
                    Text("服务商可能按用量收费并按其政策处理数据。结果仍会保存在手机，不需要 Mac。请保持 App 在前台；进入后台会暂停，未收到结果的请求重试可能重复计费。").font(.footnote)
                    if force { Text("重新生成会替换当前分析和选题（包括手动修改及口播稿），不会重复转写已保存的音频。请先导出需要保留的结果。").font(.footnote).foregroundStyle(.yellow) }
                    if draftIdea?.draft.isEmpty == false { Text("生成成功后会替换当前口播稿。请先复制需要保留的版本。").font(.footnote).foregroundStyle(.yellow) }
                }
                Section {
                    if settings.hasKey {
                        PrimaryButton(title: "确认发送", symbol: "paperplane") {
                            if let idea = draftIdea { ai.generateDraft(recording: recording, idea: idea) }
                            else { ai.start(recording, force: force) }
                            dismiss()
                        }.accessibilityIdentifier("confirmAI")
                    } else {
                        NavigationLink { ServiceSettingsView() } label: { Label("先配置 AI 服务", systemImage: "key") }
                        Text("尚未保存服务凭证，当前不会发送任何内容。").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }.listRowBackground(Color.clear)
            }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("由你确认").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }.tint(Theme.accent)
    }
}
