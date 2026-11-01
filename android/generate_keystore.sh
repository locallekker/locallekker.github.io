#!/bin/bash

# Generate Release Keystore for Local Lekker App
# Run this script ONCE to create your release keystore
# Keep the keystore file and passwords SECURE - you cannot recover them!

echo "🔐 Local Lekker Release Keystore Generator"
echo "=========================================="
echo ""
echo "⚠️  IMPORTANT:"
echo "   - Store the keystore file securely (backup to multiple locations)"
echo "   - Never commit the keystore or key.properties to version control"
echo "   - You CANNOT recover the keystore if lost - make backups!"
echo ""

# Check if keystore already exists
if [ -f "upload-keystore.jks" ]; then
    echo "❌ Error: upload-keystore.jks already exists!"
    echo "   If you need to regenerate, delete the existing keystore first."
    echo "   WARNING: This will invalidate all existing app releases!"
    exit 1
fi

# Prompt for keystore details
echo "Enter keystore password (minimum 6 characters):"
read -s STORE_PASSWORD
echo ""
echo "Confirm keystore password:"
read -s STORE_PASSWORD_CONFIRM
echo ""

if [ "$STORE_PASSWORD" != "$STORE_PASSWORD_CONFIRM" ]; then
    echo "❌ Error: Passwords do not match!"
    exit 1
fi

echo "Enter key password (can be same as keystore password):"
read -s KEY_PASSWORD
echo ""

echo "Enter your name or organization:"
read DNAME_CN

echo "Enter your organizational unit (e.g., Development):"
read DNAME_OU

echo "Enter your organization name:"
read DNAME_O

echo "Enter your city:"
read DNAME_L

echo "Enter your state/province:"
read DNAME_ST

echo "Enter your country code (2 letters, e.g., ZA for South Africa):"
read DNAME_C

echo ""
echo "Generating keystore..."

# Generate the keystore
keytool -genkeypair -v \
  -storetype PKCS12 \
  -keystore upload-keystore.jks \
  -alias upload \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "CN=$DNAME_CN, OU=$DNAME_OU, O=$DNAME_O, L=$DNAME_L, ST=$DNAME_ST, C=$DNAME_C"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Keystore generated successfully!"
    echo ""
    echo "Creating key.properties file..."
    
    # Create key.properties file
    cat > key.properties << EOF
storePassword=$STORE_PASSWORD
keyPassword=$KEY_PASSWORD
keyAlias=upload
storeFile=../upload-keystore.jks
EOF
    
    echo "✅ key.properties created!"
    echo ""
    echo "📋 NEXT STEPS:"
    echo "1. Backup upload-keystore.jks to a secure location (encrypted USB, cloud backup, etc.)"
    echo "2. Store passwords in a password manager"
    echo "3. Never commit upload-keystore.jks or key.properties to version control"
    echo "4. You can now build release versions with: flutter build appbundle --release"
    echo ""
    echo "⚠️  If you lose the keystore, you cannot update your app on Play Store!"
else
    echo ""
    echo "❌ Error: Failed to generate keystore"
    exit 1
fi
