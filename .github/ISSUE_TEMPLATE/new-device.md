---
name: Device support / unknown frames
about: Report a Bosch laser measure model or measurement mode that doesn't work
labels: device support
---

**Model** (from the label, e.g. GLM 50 C, GLM 50-27 CG, GLM 100 C):

**What happens** (doesn't connect / connects but no readings / reading shows as `unknown`):

**Measurement mode you used** (length, area, wall area, angle…), and what the device screen showed:

**Raw frames** — run this, take the measurement, and paste the output:

```sh
log stream --predicate 'subsystem == "io.github.emlama.glm-mcp"' --level debug
```

Or paste `raw_hex` values from `list_measurements`.
