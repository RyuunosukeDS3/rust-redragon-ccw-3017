# install.ps1
# Run as Administrator: Right-click -> Run as Administrator

param(
    [switch]$Uninstall
)

$ServiceName = "RedragonLCD"
$DisplayName = "Redragon LCD Temperature Monitor"
$Description = "Displays CPU temperature on Redragon CCW-3017 LCD"
$LHMServiceName = "LibreHardwareMonitor"
$LHMDisplayName = "LibreHardwareMonitor"
$LHMUrl = "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest/download/LibreHardwareMonitor.zip"

# Check if running as Administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run PowerShell as Administrator!" -ForegroundColor Red
    Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
    exit 1
}

# Uninstall
if ($Uninstall) {
    Write-Host "Uninstalling Redragon LCD Monitor Service..." -ForegroundColor Yellow

    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName

    Stop-Service -Name $LHMServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $LHMServiceName

    $InstallDir = "$env:ProgramFiles\RedragonLCD"
    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $LHMInstallDir = "$env:ProgramFiles\LibreHardwareMonitor"
    if (Test-Path $LHMInstallDir) {
        Remove-Item -Path $LHMInstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "✓ Services uninstalled successfully!" -ForegroundColor Green
    exit 0
}

Write-Host "Installing Redragon LCD Monitor Service" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# ─── Step 1: LibreHardwareMonitor ────────────────────────────────────────────

Write-Host ""
Write-Host "[1/3] Setting up LibreHardwareMonitor..." -ForegroundColor Cyan

$LHMInstallDir = "$env:ProgramFiles\LibreHardwareMonitor"
$LHMExe = "$LHMInstallDir\LibreHardwareMonitor.exe"

$lhmService = Get-Service -Name $LHMServiceName -ErrorAction SilentlyContinue
if ($lhmService) {
    Write-Host "  LibreHardwareMonitor service already exists, skipping install." -ForegroundColor Green
} else {
    # Download LHM
    $TempDir = Join-Path $env:TEMP "RedragonLCD-install"
    if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

    $LHMZip = Join-Path $TempDir "lhm.zip"
    Write-Host "  Downloading LibreHardwareMonitor..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $LHMUrl -OutFile $LHMZip -ErrorAction Stop
        Write-Host "  ✓ Downloaded" -ForegroundColor Green
    } catch {
        Write-Host "  Failed to download LibreHardwareMonitor: $_" -ForegroundColor Red
        exit 1
    }

    # Extract
    if (-not (Test-Path $LHMInstallDir)) {
        New-Item -ItemType Directory -Path $LHMInstallDir -Force | Out-Null
    }
    Expand-Archive -Path $LHMZip -DestinationPath $LHMInstallDir -Force
    Write-Host "  ✓ Extracted to $LHMInstallDir" -ForegroundColor Green

    # LHM doesn't natively run as a service, so we wrap it with sc.exe
    # It accepts no special service flags but runs fine headless
    New-Service -Name $LHMServiceName `
        -BinaryPathName "`"$LHMExe`"" `
        -DisplayName $LHMDisplayName `
        -Description "Hardware monitoring service required by Redragon LCD Monitor" `
        -StartupType Automatic `
        -ErrorAction SilentlyContinue

    if (-not (Get-Service -Name $LHMServiceName -ErrorAction SilentlyContinue)) {
        Write-Host "  Failed to create LHM service!" -ForegroundColor Red
        exit 1
    }

    sc.exe failure $LHMServiceName reset=86400 actions=restart/5000/restart/10000/restart/30000
    Write-Host "  ✓ LibreHardwareMonitor service created" -ForegroundColor Green
}

# Start LHM and wait for its WMI namespace to be ready
Write-Host "  Starting LibreHardwareMonitor..." -ForegroundColor Yellow
Start-Service -Name $LHMServiceName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Verify WMI namespace is available
$wmiReady = $false
for ($i = 0; $i -lt 10; $i++) {
    try {
        $null = Get-WmiObject -Namespace "root\LibreHardwareMonitor" -Class Sensor -ErrorAction Stop
        $wmiReady = $true
        break
    } catch {
        Write-Host "  Waiting for LHM WMI namespace... ($($i+1)/10)" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
    }
}

if ($wmiReady) {
    Write-Host "  ✓ LibreHardwareMonitor WMI namespace is ready" -ForegroundColor Green
} else {
    Write-Host "  ⚠ LHM WMI namespace not detected — continuing anyway, may work after reboot" -ForegroundColor Yellow
}

# ─── Step 2: Download / build Redragon LCD binary ────────────────────────────

Write-Host ""
Write-Host "[2/3] Installing Redragon LCD binary..." -ForegroundColor Cyan

$TempDir = Join-Path $env:TEMP "RedragonLCD-install"
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
$BinaryUrl = "https://github.com/RyuunosukeDS3/rust-redragon-ccw-3017/releases/latest/download/ccw-3017-lcd-windows-amd64.exe"
$TempBinary = Join-Path $TempDir "redragon-lcd.exe"

try {
    Invoke-WebRequest -Uri $BinaryUrl -OutFile $TempBinary -ErrorAction Stop
    Write-Host "  ✓ Download complete" -ForegroundColor Green
} catch {
    Write-Host "  Download failed, attempting to build from source..." -ForegroundColor Yellow

    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        Write-Host "  Cargo not found! Please install Rust or download binary manually." -ForegroundColor Red
        exit 1
    }

    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    Set-Location $ScriptDir
    cargo build --release

    if (Test-Path "target\release\redragon-lcd.exe") {
        Copy-Item "target\release\redragon-lcd.exe" -Destination $TempBinary -Force
        Write-Host "  ✓ Build complete" -ForegroundColor Green
    } else {
        Write-Host "  Build failed!" -ForegroundColor Red
        exit 1
    }
}

$InstallDir = "$env:ProgramFiles\RedragonLCD"
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
Copy-Item -Path $TempBinary -Destination "$InstallDir\redragon-lcd.exe" -Force
Write-Host "  ✓ Binary installed to $InstallDir" -ForegroundColor Green

# ─── Step 3: Install Redragon LCD service ────────────────────────────────────

Write-Host ""
Write-Host "[3/3] Creating Redragon LCD service..." -ForegroundColor Cyan

$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "  Service already exists, removing..." -ForegroundColor Yellow
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName
    Start-Sleep -Seconds 2
}

New-Service -Name $ServiceName `
    -BinaryPathName "$InstallDir\redragon-lcd.exe" `
    -DisplayName $DisplayName `
    -Description $Description `
    -StartupType Automatic `
    -ErrorAction SilentlyContinue

# Make RedragonLCD depend on LHM so Windows always starts LHM first
sc.exe config $ServiceName depend= $LHMServiceName
sc.exe failure $ServiceName reset=86400 actions=restart/5000/restart/10000/restart/30000

Write-Host "  ✓ Service created with dependency on LibreHardwareMonitor" -ForegroundColor Green

Write-Host "  Starting service..." -ForegroundColor Yellow
Start-Service -Name $ServiceName
Start-Sleep -Seconds 2

$service = Get-Service -Name $ServiceName
if ($service.Status -eq 'Running') {
    Write-Host ""
    Write-Host "✓ All done! Both services are running." -ForegroundColor Green
    Write-Host ""
    Write-Host "Service Information:" -ForegroundColor Cyan
    Write-Host "  $LHMServiceName  -> $((Get-Service $LHMServiceName).Status)"
    Write-Host "  $ServiceName     -> $($service.Status)"
    Write-Host ""
    Write-Host "Commands:" -ForegroundColor Yellow
    Write-Host "  .\install.ps1 -Uninstall   - Remove both services"
    Write-Host "  Get-Service $ServiceName   - Check status"
} else {
    Write-Host "✗ Redragon LCD service failed to start. Status: $($service.Status)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Check Event Viewer for errors"
    Write-Host "  2. Run manually: $InstallDir\redragon-lcd.exe"
    Write-Host "  3. Make sure the USB device is connected"
    Write-Host "  4. Check if antivirus is blocking the service"
    exit 1
}

Remove-Item $TempDir -Recurse -Force
Write-Host "Installation complete!" -ForegroundColor Green