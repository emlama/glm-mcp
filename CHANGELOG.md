# Changelog

## 0.1.0 — 2026-11-12

First release.

- Menu bar app that keeps a Bluetooth LE connection to a Bosch GLM 50 C and reconnects on its own.
- Local MCP server (`http://127.0.0.1:47650/mcp`) with `get_latest_measurement`, `wait_for_measurement`,
  `list_measurements`, `get_device_status`, `trigger_measurement`.
- Decodes length, continuous, area, volume, wall area, addition/subtraction and failed measurements;
  unknown frame types are kept raw and never reported as distances.
- History persisted to `~/Library/Application Support/GLM MCP/measurements.jsonl`.
