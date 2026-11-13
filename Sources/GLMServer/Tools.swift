import Foundation
import GLMCore
import MCP

/// The MCP tools. Tool descriptions are what Claude reads to decide when to call each one.
public struct GLMTools: Sendable {
    let store: MeasurementStore
    let device: any DeviceControl

    public init(store: MeasurementStore, device: any DeviceControl) {
        self.store = store
        self.device = device
    }

    static let maxWaitSeconds = 55.0
    static let triggerWait: Duration = .seconds(5)

    public static let tools: [Tool] = [
        Tool(
            name: "get_latest_measurement",
            description: "Get the most recent reading from the Bosch GLM laser measure. Call this when the user says they just measured something. Includes age_seconds; if the reading is older than the user implies, ask or use wait_for_measurement.",
            inputSchema: .object(["type": "object", "properties": .object([:])])
        ),
        Tool(
            name: "wait_for_measurement",
            description: "Wait for the user to take a new measurement with the laser's button and return it. Use when the user is about to measure. Args: timeout_seconds (default 30, max 55).",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "timeout_seconds": .object(["type": "number", "description": "Seconds to wait (1-55, default 30)."]),
                ]),
            ])
        ),
        Tool(
            name: "list_measurements",
            description: "List readings, newest first. Optional args: since (ISO 8601 time or a reading id), limit. Without args returns all readings in the current history.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "since": .object(["type": "string", "description": "ISO 8601 time, or the id of a reading to list readings after."]),
                    "limit": .object(["type": "integer", "description": "Maximum number of readings to return."]),
                ]),
            ])
        ),
        Tool(
            name: "get_device_status",
            description: "Connection state of the laser measure, its current mode, and whether remote triggering works.",
            inputSchema: .object(["type": "object", "properties": .object([:])])
        ),
        Tool(
            name: "trigger_measurement",
            description: "Fire the laser remotely and return the reading. May not be supported on this device; if unsupported it returns an error right away.",
            inputSchema: .object(["type": "object", "properties": .object([:])])
        ),
        Tool(
            name: "set_laser_pointer",
            description: "Turn the laser measure's red aiming dot on or off, e.g. so the user can see where it points before measuring. Args: on (boolean).",
            inputSchema: .object([
                "type": "object",
                "properties": .object(["on": .object(["type": "boolean", "description": "true to turn the dot on, false to turn it off."])]),
                "required": .array([.string("on")]),
            ])
        ),
        Tool(
            name: "set_backlight",
            description: "Turn the laser measure's display backlight on or off. Args: on (boolean).",
            inputSchema: .object([
                "type": "object",
                "properties": .object(["on": .object(["type": "boolean", "description": "true to turn the backlight on, false to turn it off."])]),
                "required": .array([.string("on")]),
            ])
        ),
    ]

    public func call(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        let args = arguments ?? [:]
        switch name {
        case "get_latest_measurement": return await latest()
        case "wait_for_measurement":
            if let raw = args["timeout_seconds"], number(raw) == nil {
                return error("timeout_seconds must be a number between 1 and 55.")
            }
            return await wait(seconds: number(args["timeout_seconds"]) ?? 30)
        case "list_measurements":
            let limit = number(args["limit"]).map { Int(min(max($0, 0), 1_000_000)) }
            return await list(since: args["since"]?.stringValue, limit: limit)
        case "get_device_status": return await respond([:])
        case "trigger_measurement": return await triggerMeasurement()
        case "set_laser_pointer":
            guard case .bool(let on)? = args["on"] else { return error("on must be true or false.") }
            return await send(on ? .laserOn : .laserOff, field: "laser_pointer", on: on)
        case "set_backlight":
            guard case .bool(let on)? = args["on"] else { return error("on must be true or false.") }
            return await send(on ? .backlightOn : .backlightOff, field: "backlight", on: on)
        default: return error("Unknown tool: \(name)")
        }
    }

    // MARK: - Tools

    private func latest() async -> CallTool.Result {
        guard let r = await store.latest() else {
            return await respond(["reading": NSNull(), "message": "No measurements yet."])
        }
        return await respond(["reading": object(r, withAge: true)])
    }

    private func wait(seconds: Double) async -> CallTool.Result {
        let s = min(max(seconds, 1), Self.maxWaitSeconds)
        guard let r = await store.next(timeout: .milliseconds(Int(s * 1000))) else {
            return await respond(["reading": NSNull(), "message": "No measurement within \(Int(s)) s."])
        }
        return await respond(["reading": object(r, withAge: true)])
    }

    private func list(since: String?, limit: Int?) async -> CallTool.Result {
        var readings: [Reading]
        if let since {
            if let id = UUID(uuidString: since) {
                readings = await store.after(id: id)
            } else if let date = parseDate(since) {
                readings = await store.since(date)
            } else {
                return error("since must be an ISO 8601 time or a reading id, got \"\(since)\".")
            }
        } else {
            readings = await store.all()
        }
        if let limit, limit >= 0 { readings = Array(readings.prefix(limit)) }
        return await respond(["readings": readings.map { object($0, withAge: false) }, "count": readings.count])
    }

    private func triggerMeasurement() async -> CallTool.Result {
        let status = await device.status()
        if status.triggerSupported == .unsupported {
            return error("Remote triggering is not supported on this device. Ask the user to press the measure button, then use wait_for_measurement.")
        }
        // Start waiting before firing so the reading can't slip past.
        async let next = store.next(timeout: Self.triggerWait)
        do {
            try await device.trigger()
        } catch {
            _ = await next
            return self.error("The laser measure is not connected (state: \(status.state.rawValue)).")
        }
        guard let r = await next else {
            await device.markTrigger(.unsupported)
            return error("The device did not respond to the remote trigger, so it is marked unsupported. Ask the user to press the measure button, then use wait_for_measurement.")
        }
        await device.markTrigger(.supported)
        return await respond(["reading": object(r, withAge: true)])
    }

    private func send(_ command: DeviceCommand, field: String, on: Bool) async -> CallTool.Result {
        do {
            try await device.send(command)
        } catch DeviceError.noResponse {
            return error("The laser measure did not answer. Ask the user to turn it off and on again.")
        } catch {
            return self.error("The laser measure is not connected (state: \(await device.status().state.rawValue)).")
        }
        return await respond([field: on ? "on" : "off"])
    }

    // MARK: - JSON

    private func respond(_ fields: [String: Any]) async -> CallTool.Result {
        var body = fields
        body["device"] = Self.jsonObject(await device.status())
        let data = (try? JSONSerialization.data(withJSONObject: Self.shortestNumbers(body), options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return CallTool.Result(content: [.text(text: String(decoding: data, as: UTF8.self), annotations: nil, _meta: nil)], isError: false)
    }

    private func error(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }

    private func object(_ r: Reading, withAge: Bool) -> [String: Any] {
        var o = Self.jsonObject(r)
        if let v = r.value { o["value_display"] = displayString(value: v, unit: r.unit) }
        if withAge { o["age_seconds"] = Int(Date().timeIntervalSince(r.timestamp).rounded()) }
        return o
    }

    /// JSONSerialization prints doubles with full binary precision (0.7758 → 0.77580000000000005).
    /// Swapping them for decimals of their shortest description keeps the output exact and readable.
    static func shortestNumbers(_ value: Any) -> Any {
        switch value {
        case let d as [String: Any]: d.mapValues(shortestNumbers)
        case let a as [Any]: a.map(shortestNumbers)
        case let n as NSNumber where CFNumberIsFloatType(n): NSDecimalNumber(string: "\(n.doubleValue)")
        default: value
        }
    }

    static func jsonObject<T: Encodable>(_ value: T) -> [String: Any] {
        guard let data = try? MeasurementStore.encoder().encode(value),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    /// Finite numbers only; NaN/infinity would trap on Int conversion.
    private func number(_ v: Value?) -> Double? {
        let d: Double? = switch v {
        case .int(let i): Double(i)
        case .double(let d): d
        case .string(let s): Double(s)
        default: nil
        }
        return d.flatMap { $0.isFinite ? $0 : nil }
    }

    private func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
