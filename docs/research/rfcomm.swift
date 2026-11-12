// Throwaway spike: open RFCOMM directly to the GLM50C via IOBluetooth, enable push mode, print frames.
import Foundation
import IOBluetooth

let address = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : { print("usage: rfcomm <bluetooth-address> [seconds]"); exit(1) }()
let seconds = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : 90

func log(_ s: String) { print(s); fflush(stdout) }

final class Delegate: NSObject, IOBluetoothRFCOMMChannelDelegate {
    var buf = [UInt8]()

    func rfcommChannelOpenComplete(_ ch: IOBluetoothRFCOMMChannel!, status: IOReturn) {
        log("open complete status=\(status)")
        guard status == kIOReturnSuccess else { return }
        var cmd: [UInt8] = [0xC0, 0x55, 0x02, 0x01, 0x00, 0x1A]
        let r = ch.writeSync(&cmd, length: UInt16(cmd.count))
        log("auto-sync sent, write=\(r)")
    }

    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data ptr: UnsafeMutableRawPointer!, length: Int) {
        let bytes = Array(UnsafeBufferPointer(start: ptr.assumingMemoryBound(to: UInt8.self), count: length))
        log("RX " + bytes.map { String(format: "%02x", $0) }.joined(separator: " "))
        buf += bytes
        while let i = buf.indices.first(where: { buf.count - $0 >= 20 && buf[$0] == 0xC0 && buf[$0 + 1] == 0x55 && buf[$0 + 2] == 0x10 }) {
            let f = Array(buf[i..<i + 20])
            buf.removeFirst(i + 20)
            let vals = (0..<3).map { k -> Float in
                let o = 7 + k * 4
                return Float(bitPattern: UInt32(f[o]) | UInt32(f[o + 1]) << 8 | UInt32(f[o + 2]) << 16 | UInt32(f[o + 3]) << 24)
            }
            log(String(format: "  FRAME type=0x%02x values=", f[3]) + "\(vals)")
        }
    }

    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) { log("channel closed") }
}

guard let device = IOBluetoothDevice(addressString: address) else { log("bad address"); exit(1) }
log("device: \(device.name ?? "?") paired=\(device.isPaired()) connected=\(device.isConnected())")

let delegate = Delegate()
var channel: IOBluetoothRFCOMMChannel?
let r = device.openRFCOMMChannelAsync(&channel, withChannelID: 5, delegate: delegate)
log("openRFCOMMChannelAsync returned \(r)")

RunLoop.main.run(until: Date().addingTimeInterval(seconds))
channel?.close()
device.closeConnection()
log("done")
