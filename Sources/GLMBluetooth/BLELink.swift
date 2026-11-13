@preconcurrency import CoreBluetooth
import Foundation
import GLMCore
import os

/// Keeps a BLE connection to a Bosch GLM and feeds its readings into the store.
///
/// All CoreBluetooth work and all mutable state live on `queue`.
public final class BLELink: NSObject, DeviceControl, @unchecked Sendable {
    static let autoSync = Data([0xC0, 0x55, 0x02, 0x01, 0x00, 0x1A])
    static let triggerCommand = Data([0xC0, 0x56, 0x01, 0x00, 0x1E])

    /// Known BLE profiles carrying the same byte protocol.
    nonisolated(unsafe) static let profiles: [(name: String, characteristic: CBUUID)] = [
        ("serial_pipe", CBUUID(string: "00004301-0000-0041-5253-534F46540000")),
        ("bosch_mt", CBUUID(string: "02A6C0D1-0451-4000-B000-FB3210111989")),
    ]
    nonisolated(unsafe) static let boschService = CBUUID(string: "FDE8")
    static let lastPeripheralKey = "lastPeripheralID"

    static let keepaliveIdle: TimeInterval = 30
    static let keepaliveGrace: TimeInterval = 10
    static let replyTimeout: TimeInterval = 2
    static let stuckMessage = "The laser connects but isn't responding. Turn it off and on again."

    public let statusUpdates: AsyncStream<DeviceStatus>
    private let statusContinuation: AsyncStream<DeviceStatus>.Continuation
    private let readingsContinuation: AsyncStream<Reading>.Continuation

    private let queue = DispatchQueue(label: "glm-mcp.ble")
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "glm-mcp", category: "frames")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var parser = FrameParser()
    private var current = DeviceStatus(state: .scanning)
    private var keepaliveSentAt: Date?
    private var backoff: TimeInterval = 1
    private var timer: DispatchSourceTimer?
    /// True while waiting on a connect to the remembered peripheral; scanning continues meanwhile
    /// so a different GLM (or the same one under a new identifier) can still be found.
    private var pendingKnown = false
    private var health = LinkHealth()
    /// Waiter for the reply to a control command; `pendingToken` identifies it for the timeout.
    private var pendingReply: CheckedContinuation<Void, Error>?
    private var pendingToken: UUID?

    public init(store: MeasurementStore) {
        (statusUpdates, statusContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        let (readings, readingsContinuation) = AsyncStream.makeStream(of: Reading.self)
        self.readingsContinuation = readingsContinuation
        super.init()
        // One consumer so readings reach the store in arrival order.
        Task {
            for await r in readings { await store.append(r) }
        }
    }

    public func start() {
        queue.async { [self] in
            central = CBCentralManager(delegate: self, queue: queue)
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 5, repeating: 5)
            t.setEventHandler { [weak self] in self?.checkKeepalive() }
            t.resume()
            timer = t
        }
    }

    // MARK: - DeviceControl

    public func status() async -> DeviceStatus { queue.sync { current } }

    public func trigger() async throws {
        let ok: Bool = queue.sync {
            guard current.state == .connected, let p = peripheral, let c = characteristic else { return false }
            p.writeValue(Self.triggerCommand, for: c, type: .withResponse)
            queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, let p = self.peripheral, let c = self.characteristic else { return }
                p.writeValue(Self.triggerCommand, for: c, type: .withResponse)
            }
            return true
        }
        if !ok { throw DeviceError.notConnected }
    }

    public func markTrigger(_ support: TriggerSupport) async {
        queue.sync { update { $0.triggerSupported = support } }
    }

    public func send(_ command: DeviceCommand) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                guard current.state == .connected, let p = peripheral, let c = characteristic else {
                    return cont.resume(throwing: DeviceError.notConnected)
                }
                // One command at a time; a newer one supersedes an unanswered older one.
                finishReply(throwing: DeviceError.noResponse)
                let token = UUID()
                pendingReply = cont
                pendingToken = token
                p.writeValue(command.bytes, for: c, type: .withResponse)
                queue.asyncAfter(deadline: .now() + Self.replyTimeout) { [weak self] in
                    guard let self, self.pendingToken == token else { return }
                    self.finishReply(throwing: DeviceError.noResponse)
                }
            }
        }
    }

    private func finishReply(throwing error: Error? = nil) {
        guard let cont = pendingReply else { return }
        pendingReply = nil
        pendingToken = nil
        if let error { cont.resume(throwing: error) } else { cont.resume() }
    }

    // MARK: - State

    private func update(_ change: (inout DeviceStatus) -> Void) {
        change(&current)
        statusContinuation.yield(current)
    }

    private func startScanning() {
        guard central.state == .poweredOn else { return }
        update {
            $0.state = .scanning
            $0.detail = health.isStuck ? Self.stuckMessage : nil
        }
        if let idString = UserDefaults.standard.string(forKey: Self.lastPeripheralKey),
           let id = UUID(uuidString: idString),
           let known = central.retrievePeripherals(withIdentifiers: [id]).first {
            // A pending connect to a known peripheral completes whenever it next appears;
            // CoreBluetooth has no timeout, so report it as searching until then.
            connect(known, state: .scanning)
            pendingKnown = true
        }
        central.scanForPeripherals(withServices: nil)
    }

    private func connect(_ p: CBPeripheral, state: LinkState = .connecting) {
        central.stopScan()
        pendingKnown = false
        peripheral = p
        p.delegate = self
        update {
            $0.state = state
            $0.deviceName = p.name ?? $0.deviceName
        }
        central.connect(p)
    }

    /// Forgets the current connection attempt without scheduling anything.
    private func resetLink() {
        peripheral = nil
        characteristic = nil
        parser = FrameParser()
        keepaliveSentAt = nil
        pendingKnown = false
        finishReply(throwing: DeviceError.notConnected)
    }

    private func scheduleReconnect() {
        // Only links that got as far as subscribing count towards spotting a stuck device.
        if current.state == .connected {
            health.connectionEnded()
            if health.isStuck { log.info("device connects but stays silent; reporting it as stuck") }
        }
        resetLink()
        update {
            $0.state = .scanning
            $0.profile = nil
            $0.detail = health.isStuck ? Self.stuckMessage : nil
        }
        let delay = backoff
        backoff = min(backoff * 2, 5)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.peripheral == nil else { return }
            self.startScanning()
        }
    }

    private func checkKeepalive() {
        guard current.state == .connected, let p = peripheral, let c = characteristic else { return }
        let last = current.lastDataAt ?? .distantPast
        if let sent = keepaliveSentAt {
            if last >= sent {
                keepaliveSentAt = nil
            } else if Date().timeIntervalSince(sent) > Self.keepaliveGrace {
                log.info("keepalive unanswered; dropping connection")
                keepaliveSentAt = nil
                central.cancelPeripheralConnection(p)
            }
        } else if Date().timeIntervalSince(last) > Self.keepaliveIdle {
            keepaliveSentAt = Date()
            p.writeValue(Self.autoSync, for: c, type: .withResponse)
        }
    }

    private func handle(_ data: Data) {
        let now = Date()
        health.dataReceived()
        update {
            $0.lastDataAt = now
            if $0.detail == Self.stuckMessage { $0.detail = nil }
        }
        if let reply = DeviceReply(data), reply.payload.isEmpty {
            finishReply(throwing: reply.status == 0 ? nil : DeviceError.noResponse)
            return
        }
        for frame in parser.feed(data) {
            log.debug("frame \(frame.raw.hexString, privacy: .public)")
            switch interpret(frame, deviceName: current.deviceName ?? "Bosch GLM", at: now) {
            case .reading(let r): readingsContinuation.yield(r)
            case .modeChanged(let m): update { $0.currentMode = m }
            case .laser: break
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLELink: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // CoreBluetooth doesn't report disconnects on power-off/reset; drop stale state ourselves.
        if central.state != .poweredOn { resetLink() }
        switch central.state {
        case .poweredOn:
            startScanning()
        case .unauthorized:
            update {
                $0.state = .off
                $0.detail = "Bluetooth permission denied. Allow GLM MCP in System Settings › Privacy & Security › Bluetooth."
            }
        case .poweredOff:
            update {
                $0.state = .off
                $0.detail = "Bluetooth is turned off."
            }
        default:
            update {
                $0.state = .off
                $0.detail = "Bluetooth unavailable."
            }
        }
    }

    public func centralManager(
        _ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber
    ) {
        let name = p.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard name.uppercased().contains("GLM") || services.contains(Self.boschService) else { return }
        if let pending = peripheral {
            // Only switch away from a still-pending connect to the remembered peripheral.
            guard pendingKnown, pending.identifier != p.identifier else {
                if pendingKnown { central.stopScan() }  // it's advertising; the pending connect will complete
                return
            }
            central.cancelPeripheralConnection(pending)
        }
        update { $0.deviceName = name.isEmpty ? $0.deviceName : name }
        connect(p)
    }

    public func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        log.info("connected to \(p.identifier.uuidString, privacy: .public)")
        update { $0.state = .connecting }
        p.discoverServices(nil)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        log.info("connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        // Ignore callbacks for a peripheral we've already moved away from.
        guard p.identifier == peripheral?.identifier else { return }
        scheduleReconnect()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log.info("disconnected: \(error?.localizedDescription ?? "clean", privacy: .public)")
        // Ignore callbacks for a peripheral we've already moved away from.
        guard p.identifier == peripheral?.identifier else { return }
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension BLELink: CBPeripheralDelegate {
    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
    }

    public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard characteristic == nil else { return }
        for (name, uuid) in Self.profiles {
            if let c = service.characteristics?.first(where: { $0.uuid == uuid }) {
                characteristic = c
                update { $0.profile = name }
                p.setNotifyValue(true, for: c)
                return
            }
        }
    }

    public func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        log.info("notify \(c.uuid.uuidString, privacy: .public) on=\(c.isNotifying) error=\(error?.localizedDescription ?? "none", privacy: .public)")
        guard c == characteristic, c.isNotifying else { return }
        p.writeValue(Self.autoSync, for: c, type: .withResponse)
        UserDefaults.standard.set(p.identifier.uuidString, forKey: Self.lastPeripheralKey)
        backoff = 1
        update {
            $0.state = .connected
            $0.deviceName = p.name ?? $0.deviceName
            $0.lastDataAt = Date()
        }
    }

    public func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        guard let error else { return }
        log.info("write failed: \(error.localizedDescription, privacy: .public)")
    }

    public func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let data = c.value else { return }
        log.info("rx \(data.hexString, privacy: .public)")
        handle(data)
    }
}
