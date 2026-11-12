import Foundation

/// One 20-byte push frame from a Bosch GLM:
/// `c0 55 10 <type> <flags> <seq u16 LE> <f32 LE> <f32 LE> <f32 LE> <checksum>`.
public struct Frame: Sendable, Equatable {
    public static let length = 20
    static let header: [UInt8] = [0xC0, 0x55, 0x10]

    public let typeCode: UInt8
    public let flags: UInt8
    public let seq: UInt16
    /// Always three values, in metres / m² / m³.
    public let values: [Float]
    public let raw: Data

    init(bytes b: [UInt8]) {
        typeCode = b[3]
        flags = b[4]
        seq = UInt16(b[5]) | UInt16(b[6]) << 8
        values = (0..<3).map { k in
            let o = 7 + k * 4
            return Float(bitPattern: UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24)
        }
        raw = Data(b)
    }
}

/// Turns a stream of BLE notification chunks into frames. Frames may arrive split or joined,
/// and non-frame bytes (e.g. the auto-sync ack) are skipped by resyncing on the header.
/// The checksum is not validated: its algorithm is unknown.
public struct FrameParser: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func feed(_ data: Data) -> [Frame] {
        buffer.append(contentsOf: data)
        var frames: [Frame] = []
        while true {
            guard let start = headerIndex() else {
                // Keep a possible partial header at the tail.
                buffer = Array(buffer.suffix(Frame.header.count - 1))
                break
            }
            buffer.removeFirst(start)
            guard buffer.count >= Frame.length else { break }
            frames.append(Frame(bytes: Array(buffer[0..<Frame.length])))
            buffer.removeFirst(Frame.length)
        }
        return frames
    }

    private func headerIndex() -> Int? {
        guard buffer.count >= Frame.header.count else { return nil }
        return (0...(buffer.count - Frame.header.count)).first { i in
            buffer[i] == Frame.header[0] && buffer[i + 1] == Frame.header[1] && buffer[i + 2] == Frame.header[2]
        }
    }
}

extension Data {
    /// Parses hex like `"c0 55 10"` (spaces optional). Returns nil on invalid input.
    public init?(hex: String) {
        let digits = hex.filter { !$0.isWhitespace }
        guard digits.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var i = digits.startIndex
        while i < digits.endIndex {
            let j = digits.index(i, offsetBy: 2)
            guard let b = UInt8(digits[i..<j], radix: 16) else { return nil }
            bytes.append(b)
            i = j
        }
        self.init(bytes)
    }

    /// Lowercase, space-separated hex, e.g. `"c0 55 10"`.
    public var hexString: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}
