import Foundation
import Testing
@testable import GLMCore

private func bytes(_ hex: String) -> Data { Data(hex: hex)! }

@Test func parsesSingleFrame() {
    var p = FrameParser()
    let f = p.feed(bytes(Fixtures.length1))
    #expect(f.count == 1)
    #expect(f[0].typeCode == 0x06 && f[0].seq == 0x01ba && f[0].flags == 0x08)
    #expect(abs(f[0].values[0] - 2.2711) < 0.0001)
    #expect(f[0].raw == bytes(Fixtures.length1))
}

@Test func skipsAckWithoutHeader() {
    var p = FrameParser()
    #expect(p.feed(bytes(Fixtures.ack)).isEmpty)
}

@Test func reassemblesSplitFrame() {
    var p = FrameParser()
    let d = bytes(Fixtures.length1)
    #expect(p.feed(d.prefix(7)).isEmpty)
    let f = p.feed(d.dropFirst(7))
    #expect(f.count == 1 && f[0].raw == d)
}

@Test func parsesConcatenatedFrames() {
    var p = FrameParser()
    let f = p.feed(bytes(Fixtures.length1) + bytes(Fixtures.length2))
    #expect(f.map(\.seq) == [0x01ba, 0x01bb])
}

@Test func resyncsAfterGarbage() {
    var p = FrameParser()
    let f = p.feed(bytes(Fixtures.ack) + bytes("ff c0 55") + bytes(Fixtures.length1))
    #expect(f.count == 1 && f[0].raw == bytes(Fixtures.length1))
}

@Test func keepsPartialHeaderAcrossFeeds() {
    var p = FrameParser()
    let d = bytes(Fixtures.length1)
    #expect(p.feed(bytes("aa bb") + d.prefix(2)).isEmpty)
    #expect(p.feed(d.dropFirst(2)).count == 1)
}

@Test func ignoresChecksum() {
    var d = bytes(Fixtures.length1)
    d[d.index(before: d.endIndex)] = 0x00
    var p = FrameParser()
    #expect(p.feed(d).count == 1)
}

@Test func hexRoundTrip() {
    #expect(bytes(Fixtures.length1).hexString == Fixtures.length1)
    #expect(Data(hex: "zz") == nil)
}
