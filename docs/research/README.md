# Research

Throwaway code from the first exploration of the GLM 50 C's Bluetooth link on macOS (2026-11).
Kept because it documents what did and didn't work; see [../design.md](../design.md).

- `ble.swift` — connects over Bluetooth LE, subscribes, enables auto-sync, prints frames. This is the approach the app uses.
- `glm50c-ble-capture.log` — output of `ble.swift` while taking length, continuous and wall-area measurements.
- `diag.swift` — scans Classic and LE. Showed Classic inquiry is refused outside an app bundle.
- `rfcomm.swift`, `spike_serial.py` — Classic Bluetooth (RFCOMM / `/dev/cu.*`) attempts; neither received data on macOS.

The Swift files must run inside an app bundle with `NSBluetoothAlwaysUsageDescription` to get Bluetooth access.
