Got it! Here's the updated README:

---

# ccw-3017-lcd

A lightweight Rust binary that displays your CPU temperature on the Redragon CCW-3017 AIO watercooler LCD screen.

## Why this exists

- **Linux support** – The official software doesn't work on Linux at all.
- **Windows alternative** – No ring0 kernel drivers, no invasive background processes, no bloat.
- **Simple** – Does one thing: puts your CPU temp on the screen.

## Requirements

- Redragon CCW-3017 AIO watercooler
- Linux or Windows

## Installation

Download the latest binary for your OS from the [Releases](https://github.com/ryuunosukeds3/rust-redragon-ccw-3017/releases) page.

### Linux

```bash
chmod +x ccw-3017-lcd
./ccw-3017-lcd
```

You may need permissions to access the USB device. Add a udev rule or run with `sudo`.

### Windows

Just double-click the `.exe` file.

No admin required. No kernel drivers.

## Usage

```bash
./ccw-3017-lcd
```

The binary will detect your CCW-3017 and start sending live CPU temperature data to its LCD.

Press `Ctrl+C` to stop.

## How it works

- Communicates directly with the AIO over USB/HID
- Reads CPU temperature from system sensors (`coretemp` on Linux, Windows API on Windows)
- Updates the LCD screen at a configurable interval

## Limitations

- Only displays CPU package temperature (for now)
- No customization of colors or layout yet

## License

MIT

---

Want me to add a "Building from source" section for people who prefer that, or keep it release-only?