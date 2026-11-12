# GLM MCP

Talk to Claude while you measure. GLM MCP is a small macOS menu bar app that keeps a Bluetooth
connection to a **Bosch GLM 50 C** laser measure and serves its readings to Claude (or any MCP
client) through a local [MCP](https://modelcontextprotocol.io) server.

> Press the measure button, then say: *"I just measured the hallway, add it to the floor plan."*
> Claude calls `get_latest_measurement` and gets `2.271 m (89.4 in)`.

The app doesn't label or organize anything; Claude does that. It just stays connected, captures
every reading accurately, and hands it over when asked.

> **Unofficial.** Not affiliated with, endorsed by, or supported by Robert Bosch GmbH. "Bosch" and
> "GLM" are trademarks of their owners. The Bluetooth protocol was reverse engineered by the
> community (see [Credits](#credits)).

## Requirements

- macOS 14 or later (Apple Silicon or Intel)
- A Bosch GLM 50 C. The GLM 50-27 C / CG should also work (same protocol, different Bluetooth
  profile) but hasn't been tested on hardware yet. [Reports welcome.](../../issues/new?template=new-device.md)

## Install

### Download

1. Download `GLM-MCP-<version>.zip` from [Releases](../../releases) and unzip it.
2. Move **GLM MCP.app** to Applications.
3. Open it. Because the app isn't notarized by Apple, macOS will block it the first time:
   open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to
   "GLM MCP was blocked". (On older macOS: right-click the app → **Open** → **Open**.)
4. Allow Bluetooth when asked.

A ruler icon appears in the menu bar. The app starts at login (toggle it in the menu).

### Build from source

Needs Apple's Command Line Tools (`xcode-select --install`) or Xcode.

```sh
git clone https://github.com/emlama/glm-mcp && cd glm-mcp
scripts/bundle.sh --install      # builds, signs ad hoc, copies to ~/Applications
open ~/Applications/GLM\ MCP.app
```

## Connect the laser

Turn the GLM on and press its **Bluetooth** button. The menu should show
"Bosch GLM50C xXXXX — Connected". No pairing in System Settings is needed.

- The device accepts **one** connection: disconnect the Bosch MeasureOn phone app first.
- The first connection can take up to a minute; after that it reconnects on its own when the
  device wakes up.

## Connect Claude

The server runs at `http://127.0.0.1:47650/mcp` (localhost only) whenever the app is running.

**Claude Code**

```sh
claude mcp add --scope user --transport http glm http://127.0.0.1:47650/mcp
```

**Claude Desktop** — add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "glm": { "command": "npx", "args": ["-y", "mcp-remote", "http://127.0.0.1:47650/mcp"] }
  }
}
```

Any other MCP client that speaks Streamable HTTP can use the URL directly ("Copy MCP URL" in the menu).

## Tools

| Tool | What it does |
|---|---|
| `get_latest_measurement` | The newest completed reading, with `age_seconds` so Claude can tell if it's stale. |
| `wait_for_measurement` | Waits (up to 55 s) for the next button press and returns that reading. |
| `list_measurements` | History, newest first. Optional `since` (ISO time or reading id) and `limit`. |
| `get_device_status` | Connection state, current mode, last data time. |
| `trigger_measurement` | Fires the laser remotely. Not supported by every model; returns an error if not. |

A reading looks like:

```json
{
  "kind": "area",
  "value": 3.1048,
  "unit": "m2",
  "value_display": "3.105 m² (33.4 ft²)",
  "components": { "length": 1.7034, "width": 1.8226 },
  "age_seconds": 4,
  "timestamp": "2026-11-12T23:21:58.112Z",
  "raw_hex": "c0 55 10 12 08 c2 01 ee b4 46 40 a6 0a da 3f 98 4c e9 3f 20"
}
```

Values are always metres (m, m², m³), whatever unit the device display is set to; `value_display`
adds an imperial equivalent. Supported kinds: `length`, `continuous` (with min/max), `area`,
`volume`, `wall_area`, `addition`, `subtraction`, `area_addition`, `area_subtraction`, `failed`.
Steps of multi-press modes are recorded as `*_partial`; `wait_for_measurement` returns only the
final result. Anything the app doesn't recognize is stored as `unknown` with raw values, never as
a distance.

History is kept in `~/Library/Application Support/GLM MCP/measurements.jsonl`. "Clear History" in
the menu archives it to a dated file.

## Troubleshooting

- **Stuck on "Searching for laser…":** make sure the GLM's Bluetooth icon is on and the phone app
  isn't connected. Toggle the GLM's Bluetooth off and on.
- **"Bluetooth permission denied":** System Settings → Privacy & Security → Bluetooth → enable GLM MCP.
- **"MCP server couldn't start":** another copy of the app is running, or something else uses port 47650.
- **See raw Bluetooth frames:**
  `log stream --predicate 'subsystem == "io.github.emlama.glm-mcp"' --level debug`

## How it works

```
GLM 50 C ──BLE indications──▶ BLELink ─▶ FrameParser ─▶ interpret ─▶ MeasurementStore (JSONL)
                                                                          │
Claude ◀── Streamable HTTP (127.0.0.1:47650/mcp) ◀── MCP server ◀── GLMTools
```

Each button press makes the device send a 20-byte frame: `c0 55 10 <type> <flags> <seq> <3 × float32 LE> <checksum>`.
[docs/design.md](docs/design.md) has the full protocol table, design decisions and hardware test
results; [docs/research/](docs/research/) has the original exploration code and a raw capture.

## Development

```sh
scripts/swiftw test     # 53 tests: frame parsing, decoding, store, tools, HTTP server
scripts/bundle.sh       # build/GLM MCP.app
```

`scripts/swiftw` is a thin wrapper around `swift` that makes `swift test` work with only the
Command Line Tools installed (and works around a stale-file problem some CLT installs have).
With Xcode, plain `swift test` works too.

Layout: `GLMCore` (protocol + store, pure Swift), `GLMBluetooth` (CoreBluetooth), `GLMServer`
(MCP tools + HTTP), `GLMApp` (menu bar app).

**New device or mode?** The most useful contribution is a capture: open an
[issue](../../issues/new?template=new-device.md) with the model, the mode, what the screen showed,
and the raw frames.

## Credits

- Protocol notes: [knulpi/glm50c](https://github.com/knulpi/glm50c) (frame types, keepalive),
  [ketan/Bosch-GLM50C-Rangefinder](https://github.com/ketan/Bosch-GLM50C-Rangefinder) (BLE on macOS),
  and the contributors to [lz1asl/CaveSurvey#150](https://github.com/lz1asl/CaveSurvey/issues/150).
- MCP: [modelcontextprotocol/swift-sdk](https://github.com/modelcontextprotocol/swift-sdk); the
  HTTP adapter is adapted from its conformance server.

## License

[MIT](LICENSE)
