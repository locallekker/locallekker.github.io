# Generate Release Keystore for Local Lekker App (PowerShell)
# Run this script ONCE to create your release keystore
# Keep the keystore file and passwords SECURE - you cannot recover them!

Write-Host "🔐 Local Lekker Release Keystore Generator" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "⚠️  IMPORTANT:" -ForegroundColor Yellow
Write-Host "   - Store the keystore file securely (backup to multiple locations)" -ForegroundColor Yellow
Write-Host "   - Never commit the keystore or key.properties to version control" -ForegroundColor Yellow
Write-Host "   - You CANNOT recover the keystore if lost - make backups!" -ForegroundColor Yellow
Write-Host ""

# Check if keystore already exists
if (Test-Path "upload-keystore.jks") {
    Write-Host "❌ Error: upload-keystore.jks already exists!" -ForegroundColor Red
    Write-Host "   If you need to regenerate, delete the existing keystore first." -ForegroundColor Red
    Write-Host "   WARNING: This will invalidate all existing app releases!" -ForegroundColor Red
    exit 1
}

# Check if keytool is available
$keytoolPath = (Get-Command keytool -ErrorAction SilentlyContinue).Source
if (-not $keytoolPath) {
    Write-Host "❌ Error: keytool not found!" -ForegroundColor Red
    Write-Host "   Keytool is part of the Java JDK. Please install JDK and add it to PATH." -ForegroundColor Red
    Write-Host "   Download from: https://adoptium.net/" -ForegroundColor Yellow
    exit 1
}

# Prompt for keystore details
$storePassword = Read-Host "Enter keystore password (minimum 6 characters)" -AsSecureString
$storePasswordConfirm = Read-Host "Confirm keystore password" -AsSecureString

# Convert SecureString to plain text for comparison
$storePasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($storePassword))
$storePasswordConfirmPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($storePasswordConfirm))

if ($storePasswordPlain -ne $storePasswordConfirmPlain) {
    Write-Host "❌ Error: Passwords do not match!" -ForegroundColor Red
    exit 1
}

$keyPassword = Read-Host "Enter key password (can be same as keystore password)" -AsSecureString
$keyPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($keyPassword))

$dnameCN = Read-Host "Enter your name or organization"
$dnameOU = Read-Host "Enter your organizational unit (e.g., Development)"
$dnameO = Read-Host "Enter your organization name"
$dnameL = Read-Host "Enter your city"
$dnameST = Read-Host "Enter your state/province"
$dnameC = Read-Host "Enter your country code (2 letters, e.g., ZA for South Africa)"

Write-Host ""
Write-Host "Generating keystore..." -ForegroundColor Cyan

# Generate the keystore
$dname = "CN=$dnameCN, OU=$dnameOU, O=$dnameO, L=$dnameL, ST=$dnameST, C=$dnameC"

& keytool -genkeypair -v `
    -storetype PKCS12 `
    -keystore upload-keystore.jks `
    -alias upload `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -storepass "$storePasswordPlain" `
    -keypass "$keyPasswordPlain" `
    -dname "$dname"

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ Keystore generated successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Creating key.properties file..." -ForegroundColor Cyan
    
    # Create key.properties file
    $keyPropertiesContent = @"
storePassword=$storePasswordPlain
keyPassword=$keyPasswordPlain
keyAlias=upload
storeFile=../upload-keystore.jks
"@
    
    $keyPropertiesContent | Out-File -FilePath "key.properties" -Encoding UTF8
    
    Write-Host "✅ key.properties created!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📋 NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Backup upload-keystore.jks to a secure location (encrypted USB, cloud backup, etc.)"
    Write-Host "2. Store passwords in a password manager"
    Write-Host "3. Never commit upload-keystore.jks or key.properties to version control"
    Write-Host "4. You can now build release versions with: flutter build appbundle --release"
    Write-Host ""
    Write-Host "⚠️  If you lose the keystore, you cannot update your app on Play Store!" -ForegroundColor Red
}
else {
    Write-Host ""
    Write-Host "❌ Error: Failed to generate keystore" -ForegroundColor Red
    exit 1
}
