#!/bin/bash
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log(){ echo -e "$1$2$NC"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

if [[ "$1" == "uninstall" || "$1" == "-u" ]]; then
  log $YELLOW "Uninstalling Redragon LCD"
  sudo systemctl stop redragon-lcd 2>/dev/null || true
  sudo systemctl disable redragon-lcd 2>/dev/null || true
  sudo rm -f /usr/local/bin/redragon-lcd \
             /etc/systemd/system/redragon-lcd.service \
             /etc/udev/rules.d/99-redragon-lcd.rules
  sudo systemctl daemon-reload
  sudo udevadm control --reload-rules
  log $GREEN "✓ Uninstalled"
  exit 0
fi

for c in curl sudo systemctl udevadm; do command -v $c >/dev/null || { log $RED "Missing $c"; exit 1; }; done

URL="https://github.com/RyuunosukeDS3/rust-redragon-ccw-3017/releases/latest/download/redragon-lcd-linux-amd64"
BIN="$TMP/redragon-lcd"

log $GREEN "Downloading binary..."
if ! curl -fL "$URL" -o "$BIN"; then
  log $YELLOW "Fallback build..."
  command -v cargo >/dev/null || { log $RED "cargo missing"; exit 1; }
  cd "$SCRIPT_DIR" && cargo build --release
  BIN="$SCRIPT_DIR/target/release/redragon-lcd"
fi

file "$BIN" | grep -q ELF || { log $RED "Invalid binary"; exit 1; }

log $GREEN "Installing binary..."
sudo systemctl stop redragon-lcd 2>/dev/null || true
sudo install -m 755 "$BIN" /usr/local/bin/redragon-lcd

# libudev
if ! ldconfig -p 2>/dev/null | grep -q libudev; then
  log $YELLOW "Installing libudev..."
  command -v pacman >/dev/null && sudo pacman -S --noconfirm systemd-libs
  command -v apt-get >/dev/null && sudo apt-get update -qq && sudo apt-get install -y libudev1
  command -v dnf >/dev/null && sudo dnf install -y systemd-libs
fi

log $GREEN "Configuring service + udev..."

sudo tee /etc/systemd/system/redragon-lcd.service >/dev/null <<EOF
[Unit]
Description=Redragon LCD
After=network.target

[Service]
ExecStart=/usr/local/bin/redragon-lcd
Restart=always
RestartSec=5
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

echo 'SUBSYSTEM=="usb", ATTRS{idVendor}=="5131", ATTRS{idProduct}=="2007", MODE="0666"' \
| sudo tee /etc/udev/rules.d/99-redragon-lcd.rules >/dev/null

sudo systemctl daemon-reload
sudo systemctl enable --now redragon-lcd
sudo udevadm control --reload-rules && sudo udevadm trigger

sleep 2

if systemctl is-active --quiet redragon-lcd; then
  log $GREEN "✓ Running"
  systemctl status redragon-lcd --no-pager
else
  log $RED "Failed"
  echo "journalctl -u redragon-lcd -n 50"
  exit 1
fi

log $GREEN "✓ Installed"
echo "restart: sudo systemctl restart redragon-lcd"
echo "logs:    journalctl -u redragon-lcd -f"