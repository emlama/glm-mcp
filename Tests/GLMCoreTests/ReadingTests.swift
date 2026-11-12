import Foundation
import Testing
@testable import GLMCore

private let when = Date(timeIntervalSince1970: 1_800_000_000)

private func event(_ hex: String) -> DeviceEvent {
    var p = FrameParser()
    let frames = p.feed(Data(hex: hex)!)
    precondition(frames.count == 1)
    return interpret(frames[0], deviceName: "Bosch GLM50C x1234", at: when)
}

private func reading(_ hex: String) -> Reading {
    guard case .reading(let r) = event(hex) else { fatalError("not a reading: \(hex)") }
    return r
}

private func approx(_ a: Double?, _ b: Double, _ tol: Double = 0.0005) -> Bool {
    guard let a else { return false }
    return abs(a - b) < tol
}

@Test func length() {
    let r = reading(Fixtures.length1)
    #expect(r.kind == .length && r.unit == .m && r.seq == 0x01ba && r.typeCode == 0x06)
    #expect(r.value == 2.2711)
    #expect(r.rawHex == Fixtures.length1)
    #expect(r.timestamp == when && r.deviceName == "Bosch GLM50C x1234")
    #expect(r.kind.isComplete)
}

@Test func continuous() {
    let r = reading(Fixtures.continuous)
    #expect(r.kind == .continuous && r.value == 1.8189)
    #expect(r.components == ["min": 1.016, "max": 1.8189])
}

@Test func area() {
    let r = reading(Fixtures.area)
    #expect(r.kind == .area && r.unit == .m2)
    #expect(approx(r.value, 1.4291))
    #expect(approx(r.components["length"], 1.1566) && approx(r.components["width"], 1.2356))
}

@Test func areaPartialHasNoValue() {
    let r = reading(Fixtures.areaPartial)
    #expect(r.kind == .areaPartial && r.value == nil && !r.kind.isComplete)
    #expect(approx(r.components["length"], 1.1566))
}

@Test func wallArea() {
    let h = reading(Fixtures.wallAreaHeight)
    #expect(h.kind == .wallAreaPartial && h.value == nil && approx(h.components["height"], 2.1293))
    let r = reading(Fixtures.wallArea1)
    #expect(r.kind == .wallArea && r.unit == .m2 && approx(r.value, 4.7402))
    #expect(approx(r.components["width"], 2.2262) && approx(r.components["total_width"], 2.2262))
    let r2 = reading(Fixtures.wallArea2)
    #expect(approx(r2.value, 9.3873) && approx(r2.components["total_width"], 4.4087))
}

@Test func modeChange() {
    #expect(event(Fixtures.modeContinuous) == .modeChanged(2))
    #expect(event(Fixtures.modeLength) == .modeChanged(1))
}

@Test func laserEvent() {
    #expect(event(Fixtures.laser) == .laser)
}

@Test func unknownNeverADistance() {
    let hex = Fixtures.length1.replacingOccurrences(of: "c0 55 10 06", with: "c0 55 10 77")
    let r = reading(hex)
    #expect(r.kind == .unknown && r.value == nil && r.kind.isComplete)
    #expect(approx(r.components["v0"], 2.2711))
}

@Test func failedMeasurement() {
    let hex = "c0 55 10 fe 08 bd 01 00 00 80 3f 00 00 00 00 00 00 00 00 00"
    let r = reading(hex)
    #expect(r.kind == .failed && r.value == nil && r.components["mode"] == 1 && r.kind.isComplete)
}

@Test func jsonUsesSnakeCase() throws {
    let json = String(decoding: try JSONEncoder().encode(reading(Fixtures.length1)), as: UTF8.self)
    #expect(json.contains("\"type_code\"") && json.contains("\"raw_hex\"") && json.contains("\"device_name\""))
}

@Test func display() {
    #expect(displayString(value: 2.2711, unit: .m) == "2.271 m (89.4 in)")
    #expect(displayString(value: 1.4291, unit: .m2) == "1.429 m² (15.4 ft²)")
    #expect(displayString(value: 2.0, unit: .m3) == "2.000 m³ (70.6 ft³)")
}

@Test func nonFiniteModeDoesNotCrash() {
    // f32 NaN (00 00 c0 7f) and 1e30 (ca f2 49 71) in a mode-change frame
    if case .modeChanged = event("c0 55 10 f2 08 b9 01 00 00 c0 7f 00 00 00 00 00 00 00 00 00") { Issue.record("NaN mode accepted") }
    if case .modeChanged = event("c0 55 10 f2 08 b9 01 ca f2 49 71 00 00 00 00 00 00 00 00 00") { Issue.record("huge mode accepted") }
}

@Test func nonFiniteValuesBecomeNil() {
    let r = reading("c0 55 10 06 08 ba 01 00 00 c0 7f 00 00 00 00 00 00 00 00 12")
    #expect(r.value == nil)
}
