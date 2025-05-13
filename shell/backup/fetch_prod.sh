#!/bin/bash

# Dataverse Production Backup & Fetch Script
# Automates syncing a Dataverse instance from production to a staging/clone server
# Handles database backup, files, Solr configuration, counter processor components

# Get the directory of the script itself
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Logging configuration
LOGFILE="${SCRIPT_DIR}/fetching_prod_backup.log"

# Function to log and print messages
log() {
    # Output timestamped log messages to both console and log file
    # $1: Message to log
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOGFILE"
}

# Function to check if counter processor variables are set
check_counter_vars() {
    # Verify that all counter processor variables are defined
    # Returns 0 if all variables are set, 1 if any are missing
    for var_name in "${COUNTER_VARS[@]}"; do
        if [[ -z "${!var_name}" ]]; then
            return 1
        fi
    done
    
    for var_name in "${PRODUCTION_COUNTER_VARS[@]}"; do
        if [[ -z "${!var_name}" ]]; then
            return 1
        fi
    done
    
    return 0
}

# Function to check for errors and exit if found
check_error() {
    # Check the exit code of the last command and exit if an error occurred
    # $1: Error message to display before exiting
    if [ $? -ne 0 ]; then
        log "ERROR: $1. Exiting."
        exit 1
    fi
}

# Function to check for required commands
check_required_commands() {
    local missing_commands=()
    local required_commands=(
        "rsync" "ssh" "psql" "pg_dump" "sed" "systemctl" "sudo"
    )

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands+=("$cmd")
        fi
    done

    if [ ${#missing_commands[@]} -ne 0 ]; then
        log "Error: The following required commands are not installed:"
        printf ' - %s\n' "${missing_commands[@]}" | tee -a "$LOGFILE"
        echo
        log "Please install these commands before running the script."
        exit 1
    fi
}

# Security check: Prevent running as root directly
if [[ $EUID -eq 0 ]]; then
    log "Please do not run this script as root."
    log "This script uses sudo when necessary for specific operations."
    exit 1
fi

# Check for required commands
check_required_commands

# Function to check required environment variables
check_required_vars() {
    # Check a group of environment variables and report if any are missing
    # $1: Section name for the group of variables
    # $@: List of variable names to check
    local missing_vars=0
    local section_name="$1"
    shift
    local var_list=("$@")
    
    log "Checking ${section_name} variables..."
    
    for var_name in "${var_list[@]}"; do
        if [[ -z "${!var_name}" ]]; then
            log "  - Missing: $var_name"
            missing_vars=$((missing_vars + 1))
        fi
    done
    
    if [[ $missing_vars -gt 0 ]]; then
        log "Error: $missing_vars ${section_name} variables are missing in ${SCRIPT_DIR}/.env"
        return 1
    fi
    
    return 0
}

# Define arrays of required variables by section
DATAVERSE_VARS=(
    "DOMAIN" 
    "PAYARA" 
    "DATAVERSE_USER" 
    "SOLR_USER" 
    "DATAVERSE_CONTENT_STORAGE" 
    "SOLR_PATH"
)

PRODUCTION_VARS=(
    "PRODUCTION_DOMAIN" 
    "PRODUCTION_DATAVERSE_USER" 
    "PRODUCTION_SOLR_USER" 
    "PRODUCTION_DATAVERSE_CONTENT_STORAGE" 
    "PRODUCTION_SOLR_PATH"
)

# Counter processor variables (optional)
COUNTER_VARS=(
    "COUNTER_DAILY_SCRIPT"
    "COUNTER_WEEKLY_SCRIPT"
    "COUNTER_PROCESSOR_DIR"
)

PRODUCTION_COUNTER_VARS=(
    "PRODUCTION_COUNTER_DAILY_SCRIPT"
    "PRODUCTION_COUNTER_WEEKLY_SCRIPT"
    "PRODUCTION_COUNTER_PROCESSOR_DIR"
)

DB_VARS=(
    "PRODUCTION_SERVER" 
    "PRODUCTION_DB_HOST" 
    "DB_HOST" 
    "DB_NAME" 
    "DB_USER"
    "PRODUCTION_DB_NAME" 
    "PRODUCTION_DB_USER"
)

# Load environment variables
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
    source "${SCRIPT_DIR}/.env"
    log "Loaded environment variables from ${SCRIPT_DIR}/.env"
else
    log "Error: .env file not found in ${SCRIPT_DIR}."
    log "Please create a .env file in the script directory with required settings."
    log "Example: cp ${SCRIPT_DIR}/../upgrades/sample.env ${SCRIPT_DIR}/.env && nano ${SCRIPT_DIR}/.env"
    exit 1
fi

# Set SSH user for production server - use PRODUCTION_SSH_USER if defined, otherwise use current user
if [[ -z "$PRODUCTION_SSH_USER" ]]; then
    PRODUCTION_SSH_USER=$(whoami)
    log "PRODUCTION_SSH_USER not defined, using current user: $PRODUCTION_SSH_USER"
fi

# Check all required variable groups
check_required_vars "local Dataverse" "${DATAVERSE_VARS[@]}" || exit 1
check_required_vars "production Dataverse" "${PRODUCTION_VARS[@]}" || exit 1
check_required_vars "database connection" "${DB_VARS[@]}" || exit 1

log "All required environment variables are properly set."

# Parse command-line arguments
DRY_RUN=false
VERBOSE=false
SKIP_DB=false
SKIP_FILES=false
SKIP_SOLR=false
SKIP_COUNTER=false
SKIP_BACKUP=false

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --dry-run)
            DRY_RUN=true
            log "Running in DRY RUN mode - no changes will be made"
            shift
            ;;
        --verbose)
            VERBOSE=true
            log "Verbose mode enabled"
            shift
            ;;
        --skip-db)
            SKIP_DB=true
            log "Skipping database sync"
            shift
            ;;
        --skip-files)
            SKIP_FILES=true
            log "Skipping files sync"
            shift
            ;;
        --skip-solr)
            SKIP_SOLR=true
            log "Skipping Solr sync"
            shift
            ;;
        --skip-counter)
            SKIP_COUNTER=true
            log "Skipping counter processor sync"
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            log "Skipping backup of clone server before sync"
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --dry-run          Show what would be done without making changes"
            echo "  --verbose          Show detailed output"
            echo "  --skip-db          Skip database sync"
            echo "  --skip-files       Skip files sync"
            echo "  --skip-solr        Skip Solr sync"
            echo "  --skip-counter     Skip counter processor sync"
            echo "  --skip-backup      Skip backup of clone server before sync"
            echo "  --help             Show this help message"
            exit 0
            ;;
        *)
            log "Unknown option: $1"
            shift
            ;;
    esac
done

# Create temporary directory for operations
TEMP_DIR=$(mktemp -d)
log "Created temporary directory: $TEMP_DIR"

# Function to clean up temporary files
cleanup() {
    # Remove all temporary files and directories created during execution
    log "Cleaning up temporary files"
    rm -rf "$TEMP_DIR"
    log "Temporary files removed"
}

# Set trap to ensure cleanup on exit
trap cleanup EXIT

# Function for verbose output
verbose() {
    # Output detailed information when verbose mode is enabled
    # $1: Message to output
    if [ "$VERBOSE" = true ]; then
        log "$1"
    fi
}

# Function to list excluded files in dry run mode
list_excluded_files() {
    # Display information about files being excluded from transfer
    # $1: Directory being processed
    # $2: Message describing the exclusion
    local dir="$1"
    local exclusion_message="$2"
    
    if [ "$DRY_RUN" = true ]; then
        log "PRESERVED: $exclusion_message in $dir"
    fi
}

# Safety check - confirm we're not running on production
log "Performing safety check to ensure this is not the production server..."
if [ -f "$PAYARA/glassfish/domains/domain1/config/domain.xml" ]; then
    # Extract FQDN from domain.xml - find the dataverse.fqdn line and extract just the domain value
    LOCAL_FQDN=$(grep -oP 'dataverse\.fqdn=\K[^<>"[:space:]]+' "$PAYARA/glassfish/domains/domain1/config/domain.xml" || echo "unknown")

    if [[ "$LOCAL_FQDN" == "$PRODUCTION_DOMAIN" ]]; then
        log "ERROR: This script detected this is the PRODUCTION server (FQDN: $LOCAL_FQDN matches PRODUCTION_DOMAIN: $PRODUCTION_DOMAIN)!"
        log "This script should NOT be run on the production server. Exiting."
        exit 1
    fi
    
    log "Safety check passed - Running on non-production server (FQDN: $LOCAL_FQDN)"
else
    log "WARNING: Could not verify server identity from domain.xml. Proceeding with caution."
    log "If this is the production server, please abort now."
    echo -n "Are you SURE this is NOT the production server? Type 'yes' to continue: "
    read -r PRODUCTION_CONFIRMATION
    if [[ "$PRODUCTION_CONFIRMATION" != "yes" ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
fi

# Safety check - ensure we're not restoring to production database
if [[ "$DB_HOST" == "$PRODUCTION_DOMAIN" || "$DB_HOST" == "$PRODUCTION_DB_HOST" ]]; then
    log "ERROR: Your DB_HOST (${DB_HOST}) is set to the production domain or database host!"
    log "This would cause the script to restore TO the production database rather than FROM it."
    log "Please update your .env file to set DB_HOST to localhost or your clone server's database host."
    log "Example: DB_HOST=localhost"
    exit 1
fi

# Version compatibility check
if [ "$DRY_RUN" = false ]; then
    log "Checking version compatibility between production and clone..."
    PROD_VERSION=$(ssh "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER" "cat $PRODUCTION_DATAVERSE_CONTENT_STORAGE/version.txt" 2>/dev/null || echo "unknown")
    LOCAL_VERSION=$(cat "$DATAVERSE_CONTENT_STORAGE/version.txt" 2>/dev/null || echo "unknown")
    
    if [ "$PROD_VERSION" != "unknown" ] && [ "$LOCAL_VERSION" != "unknown" ] && [ "$PROD_VERSION" != "$LOCAL_VERSION" ]; then
        log "WARNING: Version mismatch detected. Production: $PROD_VERSION, Clone: $LOCAL_VERSION"
        echo -n "Version mismatch may cause issues. Continue anyway? (y/n): "
        read -r VERSION_CONFIRMATION
        if [[ "$VERSION_CONFIRMATION" != "y" && "$VERSION_CONFIRMATION" != "Y" ]]; then
            log "Operation cancelled by user due to version mismatch"
            exit 0
        fi
    fi
fi

# Create backup of the clone server before making changes
if [ "$SKIP_BACKUP" = false ] && [ "$DRY_RUN" = false ]; then
    log "Creating backup of clone server before syncing from production..."
    
    # Create backup directory
    BACKUP_DIR="$HOME/dataverse_clone_backup_$(date +"%Y%m%d_%H%M%S")"
    mkdir -p "$BACKUP_DIR"
    
    # Backup database
    log "Backing up local database..."
    # Use system authentication (pgpass or peer auth) rather than password
    pg_dump -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -c --no-owner > "$BACKUP_DIR/database_backup.sql"
    check_error "Failed to create local database backup"
    
    # Backup critical configuration files
    log "Backing up critical configuration files..."
    
    # Create configuration directory structure
    mkdir -p "$BACKUP_DIR/config"
    
    # Backup Payara domain.xml
    cp "$PAYARA/glassfish/domains/domain1/config/domain.xml" "$BACKUP_DIR/config/" 2>/dev/null || log "Warning: Could not backup domain.xml"
    
    # Backup local application settings
    if [ -d "$DATAVERSE_CONTENT_STORAGE/config" ]; then
        cp -r "$DATAVERSE_CONTENT_STORAGE/config" "$BACKUP_DIR/" || log "Warning: Could not backup Dataverse config dir"
    fi
    
    log "Clone server backup created at $BACKUP_DIR"
    log "In case of problems, you can restore from this backup"
fi

# Ask for confirmation before proceeding
if [ "$DRY_RUN" = false ]; then
    echo -n "This will sync data from production ($PRODUCTION_DOMAIN) to this server ($DOMAIN). Continue? (y/n): "
    read -r CONFIRMATION
    if [[ "$CONFIRMATION" != "y" && "$CONFIRMATION" != "Y" ]]; then
        log "Operation cancelled by user"
        exit 0
    fi
fi

log "Starting production data fetch from $PRODUCTION_DOMAIN to $DOMAIN"

# ==============================================================================
# 1. DATABASE BACKUP & RESTORE
# ==============================================================================
if [ "$SKIP_DB" = false ]; then
    log "=== DATABASE OPERATIONS ==="
    
    DB_DUMP_FILE="$TEMP_DIR/${PRODUCTION_DB_NAME}_dump.sql"
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would fetch database dump from $PRODUCTION_SERVER"
        log "DRY RUN: Would create database dump: $DB_DUMP_FILE"
        log "DRY RUN: Would restore database to $DB_HOST/$DB_NAME"
        log "PRESERVED: Local database credentials"
    else
        # Create database dump on production
        log "Creating database dump on production server..."
        ssh "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER" "sudo -u postgres pg_dump -d \"$PRODUCTION_DB_NAME\" -c --no-owner -f /tmp/dataverse_dump.sql && sudo chown \"$USER\": /tmp/dataverse_dump.sql"
        check_error "Failed to create database dump on production"
        
        # Copy database dump to local server
        log "Copying database dump from production..."
        rsync -avz "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER:/tmp/dataverse_dump.sql" "$DB_DUMP_FILE"
        check_error "Failed to copy database dump"
        
        # Clean up remote temp file
        ssh "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER" "rm -f /tmp/dataverse_dump.sql"
        
        # Modify domain-specific settings in the dump
        log "Updating domain-specific settings in database dump..."
        sed -i "s/$PRODUCTION_DOMAIN/$DOMAIN/g" "$DB_DUMP_FILE"
        
        # Restore database
        log "Restoring database to local server..."
        sudo -u postgres psql -h "$DB_HOST" -d "$DB_NAME" -f "$DB_DUMP_FILE"
        check_error "Failed to restore database"
        
        # Run post-restore SQL to disable unnecessary services on the clone
        log "Running post-restore SQL to update settings for non-production instance..."
        sudo -u postgres psql -h "$DB_HOST" -d "$DB_NAME" << EOF
-- Disable DOI registration if it exists
UPDATE setting SET content = 'false' WHERE name = 'DoiProvider.isActive';
-- Set site as non-production
INSERT INTO setting (name, content) VALUES ('SiteNotice', 'THIS IS A TEST INSTANCE - NOT PRODUCTION') 
ON CONFLICT (name) DO UPDATE SET content = 'THIS IS A TEST INSTANCE - NOT PRODUCTION';
-- Disable any email sending
UPDATE setting SET content = 'false' WHERE name IN ('SystemEmail.enabled', 'MailService.enabled');
EOF
        check_error "Failed to run post-restore SQL"
    fi
    
    log "Database operations completed"
fi

# ==============================================================================
# 2. DATAVERSE FILES
# ==============================================================================
if [ "$SKIP_FILES" = false ]; then
    log "=== DATAVERSE FILES OPERATIONS ==="
    
    # Files to exclude from copying
    EXCLUDE_FILES=(
        "--exclude=*.pem"
        "--exclude=*.key"
        "--exclude=*.keystore"
        "--exclude=*.jks"
        "--exclude=secrets.env"
        "--exclude=*.cer"
        "--exclude=*.crt"
        "--exclude=domain.xml"
        "--exclude=keyfile"
        "--exclude=password"
        "--exclude=.secret"
        "--exclude=.env"
    )
    
    # List exclusions in dry-run mode
    if [ "$DRY_RUN" = true ]; then
        list_excluded_files "$PRODUCTION_DATAVERSE_CONTENT_STORAGE" "SSL certificates and secrets"
        log "DRY RUN: Would copy dataverse files from $PRODUCTION_SERVER:$PRODUCTION_DATAVERSE_CONTENT_STORAGE to $DATAVERSE_CONTENT_STORAGE"
    else
        # Copy Dataverse files
        log "Copying Dataverse files from production..."
        if [[ "$FULL_COPY" == "true" ]]; then
            log "Performing FULL copy of Dataverse files"
            rsync -avz --stats "${EXCLUDE_FILES[@]}" \
                "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER:$PRODUCTION_DATAVERSE_CONTENT_STORAGE/" \
                "$DATAVERSE_CONTENT_STORAGE/"
        else
            log "Performing LIMITED copy of Dataverse files (max size: 2MB)"
            rsync -avz --stats --max-size=2M "${EXCLUDE_FILES[@]}" \
                "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER:$PRODUCTION_DATAVERSE_CONTENT_STORAGE/" \
                "$DATAVERSE_CONTENT_STORAGE/"
        fi
        check_error "Failed to copy Dataverse files"
    fi
    
    # Handle Payara configuration files
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would copy essential Payara configuration files (excluding domain.xml and credentials)"
    else
        # Copy only essential config files, excluding domain.xml which contains production-specific settings
        log "Copying essential Payara configuration files..."
        mkdir -p "$TEMP_DIR/payara_configs"
        ssh "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER" "find $PAYARA/glassfish/domains -name '*.properties' -not -path '*/domain.xml' -not -path '*password*' -not -path '*keyfile*'" | \
        while read -r file; do
            target_dir="$TEMP_DIR/payara_configs/$(dirname "${file#$PAYARA/glassfish/domains/}")"
            mkdir -p "$target_dir"
            rsync -avz "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER:$file" "$target_dir/"
        done
        
        # Process config files to remove production-specific settings
        find "$TEMP_DIR/payara_configs" -type f -name "*.properties" | while read -r file; do
            sed -i "s/$PRODUCTION_DOMAIN/$DOMAIN/g" "$file"
            cp "$file" "$PAYARA/glassfish/domains/$(dirname "${file#$TEMP_DIR/payara_configs/}")/$(basename "$file")"
        done
    fi
    
    log "Dataverse files operations completed"
fi

# ==============================================================================
# 3. SOLR INDEX & CONFIG
# ==============================================================================
if [ "$SKIP_SOLR" = false ]; then
    log "=== SOLR OPERATIONS ==="
    
    # Define Solr directories to sync
    SOLR_CONFIG_DIR="$SOLR_PATH/server/solr/collection1/conf"
    SOLR_PROD_CONFIG_DIR="$PRODUCTION_SOLR_PATH/server/solr/collection1/conf"
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would copy Solr configuration from $PRODUCTION_SERVER:$SOLR_PROD_CONFIG_DIR to $SOLR_CONFIG_DIR"
        list_excluded_files "$PRODUCTION_SOLR_PATH" "Solr SSL configurations and credentials"
    else
        # Ensure Solr is stopped on the local server
        log "Stopping local Solr service..."
        if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl stop solr || log "Warning: Could not stop Solr service. It may not be running."
        else
            sudo service solr stop || log "Warning: Could not stop Solr service. It may not be running."
        fi
        
        # Copy Solr configuration
        log "Copying Solr configuration from production..."
        rsync -avzP --stats \
            --exclude="*.keystore" \
            --exclude="*.jks" \
            --exclude="security.json" \
            "$PRODUCTION_SOLR_USER@$PRODUCTION_SERVER:$SOLR_PROD_CONFIG_DIR/" \
            "$SOLR_CONFIG_DIR/"
        check_error "Failed to copy Solr configuration"
        
        # Optionally copy Solr data (indexes)
        read -p "Do you want to copy Solr indexes? This may take a long time. (y/n): " COPY_INDEXES
        if [[ "$COPY_INDEXES" == "y" || "$COPY_INDEXES" == "Y" ]]; then
            SOLR_DATA_DIR="$SOLR_PATH/server/solr/collection1/data"
            SOLR_PROD_DATA_DIR="$PRODUCTION_SOLR_PATH/server/solr/collection1/data"
            
            log "Copying Solr indexes from production..."
            rsync -avzP --stats \
                "$PRODUCTION_SOLR_USER@$PRODUCTION_SERVER:$SOLR_PROD_DATA_DIR/" \
                "$SOLR_DATA_DIR/"
            check_error "Failed to copy Solr indexes"
        else
            log "Skipping Solr indexes copy. You may need to reindex."
        fi
        
        # Start Solr service
        log "Starting local Solr service..."
        if command -v systemctl >/dev/null 2>&1; then
            sudo systemctl start solr
        else
            sudo service solr start
        fi
        check_error "Failed to start Solr service"
    fi
    
    log "Solr operations completed"
fi

# ==============================================================================
# 4. COUNTER PROCESSOR
# ==============================================================================
if [ "$SKIP_COUNTER" = false ]; then
    # Check if counter processor variables are set
    if ! check_counter_vars; then
        log "Skipping counter processor operations - one or more required variables not set"
        SKIP_COUNTER=true
    fi
fi

if [ "$SKIP_COUNTER" = false ]; then
    log "=== COUNTER PROCESSOR OPERATIONS ==="
    
    if [ "$DRY_RUN" = true ]; then
        log "DRY RUN: Would copy counter-processor from $PRODUCTION_SERVER:$PRODUCTION_COUNTER_PROCESSOR_DIR to $COUNTER_PROCESSOR_DIR"
        log "DRY RUN: Would update counter daily script from $PRODUCTION_SERVER:$PRODUCTION_COUNTER_DAILY_SCRIPT to $COUNTER_DAILY_SCRIPT"
        log "DRY RUN: Would update counter weekly script from $PRODUCTION_SERVER:$PRODUCTION_COUNTER_WEEKLY_SCRIPT to $COUNTER_WEEKLY_SCRIPT"
    else
        # Copy counter processor directory
        log "Copying counter processor from production..."
        rsync -avzP --stats \
            --exclude="*.log" \
            --exclude="application.properties" \
            "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER:$PRODUCTION_COUNTER_PROCESSOR_DIR/" \
            "$COUNTER_PROCESSOR_DIR/"
        check_error "Failed to copy counter processor"
        
        # Copy application.properties separately and update it
        ssh "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER" "cat $PRODUCTION_COUNTER_PROCESSOR_DIR/application.properties" > "$TEMP_DIR/counter_application.properties"
        sed -i "s/$PRODUCTION_DOMAIN/$DOMAIN/g" "$TEMP_DIR/counter_application.properties"
        cp "$TEMP_DIR/counter_application.properties" "$COUNTER_PROCESSOR_DIR/application.properties"
        
        # Copy counter daily script
        log "Copying counter daily script from production..."
        # Use sudo to read the file on production if needed
        ssh "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER" "sudo cat $PRODUCTION_COUNTER_DAILY_SCRIPT" > "$TEMP_DIR/counter_daily_script"
        check_error "Failed to read counter daily script from production"
        
        # Update paths in the script
        sed -i "s|$PRODUCTION_COUNTER_PROCESSOR_DIR|$COUNTER_PROCESSOR_DIR|g" "$TEMP_DIR/counter_daily_script"
        # Use sudo to write to the destination
        sudo cp "$TEMP_DIR/counter_daily_script" "$COUNTER_DAILY_SCRIPT"
        check_error "Failed to copy counter daily script to local path"
        
        # Copy counter weekly script
        log "Copying counter weekly script from production..."
        # Use sudo to read the file on production if needed
        ssh "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER" "sudo cat $PRODUCTION_COUNTER_WEEKLY_SCRIPT" > "$TEMP_DIR/counter_weekly_script"
        check_error "Failed to read counter weekly script from production"
        
        # Update paths in the script
        sed -i "s|$PRODUCTION_COUNTER_PROCESSOR_DIR|$COUNTER_PROCESSOR_DIR|g" "$TEMP_DIR/counter_weekly_script"
        # Use sudo to write to the destination
        sudo cp "$TEMP_DIR/counter_weekly_script" "$COUNTER_WEEKLY_SCRIPT"
        check_error "Failed to copy counter weekly script to local path"
    fi
    
    log "Counter processor operations completed"
fi

# ==============================================================================
# 5. CRON JOBS
# ==============================================================================
log "=== CRON JOBS OPERATIONS ==="

CRON_TEMP_FILE="$TEMP_DIR/production_crontab"

if [ "$DRY_RUN" = true ]; then
    log "DRY RUN: Would fetch and review production cron jobs"
    log "PRESERVED: Would not automatically apply cron jobs to avoid scheduling conflicts"
else
    # Fetch production crontab
    log "Fetching production crontab..."
    ssh "$PRODUCTION_SSH_USER@$PRODUCTION_SERVER" "crontab -l" > "$CRON_TEMP_FILE" 2>/dev/null || echo "# No crontab found on production" > "$CRON_TEMP_FILE"
    
    # Process crontab to replace production paths
    sed -i "s|$PRODUCTION_DATAVERSE_CONTENT_STORAGE|$DATAVERSE_CONTENT_STORAGE|g" "$CRON_TEMP_FILE"
    sed -i "s|$PRODUCTION_COUNTER_PROCESSOR_DIR|$COUNTER_PROCESSOR_DIR|g" "$CRON_TEMP_FILE"
    sed -i "s|$PRODUCTION_DOMAIN|$DOMAIN|g" "$CRON_TEMP_FILE"
    
    # Add comment at the top
    sed -i '1i# Modified crontab from production - REVIEW BEFORE APPLYING' "$CRON_TEMP_FILE"
    sed -i '2i# Applied on staging server on '"$(date)"'' "$CRON_TEMP_FILE"
    
    log "Production crontab modified for staging environment"
    log "Crontab saved to $TEMP_DIR/production_crontab"
    log "IMPORTANT: Review the crontab file manually and apply it using 'crontab $TEMP_DIR/production_crontab' if desired"
    
    # Move crontab file to home directory for easier access
    cp "$CRON_TEMP_FILE" "$HOME/dataverse_crontab_for_review"
    log "Crontab also copied to $HOME/dataverse_crontab_for_review for your review"
fi

# ==============================================================================
# 6. POST-SYNC CHECKS & ADJUSTMENTS
# ==============================================================================
log "=== POST-SYNC OPERATIONS ==="

if [ "$DRY_RUN" = true ]; then
    log "DRY RUN: Would update file permissions and ownership"
    log "DRY RUN: Would perform post-sync validation checks"
else
    # Fix permissions on all copied files
    log "Updating file permissions and ownership..."
    
    # Fix Dataverse files permissions
    if [ "$SKIP_FILES" = false ]; then
        sudo chown -R "$DATAVERSE_USER:" "$DATAVERSE_CONTENT_STORAGE"
        check_error "Failed to update Dataverse files ownership"
    fi
    
    # Fix Solr permissions
    if [ "$SKIP_SOLR" = false ]; then
        sudo chown -R "$SOLR_USER:" "$SOLR_PATH"
        check_error "Failed to update Solr files ownership"
    fi
    
    # Fix Counter processor permissions
    if [ "$SKIP_COUNTER" = false ]; then
        if check_counter_vars; then
            sudo chown -R "$DATAVERSE_USER:" "$COUNTER_PROCESSOR_DIR"
            sudo chmod +x "$COUNTER_DAILY_SCRIPT"
            sudo chmod +x "$COUNTER_WEEKLY_SCRIPT"
            check_error "Failed to update Counter processor files ownership/permissions"
        fi
    fi
    
    log "Permissions and ownership updated"
    
    # Restart services if needed
    log "IMPORTANT: You may need to restart Dataverse services now"
    log "Consider running: sudo systemctl restart payara"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================
log "=== SYNC SUMMARY ==="

if [ "$DRY_RUN" = true ]; then
    log "DRY RUN COMPLETED - No changes were made"
    log "The following operations would have been performed:"
    [ "$SKIP_BACKUP" = false ] && log "- Backup of clone server before sync"
    [ "$SKIP_DB" = false ] && log "- Database backup and restore from Production:$PRODUCTION_DB_NAME to Local:$DB_NAME"
    [ "$SKIP_FILES" = false ] && log "- Dataverse files sync from Production:$PRODUCTION_DATAVERSE_CONTENT_STORAGE to Local:$DATAVERSE_CONTENT_STORAGE"
    [ "$SKIP_SOLR" = false ] && log "- Solr configuration sync from Production:$PRODUCTION_SOLR_PATH to Local:$SOLR_PATH"
    [ "$SKIP_COUNTER" = false ] && log "- Counter processor sync from Production:$PRODUCTION_COUNTER_PROCESSOR_DIR to Local:$COUNTER_PROCESSOR_DIR"
    
    log "The following would NOT have been copied (preserved locally):"
    log "- SSL certificates and private keys"
    log "- Domain-specific configuration in Payara domain.xml"
    log "- Secret keys and credentials"
    log "- Solr security configurations" 
    log "- Production-specific cron jobs (would require manual review)"
    log "- Local .env file"
else
    log "SYNC COMPLETED SUCCESSFULLY"
    log "The following operations were performed:"
    [ "$SKIP_BACKUP" = false ] && log "- Backup of clone server created at $BACKUP_DIR"
    [ "$SKIP_DB" = false ] && log "- Database backup and restore from Production:$PRODUCTION_DB_NAME to Local:$DB_NAME"
    [ "$SKIP_FILES" = false ] && log "- Dataverse files sync from Production:$PRODUCTION_DATAVERSE_CONTENT_STORAGE to Local:$DATAVERSE_CONTENT_STORAGE"
    [ "$SKIP_SOLR" = false ] && log "- Solr configuration sync from Production:$PRODUCTION_SOLR_PATH to Local:$SOLR_PATH"
    [ "$SKIP_COUNTER" = false ] && log "- Counter processor sync from Production:$PRODUCTION_COUNTER_PROCESSOR_DIR to Local:$COUNTER_PROCESSOR_DIR"
    
    log "IMPORTANT NEXT STEPS:"
    log "1. Review modified crontab at $HOME/dataverse_crontab_for_review"
    log "2. Verify database settings were properly updated (domain names, etc.)"
    log "3. Check that Solr is properly configured and indexes are available"
    log "4. Restart Payara/Glassfish server if needed"
    log "5. Test the staging instance to ensure it works correctly"
    log "6. Verify the site notice indicates this is a test/staging instance"
    
    # Provide rollback instructions
    log "7. If needed, you can roll back using the backup at $BACKUP_DIR"
fi

# Add hints for troubleshooting
log "IMPORTANT: If you encounter issues, please check the logs in $PAYARA/glassfish/domains/domain1/logs"
log "TROUBLESHOOTING HINTS:"
log "- Check logs in $PAYARA/glassfish/domains/domain1/logs if Dataverse fails to start"
log "- Verify Solr service is running: systemctl status solr"
log "- Check database connectivity (make sure you're using localhost or your local DB server): psql -h $DB_HOST -U postgres -d $DB_NAME -c 'SELECT 1'"

log "Script completed at $(date)"
