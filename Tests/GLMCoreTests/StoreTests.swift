import Foundation
import Testing
@testable import GLMCore

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("glm-store-\(UUID().uuidString)")
    return d
}

private func make(_ hex: String, at date: Date = Date()) -> Reading {
    var p = FrameParser()
    guard case .reading(let r) = interpret(p.feed(Data(hex: hex)!)[0], deviceName: "GLM", at: date) else { fatalError() }
    return r
}

@Test func appendAndLatest() async throws {
    let s = try MeasurementStore(directory: tempDir())
    let a = make(Fixtures.length1), b = make(Fixtures.length2)
    let okA = await s.append(a), okB = await s.append(b)
    #expect(okA && okB)
    #expect(await s.latest() == b)
    #expect(await s.all() == [b, a])
}

@Test func persistsAcrossInstances() async throws {
    let dir = tempDir()
    let s = try MeasurementStore(directory: dir)
    let a = make(Fixtures.length1), b = make(Fixtures.continuous)
    _ = await s.append(a)
    _ = await s.append(b)
    let s2 = try MeasurementStore(directory: dir)
    let loaded = await s2.all()
    #expect(loaded.map(\.id) == [b.id, a.id])
    #expect(loaded[0].components == b.components && loaded[1].value == a.value)
    #expect(abs(loaded[1].timestamp.timeIntervalSince(a.timestamp)) < 0.001)
}

@Test func skipsCorruptLines() async throws {
    let dir = tempDir()
    let s = try MeasurementStore(directory: dir)
    _ = await s.append(make(Fixtures.length1))
    let file = dir.appendingPathComponent("measurements.jsonl")
    let h = try FileHandle(forWritingTo: file)
    try h.seekToEnd()
    try h.write(contentsOf: Data("{garbage\n".utf8))
    try h.close()
    let s2 = try MeasurementStore(directory: dir)
    _ = await s2.append(make(Fixtures.length2))
    let s3 = try MeasurementStore(directory: dir)
    #expect(await s3.all().count == 2)
}

@Test func dedupesRepeatedFrame() async throws {
    let s = try MeasurementStore(directory: tempDir())
    #expect(await s.append(make(Fixtures.length1)))
    #expect(await s.append(make(Fixtures.length1)) == false)
    #expect(await s.all().count == 1)
}

@Test func keepsSameSeqDifferentFrames() async throws {
    let s = try MeasurementStore(directory: tempDir())
    for hex in [Fixtures.wallAreaHeight, Fixtures.wallArea1, Fixtures.wallArea2] { _ = await s.append(make(hex)) }
    #expect(await s.all().count == 3)
}

@Test func latestSkipsPartials() async throws {
    let s = try MeasurementStore(directory: tempDir())
    let a = make(Fixtures.length1)
    _ = await s.append(a)
    _ = await s.append(make(Fixtures.areaPartial))
    #expect(await s.latest() == a)
}

@Test func waitIgnoresExisting() async throws {
    let s = try MeasurementStore(directory: tempDir())
    _ = await s.append(make(Fixtures.length1))
    let b = make(Fixtures.length2)
    let waiter = Task { await s.next(timeout: .seconds(2)) }
    try await Task.sleep(for: .milliseconds(50))
    _ = await s.append(b)
    #expect(await waiter.value == b)
}

@Test func waitSkipsPartials() async throws {
    let s = try MeasurementStore(directory: tempDir())
    let area = make(Fixtures.area)
    let waiter = Task { await s.next(timeout: .seconds(2)) }
    try await Task.sleep(for: .milliseconds(50))
    _ = await s.append(make(Fixtures.areaPartial))
    _ = await s.append(area)
    #expect(await waiter.value == area)
}

@Test func waitTimesOut() async throws {
    let s = try MeasurementStore(directory: tempDir())
    let start = Date()
    #expect(await s.next(timeout: .milliseconds(100)) == nil)
    #expect(Date().timeIntervalSince(start) < 1)
}

@Test func clearArchives() async throws {
    let dir = tempDir()
    let s = try MeasurementStore(directory: dir)
    _ = await s.append(make(Fixtures.length1))
    try await s.clear()
    #expect(await s.all().isEmpty)
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(files.contains { $0.hasPrefix("measurements-") && $0.hasSuffix(".jsonl") })
    #expect(try await MeasurementStore(directory: dir).all().isEmpty)
}

@Test func sinceAndAfterFilter() async throws {
    let s = try MeasurementStore(directory: tempDir())
    let t0 = Date(timeIntervalSince1970: 1_000)
    let a = make(Fixtures.length1, at: t0)
    let b = make(Fixtures.length2, at: t0.addingTimeInterval(10))
    let c = make(Fixtures.continuous, at: t0.addingTimeInterval(20))
    for r in [a, b, c] { _ = await s.append(r) }
    #expect(await s.since(t0.addingTimeInterval(10)) == [c, b])
    #expect(await s.after(id: a.id) == [c, b])
}

@Test func updatesStreamYieldsAppends() async throws {
    let s = try MeasurementStore(directory: tempDir())
    let a = make(Fixtures.length1)
    var it = s.updates.makeAsyncIterator()
    _ = await s.append(a)
    #expect(await it.next() == a)
}

@Test func truncatedLastLineDoesNotEatNextReading() async throws {
    let dir = tempDir()
    let s = try MeasurementStore(directory: dir)
    _ = await s.append(make(Fixtures.length1))
    let h = try FileHandle(forWritingTo: dir.appendingPathComponent("measurements.jsonl"))
    try h.seekToEnd()
    try h.write(contentsOf: Data("{\"id\":\"cut-off".utf8))
    try h.close()
    let s2 = try MeasurementStore(directory: dir)
    _ = await s2.append(make(Fixtures.length2))
    #expect(try await MeasurementStore(directory: dir).all().count == 2)
}

@Test func dedupeSurvivesClear() async throws {
    let s = try MeasurementStore(directory: tempDir())
    _ = await s.append(make(Fixtures.length1))
    try await s.clear()
    #expect(await s.append(make(Fixtures.length1)) == false)
}
