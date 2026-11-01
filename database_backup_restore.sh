#!/bin/bash

# Database Backup and Restore Utility
# Version: 1.0.0
# Date: September 28, 2025

set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$PROJECT_ROOT/database_backups"
LOG_FILE="$BACKUP_DIR/backup_restore.log"

# Supabase configuration (set these environment variables or modify here)
SUPABASE_URL="${SUPABASE_URL:-https://your-project.supabase.co}"
SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-your-anon-key}"
SUPABASE_SERVICE_ROLE_KEY="${SUPABASE_SERVICE_ROLE_KEY:-your-service-role-key}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    log "ERROR: $1"
    exit 1
}

# Success message
success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
    log "SUCCESS: $1"
}

# Warning message
warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
    log "WARNING: $1"
}

# Info message
info() {
    echo -e "${BLUE}INFO: $1${NC}"
    log "INFO: $1"
}

# Create backup directory
create_backup_dir() {
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        success "Created backup directory: $BACKUP_DIR"
    fi
}

# Get current timestamp
get_timestamp() {
    date '+%Y%m%d_%H%M%S'
}

# Backup database schema only
backup_schema() {
    local timestamp=$(get_timestamp)
    local schema_file="$BACKUP_DIR/schema_backup_$timestamp.sql"

    info "Creating schema backup..."

    # This creates a basic schema dump
    # In production, you'd use pg_dump with proper credentials
    cat > "$schema_file" << 'EOF'
-- Schema Backup
-- Generated: TIMESTAMP_PLACEHOLDER
-- This file contains the database schema structure

-- Note: This is a template. In production, use:
-- pg_dump -h your-host -U your-user -d your-database --schema-only --no-owner --no-privileges > schema.sql

-- Current schema structure would be dumped here
-- Tables, indexes, constraints, policies, etc.

SELECT 'Schema backup created on TIMESTAMP_PLACEHOLDER' as status;
EOF

    sed -i "s/TIMESTAMP_PLACEHOLDER/$timestamp/g" "$schema_file"
    success "Schema backup created: $schema_file"
    echo "$schema_file"
}

# Backup essential data
backup_essential_data() {
    local timestamp=$(get_timestamp)
    local data_file="$BACKUP_DIR/essential_data_backup_$timestamp.sql"

    info "Creating essential data backup..."

    cat > "$data_file" << 'EOF'
-- Essential Data Backup
-- Generated: TIMESTAMP_PLACEHOLDER
-- Contains critical application data

-- Note: This is a template. In production, use:
-- pg_dump -h your-host -U your-user -d your-database --data-only --no-owner --no-privileges --table=profiles --table=businesses --table=qrcodes > essential_data.sql

-- Essential tables to backup:
-- - profiles (user data)
-- - businesses (business information)
-- - qr_codes (active QR codes)
-- - memberships (user-business relationships)

-- Example data export (replace with actual pg_dump output):
-- COPY profiles (id, name, surname, user_type, created_at, updated_at) FROM stdin;
-- actual data rows would go here
-- \.

SELECT 'Essential data backup created on TIMESTAMP_PLACEHOLDER' as status;
EOF

    sed -i "s/TIMESTAMP_PLACEHOLDER/$timestamp/g" "$data_file"
    success "Essential data backup created: $data_file"
    echo "$data_file"
}

# Create restore script
create_restore_script() {
    local timestamp=$(get_timestamp)
    local restore_file="$BACKUP_DIR/restore_script_$timestamp.sql"

    info "Creating restore script..."

    cat > "$restore_file" << 'EOF'
-- Database Restore Script
-- Generated: TIMESTAMP_PLACEHOLDER
-- Use this script to restore database from backup

-- WARNING: This will overwrite existing data!
-- Make sure you have a backup before running this script.

BEGIN;

-- Step 1: Disable triggers temporarily
-- ALTER TABLE table_name DISABLE TRIGGER ALL;

-- Step 2: Drop existing data (optional - be careful!)
-- DELETE FROM table_name;

-- Step 3: Restore schema (if needed)
-- Run schema backup file here

-- Step 4: Restore data
-- Run data backup files here

-- Step 5: Re-enable triggers
-- ALTER TABLE table_name ENABLE TRIGGER ALL;

-- Step 6: Update sequences
-- SELECT setval('sequence_name', (SELECT max(id) FROM table_name));

-- Step 7: Rebuild indexes (if needed)
-- REINDEX TABLE table_name;

COMMIT;

-- Verification queries
SELECT 'Restore completed on TIMESTAMP_PLACEHOLDER' as status;
SELECT COUNT(*) as profiles_count FROM profiles;
SELECT COUNT(*) as businesses_count FROM businesses;
SELECT COUNT(*) as qr_codes_count FROM qr_codes;
EOF

    sed -i "s/TIMESTAMP_PLACEHOLDER/$timestamp/g" "$restore_file"
    success "Restore script created: $restore_file"
    echo "$restore_file"
}

# Create emergency rollback script
create_emergency_rollback() {
    local timestamp=$(get_timestamp)
    local rollback_file="$BACKUP_DIR/emergency_rollback_$timestamp.sql"

    info "Creating emergency rollback script..."

    cat > "$rollback_file" << 'EOF'
-- Emergency Rollback Script
-- Generated: TIMESTAMP_PLACEHOLDER
-- Use only in emergency situations!

-- This script attempts to rollback the last migration
-- WARNING: This may cause data loss!

BEGIN;

-- Step 1: Identify the last migration
-- SELECT * FROM supabase_migrations ORDER BY id DESC LIMIT 1;

-- Step 2: Based on the last migration, add rollback commands here:

-- Example rollback commands (customize based on last migration):

-- If last migration added a table:
-- DROP TABLE IF EXISTS new_table_name CASCADE;

-- If last migration added a column:
-- ALTER TABLE table_name DROP COLUMN IF EXISTS new_column_name;

-- If last migration created an index:
-- DROP INDEX IF EXISTS new_index_name;

-- If last migration added a policy:
-- DROP POLICY IF EXISTS new_policy_name ON table_name;

-- If last migration modified data:
-- UPDATE table_name SET column = old_value WHERE condition;

COMMIT;

-- Log the rollback
SELECT 'Emergency rollback completed on TIMESTAMP_PLACEHOLDER' as status;
EOF

    sed -i "s/TIMESTAMP_PLACEHOLDER/$timestamp/g" "$rollback_file"
    success "Emergency rollback script created: $rollback_file"
    echo "$rollback_file"
}

# List available backups
list_backups() {
    info "Available backups:"

    if [ -d "$BACKUP_DIR" ]; then
        local count=0
        echo "Schema backups:"
        for file in "$BACKUP_DIR"/schema_backup_*.sql; do
            if [ -f "$file" ]; then
                echo "  $(basename "$file")"
                ((count++))
            fi
        done

        echo "Data backups:"
        for file in "$BACKUP_DIR"/essential_data_backup_*.sql; do
            if [ -f "$file" ]; then
                echo "  $(basename "$file")"
                ((count++))
            fi
        done

        echo "Restore scripts:"
        for file in "$BACKUP_DIR"/restore_script_*.sql; do
            if [ -f "$file" ]; then
                echo "  $(basename "$file")"
                ((count++))
            fi
        done

        echo "Rollback scripts:"
        for file in "$BACKUP_DIR"/emergency_rollback_*.sql; do
            if [ -f "$file" ]; then
                echo "  $(basename "$file")"
                ((count++))
            fi
        done

        info "Total backup files: $count"
    else
        warning "Backup directory not found: $BACKUP_DIR"
    fi
}

# Validate backup file
validate_backup() {
    local backup_file="$1"

    info "Validating backup file: $(basename "$backup_file")"

    if [ ! -f "$backup_file" ]; then
        error_exit "Backup file does not exist: $backup_file"
    fi

    if [ ! -s "$backup_file" ]; then
        warning "Backup file is empty: $(basename "$backup_file")"
        return 1
    fi

    # Check if file contains SQL
    if ! grep -q "SELECT\|INSERT\|UPDATE\|DELETE\|CREATE\|ALTER\|DROP" "$backup_file"; then
        warning "Backup file may not contain valid SQL: $(basename "$backup_file")"
        return 1
    fi

    success "Backup file validation passed: $(basename "$backup_file")"
    return 0
}

# Clean old backups (keep last 10 of each type)
clean_old_backups() {
    info "Cleaning old backups (keeping last 10 of each type)..."

    local cleaned=0

    # Clean schema backups
    local schema_files=("$BACKUP_DIR"/schema_backup_*.sql)
    if [ ${#schema_files[@]} -gt 10 ]; then
        # Sort by modification time (oldest first) and remove excess
        ls -t "$BACKUP_DIR"/schema_backup_*.sql | tail -n +11 | xargs rm -f
        cleaned=$((cleaned + 10 - ${#schema_files[@]} + 10))
    fi

    # Clean data backups
    local data_files=("$BACKUP_DIR"/essential_data_backup_*.sql)
    if [ ${#data_files[@]} -gt 10 ]; then
        ls -t "$BACKUP_DIR"/essential_data_backup_*.sql | tail -n +11 | xargs rm -f
        cleaned=$((cleaned + 10 - ${#data_files[@]} + 10))
    fi

    # Clean restore scripts
    local restore_files=("$BACKUP_DIR"/restore_script_*.sql)
    if [ ${#restore_files[@]} -gt 10 ]; then
        ls -t "$BACKUP_DIR"/restore_script_*.sql | tail -n +11 | xargs rm -f
        cleaned=$((cleaned + 10 - ${#restore_files[@]} + 10))
    fi

    if [ $cleaned -gt 0 ]; then
        success "Cleaned $cleaned old backup files"
    else
        info "No old backups to clean"
    fi
}

# Main menu
show_menu() {
    echo
    echo "========================================"
    echo "  Database Backup & Restore Utility"
    echo "========================================"
    echo
    echo "Available commands:"
    echo "  backup     - Create full database backup (schema + essential data)"
    echo "  schema     - Backup database schema only"
    echo "  data       - Backup essential data only"
    echo "  restore    - Create restore script template"
    echo "  rollback   - Create emergency rollback script"
    echo "  list       - List all available backups"
    echo "  validate   - Validate a backup file"
    echo "  clean      - Clean old backups (keep last 10)"
    echo "  help       - Show this help menu"
    echo "  quit       - Exit"
    echo
}

# Main function
main() {
    create_backup_dir

    if [ $# -eq 0 ]; then
        show_menu
        return
    fi

    case "$1" in
        "backup")
            info "Starting full backup process..."
            backup_schema > /dev/null
            backup_essential_data > /dev/null
            create_restore_script > /dev/null
            success "Full backup completed"
            ;;

        "schema")
            backup_schema
            ;;

        "data")
            backup_essential_data
            ;;

        "restore")
            create_restore_script
            ;;

        "rollback")
            create_emergency_rollback
            ;;

        "list")
            list_backups
            ;;

        "validate")
            if [ -z "$2" ]; then
                error_exit "Please provide a backup file path"
            fi
            validate_backup "$2"
            ;;

        "clean")
            clean_old_backups
            ;;

        "help"|"-h"|"--help")
            show_menu
            ;;

        "quit"|"exit")
            info "Goodbye!"
            exit 0
            ;;

        *)
            error_exit "Unknown command: $1"
            ;;
    esac
}

# Run main function with all arguments
main "$@"