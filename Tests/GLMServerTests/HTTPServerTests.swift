import Foundation
import GLMCore
import Testing
@testable import GLMServer

private func post(_ port: Int, _ body: String, session: String? = nil) async throws -> (Int, [AnyHashable: Any], String) {
    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    req.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
    if let session { req.setValue(session, forHTTPHeaderField: "Mcp-Session-Id") }
    req.httpBody = Data(body.utf8)
    let (data, resp) = try await URLSession.shared.data(for: req)
    let http = resp as! HTTPURLResponse
    var text = String(decoding: data, as: UTF8.self)
    // SSE responses carry the JSON-RPC message on a "data:" line.
    if (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("text/event-stream") {
        text = text.split(separator: "\n").filter { $0.hasPrefix("data:") }.map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }
    return (http.statusCode, http.allHeaderFields, text)
}

private func makeServer(port: Int = 0) throws -> MCPHTTPServer {
    let store = try MeasurementStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("glm-http-\(UUID())"))
    return MCPHTTPServer(tools: GLMTools(store: store, device: FakeDevice()), port: port)
}

@Test func initializeListAndCall() async throws {
    let server = try makeServer()
    try await server.start()
    defer { Task { await server.stop() } }
    let port = try #require(await server.boundPort)

    let (status, headers, body) = try await post(port, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}"#)
    #expect(status == 200)
    #expect(body.contains("\"glm-mcp\""))
    let session = try #require(headers.first { ($0.key as? String)?.lowercased() == "mcp-session-id" }?.value as? String)

    let (s2, _, _) = try await post(port, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, session: session)
    #expect(s2 == 202)

    let (_, _, list) = try await post(port, #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#, session: session)
    #expect(list.contains("get_latest_measurement") && list.contains("wait_for_measurement"))

    let (_, _, call) = try await post(port, #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_device_status","arguments":{}}}"#, session: session)
    #expect(call.contains("\\\"state\\\"") || call.contains("\"state\""))
}

@Test func portInUseThrows() async throws {
    let a = try makeServer()
    try await a.start()
    defer { Task { await a.stop() } }
    let port = try #require(await a.boundPort)
    let b = try makeServer(port: port)
    await #expect(throws: (any Error).self) { try await b.start() }
}

@Test func rebindsSamePortAfterStopWithClientConnected() async throws {
    let a = try makeServer()
    try await a.start()
    let port = try #require(await a.boundPort)
    _ = try await post(port, #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"0"}}}"#)
    await a.stop()
    let b = try makeServer(port: port)
    try await b.start()
    await b.stop()
}
