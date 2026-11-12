// Throwaway spike: connect to the GLM over BLE, dump GATT, enable push mode, print frames.
import CoreBluetooth
import Foundation

let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1])! : 90
let start = Date()
func log(_ s: String) { print("[\(String(format: "%5.1f", Date().timeIntervalSince(start)))] " + s); fflush(stdout) }
func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined(separator: " ") }

let glmChar = CBUUID(string: "02a6c0d1-0451-4000-b000-fb3210111989")
let autoSync = Data([0xC0, 0x55, 0x02, 0x01, 0x00, 0x1A])

final class Spike: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var cm: CBCentralManager!
    var glm: CBPeripheral?
    var buf = Data()

    override init() { super.init(); cm = CBCentralManager(delegate: self, queue: nil) }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        log("state=\(c.state.rawValue)")
        if c.state == .poweredOn { c.scanForPeripherals(withServices: nil) }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard glm == nil, (p.name ?? "").uppercased().contains("GLM") else { return }
        log("found \(p.name!) rssi=\(rssi); connecting")
        glm = p
        c.stopScan()
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        log("connected; discovering services")
        p.delegate = self
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        log("connect failed: \(error?.localizedDescription ?? "?")")
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log("disconnected: \(error?.localizedDescription ?? "clean")")
        glm = nil
        c.scanForPeripherals(withServices: nil)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] {
            log("service \(s.uuid)")
            p.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            log("  char \(ch.uuid) props=\(ch.properties.rawValue)")
            if ch.uuid == glmChar || ch.properties.contains(.indicate) || ch.properties.contains(.notify) { p.setNotifyValue(true, for: ch) }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        log("notify on=\(ch.isNotifying) err=\(error?.localizedDescription ?? "none"); sending auto-sync")
        p.writeValue(autoSync, for: ch, type: .withResponse)
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        log("write ack err=\(error?.localizedDescription ?? "none")")
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value else { return }
        log("RX \(hex(d))")
        buf.append(d)
        while let r = buf.range(of: Data([0xC0, 0x55, 0x10])), buf.distance(from: r.lowerBound, to: buf.endIndex) >= 20 {
            let f = Data(buf[r.lowerBound..<buf.index(r.lowerBound, offsetBy: 20)])
            buf.removeSubrange(buf.startIndex..<buf.index(r.lowerBound, offsetBy: 20))
            let vals = (0..<3).map { k in f.subdata(in: (7 + k * 4)..<(11 + k * 4)).withUnsafeBytes { $0.loadUnaligned(as: Float.self) } }
            log(String(format: "  FRAME type=0x%02x ", f[3]) + "values=\(vals)")
        }
    }
}

let spike = Spike()
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
log("done")
