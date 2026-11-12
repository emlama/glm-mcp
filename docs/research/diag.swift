// Throwaway diagnostic: is the GLM visible over Classic or BLE, and does an SDP query reach it?
import CoreBluetooth
import Foundation
import IOBluetooth

let address = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : { print("usage: diag <bluetooth-address>"); exit(1) }()
func log(_ s: String) { print("[\(String(format: "%5.1f", Date().timeIntervalSince(start)))] " + s); fflush(stdout) }
let start = Date()

final class Inquiry: NSObject, IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        log("CLASSIC found: \(device.name ?? "?") \(device.addressString ?? "?")")
    }
    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        log("CLASSIC inquiry complete error=\(error)")
    }
}

final class Central: NSObject, CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        log("BLE state=\(c.state.rawValue) (5=poweredOn, 3=unauthorized) auth=\(CBManager.authorization.rawValue)")
        if c.state == .poweredOn { c.scanForPeripherals(withServices: nil) }
    }
    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let name = p.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.map(\.uuidString) ?? []
        if name.uppercased().contains("GLM") || name.uppercased().contains("BOSCH") || uuids.contains("FDE8") {
            log("BLE found: \(name) \(p.identifier) rssi=\(rssi) services=\(uuids)")
        }
    }
}

final class SDP: NSObject {
    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        log("SDP complete status=\(String(format: "0x%08x", status)) services=\(device.services?.count ?? 0)")
        for case let rec as IOBluetoothSDPServiceRecord in device.services ?? [] {
            var ch: BluetoothRFCOMMChannelID = 0
            let hasCh = rec.getRFCOMMChannelID(&ch) == kIOReturnSuccess
            log("  service: \(rec.getServiceName() ?? "?")" + (hasCh ? " rfcomm=\(ch)" : ""))
        }
    }
}

let inq = Inquiry()
let inquiry = IOBluetoothDeviceInquiry(delegate: inq)!
inquiry.inquiryLength = 15
log("CLASSIC inquiry start=\(inquiry.start())")

let central = Central()
let cm = CBCentralManager(delegate: central, queue: nil)

let sdp = SDP()
if let d = IOBluetoothDevice(addressString: address) {
    log("SDP query start=\(d.performSDPQuery(sdp))")
}

RunLoop.main.run(until: Date().addingTimeInterval(40))
cm.stopScan()
log("done")
