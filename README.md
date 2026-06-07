# rust-redragon-ccw-3017

A lightweight Rust binary that displays your CPU temperature on the Redragon CCW-3017 AIO watercooler LCD screen.

## Why this exists

- **Linux support** – The official software doesn't work on Linux at all.
- **Windows alternative** – No ring0 kernel drivers, no invasive background processes, no bloat.
- **Simple** – Does one thing: puts your CPU temp on the screen.

## Requirements

- Redragon CCW-3017 AIO watercooler
- Linux or Windows

## Installation as a Service

### Linux
```bash
curl -sSL https://raw.githubusercontent.com/RyuunosukeDS3/rust-redragon-ccw-3017/main/install.sh | sudo bash
```

### Windows (Run PowerShell as Administrator)
```powershell
iex (irm https://raw.githubusercontent.com/RyuunosukeDS3/rust-redragon-ccw-3017/main/install.ps1)
```

## Uninstall

### Linux
```bash
curl -sSL https://raw.githubusercontent.com/RyuunosukeDS3/rust-redragon-ccw-3017/main/install.sh | sudo bash -s uninstall
```

### Windows (Run PowerShell as Administrator)
```powershell
iex (irm https://raw.githubusercontent.com/RyuunosukeDS3/rust-redragon-ccw-3017/main/install.ps1 -Uninstall)
```

## How it works

- Communicates directly with the AIO over USB/HID
- Reads CPU temperature from system sensors
- Updates the LCD screen every 2 seconds