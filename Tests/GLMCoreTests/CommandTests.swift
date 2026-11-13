import Foundation
import Testing
@testable import GLMCore

@Test func commandBytes() {
    #expect(DeviceCommand.laserOn.bytes.hexString == "c0 41 00 96")
    #expect(DeviceCommand.laserOff.bytes.hexString == "c0 42 00 1e")
    #expect(DeviceCommand.backlightOn.bytes.hexString == "c0 47 00 20")
    #expect(DeviceCommand.backlightOff.bytes.hexString == "c0 48 00 62")
}

@Test func replyOK() {
    let r = DeviceReply(Data(hex: "00 00 82")!)
    #expect(r == DeviceReply(status: 0, payload: Data()))
}

@Test func replyWithPayload() {
    // Auto-sync acknowledgement captured from a GLM 50 C.
    let r = DeviceReply(Data(hex: "00 10 02 08 00 02 00 00 00 00 00 00 00 00 00 00 00 00 b8")!)
    #expect(r?.status == 0)
    #expect(r?.payload.count == 16)
}

@Test func replyRejectsFramesAndJunk() {
    #expect(DeviceReply(Data(hex: "c0 55 10 02 0d 07 02 00 00 00 00 00 00 00 00 00 00 00 00 c6")!) == nil)
    #expect(DeviceReply(Data(hex: "00 05 01")!) == nil)
    #expect(DeviceReply(Data()) == nil)
}

@Test func healthyLinkIsNotStuck() {
    var h = LinkHealth()
    h.connectionEnded()
    h.dataReceived()
    h.connectionEnded()
    #expect(!h.isStuck)
}

@Test func twoSilentConnectionsInARowAreStuck() {
    var h = LinkHealth()
    h.connectionEnded()
    #expect(!h.isStuck)
    h.connectionEnded()
    #expect(h.isStuck)
}

@Test func dataClearsStuck() {
    var h = LinkHealth()
    h.connectionEnded()
    h.connectionEnded()
    h.dataReceived()
    #expect(!h.isStuck)
}

@Test func dataOnlyCountsForTheConnectionItArrivedOn() {
    var h = LinkHealth()
    h.dataReceived()
    h.connectionEnded()  // had data
    h.connectionEnded()  // silent
    #expect(!h.isStuck)
    h.connectionEnded()  // silent
    #expect(h.isStuck)
}
