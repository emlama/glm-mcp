import Foundation

/// Reading history, persisted as JSON Lines (`measurements.jsonl`) so it survives restarts.
public actor MeasurementStore {
    public nonisolated let updates: AsyncStream<Reading>
    private let updatesContinuation: AsyncStream<Reading>.Continuation

    private let directory: URL
    private var file: URL { directory.appendingPathComponent("measurements.jsonl") }
    /// Oldest first.
    private var readings: [Reading] = []
    private var waiters: [UUID: CheckedContinuation<Reading?, Never>] = [:]
    /// Last frame stored, kept across `clear()` so a device repeat right after clearing is still dropped.
    private var lastRawHex: String?

    public init(directory: URL) throws {
        self.directory = directory
        (updates, updatesContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(100))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("measurements.jsonl")) {
            let decoder = Self.decoder()
            // Skip lines that don't decode (e.g. a write cut off by a crash).
            readings = data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(Reading.self, from: Data($0)) }
            // A write cut off mid-line would otherwise swallow the next appended line.
            if let last = data.last, last != UInt8(ascii: "\n"),
               let h = try? FileHandle(forWritingTo: directory.appendingPathComponent("measurements.jsonl")) {
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: Data("\n".utf8))
                try? h.close()
            }
        }
        lastRawHex = readings.last?.rawHex
    }

    /// Stores a reading. Returns false if it is a byte-identical repeat of the previous frame
    /// (indication retransmit or keepalive echo). Seq is not a key: multi-step frames share it.
    @discardableResult
    public func append(_ r: Reading) -> Bool {
        if lastRawHex == r.rawHex { return false }
        lastRawHex = r.rawHex
        readings.append(r)
        persist(r)
        updatesContinuation.yield(r)
        if r.kind.isComplete {
            let pending = waiters
            waiters.removeAll()
            for (_, c) in pending { c.resume(returning: r) }
        }
        return true
    }

    /// Newest complete reading.
    public func latest() -> Reading? { readings.last { $0.kind.isComplete } }

    /// All readings, newest first.
    public func all() -> [Reading] { readings.reversed() }

    /// Readings with timestamp >= date, newest first.
    public func since(_ date: Date) -> [Reading] { readings.filter { $0.timestamp >= date }.reversed() }

    /// Readings appended after the one with this id, newest first. Empty if the id is unknown.
    public func after(id: UUID) -> [Reading] {
        guard let i = readings.firstIndex(where: { $0.id == id }) else { return [] }
        return readings[(i + 1)...].reversed()
    }

    /// Waits for the first complete reading appended after this call. Nil on timeout.
    public func next(timeout: Duration) async -> Reading? {
        let id = UUID()
        return await withCheckedContinuation { c in
            waiters[id] = c
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.expire(id)
            }
        }
    }

    /// Archives the current history file and starts empty.
    public func clear() throws {
        if FileManager.default.fileExists(atPath: file.path) {
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmmss"
            f.locale = Locale(identifier: "en_US_POSIX")
            let archive = directory.appendingPathComponent("measurements-\(f.string(from: Date())).jsonl")
            try FileManager.default.moveItem(at: file, to: archive)
        }
        readings.removeAll()
    }

    private func expire(_ id: UUID) {
        waiters.removeValue(forKey: id)?.resume(returning: nil)
    }

    private func persist(_ r: Reading) {
        guard var line = try? Self.encoder().encode(r) else { return }
        line.append(UInt8(ascii: "\n"))
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        guard let h = try? FileHandle(forWritingTo: file) else { return }
        defer { try? h.close() }
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: line)
        try? h.synchronize()
    }

    private static func formatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    /// Encoder used for persisted and served JSON (ISO 8601 dates with milliseconds).
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(formatter().string(from: date))
        }
        e.outputFormatting = [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            guard let date = formatter().date(from: s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
            }
            return date
        }
        return d
    }
}
