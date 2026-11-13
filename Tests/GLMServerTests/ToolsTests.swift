import Foundation
import GLMCore
import MCP
import Testing
@testable import GLMServer

actor FakeDevice: DeviceControl {
    var current = DeviceStatus(state: .connected, deviceName: "Bosch GLM50C x1234", profile: "serial_pipe")
    var triggerCount = 0
    var sent: [DeviceCommand] = []
    var sendError: DeviceError?
    /// Appended to the store when trigger() is called, if set.
    var onTrigger: (MeasurementStore, Reading)?

    func status() -> DeviceStatus { current }
    func trigger() async throws {
        triggerCount += 1
        if let (store, r) = onTrigger {
            Task { try? await Task.sleep(for: .milliseconds(50)); await store.append(r) }
        }
    }
    func markTrigger(_ s: TriggerSupport) { current.triggerSupported = s }
    func send(_ command: DeviceCommand) async throws {
        if let sendError { throw sendError }
        sent.append(command)
    }
    func setSendError(_ e: DeviceError?) { sendError = e }
    func set(_ s: LinkState) { current.state = s }
    func setOnTrigger(_ v: (MeasurementStore, Reading)) { onTrigger = v }
}

private let lengthHex = "c0 55 10 06 08 ba 01 b4 59 11 40 00 00 00 00 00 00 00 00 12"
private let length2Hex = "c0 55 10 06 08 bb 01 09 f9 0e 40 00 00 00 00 00 00 00 00 30"
private let length3Hex = "c0 55 10 06 08 bc 01 09 f9 0e 40 00 00 00 00 00 00 00 00 31"

private func make(_ hex: String, at date: Date = Date()) -> Reading {
    var p = FrameParser()
    guard case .reading(let r) = interpret(p.feed(Data(hex: hex)!)[0], deviceName: "GLM", at: date) else { fatalError() }
    return r
}

private func setup() throws -> (GLMTools, MeasurementStore, FakeDevice) {
    let store = try MeasurementStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("glm-tools-\(UUID())"))
    let device = FakeDevice()
    return (GLMTools(store: store, device: device), store, device)
}

private func json(_ r: CallTool.Result) -> [String: Any] {
    guard case .text(let text, _, _) = r.content.first,
          let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return [:] }
    return obj
}

private func text(_ r: CallTool.Result) -> String {
    if case .text(let t, _, _) = r.content.first { return t }
    return ""
}

@Test func listsTools() {
    #expect(GLMTools.tools.map(\.name) == [
        "get_latest_measurement", "wait_for_measurement", "list_measurements", "get_device_status", "trigger_measurement",
        "set_laser_pointer", "set_backlight",
    ])
}

@Test func latestEmpty() async throws {
    let (tools, _, _) = try setup()
    let r = await tools.call(name: "get_latest_measurement", arguments: nil)
    let j = json(r)
    #expect(r.isError != true)
    #expect(j["reading"] is NSNull && j["message"] as? String == "No measurements yet.")
}

@Test func latestHasAgeAndDisplay() async throws {
    let (tools, store, _) = try setup()
    await store.append(make(lengthHex, at: Date().addingTimeInterval(-3)))
    let j = json(await tools.call(name: "get_latest_measurement", arguments: nil))
    let reading = j["reading"] as? [String: Any]
    #expect(reading?["age_seconds"] as? Int == 3)
    #expect(reading?["value_display"] as? String == "2.271 m (89.4 in)")
    #expect(reading?["kind"] as? String == "length")
}

@Test func latestWhenDisconnected() async throws {
    let (tools, store, device) = try setup()
    await store.append(make(lengthHex))
    await device.set(.scanning)
    let j = json(await tools.call(name: "get_latest_measurement", arguments: nil))
    #expect((j["device"] as? [String: Any])?["state"] as? String == "scanning")
    #expect(j["reading"] is [String: Any])
}

@Test func waitReturnsNewReading() async throws {
    let (tools, store, _) = try setup()
    await store.append(make(lengthHex))
    let b = make(length2Hex)
    Task { try? await Task.sleep(for: .milliseconds(50)); await store.append(b) }
    let j = json(await tools.call(name: "wait_for_measurement", arguments: ["timeout_seconds": .int(5)]))
    #expect((j["reading"] as? [String: Any])?["id"] as? String == b.id.uuidString)
}

@Test func waitTimeoutClamped() async throws {
    let (tools, _, _) = try setup()
    let start = Date()
    let j = json(await tools.call(name: "wait_for_measurement", arguments: ["timeout_seconds": .double(0.1)]))
    let elapsed = Date().timeIntervalSince(start)
    #expect(j["reading"] is NSNull && j["message"] as? String == "No measurement within 1 s.")
    #expect(elapsed >= 0.9 && elapsed < 3)
}

@Test func listSinceId() async throws {
    let (tools, store, _) = try setup()
    let a = make(lengthHex), b = make(length2Hex), c = make(length3Hex)
    for r in [a, b, c] { await store.append(r) }
    let j = json(await tools.call(name: "list_measurements", arguments: ["since": .string(b.id.uuidString)]))
    let ids = (j["readings"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
    #expect(ids == [c.id.uuidString])
    let all = json(await tools.call(name: "list_measurements", arguments: nil))
    #expect((all["readings"] as? [Any])?.count == 3)
    let limited = json(await tools.call(name: "list_measurements", arguments: ["limit": .int(1)]))
    #expect((limited["readings"] as? [[String: Any]])?.first?["id"] as? String == c.id.uuidString)
}

@Test func listSinceTime() async throws {
    let (tools, store, _) = try setup()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    await store.append(make(lengthHex, at: t0))
    await store.append(make(length2Hex, at: t0.addingTimeInterval(60)))
    let j = json(await tools.call(name: "list_measurements", arguments: ["since": .string("2027-01-15T08:00:30Z")]))
    #expect((j["readings"] as? [Any])?.count == 1)
}

@Test func deviceStatus() async throws {
    let (tools, _, _) = try setup()
    let j = json(await tools.call(name: "get_device_status", arguments: nil))
    let d = j["device"] as? [String: Any]
    #expect(d?["state"] as? String == "connected" && d?["trigger_supported"] as? String == "unknown")
}

@Test func triggerUnsupportedAfterFailedProbe() async throws {
    let (tools, _, device) = try setup()
    let r = await tools.call(name: "trigger_measurement", arguments: nil)
    #expect(r.isError == true)
    #expect(await device.status().triggerSupported == .unsupported)
    let start = Date()
    let r2 = await tools.call(name: "trigger_measurement", arguments: nil)
    #expect(r2.isError == true && Date().timeIntervalSince(start) < 0.1)
    #expect(await device.triggerCount == 1)
}

@Test func triggerSupported() async throws {
    let (tools, store, device) = try setup()
    let r = make(lengthHex)
    await device.setOnTrigger((store, r))
    let j = json(await tools.call(name: "trigger_measurement", arguments: nil))
    #expect((j["reading"] as? [String: Any])?["id"] as? String == r.id.uuidString)
    #expect(await device.status().triggerSupported == .supported)
}

@Test func unknownToolIsError() async throws {
    let (tools, _, _) = try setup()
    let r = await tools.call(name: "nope", arguments: nil)
    #expect(r.isError == true && text(r).contains("nope"))
}

@Test func hugeLimitDoesNotCrash() async throws {
    let (tools, store, _) = try setup()
    await store.append(make(lengthHex))
    let j = json(await tools.call(name: "list_measurements", arguments: ["limit": .double(1e30)]))
    #expect((j["readings"] as? [Any])?.count == 1)
}

@Test func nanTimeoutIsRejected() async throws {
    let (tools, _, _) = try setup()
    let r = await tools.call(name: "wait_for_measurement", arguments: ["timeout_seconds": .string("nan")])
    #expect(r.isError == true)
}

@Test func numbersAreNotNoisy() async throws {
    let (tools, store, _) = try setup()
    await store.append(make("c0 55 10 0a 08 bf 01 e3 a5 43 3f 54 e3 2d 3f d4 9a 46 3f ba"))
    let t = text(await tools.call(name: "get_latest_measurement", arguments: nil))
    #expect(t.contains("0.7758") && t.contains("0.6793"))
    #expect(!t.contains("0.77580000"))
}

@Test func laserPointerOnAndOff() async throws {
    let (tools, _, device) = try setup()
    let on = await tools.call(name: "set_laser_pointer", arguments: ["on": .bool(true)])
    let off = await tools.call(name: "set_laser_pointer", arguments: ["on": .bool(false)])
    #expect(on.isError == false && off.isError == false)
    #expect(json(on)["laser_pointer"] as? String == "on")
    #expect(json(off)["laser_pointer"] as? String == "off")
    #expect(await device.sent == [.laserOn, .laserOff])
}

@Test func backlightOnAndOff() async throws {
    let (tools, _, device) = try setup()
    let on = await tools.call(name: "set_backlight", arguments: ["on": .bool(true)])
    _ = await tools.call(name: "set_backlight", arguments: ["on": .bool(false)])
    #expect(json(on)["backlight"] as? String == "on")
    #expect(await device.sent == [.backlightOn, .backlightOff])
}

@Test func switchToolsRequireOn() async throws {
    let (tools, _, device) = try setup()
    let missing = await tools.call(name: "set_laser_pointer", arguments: nil)
    let wrongType = await tools.call(name: "set_backlight", arguments: ["on": .string("maybe")])
    #expect(missing.isError == true && wrongType.isError == true)
    #expect(await device.sent.isEmpty)
}

@Test func switchToolsReportNotConnected() async throws {
    let (tools, _, device) = try setup()
    await device.set(.scanning)
    await device.setSendError(.notConnected)
    let r = await tools.call(name: "set_laser_pointer", arguments: ["on": .bool(true)])
    #expect(r.isError == true)
    #expect(text(r).contains("not connected"))
}

@Test func switchToolsReportNoResponse() async throws {
    let (tools, _, device) = try setup()
    await device.setSendError(.noResponse)
    let r = await tools.call(name: "set_backlight", arguments: ["on": .bool(true)])
    #expect(r.isError == true)
    #expect(text(r).contains("off and on"))
}
