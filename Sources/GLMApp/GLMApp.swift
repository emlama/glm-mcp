import AppKit
import GLMBluetooth
import GLMCore
import GLMServer
import Observation
import ServiceManagement
import SwiftUI

@main
struct GLMApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let port = 47650
    static var mcpURL: String { "http://127.0.0.1:\(port)/mcp" }

    private(set) var status = DeviceStatus(state: .scanning)
    private(set) var recent: [Reading] = []
    private(set) var serverError: String?
    private(set) var storeError: String?
    private(set) var flashing = false
    var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    private var store: MeasurementStore?
    private var link: BLELink?
    private var server: MCPHTTPServer?
    private var flashTask: Task<Void, Never>?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GLM MCP")
        do {
            let store = try MeasurementStore(directory: dir)
            self.store = store
            let link = BLELink(store: store)
            self.link = link
            let server = MCPHTTPServer(tools: GLMTools(store: store, device: link), port: Self.port)
            self.server = server
            Task { await self.run(store: store, link: link, server: server) }
        } catch {
            storeError = "Can't open history: \(error.localizedDescription)"
        }
        registerLoginItemOnFirstLaunch()
    }

    var menuBarSymbol: String {
        if flashing { return "checkmark.circle.fill" }
        return status.state == .connected ? "ruler.fill" : "ruler"
    }

    var statusLine: String {
        let name = status.deviceName ?? "Bosch GLM"
        if let detail = status.detail { return detail }
        switch status.state {
        case .connected: return "\(name) — Connected"
        case .connecting: return "\(name) — Connecting…"
        case .scanning: return "Searching for laser…"
        case .off: return "Bluetooth unavailable"
        }
    }

    func clearHistory() {
        guard let store else { return }
        Task {
            try? await store.clear()
            recent = []
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {}
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func run(store: MeasurementStore, link: BLELink, server: MCPHTTPServer) async {
        recent = Array(await store.all().prefix(10))
        do {
            try await server.start()
        } catch {
            // Don't take the Bluetooth link either: readings would land in an instance Claude can't reach.
            serverError = "MCP server couldn't start on port \(Self.port): \(error.localizedDescription). Is another copy running? Quit this one."
            status = DeviceStatus(state: .off, detail: "Not connecting: another copy of GLM MCP is probably running.")
            return
        }
        link.start()
        Task {
            for await s in link.statusUpdates { status = s }
        }
        for await r in store.updates {
            recent = Array(([r] + recent).prefix(10))
            if r.kind.isComplete { flash() }
        }
    }

    private func flash() {
        flashTask?.cancel()
        flashing = true
        flashTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { flashing = false }
        }
    }

    private func registerLoginItemOnFirstLaunch() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        setLaunchAtLogin(true)
    }
}
