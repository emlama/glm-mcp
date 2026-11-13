import Foundation

/// Simple control commands from the older Classic-Bluetooth protocol. The GLM 50 C also accepts them
/// over BLE and answers with a `DeviceReply` (`00 00 82` for OK).
public enum DeviceCommand: String, Sendable, CaseIterable {
    case laserOn, laserOff, backlightOn, backlightOff

    public var bytes: Data {
        switch self {
        case .laserOn: Data([0xC0, 0x41, 0x00, 0x96])
        case .laserOff: Data([0xC0, 0x42, 0x00, 0x1E])
        case .backlightOn: Data([0xC0, 0x47, 0x00, 0x20])
        case .backlightOff: Data([0xC0, 0x48, 0x00, 0x62])
        }
    }
}

/// A command reply: `<status> <length> <payload…> <checksum>`. Arrives as one notification,
/// separate from the 20-byte push frames. The checksum is not validated.
public struct DeviceReply: Sendable, Equatable {
    public let status: UInt8
    public let payload: Data

    public init(status: UInt8, payload: Data) {
        self.status = status
        self.payload = payload
    }

    public init?(_ data: Data) {
        let b = [UInt8](data)
        guard b.count >= 3, b[0] != 0xC0, b.count == Int(b[1]) + 3 else { return nil }
        status = b[0]
        payload = Data(b[2..<(b.count - 1)])
    }
}

/// Spots a device that accepts connections but never answers. After a link timeout the GLM 50 C
/// can get into this state; only power-cycling it helps.
public struct LinkHealth: Sendable {
    static let silentConnectionsBeforeStuck = 2

    private var silentConnections = 0
    private var gotData = false

    public init() {}

    public var isStuck: Bool { silentConnections >= Self.silentConnectionsBeforeStuck }

    public mutating func dataReceived() {
        gotData = true
        silentConnections = 0
    }

    public mutating func connectionEnded() {
        if !gotData { silentConnections += 1 }
        gotData = false
    }
}
