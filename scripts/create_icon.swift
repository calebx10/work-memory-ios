// Export the approved imagegen artwork into the iOS asset catalog.
// Usage: swift scripts/create_icon.swift <output.png>
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift scripts/create_icon.swift <output.png>\n", stderr)
    exit(1)
}
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let source = repository.appendingPathComponent("docs/design/work-memory-icon-source.png")
guard FileManager.default.fileExists(atPath: source.path) else {
    fputs("Missing approved icon source: docs/design/work-memory-icon-source.png\n", stderr)
    exit(1)
}
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
process.arguments = ["-z", "1024", "1024", source.path, "--out", CommandLine.arguments[1]]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
