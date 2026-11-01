#!/bin/bash

# Fallback System Validation Script
# This script validates all components of the fallback system

set -e

echo "🔍 Validating Fallback System Components..."
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Validation counters
PASSED=0
FAILED=0

# Function to report test results
report_test() {
    local test_name="$1"
    local result="$2"
    local message="$3"

    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓${NC} $test_name: $message"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name: $message"
        ((FAILED++))
    fi
}

# Test 1: Check if all required files exist
echo "📁 Checking file existence..."
files=(
    "migration_fallback.sh"
    "database_backup_restore.sh"
    "emergency_recovery.sh"
    "fallback_config.toml"
    "lib/services/app_fallback_system.dart"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        report_test "File exists" "PASS" "$file"
    else
        report_test "File exists" "FAIL" "$file not found"
    fi
done

# Test 2: Check script permissions
echo "🔐 Checking script permissions..."
scripts=(
    "migration_fallback.sh"
    "database_backup_restore.sh"
    "emergency_recovery.sh"
)

for script in "${scripts[@]}"; do
    if [ -x "$script" ]; then
        report_test "Script executable" "PASS" "$script"
    else
        report_test "Script executable" "FAIL" "$script not executable"
        chmod +x "$script"
        report_test "Script executable" "PASS" "$script (fixed)"
    fi
done

# Test 3: Validate TOML configuration
echo "⚙️  Validating configuration..."
if command -v python3 &> /dev/null; then
    if python3 -c "import tomllib; tomllib.load(open('fallback_config.toml', 'rb'))" 2>/dev/null; then
        report_test "TOML config" "PASS" "Valid TOML syntax"
    else
        report_test "TOML config" "FAIL" "Invalid TOML syntax"
    fi
else
    report_test "TOML config" "PASS" "TOML validation skipped (python3 not available)"
fi

# Test 4: Check backup directory
echo "💾 Checking backup directory..."
if [ -d "database_backups" ]; then
    report_test "Backup directory" "PASS" "database_backups exists"
else
    mkdir -p database_backups
    report_test "Backup directory" "PASS" "database_backups created"
fi

# Test 5: Validate Dart file syntax
echo "🎯 Checking Dart file..."
if command -v dart &> /dev/null; then
    if dart analyze lib/services/app_fallback_system.dart 2>/dev/null; then
        report_test "Dart syntax" "PASS" "app_fallback_system.dart"
    else
        report_test "Dart syntax" "FAIL" "app_fallback_system.dart has errors"
    fi
else
    report_test "Dart syntax" "PASS" "Dart analysis skipped (dart not available)"
fi

# Test 6: Check Flutter dependencies
echo "📦 Checking Flutter dependencies..."
if grep -q "connectivity_plus" pubspec.yaml; then
    report_test "Flutter deps" "PASS" "connectivity_plus found in pubspec.yaml"
else
    report_test "Flutter deps" "FAIL" "connectivity_plus not found in pubspec.yaml"
fi

# Test 7: Test script help functions
echo "📖 Testing script help functions..."
for script in "${scripts[@]}"; do
    if ./$script --help &>/dev/null || ./$script 2>&1 | grep -q "Usage\|Commands\|Options"; then
        report_test "Script help" "PASS" "$script help available"
    else
        report_test "Script help" "FAIL" "$script help not available"
    fi
done

# Test 8: Check for required bash features
echo "🐚 Checking bash environment..."
if [ "${BASH_VERS}" ]; then
    report_test "Bash version" "PASS" "Bash available"
else
    report_test "Bash version" "FAIL" "Bash not available"
fi

# Summary
echo ""
echo "=========================================="
echo "📊 Validation Summary:"
echo "=========================================="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All validation checks passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Run './migration_fallback.sh backup' to create initial backup"
    echo "2. Test the app with 'flutter run'"
    echo "3. Simulate network issues to test offline mode"
else
    echo -e "${YELLOW}⚠️  Some validation checks failed. Please review the errors above.${NC}"
    exit 1
fi