# Changelog

## 0.2.0 — 2026-11-12

- New tools `set_laser_pointer` and `set_backlight` (on/off). Both wait for the laser to acknowledge.
- `trigger_measurement` confirmed working on the original GLM 50 C.
- Detects a laser that connects but stays silent (seen after a dropped link) and reports
  "The laser connects but isn't responding. Turn it off and on again." in the menu and device status.
- Logs connections, notification setup, write errors and raw incoming bytes for troubleshooting.

## 0.1.1 — 2026-11-12

First published release. Same as 0.1.0, whose release build failed; the universal app is now
built per architecture and merged with `lipo`.

## 0.1.0 — 2026-11-12

First release.

- Menu bar app that keeps a Bluetooth LE connection to a Bosch GLM 50 C and reconnects on its own.
- Local MCP server (`http://127.0.0.1:47650/mcp`) with `get_latest_measurement`, `wait_for_measurement`,
  `list_measurements`, `get_device_status`, `trigger_measurement`.
- Decodes length, continuous, area, volume, wall area, addition/subtraction and failed measurements;
  unknown frame types are kept raw and never reported as distances.
- History persisted to `~/Library/Application Support/GLM MCP/measurements.jsonl`.
