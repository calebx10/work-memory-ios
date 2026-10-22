import SwiftUI

enum Theme {
    static let background = Color(red: 0.055, green: 0.075, blue: 0.10)
    static let panel = Color(red: 0.09, green: 0.115, blue: 0.15)
    static let accent = Color(red: 0.98, green: 0.62, blue: 0.38)
    static let muted = Color(red: 0.60, green: 0.66, blue: 0.72)
    static let mint = Color(red: 0.49, green: 0.81, blue: 0.70)
}
struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 24))
    }
}
struct StatusPill: View {
    let state: RecordingState
    var body: some View {
        Text(state.label).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 6)
            .background((state == .recording ? Theme.accent : state == .saved ? Theme.mint : .yellow).opacity(0.12), in: Capsule())
            .foregroundStyle(state == .recording ? Theme.accent : state == .saved ? Theme.mint : .yellow)
    }
}
struct RecordingRow: View {
    let recording: Recording
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: recording.scene.symbol).font(.title3).foregroundStyle(Theme.accent)
                .frame(width: 46, height: 48).background(Theme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 7) {
                Text(recording.title).font(.headline).lineLimit(2).foregroundStyle(.white)
                Text("\(recording.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(clockText(recording.duration))")
                    .font(.caption).foregroundStyle(Theme.muted)
                StatusPill(state: recording.state)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}
struct PrimaryButton: View {
    var title: String
    var symbol: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
        }.buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Theme.background)
            .controlSize(.large)
    }
}
