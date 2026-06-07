#!/bin/bash

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for install or uninstall flag
if [ "$1" == "uninstall" ] || [ "$1" == "-u" ]; then
    echo -e "${YELLOW}Uninstalling Redragon LCD Monitor Service${NC}"
    
    # Stop and disable service
    sudo systemctl stop redragon-lcd.service 2>/dev/null || true
    sudo systemctl disable redragon-lcd.service 2>/dev/null || true
    
    # Remove service file
    sudo rm -f /etc/systemd/system/redragon-lcd.service
    
    # Remove binary
    sudo rm -f /usr/local/bin/redragon-lcd
    
    # Remove udev rule
    sudo rm -f /etc/udev/rules.d/99-redragon-lcd.rules
    
    # Reload systemd and udev
    sudo systemctl daemon-reload
    sudo udevadm control --reload-rules
    
    echo -e "${GREEN}✓ Uninstall complete${NC}"
    exit 0
fi

# Install script
echo -e "${GREEN}Installing Redragon LCD Monitor Service${NC}"

# Check for required commands
for cmd in curl cargo sudo systemctl; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd not found${NC}"
        exit 1
    fi
done

# Create temp directory for download
TMP_DIR=$(mktemp -d)
cd $TMP_DIR

# Download latest binary from GitHub releases
echo -e "${GREEN}Downloading latest binary...${NC}"
curl -sSL -o redragon-lcd https://github.com/RyuunosukeDS3/rust-redragon-ccw-3017/releases/latest/download/ccw-3017-lcd-linux-amd64

# Make binary executable
chmod +x redragon-lcd

# Check if download was successful
if [ ! -f "$TMP_DIR/redragon-lcd" ]; then
    echo -e "${RED}Error: Failed to download binary${NC}"
    echo -e "${YELLOW}Falling back to local build...${NC}"
    cd "$SCRIPT_DIR"
    if [ ! -f "target/release/redragon-lcd" ]; then
        cargo build --release
    fi
    BINARY_PATH="$SCRIPT_DIR/target/release/redragon-lcd"
else
    BINARY_PATH="$TMP_DIR/redragon-lcd"
fi

# Copy binary to system location
echo -e "${GREEN}Copying binary to /usr/local/bin/${NC}"
sudo cp "$BINARY_PATH" /usr/local/bin/redragon-lcd
sudo chmod 755 /usr/local/bin/redragon-lcd

# Check and install runtime dependencies
echo -e "${GREEN}Checking dependencies...${NC}"

# Check for libudev
if ! ldconfig -p | grep -q libudev; then
    echo -e "${YELLOW}libudev not found, installing...${NC}"
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -qq
        sudo apt-get install -y libudev1
    elif command -v yum &> /dev/null; then
        sudo yum install -y libudev
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm systemd-libs
    else
        echo -e "${RED}Error: Cannot install libudev. Please install manually${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ libudev found${NC}"
fi

# Create systemd service file
echo -e "${GREEN}Creating systemd service...${NC}"
sudo tee /etc/systemd/system/redragon-lcd.service > /dev/null << 'EOF'
[Unit]
Description=Redragon LCD Temperature Monitor
After=multi-user.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/local/bin/redragon-lcd
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
Environment="RUST_BACKTRACE=1"

# Security
NoNewPrivileges=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

# Set proper permissions on service file
sudo chmod 644 /etc/systemd/system/redragon-lcd.service

# Create udev rule for device permissions
echo -e "${GREEN}Setting up udev rules...${NC}"
sudo tee /etc/udev/rules.d/99-redragon-lcd.rules > /dev/null << 'EOF'
# Redragon CCW-3017 LCD
SUBSYSTEM=="usb", ATTRS{idVendor}=="5131", ATTRS{idProduct}=="2007", MODE="0666", GROUP="plugdev"
EOF

# Set proper permissions on udev rule
sudo chmod 644 /etc/udev/rules.d/99-redragon-lcd.rules

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

# Add current user to plugdev group if not already
if ! groups $USER | grep -q plugdev; then
    echo -e "${YELLOW}Adding $USER to plugdev group (requires logout)${NC}"
    sudo usermod -a -G plugdev $USER
fi

# Reload systemd and enable service
sudo systemctl daemon-reload
sudo systemctl enable redragon-lcd.service

# Start the service
echo -e "${GREEN}Starting service...${NC}"
sudo systemctl start redragon-lcd.service

# Check status
sleep 2
if sudo systemctl is-active --quiet redragon-lcd.service; then
    echo -e "${GREEN}✓ Service is running!${NC}"
    sudo systemctl status redragon-lcd.service --no-pager
else
    echo -e "${RED}✗ Service failed to start${NC}"
    echo -e "${YELLOW}Check logs: sudo journalctl -u redragon-lcd.service -n 50${NC}"
    exit 1
fi

# Cleanup temp directory
rm -rf $TMP_DIR

echo -e "\n${GREEN}✓ Service installed successfully!${NC}"
echo -e "${YELLOW}Commands:${NC}"
echo "  sudo systemctl status redragon-lcd  - Check status"
echo "  sudo systemctl restart redragon-lcd - Restart service"
echo "  sudo systemctl stop redragon-lcd    - Stop service"
echo "  sudo journalctl -u redragon-lcd -f  - View logs"
echo "  $0 uninstall                        - Uninstall service"
echo -e "${YELLOW}Note: Log out and back in for USB permissions to take effect${NC}"