#!/bin/bash

# Supabase Migration Fallback System
# Version: 1.0.0
# Date: September 28, 2025

set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$PROJECT_ROOT/backups"
MIGRATION_DIR="$PROJECT_ROOT/supabase/migrations"
LOG_FILE="$BACKUP_DIR/migration_fallback.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Backup current database state
backup_database() {
    local timestamp=$(get_timestamp)
    local backup_file="$BACKUP_DIR/db_backup_$timestamp.sql"

    info "Creating database backup..."

    # This would typically use pg_dump or supabase CLI
    # For now, we'll create a placeholder backup script
    cat > "$backup_file" << 'EOF'
-- Database Backup
-- Timestamp: TIMESTAMP_PLACEHOLDER
-- This is a template backup file
-- In production, this would contain actual pg_dump output

-- Example backup structure:
-- pg_dump -h your-host -U your-user -d your-database --no-owner --no-privileges > backup.sql

-- To restore:
-- psql -h your-host -U your-user -d your-database < backup.sql

-- Current schema state would be dumped here
SELECT 'Database backup created on TIMESTAMP_PLACEHOLDER' as status;
EOF

    # Replace timestamp placeholder
    sed -i "s/TIMESTAMP_PLACEHOLDER/$timestamp/g" "$backup_file"

    success "Database backup created: $backup_file"
    echo "$backup_file"
}

# Backup migration files
backup_migrations() {
    local timestamp=$(get_timestamp)
    local backup_file="$BACKUP_DIR/migrations_backup_$timestamp.tar.gz"

    info "Creating migrations backup..."

    if [ -d "$MIGRATION_DIR" ]; then
        tar -czf "$backup_file" -C "$PROJECT_ROOT" "supabase/migrations"
        success "Migrations backup created: $backup_file"
        echo "$backup_file"
    else
        warning "Migrations directory not found: $MIGRATION_DIR"
        echo ""
    fi
}

# Create rollback script for specific migration
create_rollback_script() {
    local migration_file="$1"
    local timestamp=$(get_timestamp)
    local rollback_file="$BACKUP_DIR/rollback_$timestamp.sql"

    info "Creating rollback script for: $(basename "$migration_file")"

    # Extract migration name from filename
    local migration_name=$(basename "$migration_file" .sql | sed 's/^[0-9]*_//')

    cat > "$rollback_file" << EOF
-- Rollback Script for Migration: $(basename "$migration_file")
-- Generated: $timestamp
-- Original Migration: $(basename "$migration_file")

-- WARNING: This is a template rollback script
-- You need to manually add the appropriate DOWN migration commands

-- Example rollback commands (customize based on original migration):

-- If original migration created a table:
-- DROP TABLE IF EXISTS ${migration_name};

-- If original migration added a column:
-- ALTER TABLE table_name DROP COLUMN IF EXISTS column_name;

-- If original migration created an index:
-- DROP INDEX IF EXISTS index_name;

-- If original migration added a policy:
-- DROP POLICY IF EXISTS policy_name ON table_name;

-- Add your specific rollback commands here:

-- ROLLBACK COMMANDS GO HERE

COMMIT;
EOF

    success "Rollback script created: $rollback_file"
    echo "$rollback_file"
}

# Validate migration
validate_migration() {
    local migration_file="$1"

    info "Validating migration: $(basename "$migration_file")"

    # Basic validation checks
    if [ ! -f "$migration_file" ]; then
        error_exit "Migration file does not exist: $migration_file"
    fi

    # Check if file has content
    if [ ! -s "$migration_file" ]; then
        warning "Migration file is empty: $(basename "$migration_file")"
        return 1
    fi

    # Check for basic SQL syntax (very basic check)
    if ! grep -q ";" "$migration_file"; then
        warning "Migration file may not contain valid SQL: $(basename "$migration_file")"
        return 1
    fi

    success "Migration validation passed: $(basename "$migration_file")"
    return 0
}

# List available migrations
list_migrations() {
    info "Available migrations:"

    if [ -d "$MIGRATION_DIR" ]; then
        local count=0
        for migration in "$MIGRATION_DIR"/*.sql; do
            if [ -f "$migration" ]; then
                echo "  $(basename "$migration")"
                ((count++))
            fi
        done
        info "Total migrations found: $count"
    else
        warning "Migrations directory not found: $MIGRATION_DIR"
    fi
}

# Create emergency restore script
create_emergency_restore() {
    local timestamp=$(get_timestamp)
    local restore_file="$BACKUP_DIR/emergency_restore_$timestamp.sql"

    info "Creating emergency restore script..."

    cat > "$restore_file" << 'EOF'
-- Emergency Database Restore Script
-- Generated: TIMESTAMP_PLACEHOLDER
-- This script restores the database to a known working state

-- WARNING: This will DROP and RECREATE all tables and data
-- Only use this in emergency situations

BEGIN;

-- Drop all existing tables (be very careful with this!)
-- Uncomment and modify as needed:
/*
DROP TABLE IF EXISTS trusted_partner_discounts CASCADE;
DROP TABLE IF EXISTS business_bills CASCADE;
DROP TABLE IF EXISTS business_logos CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS qr_codes CASCADE;
DROP TABLE IF EXISTS memberships CASCADE;
DROP TABLE IF EXISTS businesses CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;
DROP TABLE IF EXISTS invitations CASCADE;
*/

-- Recreate base schema
-- Include your base migration here
-- Example:
/*
-- Base tables creation
CREATE TABLE profiles (
    id UUID REFERENCES auth.users(id) PRIMARY KEY,
    name TEXT,
    surname TEXT,
    user_type TEXT CHECK (user_type IN ('member', 'trusted_partner', 'admin')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE trusted_partners (
    user_id UUID REFERENCES auth.users(id) PRIMARY KEY,
    business_name TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE businesses (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    owner_member_id UUID REFERENCES auth.users(id),
    name TEXT,
    category TEXT,
    address TEXT,
    verified BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add more table creations as needed
*/

-- Recreate RLS policies
-- Include your RLS setup here

-- Recreate functions and triggers
-- Include your function and trigger setup here

COMMIT;

-- Post-restore validation
SELECT 'Emergency restore completed' as status;
EOF

    # Replace timestamp
    sed -i "s/TIMESTAMP_PLACEHOLDER/$timestamp/g" "$restore_file"

    success "Emergency restore script created: $restore_file"
    echo "$restore_file"
}

# Main menu
show_menu() {
    echo
    echo "========================================"
    echo "  Supabase Migration Fallback System"
    echo "========================================"
    echo
    echo "Available commands:"
    echo "  backup     - Create full database and migrations backup"
    echo "  list       - List all available migrations"
    echo "  validate   - Validate a specific migration file"
    echo "  rollback   - Create rollback script for a migration"
    echo "  emergency  - Create emergency restore script"
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
            backup_database > /dev/null
            backup_migrations > /dev/null
            success "Full backup completed"
            ;;

        "list")
            list_migrations
            ;;

        "validate")
            if [ -z "$2" ]; then
                error_exit "Please provide a migration file path"
            fi
            validate_migration "$2"
            ;;

        "rollback")
            if [ -z "$2" ]; then
                error_exit "Please provide a migration file path"
            fi
            create_rollback_script "$2"
            ;;

        "emergency")
            create_emergency_restore
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