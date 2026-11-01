#!/bin/bash

# Local Lekker Production Build Script
# Run this script to build production-ready APKs and app bundles

set -e  # Exit on any error

echo "🚀 Local Lekker Production Build Script"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    echo -e "${RED}Error: pubspec.yaml not found. Please run this script from the project root.${NC}"
    exit 1
fi

# Check Flutter installation
echo "📱 Checking Flutter installation..."
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: Flutter is not installed or not in PATH.${NC}"
    exit 1
fi

FLUTTER_VERSION=$(flutter --version | head -n 1)
echo -e "${GREEN}✓ Flutter: $FLUTTER_VERSION${NC}"

# Switch to production environment configuration
echo "🔧 Configuring production environment..."
if [ -f ".env.production" ]; then
    cp .env.production .env
    echo -e "${GREEN}✓ Production environment configured (PAYSTACK_DEVELOPMENT_MODE=false)${NC}"
else
    echo -e "${YELLOW}⚠ .env.production not found, using existing .env${NC}"
fi

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Run tests
echo "🧪 Running tests..."
if flutter test; then
    echo -e "${GREEN}✓ All tests passed${NC}"
else
    echo -e "${RED}✗ Some tests failed. Please fix before building for production.${NC}"
    exit 1
fi

# Run analyzer
echo "🔍 Running code analysis..."
if flutter analyze; then
    echo -e "${GREEN}✓ Code analysis passed${NC}"
else
    echo -e "${YELLOW}⚠ Code analysis found issues. Please review.${NC}"
fi

# Build Android APK (for testing)
echo "🤖 Building Android APK..."
flutter build apk --release
if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    echo -e "${GREEN}✓ Android APK built successfully${NC}"
    APK_SIZE=$(du -h "build/app/outputs/flutter-apk/app-release.apk" | cut -f1)
    echo -e "${GREEN}  APK Size: $APK_SIZE${NC}"
else
    echo -e "${RED}✗ Android APK build failed${NC}"
    exit 1
fi

# Build Android App Bundle (for Play Store)
echo "📦 Building Android App Bundle..."
flutter build appbundle --release
if [ -f "build/app/outputs/bundle/release/app-release.aab" ]; then
    echo -e "${GREEN}✓ Android App Bundle built successfully${NC}"
    AAB_SIZE=$(du -h "build/app/outputs/bundle/release/app-release.aab" | cut -f1)
    echo -e "${GREEN}  Bundle Size: $AAB_SIZE${NC}"
else
    echo -e "${RED}✗ Android App Bundle build failed${NC}"
    exit 1
fi

# Build iOS (if on macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍎 Building iOS..."
    flutter build ios --release --no-codesign
    if [ -d "build/ios/iphoneos" ]; then
        echo -e "${GREEN}✓ iOS build completed${NC}"
    else
        echo -e "${YELLOW}⚠ iOS build may have issues (check manually)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Skipping iOS build (not on macOS)${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Production builds completed successfully!${NC}"
echo ""
echo "📁 Build outputs:"
echo "  Android APK: build/app/outputs/flutter-apk/app-release.apk"
echo "  Android Bundle: build/app/outputs/bundle/release/app-release.aab"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  iOS: build/ios/iphoneos/Runner.app"
fi
echo ""
echo "📋 Next steps:"
echo "1. Test the APK on a physical device"
echo "2. Upload AAB to Google Play Console"
echo "3. Configure app store listings"
echo "4. Set up PayFast live credentials"
echo "5. Update environment variables for production"
echo "6. Deploy Supabase functions (if any)"
echo ""
echo -e "${YELLOW}⚠️  Remember to:${NC}"
echo "  - Update version codes before release"
echo "  - Test payments with live PayFast credentials"
echo "  - Verify all API endpoints work in production"
echo "  - Set up monitoring and error tracking"
echo "  - Have a rollback plan ready"</content>
<parameter name="filePath">c:\Users\clyde\local_lekker\build_production.sh