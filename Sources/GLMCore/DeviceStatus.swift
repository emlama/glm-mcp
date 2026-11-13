import Foundation

public enum LinkState: String, Codable, Sendable {
    /// Bluetooth is off or the app lacks permission; see `DeviceStatus.detail`.
    case off
    case scanning, connecting, connected
}

public enum TriggerSupport: String, Codable, Sendable {
    case unknown, supported, unsupported
}

public struct DeviceStatus: Codable, Sendable, Equatable {
    public var state: LinkState
    public var deviceName: String?
    /// "serial_pipe" or "bosch_mt".
    public var profile: String?
    /// Mode id from the last mode-change frame: 1 length, 2 continuous, 4 area, 7 volume.
    public var currentMode: Int?
    public var lastDataAt: Date?
    public var triggerSupported: TriggerSupport
    /// Human-readable problem, e.g. "Bluetooth permission denied".
    public var detail: String?

    enum CodingKeys: String, CodingKey {
        case state, profile, detail
        case deviceName = "device_name"
        case currentMode = "current_mode"
        case lastDataAt = "last_data_at"
        case triggerSupported = "trigger_supported"
    }

    public init(
        state: LinkState, deviceName: String? = nil, profile: String? = nil, currentMode: Int? = nil,
        lastDataAt: Date? = nil, triggerSupported: TriggerSupport = .unknown, detail: String? = nil
    ) {
        self.state = state
        self.deviceName = deviceName
        self.profile = profile
        self.currentMode = currentMode
        self.lastDataAt = lastDataAt
        self.triggerSupported = triggerSupported
        self.detail = detail
    }
}

public enum DeviceError: Error, Sendable {
    case notConnected
    /// The device took the command but never acknowledged it.
    case noResponse
}

/// What the MCP tools need from the device link.
public protocol DeviceControl: Sendable {
    func status() async -> DeviceStatus
    /// Fires the laser remotely. Throws `DeviceError.notConnected` when not connected.
    func trigger() async throws
    func markTrigger(_ support: TriggerSupport) async
    /// Sends a control command and waits for the device's OK.
    /// Throws `DeviceError.notConnected` or `DeviceError.noResponse`.
    func send(_ command: DeviceCommand) async throws
}
