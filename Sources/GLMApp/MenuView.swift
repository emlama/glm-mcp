import AppKit
import GLMCore
import SwiftUI

struct MenuView: View {
    let model: AppModel

    var body: some View {
        Text(model.statusLine)
        if let error = model.serverError { Text(error) }
        if let error = model.storeError { Text(error) }

        Divider()

        if model.recent.isEmpty {
            Text("No measurements yet")
        } else {
            Text("Recent (click to copy)")
            ForEach(model.recent) { r in
                Button(Self.label(r)) { Self.copy(r) }
            }
        }

        Divider()

        Button("Copy MCP URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(AppModel.mcpURL, forType: .string)
        }
        Button("Clear History") { model.clearHistory() }
        Toggle("Launch at Login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
        Divider()
        Button("Quit GLM MCP") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    static func label(_ r: Reading) -> String {
        let age = RelativeDateTimeFormatter().localizedString(for: r.timestamp, relativeTo: Date())
        let kind = r.kind.rawValue.replacingOccurrences(of: "_", with: " ")
        guard let v = r.value else { return "\(kind) — \(age)" }
        return "\(displayString(value: v, unit: r.unit)) · \(kind) — \(age)"
    }

    static func copy(_ r: Reading) {
        guard let v = r.value else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(format: "%.4f", v), forType: .string)
    }
}
