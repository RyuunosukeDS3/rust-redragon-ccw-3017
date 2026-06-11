# install.ps1
param([switch]$Uninstall)

$SVC="RedragonLCD"
$LHM="LibreHardwareMonitor"
$DIR="$env:ProgramFiles\RedragonLCD"
$TMP="$env:TEMP\redragonlcd"
$BIN="$DIR\redragon-lcd.exe"

function rm-svc($n){
    Stop-Service $n -Force -ErrorAction SilentlyContinue
    sc.exe delete $n | Out-Null
}

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole("Administrator")) { echo "Run as admin"; exit 1 }

if ($Uninstall) {
    rm-svc $SVC; rm-svc $LHM
    Remove-Item $DIR,$TMP -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}

New-Item $TMP -Force -ItemType Directory | Out-Null
New-Item $DIR -Force -ItemType Directory | Out-Null

# ── LibreHardwareMonitor ─────────────────────────────
if (-not (Get-Service $LHM -ErrorAction SilentlyContinue)) {
    $zip="$TMP\lhm.zip"
    try { Invoke-WebRequest "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/latest/download/LibreHardwareMonitor.zip" -OutFile $zip -ErrorAction Stop }
    catch { echo "LHM download failed"; exit 1 }

    Expand-Archive $zip "$env:ProgramFiles\LibreHardwareMonitor" -Force

    New-Service $LHM "$env:ProgramFiles\LibreHardwareMonitor\LibreHardwareMonitor.exe" -StartupType Automatic
    sc.exe failure $LHM reset=86400 actions=restart/5000 | Out-Null
}

Start-Service $LHM -ErrorAction SilentlyContinue

# ── Redragon binary ──────────────────────────────────
$url="https://github.com/RyuunosukeDS3/rust-redragon-ccw-3017/releases/latest/download/ccw-3017-lcd-windows-amd64.exe"
$dl="$TMP\lcd.exe"

try {
    Invoke-WebRequest $url -OutFile $dl -ErrorAction Stop
} catch {
    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
        echo "Need cargo for fallback build"; exit 1
    }
    Set-Location $PSScriptRoot
    cargo build --release
    $dl="target\release\redragon-lcd.exe"
}

Copy-Item $dl $BIN -Force

# ── Service ──────────────────────────────────────────
rm-svc $SVC

New-Service $SVC $BIN -StartupType Automatic
sc.exe config $SVC depend= $LHM | Out-Null
sc.exe failure $SVC reset=86400 actions=restart/5000 | Out-Null

Start-Service $SVC

if ((Get-Service $SVC).Status -ne "Running") {
    echo "Service failed"; exit 1
}

Remove-Item $TMP -Recurse -Force
echo "OK: running"