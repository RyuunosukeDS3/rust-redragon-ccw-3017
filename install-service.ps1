# install.ps1
# Run as Administrator: Right-click -> Run as Administrator

param(
    [switch]$Uninstall
)

$ServiceName = "RedragonLCD"
$DisplayName = "Redragon LCD Temperature Monitor"
$Description = "Displays CPU temperature on Redragon CCW-3017 LCD"

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run PowerShell as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Uninstall
if ($Uninstall) {
    Write-Host "Uninstalling Redragon LCD Monitor Service..." -ForegroundColor Yellow
    
    # Stop and remove service
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName
    
    # Remove installation directory
    $InstallDir = "$env:ProgramFiles\RedragonLCD"
    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    Write-Host "✓ Service uninstalled successfully!" -ForegroundColor Green
    exit 0
}

# Install script
Write-Host "Installing Redragon LCD Monitor Service" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Create temp directory for download
$TempDir = Join-Path $env:TEMP "RedragonLCD-install"
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# Download latest binary from GitHub releases
Write-Host "Downloading latest binary..." -ForegroundColor Yellow
$BinaryUrl = "https://github.com/RyuunosukeDS3/rust-redragon-ccw-3017/releases/latest/download/ccw-3017-lcd-windows-amd64.exe"
$TempBinary = Join-Path $TempDir "redragon-lcd.exe"

try {
    Invoke-WebRequest -Uri $BinaryUrl -OutFile $TempBinary -ErrorAction Stop
    Write-Host "✓ Download complete" -ForegroundColor Green
} catch {
    Write-Host "Failed to download binary: $_" -ForegroundColor Red
    Write-Host "Attempting to build from source..." -ForegroundColor Yellow
    
    # Check if cargo is available
    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        Write-Host "Cargo not found! Please install Rust or download binary manually" -ForegroundColor Red
        exit 1
    }
    
    # Build from source
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    Set-Location $ScriptDir
    cargo build --release
    
    if (Test-Path "target\release\redragon-lcd.exe") {
        Copy-Item "target\release\redragon-lcd.exe" -Destination $TempBinary -Force
        Write-Host "✓ Build complete" -ForegroundColor Green
    } else {
        Write-Host "Build failed!" -ForegroundColor Red
        exit 1
    }
}

# Verify binary downloaded/built successfully
if (-not (Test-Path $TempBinary)) {
    Write-Host "Binary not found!" -ForegroundColor Red
    exit 1
}

# Create installation directory
$InstallDir = "$env:ProgramFiles\RedragonLCD"
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Write-Host "Created installation directory: $InstallDir" -ForegroundColor Green
}

# Copy binary to installation directory
Copy-Item -Path $TempBinary -Destination "$InstallDir\redragon-lcd.exe" -Force
Write-Host "✓ Binary installed to $InstallDir" -ForegroundColor Green

# Check if service already exists
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Service already exists, removing..." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName
    Start-Sleep -Seconds 2
}

# Create Windows service
Write-Host "Creating Windows service..." -ForegroundColor Yellow
New-Service -Name $ServiceName `
    -BinaryPathName "$InstallDir\redragon-lcd.exe" `
    -DisplayName $DisplayName `
    -Description $Description `
    -StartupType Automatic `
    -ErrorAction SilentlyContinue

if (-not (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)) {
    Write-Host "Failed to create service!" -ForegroundColor Red
    exit 1
}

# Configure recovery options
Write-Host "Configuring service recovery options..." -ForegroundColor Yellow
sc.exe failure $ServiceName reset=86400 actions=restart/5000/restart/10000/restart/30000

# Start the service
Write-Host "Starting service..." -ForegroundColor Yellow
Start-Service -Name $ServiceName

# Check status
Start-Sleep -Seconds 2
$service = Get-Service -Name $ServiceName

if ($service.Status -eq 'Running') {
    Write-Host ""
    Write-Host "✓ Service is running!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Service Information:" -ForegroundColor Cyan
    Write-Host "  Name:        $($service.Name)"
    Write-Host "  DisplayName: $($service.DisplayName)"
    Write-Host "  Status:      $($service.Status)"
    Write-Host "  StartType:   $($service.StartType)"
    Write-Host ""
    Write-Host "Commands (run PowerShell as Administrator):" -ForegroundColor Yellow
    Write-Host "  Start-Service $ServiceName     - Start service"
    Write-Host "  Stop-Service $ServiceName      - Stop service"
    Write-Host "  Get-Service $ServiceName       - Check status"
    Write-Host "  .\install.ps1 -Uninstall       - Uninstall service"
    Write-Host ""
    Write-Host "Or using CMD:" -ForegroundColor Yellow
    Write-Host "  net start $ServiceName         - Start service"
    Write-Host "  net stop $ServiceName          - Stop service"
    Write-Host "  sc query $ServiceName          - Check status"
} else {
    Write-Host "✗ Service failed to start. Status: $($service.Status)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
    Write-Host "  1. Check Event Viewer for errors"
    Write-Host "  2. Try running the binary manually: $InstallDir\redragon-lcd.exe"
    Write-Host "  3. Make sure the USB device is connected"
    Write-Host "  4. Check if antivirus is blocking the service"
    exit 1
}

# Cleanup temp directory
Remove-Item $TempDir -Recurse -Force

Write-Host "Installation complete!" -ForegroundColor Green