# GLM MCP: design

A macOS menu bar app that holds a Bluetooth connection to a Bosch GLM laser measure and exposes the readings to Claude through a local MCP server.

## Intent

The user holds the laser, takes a reading with the device's own button, and speaks to Claude (voice mode): "I just measured this spot." Claude calls an MCP tool, gets the reading, and does whatever the conversation needs with it.

The app is plumbing. It does not label, organize, or interpret measurements; Claude does that. Its job is to stay connected, capture every reading accurately, and hand readings to Claude quickly.

## Goals

- Every button press on the device becomes a timestamped reading Claude can retrieve within about a second.
- Works with both Bosch GLM 50 C hardware variants (see Device protocol): the original GLM 50 C (the author's device) and the GLM 50-27 C / CG.
- Stays connected without supervision. The device sleeps, wakes, and wanders out of range; the app reconnects on its own.
- Any MCP client on the laptop can connect: Claude Code, Claude Desktop, or whatever runs the voice session. The voice session runs on the same laptop, so localhost is enough; phone or claude.ai clients are out of scope.

## Non-goals

- Labels, projects, rooms, floor plans, exports. Claude handles meaning.
- Windows or Linux.
- Multiple simultaneous devices (one active device; picking a different one is fine).
- Replacing the Bosch MeasureOn app.

## Anti-goals (failure even if it "works")

- Reporting a wrong number. Unknown or malformed frames must never be presented as a distance. When in doubt, report raw values and say the type is unknown.
- Handing Claude a stale reading as if it were fresh. Every reading carries its age.
- Silent disconnection. If the device is not connected, tools must say so plainly.
- Needing a terminal to run day to day.

## Constraints and verified facts

Verified on 2026-11-12 against the author's device, "Bosch GLM50C x1234", on macOS 26.6.2 (Apple Silicon). Research code and a raw capture are in `docs/research/`.

- **Bluetooth needs an app bundle.** A bare command-line binary was refused Classic Bluetooth inquiry (`kIOReturnNotPermitted`). The same code in an ad-hoc-signed `.app` with `NSBluetoothAlwaysUsageDescription` in Info.plist worked. The product must be a real app bundle.
- **The author's GLM 50 C is dual-mode.** It is paired over Classic (macOS created `/dev/cu.BoschGLM50Cx1234`), but it also advertises over BLE under the same name, and BLE is what works:
  - The macOS serial port opened but never produced data (two 90–120 s attempts).
  - Direct IOBluetooth RFCOMM to channel 5 never completed its open (no success or error in 90 s).
  - BLE connected and streamed every reading. First connection took 64 s, the second 2.5 s.
- **Single client.** The device accepts one connection at a time. If the MeasureOn phone app is connected, the laptop cannot connect.

## Hardware check (2026-11-12, GLM 50 C, installed app)

Passed: auto-connect over the serial-pipe profile, single length, continuous (min/max), area (partial `0e` + result `12`, 1.7034 × 1.8226 = 3.1048), mode-change tracking (1 and 4), display unit independence. Not exercised: failed measurement (`0xFE`), so whether consecutive failures are byte-identical (and would be de-duplicated) is still unknown.

## Device protocol

### BLE profiles

The app scans for peripherals whose advertised name contains `GLM` (case-insensitive) or that advertise service `FDE8` (Bosch), then probes for these profiles in order:

| Profile | Service | Characteristic | Seen on | Status |
|---|---|---|---|---|
| Serial pipe | `00005301-0000-0041-5253-534F46540000` | `00004301-0000-0041-5253-534F46540000` (write + indicate) | GLM 50 C (author's device) | Verified 2026-11-12 |
| Bosch MT | `FDE8` (or as discovered) | `02a6c0d1-0451-4000-b000-fb3210111989` (write + indicate) | GLM 50-27 C / CG, GLM 120 C | Verified by others ([ketan/Bosch-GLM50C-Rangefinder](https://github.com/ketan/Bosch-GLM50C-Rangefinder), [CaveSurvey #150](https://github.com/lz1asl/CaveSurvey/issues/150)) |

Both profiles carry the same byte protocol. Session start: subscribe to indications on the characteristic, then write `c0 55 02 01 00 1a` (with response). This enables auto-sync. Without it the device sends nothing. The device replies with a short status frame that does not start with `c0` (observed: `00 10 02 09 b8 01 00 … ce`).

### Frames

Every measurement frame is 20 bytes. Frames can arrive split or joined, so the parser buffers and resyncs on the `c0 55 10` header.

```
offset  0  1  2  3     4      5-6          7-10    11-14   15-18   19
        c0 55 10 type  flags  seq (u16 LE) f32 LE  f32 LE  f32 LE  checksum
```

- `seq` is a little-endian counter that advances per measurement *operation*, not per frame. All frames of one multi-step operation share it (the wall-area frames `3a`, `3e`, `3e` all carry `0x01b9`), laser events reuse the neighboring seq, and the auto-sync ack carries the last one. Do not de-duplicate on seq. De-duplicate only a frame whose 20 bytes are identical to the previous frame's, which guards against indication retransmits and a keepalive making the device repeat itself.
- Values are metres regardless of the display unit. Verified 2026-11-12: with the display in fractional inches (0/32"), frames still carried metre values (e.g. `c0 55 10 06 08 c4 01 1f 63 ea 3f …` = 1.8311). The flags byte stayed `08` and does not encode the unit.
- Values are metres, m², or m³.
- The checksum algorithm is unknown (others brute-forced CRC-8 without success). Validate by header and length. Do not reject on checksum.

| Type | Meaning | Values | Source |
|---|---|---|---|
| `0x02` | laser on/off event | ignore | verified |
| `0x06` | single length | [distance] | verified |
| `0x0A` | continuous measurement result | [current, min, max] | verified |
| `0x0E` | area, first partial | [0, length, 0] | knulpi |
| `0x12` | area result | [area, length, width] | knulpi |
| `0x16` | volume, first partial | [0, length, 0] | knulpi |
| `0x1A` | volume, second partial | [0, length, 0] | knulpi |
| `0x1E` | volume result | [volume, third length, 0] | knulpi |
| `0x42` | addition result | [sum, a, b] | knulpi |
| `0x46` | subtraction result | [result, a, b] | knulpi |
| `0x4A` | area addition | [sum, a, b] m² | knulpi |
| `0x4E` | area subtraction | [result, a, b] m² | knulpi, unverified |
| `0xF2` | mode change | [mode id] (1 length, 2 continuous, 4 area, 7 volume) | verified (1, 2) |
| `0xFE` | measurement failed | [active mode id] | knulpi |
| `0x3A` | wall area: height (partial) | [0, height, 0] | seen 2026-11-12, inferred |
| `0x3E` | wall area: running result after each width | [total area m², this width, total width] | seen 2026-11-12, inferred (2.1293 × 2.2262 = 4.740; + 2.1293 × 2.18245 = 9.387; widths sum to 4.409) |

Other observed types on related devices (AdvancedDistance 50C, from CaveSurvey #150) such as `0x21` angle, `0x2A`/`0x2E` indirect height/horizontal, and `0x32`/`0x36` point-to-point may appear on the 50-27 variant and should decode the same way if seen.

Unknown types are stored and returned with their raw values and `kind: "unknown"`, never interpreted as a distance.

**Partial vs complete readings.** `area_partial`, `volume_partial`, and `wall_area_partial` are recorded and listed but are not "complete". `get_latest_measurement` and `wait_for_measurement` deal in complete readings (including `failed` and `unknown`); `list_measurements` returns everything.

### Remote trigger (optional)

`c0 56 01 00 1e` written twice fires a measurement on the GLM 120 C. One report says a similar Bosch 50C model does not support it. Expose it only if a probe shows it works on the connected device (see tools).

**Verified on the original GLM 50 C (2026-11-12):** the trigger works. The device sends a laser event, then a normal reading frame in its current mode, which the store records like a button press. Untested on the 50-27 C/CG.

### Other commands (verified on the original GLM 50 C, 2026-11-12)

The older Classic-Bluetooth command set (as documented by philipptrenz/BOSCH-GLM-rangefinder for the GLM 100 C) also works over the BLE serial-pipe characteristic. Replies to these use a short format, `<status> <length> <payload…> <checksum>`, separate from the 20-byte push frames; `00 00 82` is "OK, no payload".

| Command | Bytes | Reply | Observed effect |
|---|---|---|---|
| Laser pointer on | `c0 41 00 96` | `00 00 82` | Red dot on. No laser event frame is pushed. |
| Laser pointer off | `c0 42 00 1e` | `00 00 82` | Red dot off. |
| Backlight on | `c0 47 00 20` | `00 00 82` | Display backlight on. |
| Backlight off | `c0 48 00 62` | `00 00 82` | Display backlight off. |
| Measure (silent) | `c0 40 00 ee` | `00 04 <u32 LE> <crc>` | Returns a distance in 0.05 mm units without a push frame. One sample read 9.05 cm where the trigger read 19.46 cm, about the device's length less: likely measured from the front edge. Unconfirmed. |

### Stuck device (observed 2026-11-12)

After a link supervision timeout, the device kept accepting connections and GATT writes (no errors, notifications enabled) but never acknowledged auto-sync or pushed frames, even while the user measured. This lasted at least 14 minutes over a dozen reconnects. Power-cycling the device cleared it. No remote command is known to recover it; whether the commands above wake it is untested.

### Keepalive and reconnect

- If no data arrives for 30 s while connected, re-send the auto-sync command. The device acknowledges it, which proves the link is alive. If the write fails or nothing comes back within 10 s, drop the connection and reconnect. (This approach comes from knulpi/glm50c.)
- On disconnect, scan and reconnect indefinitely with backoff capped at about 5 s. Remember the last device's CoreBluetooth identifier and prefer it.
- First connection can take a minute. Show "Connecting…" rather than an error during that time.

### Classic fallback

The design has a transport abstraction (BLE now, Classic RFCOMM possible later). Classic is **not** in v1: both known variants work over BLE, and Classic did not respond on macOS in testing. Do not build it unless a device turns up that lacks BLE.

## The app

### Shape

- Swift 6, SwiftUI `MenuBarExtra`, no Dock icon (`LSUIElement`), macOS 14+.
- Bundle includes `NSBluetoothAlwaysUsageDescription`. Ad-hoc signing is fine for personal use.
- Launch at login via `SMAppService` (toggle in the menu, default on).

### Menu bar

- Icon shows state: disconnected / connecting / connected, and briefly flashes when a reading arrives.
- Menu contents: device name and connection state; the last reading (value, mode, age); the last ~10 readings; "Copy MCP URL"; "Clear history"; "Launch at login"; "Quit".
- No main window.

### Measurement store

- Each reading: `id` (UUID), `seq` (device counter), `timestamp` (receive time, ISO 8601 with offset), `kind` (`length`, `continuous`, `area`, `area_partial`, `volume`, `volume_partial`, `addition`, `subtraction`, `area_addition`, `area_subtraction`, `failed`, `unknown`), `type_code`, `value` (primary number, null for partials/failed), `unit` (`m`, `m2`, `m3`), `components` (named secondary values, e.g. `{length, width}` or `{min, max}`), `raw_hex`, `device_name`.
- Laser on/off events and mode changes are not readings. Mode changes update device status (current mode).
- Persist to an append-only JSON Lines file in `~/Library/Application Support/GLM MCP/measurements.jsonl` so readings survive restarts. "Clear history" starts a new file; old files are kept.

## MCP server

### Transport

- Streamable HTTP on `127.0.0.1` only, fixed default port `47650` (configurable), endpoint `/mcp`. Hosted by the app, so the Bluetooth connection lives in one place regardless of how many clients connect.
- Claude Code: `claude mcp add --transport http glm http://127.0.0.1:47650/mcp`.
- Claude Desktop (stdio config): `npx -y mcp-remote http://127.0.0.1:47650/mcp`.
- Use the official MCP Swift SDK if its server-side HTTP transport is solid. Otherwise implement the small subset needed (initialize, tools/list, tools/call, JSON-RPC over HTTP POST) with a lightweight HTTP server. Builder's call.

### Tools

Tool descriptions matter: they are how Claude knows to call these when the user says "I just measured…".

**`get_latest_measurement`**
- Use when the user says they just took a measurement.
- Input: none.
- Returns the newest complete reading plus `age_seconds`, and the device connection state. If there are no readings, it says so. If the device is disconnected, it says so and still returns the last reading with its age.

**`wait_for_measurement`**
- Use when the user is about to measure ("hold on, measuring now") or when the latest reading is older than the user implies.
- Input: `timeout_seconds` (default 30, max 55; many MCP clients cut tool calls off at about 60 s).
- Blocks until a new complete reading arrives (failed measurements count; partials do not), then returns it. Returns a timeout result if none arrives.

**`list_measurements`**
- Input: optional `since` (ISO time or reading id), optional `limit`.
- Returns readings newest first. With no arguments, returns the whole current history file.

**`get_device_status`**
- Returns connection state, device name, BLE profile in use, current mode (from the last mode-change frame), last-data time, and whether remote trigger is supported (`unknown` until probed).

**`trigger_measurement`** (only listed if supported)
- Fires the laser remotely and returns the resulting reading (like `wait_for_measurement`).
- Always listed, with a description saying it may not be supported. On first call, attempt the trigger. If no reading arrives within 5 s, mark it unsupported; later calls return "not supported on this device" immediately. (Changed during planning: removing the tool via `tools/list_changed` across live HTTP sessions wasn't worth the complexity.)

**`set_laser_pointer`**, **`set_backlight`** (added 2026-11-12)
- Input: `on` (boolean, required).
- Sends the matching command from "Other commands" and waits up to 2 s for the device's `00 00 82` OK. Errors: not connected, or no answer (ask the user to power-cycle the laser).

**Stuck detection.** Two connections in a row that reach "connected" but receive no bytes at all mark the device as stuck. Status `detail` then reads "The laser connects but isn't responding. Turn it off and on again." until any data arrives.

All tool results are JSON text content with readings in the store's shape, values in metres with a convenience `value_display` (e.g. `"2.271 m (89.4 in)"`) so Claude can speak either unit.

## Testing

- **Decoder:** pure function. Unit-test it with every frame captured in `docs/research/glm50c-ble-capture.log` and the published examples from CaveSurvey #150. Cover split and concatenated frames, the non-`c0` ack, unknown types, and garbage between frames.
- **Store and MCP:** test against a fake transport that replays captured frames; exercise every tool including `wait_for_measurement` timeout and the disconnected path.
- **GLM 50-27 C / CG:** best effort. The Bosch MT profile is implemented from published reports and covered by replayed-frame tests; no hardware is available.
- **Hardware:** manual checklist on a GLM 50 C: connect, single length, continuous, area, volume, failed measurement (aim at the sky), device sleep and wake, walk out of range and back, phone app holding the connection, app restart keeps history, display set to feet still yields metre values. Then call each tool from Claude Code.

## Left to the builder

- Project layout and build tooling (Xcode project or SwiftPM plus a bundling script), within the constraints above.
- MCP SDK versus hand-rolled server.
- Exact icon and menu styling.
- Logging (keep a debug log of raw frames, which is useful for decoding unknown types later).
