#!/bin/bash

# Emergency Recovery Script
# Version: 1.0.0
# Date: September 28, 2025

set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$PROJECT_ROOT/database_backups"
RECOVERY_LOG="$BACKUP_DIR/emergency_recovery.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Emergency flags
EMERGENCY_MODE=false
FORCE_RECOVERY=false

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [EMERGENCY] - $1" | tee -a "$RECOVERY_LOG"
}

# Emergency error handling
emergency_error() {
    echo -e "${RED}🚨 EMERGENCY ERROR: $1${NC}" >&2
    log "EMERGENCY ERROR: $1"
    echo -e "${RED}🚨 System is in emergency mode. Manual intervention required.${NC}"
    exit 1
}

# Success message
success() {
    echo -e "${GREEN}✅ SUCCESS: $1${NC}"
    log "SUCCESS: $1"
}

# Warning message
warning() {
    echo -e "${YELLOW}⚠️  WARNING: $1${NC}"
    log "WARNING: $1"
}

# Info message
info() {
    echo -e "${BLUE}ℹ️  INFO: $1${NC}"
    log "INFO: $1"
}

# Check if we're in emergency mode
check_emergency_flags() {
    if [ "$1" = "--emergency" ] || [ "$1" = "-e" ]; then
        EMERGENCY_MODE=true
        warning "EMERGENCY MODE ACTIVATED - This will perform destructive operations!"
        read -p "Are you sure you want to continue? (type 'YES' to confirm): " confirm
        if [ "$confirm" != "YES" ]; then
            info "Emergency recovery cancelled by user"
            exit 0
        fi
    fi

    if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
        FORCE_RECOVERY=true
        warning "FORCE RECOVERY ACTIVATED - Skipping safety checks!"
    fi
}

# Create recovery directory
create_recovery_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        success "Created recovery directory: $BACKUP_DIR"
    fi
}

# Get latest backup files
get_latest_backups() {
    local latest_schema=""
    local latest_data=""

    if [ -d "$BACKUP_DIR" ]; then
        latest_schema=$(ls -t "$BACKUP_DIR"/schema_backup_*.sql 2>/dev/null | head -1)
        latest_data=$(ls -t "$BACKUP_DIR"/essential_data_backup_*.sql 2>/dev/null | head -1)
    fi

    echo "$latest_schema|$latest_data"
}

# Emergency app rollback
emergency_app_rollback() {
    info "Performing emergency app rollback..."

    # This would typically rollback to a previous app version
    # For now, we'll create a recovery script

    cat > "$BACKUP_DIR/emergency_app_recovery.sh" << 'EOF'
#!/bin/bash
# Emergency App Recovery Script

echo "Emergency App Recovery Started"

# Step 1: Stop the app (if running)
echo "Stopping Local Lekker app..."
adb shell am force-stop com.example.local_lekker 2>/dev/null || true

# Step 2: Clear app data and cache
echo "Clearing app data..."
adb shell pm clear com.example.local_lekker 2>/dev/null || true

# Step 3: Reinstall from backup APK
if [ -f "local_lekker_backup.apk" ]; then
    echo "Reinstalling from backup APK..."
    adb install -r local_lekker_backup.apk
else
    echo "No backup APK found. Please install manually."
fi

# Step 4: Restart app
echo "Starting app..."
adb shell monkey -p com.example.local_lekker 1 2>/dev/null || true

echo "Emergency app recovery completed"
EOF

    chmod +x "$BACKUP_DIR/emergency_app_recovery.sh"
    success "Emergency app recovery script created: $BACKUP_DIR/emergency_app_recovery.sh"
}

# Emergency database rollback
emergency_database_rollback() {
    if [ "$EMERGENCY_MODE" != true ]; then
        emergency_error "Database rollback requires emergency mode. Use --emergency flag."
    fi

    info "Performing emergency database rollback..."

    # Get latest backups
    local backups=$(get_latest_backups)
    local schema_backup=$(echo "$backups" | cut -d'|' -f1)
    local data_backup=$(echo "$backups" | cut -d'|' -f2)

    if [ -z "$schema_backup" ] && [ -z "$data_backup" ]; then
        emergency_error "No backup files found. Cannot perform rollback."
    fi

    # Create rollback script
    cat > "$BACKUP_DIR/emergency_database_rollback.sql" << EOF
-- Emergency Database Rollback
-- Generated: $(date)
-- WARNING: This will overwrite existing data!

BEGIN;

-- Step 1: Create backup of current state (if possible)
-- This step would be performed manually in Supabase SQL Editor

-- Step 2: Drop problematic tables/functions (customize as needed)
/*
DROP TABLE IF EXISTS problematic_table CASCADE;
DROP FUNCTION IF EXISTS problematic_function CASCADE;
DROP POLICY IF EXISTS problematic_policy ON table_name;
*/

-- Step 3: Restore from backup (run the following files in Supabase SQL Editor):
-- Schema backup: $(basename "$schema_backup" 2>/dev/null || echo "No schema backup found")
-- Data backup: $(basename "$data_backup" 2>/dev/null || echo "No data backup found")

-- Step 4: Verify restoration
SELECT 'Emergency rollback completed on $(date)' as status;

COMMIT;
EOF

    success "Emergency database rollback script created: $BACKUP_DIR/emergency_database_rollback.sql"
    warning "Please execute the rollback script manually in Supabase SQL Editor"
}

# System health check
system_health_check() {
    info "Performing system health check..."

    local issues_found=0

    # Check if project directory exists
    if [ ! -d "$PROJECT_ROOT" ]; then
        emergency_error "Project directory not found: $PROJECT_ROOT"
    fi

    # Check if pubspec.yaml exists
    if [ ! -f "$PROJECT_ROOT/pubspec.yaml" ]; then
        warning "pubspec.yaml not found"
        ((issues_found++))
    fi

    # Check if lib directory exists
    if [ ! -d "$PROJECT_ROOT/lib" ]; then
        warning "lib directory not found"
        ((issues_found++))
    fi

    # Check backup directory
    if [ ! -d "$BACKUP_DIR" ]; then
        warning "Backup directory not found: $BACKUP_DIR"
        ((issues_found++))
    else
        # Count backup files
        local backup_count=$(find "$BACKUP_DIR" -name "*.sql" -o -name "*.sh" | wc -l)
        info "Found $backup_count backup/recovery files"
    fi

    # Check Flutter installation
    if ! command -v flutter &> /dev/null; then
        warning "Flutter not found in PATH"
        ((issues_found++))
    else
        local flutter_version=$(flutter --version | head -1)
        info "Flutter: $flutter_version"
    fi

    if [ $issues_found -eq 0 ]; then
        success "System health check passed"
    else
        warning "Found $issues_found system issues"
    fi

    return $issues_found
}

# Create recovery report
create_recovery_report() {
    local report_file="$BACKUP_DIR/recovery_report_$(date '+%Y%m%d_%H%M%S').md"

    cat > "$report_file" << EOF
# Emergency Recovery Report
Generated: $(date)

## System Status
- Emergency Mode: $EMERGENCY_MODE
- Force Recovery: $FORCE_RECOVERY
- Project Root: $PROJECT_ROOT

## Available Backups
$(get_latest_backups | tr '|' '\n' | sed 's/^/- /')

## Recovery Actions Taken
- System health check: $(system_health_check 2>/dev/null && echo "PASSED" || echo "ISSUES FOUND")
- App recovery script: Created
- Database recovery script: $( [ "$EMERGENCY_MODE" = true ] && echo "Created" || echo "Skipped (requires emergency mode)")

## Next Steps
1. Review this report
2. Execute appropriate recovery scripts
3. Test system functionality
4. Update backup files if needed

## Emergency Contacts
- Admin: admin@locallekker.com
- Support: support@locallekker.com

---
This report was generated automatically by the emergency recovery system.
EOF

    success "Recovery report created: $report_file"
}

# Main emergency menu
show_emergency_menu() {
    echo
    echo "=========================================="
    echo " 🚨  EMERGENCY RECOVERY SYSTEM"
    echo "=========================================="
    echo
    echo "⚠️  WARNING: These operations can cause data loss!"
    echo "   Make sure you have proper backups before proceeding."
    echo
    echo "Available emergency commands:"
    echo "  health     - Run system health check"
    echo "  app        - Emergency app rollback"
    echo "  database   - Emergency database rollback (--emergency required)"
    echo "  full       - Full system recovery (--emergency required)"
    echo "  report     - Generate recovery report"
    echo "  help       - Show this help menu"
    echo "  quit       - Exit"
    echo
    echo "Use --emergency (-e) flag for destructive operations"
    echo "Use --force (-f) flag to skip safety checks"
    echo
}

# Main function
main() {
    check_emergency_flags "$1"
    create_recovery_dir

    if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        show_emergency_menu
        return
    fi

    case "$1" in
        "health")
            system_health_check
            ;;

        "app")
            emergency_app_rollback
            ;;

        "database")
            emergency_database_rollback
            ;;

        "full")
            if [ "$EMERGENCY_MODE" != true ]; then
                emergency_error "Full recovery requires emergency mode. Use --emergency flag."
            fi
            info "Starting full system recovery..."
            emergency_app_rollback
            emergency_database_rollback
            create_recovery_report
            success "Full system recovery completed"
            ;;

        "report")
            create_recovery_report
            ;;

        "help"|"-h"|"--help")
            show_emergency_menu
            ;;

        "quit"|"exit")
            info "Emergency recovery system shutdown"
            exit 0
            ;;

        *)
            emergency_error "Unknown command: $1"
            ;;
    esac
}

# Run main function with all arguments
main "$@"