# /// script
# requires-python = ">=3.11"
# dependencies = ["pyserial"]
# ///
"""Throwaway spike: open the GLM50C's macOS Bluetooth serial port, enable push mode, print frames."""
import struct
import sys
import time

import serial

PORT = sys.argv[1] if len(sys.argv) > 1 else "/dev/cu.BoschGLM50Cx1234"
SECONDS = float(sys.argv[2]) if len(sys.argv) > 2 else 120

print(f"opening {PORT} ...", flush=True)
t0 = time.time()
s = serial.Serial(PORT, 9600, timeout=1)
print(f"opened in {time.time() - t0:.1f}s; enabling auto-sync", flush=True)
s.write(bytes([0xC0, 0x55, 0x02, 0x01, 0x00, 0x1A]))

buf = b""
end = time.time() + SECONDS
while time.time() < end:
    chunk = s.read(64)
    if not chunk:
        continue
    print("RX", chunk.hex(" "), flush=True)
    buf += chunk
    while True:
        i = buf.find(b"\xc0\x55\x10")
        if i < 0 or len(buf) - i < 20:
            break
        frame, buf = buf[i:i + 20], buf[i + 20:]
        vals = struct.unpack("<3f", frame[7:19])
        print(f"  FRAME type=0x{frame[3]:02x} values={[round(v, 4) for v in vals]}", flush=True)
print("done", flush=True)
