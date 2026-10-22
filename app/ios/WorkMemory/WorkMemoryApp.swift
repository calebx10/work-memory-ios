import SwiftUI

@main
struct WorkMemoryApp: App {
    @StateObject private var bootstrap = AppBootstrap()
    var body: some Scene {
        WindowGroup {
            if let controller = bootstrap.controller, let ai = bootstrap.ai, let settings = bootstrap.settings {
                RootView().environmentObject(controller).environmentObject(controller.playback).environmentObject(ai).environmentObject(settings)
                    .preferredColorScheme(.dark)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "externaldrive.badge.exclamationmark").font(.largeTitle)
                    Text("无法打开本地录音库").font(.title2.bold())
                    Text(bootstrap.failure ?? "请检查手机存储空间。").multilineTextAlignment(.center)
                    Button("重试") { bootstrap.load() }.buttonStyle(.borderedProminent)
                    Text("请不要卸载 App，卸载会删除手机中的录音。").font(.footnote)
                }.padding()
            }
        }
    }
}

@MainActor
final class AppBootstrap: ObservableObject {
    @Published var controller: RecordingController?
    @Published var failure: String?
    @Published var ai: AIController?
    @Published var settings: AISettings?
    init() { load() }
    func load() {
        do {
            var root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("WorkMemory/Recordings", isDirectory: true)
            #if DEBUG
            if DebugHarness.enabled { root = try DebugHarness.prepare(root: root) }
            #endif
            let repository = try LocalRepository(root: root)
            let recorder = RecordingController(repository: repository)
            let serviceSettings: AISettings
            #if DEBUG
            if DebugHarness.enabled { serviceSettings = AISettings(defaults: AppPreferences.defaults, serviceOverride: { PreviewAIService() }) }
            else { serviceSettings = AISettings() }
            #else
            serviceSettings = AISettings()
            #endif
            controller = recorder
            settings = serviceSettings
            ai = AIController(recordings: recorder, settings: serviceSettings)
            failure = nil
        } catch { failure = error.localizedDescription }
    }
}
