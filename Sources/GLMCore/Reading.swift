import Foundation

public enum ReadingKind: String, Codable, Sendable {
    case length, continuous, area
    case areaPartial = "area_partial"
    case volume
    case volumePartial = "volume_partial"
    case wallArea = "wall_area"
    case wallAreaPartial = "wall_area_partial"
    case addition, subtraction
    case areaAddition = "area_addition"
    case areaSubtraction = "area_subtraction"
    case failed, unknown

    /// Partials are intermediate steps of a multi-press measurement, not results.
    public var isComplete: Bool {
        switch self {
        case .areaPartial, .volumePartial, .wallAreaPartial: false
        default: true
        }
    }
}

public enum MeasureUnit: String, Codable, Sendable {
    case m, m2, m3
}

public struct Reading: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var seq: UInt16
    public var timestamp: Date
    public var kind: ReadingKind
    public var typeCode: UInt8
    /// Primary value; nil for partials, failed and unknown frames.
    public var value: Double?
    public var unit: MeasureUnit
    public var components: [String: Double]
    public var rawHex: String
    public var deviceName: String

    enum CodingKeys: String, CodingKey {
        case id, seq, timestamp, kind, value, unit, components
        case typeCode = "type_code"
        case rawHex = "raw_hex"
        case deviceName = "device_name"
    }

    public init(
        id: UUID = UUID(), seq: UInt16, timestamp: Date, kind: ReadingKind, typeCode: UInt8,
        value: Double?, unit: MeasureUnit, components: [String: Double] = [:], rawHex: String, deviceName: String
    ) {
        self.id = id
        self.seq = seq
        self.timestamp = timestamp
        self.kind = kind
        self.typeCode = typeCode
        self.value = value
        self.unit = unit
        self.components = components
        self.rawHex = rawHex
        self.deviceName = deviceName
    }
}

public enum DeviceEvent: Sendable, Equatable {
    case reading(Reading)
    case modeChanged(Int)
    case laser
}

/// Maps a frame to what it means. Frame types are documented in the design spec;
/// anything unrecognised becomes `.unknown` with raw values and no primary value.
public func interpret(_ frame: Frame, deviceName: String, at date: Date, id: UUID = UUID()) -> DeviceEvent {
    // Non-finite values (garbage or a false header) are dropped, never reported.
    let v = frame.values.map { (Double($0) * 10_000).rounded() / 10_000 }

    func reading(_ kind: ReadingKind, _ unit: MeasureUnit, _ value: Double?, _ components: [String: Double] = [:]) -> DeviceEvent {
        .reading(Reading(
            id: id, seq: frame.seq, timestamp: date, kind: kind, typeCode: frame.typeCode,
            value: value.flatMap { $0.isFinite ? $0 : nil }, unit: unit,
            components: components.filter { $0.value.isFinite }, rawHex: frame.raw.hexString, deviceName: deviceName
        ))
    }

    switch frame.typeCode {
    case 0x02: return .laser
    case 0xF2:
        guard v[0].isFinite, let mode = Int(exactly: v[0]), (0...255).contains(mode) else {
            return reading(.unknown, .m, nil, ["v0": v[0], "v1": v[1], "v2": v[2]])
        }
        return .modeChanged(mode)
    case 0x06: return reading(.length, .m, v[0])
    case 0x0A: return reading(.continuous, .m, v[0], ["min": v[1], "max": v[2]])
    case 0x0E: return reading(.areaPartial, .m, nil, ["length": v[1]])
    case 0x12: return reading(.area, .m2, v[0], ["length": v[1], "width": v[2]])
    case 0x16, 0x1A: return reading(.volumePartial, .m, nil, ["length": v[1]])
    case 0x1E: return reading(.volume, .m3, v[0], ["length": v[1]])
    case 0x3A: return reading(.wallAreaPartial, .m, nil, ["height": v[1]])
    case 0x3E: return reading(.wallArea, .m2, v[0], ["width": v[1], "total_width": v[2]])
    case 0x42: return reading(.addition, .m, v[0], ["a": v[1], "b": v[2]])
    case 0x46: return reading(.subtraction, .m, v[0], ["a": v[1], "b": v[2]])
    case 0x4A: return reading(.areaAddition, .m2, v[0], ["a": v[1], "b": v[2]])
    case 0x4E: return reading(.areaSubtraction, .m2, v[0], ["a": v[1], "b": v[2]])
    case 0xFE: return reading(.failed, .m, nil, ["mode": v[0]])
    default: return reading(.unknown, .m, nil, ["v0": v[0], "v1": v[1], "v2": v[2]])
    }
}
