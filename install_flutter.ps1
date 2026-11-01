# Flutter Installation Helper Script
# Run this script after downloading Flutter

Write-Host "=== Flutter Installation Helper ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check if Flutter ZIP is downloaded
$downloadsPath = "$env:USERPROFILE\Downloads"
$flutterZip = Get-ChildItem $downloadsPath -Filter "flutter_windows_*.zip" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($flutterZip) {
    Write-Host "[OK] Found Flutter ZIP: $($flutterZip.Name)" -ForegroundColor Green
    $useDownloaded = Read-Host "Extract this file? (Y/N)"
    
    if ($useDownloaded -eq 'Y' -or $useDownloaded -eq 'y') {
        # Step 2: Extract Flutter
        $extractPath = "C:\src"
        if (-not (Test-Path $extractPath)) {
            New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
            Write-Host "[OK] Created directory: $extractPath" -ForegroundColor Green
        }
        
        Write-Host "Extracting Flutter to $extractPath..." -ForegroundColor Yellow
        Expand-Archive -Path $flutterZip.FullName -DestinationPath $extractPath -Force
        Write-Host "[OK] Flutter extracted successfully!" -ForegroundColor Green
        
        $flutterBinPath = "$extractPath\flutter\bin"
        
        # Step 3: Add to PATH (current session)
        $env:PATH = "$flutterBinPath;$env:PATH"
        Write-Host "[OK] Added Flutter to PATH for this session" -ForegroundColor Green
        
        # Step 4: Add to User PATH permanently
        Write-Host ""
        $addToPermanentPath = Read-Host "Add Flutter to your permanent PATH? (Y/N)"
        if ($addToPermanentPath -eq 'Y' -or $addToPermanentPath -eq 'y') {
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($userPath -notlike "*$flutterBinPath*") {
                [Environment]::SetEnvironmentVariable("Path", "$userPath;$flutterBinPath", "User")
                Write-Host "[OK] Flutter added to permanent PATH" -ForegroundColor Green
                Write-Host "  (Restart terminal for permanent PATH to take effect)" -ForegroundColor Yellow
            } else {
                Write-Host "[OK] Flutter already in permanent PATH" -ForegroundColor Green
            }
        }
        
        # Step 5: Run flutter doctor
        Write-Host ""
        Write-Host "Running 'flutter doctor' to check installation..." -ForegroundColor Yellow
        & "$flutterBinPath\flutter.bat" doctor
        
        # Step 6: Update project configuration
        Write-Host ""
        Write-Host "Updating project configuration..." -ForegroundColor Yellow
        $localPropsPath = "android\local.properties"
        if (Test-Path $localPropsPath) {
            $content = Get-Content $localPropsPath
            $newContent = $content -replace 'flutter\.sdk=.*', "flutter.sdk=$extractPath\flutter"
            $newContent | Set-Content $localPropsPath
            Write-Host "[OK] Updated android\local.properties" -ForegroundColor Green
        }
        
        Write-Host ""
        Write-Host "=== Installation Complete! ===" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "1. Accept Android licenses: flutter doctor --android-licenses"
        Write-Host "2. Connect your Android device"
        Write-Host "3. Run the app: flutter run"
        Write-Host ""
        
    } else {
        Write-Host "Installation cancelled." -ForegroundColor Yellow
    }
} else {
    Write-Host "No Flutter ZIP found in Downloads folder." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please download Flutter from:" -ForegroundColor Cyan
    Write-Host "https://docs.flutter.dev/get-started/install/windows/mobile" -ForegroundColor White
    Write-Host ""
    Write-Host "After downloading, run this script again." -ForegroundColor Yellow
}

Write-Host ""
Read-Host "Press Enter to exit"

