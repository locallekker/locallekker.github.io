# Local Lekker - Quick Run Script
# This script runs the app after setting up Flutter PATH

Write-Host "=== Local Lekker App Launcher ===" -ForegroundColor Green
Write-Host ""

# Set Flutter PATH
$env:PATH = "C:\src\flutter\bin;C:\Users\clyde\AppData\Local\Android\sdk\platform-tools;$env:PATH"

# Check for connected devices
Write-Host "Checking for devices..." -ForegroundColor Yellow
$devices = flutter devices 2>&1

# Check if Android device is connected
if ($devices -match "android") {
    Write-Host "Android device detected! Running on Android..." -ForegroundColor Green
    flutter run
} else {
    Write-Host "No Android device detected. Running on Windows Desktop..." -ForegroundColor Yellow
    flutter run -d windows
}
