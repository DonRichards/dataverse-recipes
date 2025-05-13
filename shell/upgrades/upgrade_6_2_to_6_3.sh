#!/bin/bash
# Used release to generate this: https://github.com/IQSS/dataverse/releases/tag/v6.3

# Logging configuration
LOGFILE="dataverse_upgrade_6_2_to_6_3.log"
PAYARA_DOWNLOAD_URL="https://nexus.payara.fish/repository/payara-community/fish/payara/distributions/payara/6.2024.6/payara-6.2024.6.zip"
PAYARA_DOWNLOAD_HASH="5c67893491625d589f941309f8d83a36d1589ec8"
OLD_PAYARA_VERSION_DATE="$(date +%Y.%m)"
CITATION_TSV_URL="https://raw.githubusercontent.com/IQSS/dataverse/v6.3/scripts/api/data/metadatablocks/citation.tsv"
BIOLOGICAL_TSV_URL="https://raw.githubusercontent.com/IQSS/dataverse/v6.3/scripts/api/data/metadatablocks/biological.tsv"
COMPUTATIONAL_WORKFLOW_TSV_URL="https://raw.githubusercontent.com/IQSS/dataverse/v6.3/scripts/api/data/metadatablocks/computational_workflow.tsv"
SOLR_CONFIG_URL="https://raw.githubusercontent.com/IQSS/dataverse/v6.3/conf/solr/solrconfig.xml"
SOLR_SCHEMA_URL="https://raw.githubusercontent.com/IQSS/dataverse/v6.3/conf/solr/schema.xml"
UPDATE_FIELDS_URL="https://raw.githubusercontent.com/IQSS/dataverse/v6.3/conf/solr/update-fields.sh"
SOLR_VERSION="9.4.1"
TARGET_VERSION="6.3"

# Function to log and print messages
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOGFILE"
}

# Function to check for errors and exit if found
check_error() {
    if [ $? -ne 0 ]; then
        log "ERROR: $1. Exiting."
        exit 1
    fi
}

# Load environment variables from .env file
if [[ -f ".env" ]]; then
    source ".env"
    log "Loaded environment variables from .env file"
else
    log "Error: .env file not found. Please create one based on sample.env"
    exit 1
fi

# Required variables check
if [[ -z "$DOMAIN" || -z "$PAYARA" || -z "$DATAVERSE_USER" ]]; then
    log "Error: Required environment variables are not set in .env file."
    log "Please ensure DOMAIN, PAYARA, DATAVERSE_USER are defined."
    exit 1
fi

# If current user isn't dataverse, reload this script as the dataverse user
if [ "$USER" != "$DATAVERSE_USER" ]; then
    # Prompt user to confirm they want to continue
    read -p "Current user is not $DATAVERSE_USER. Continue? (y/n): " CONTINUE
    if [[ "$CONTINUE" != [Yy] ]]; then
        log "Exiting."
        exit 1
    fi
    log "Reloading script as $DATAVERSE_USER..."
    # Check if that user exists
    if ! id "$DATAVERSE_USER" > /dev/null 2>&1; then
        log "Error: User $DATAVERSE_USER does not exist."
        exit 1
    fi
    sudo -u "$DATAVERSE_USER" -i "$0" "$@"
    exit $?
fi

DATAVERSE_WAR_URL="https://github.com/IQSS/dataverse/releases/download/v6.3/dataverse-6.3.war"
# SHA1SUM HASH
DATAVERSE_WAR_HASH="264665217a80d4a6504b60a5978aa17f3b3205b5"
DATAVERSE_WAR_FILENAME="dataverse-6.3.war"
DATAVERSE_WAR_FILE="$DEPLOY_DIR/$DATAVERSE_WAR_FILENAME"
CURRENT_VERSION="6.2"
TARGET_VERSION="6.3"
PAYARA_EXPORT_LINE="export PAYARA=\"$PAYARA\""

# Ensure the script is not run as root
if [[ $EUID -eq 0 ]]; then
    log "Please do not run this script as root."
    log "This script runs several commands with sudo from within functions."
    exit 1
fi

# The potential issue is that files are only cleaned up in the success path of
# each function. If a function fails and returns an error, the temporary files
# may be left behind. This is a simple cleanup function that will clean up all
# potential temporary files.
cleanup_temp_files() {
    log "Cleaning up temporary files..."
    # Clean up all potential temporary files
    sudo rm -f "tmp/$DATAVERSE_WAR_FILENAME"
    log "Cleanup complete."
}

# Register cleanup function to run on script exit
trap cleanup_temp_files EXIT

# Function to check for required commands
check_required_commands() {
    local missing_commands=()
    local required_commands=(
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
        log "On Debian/Ubuntu systems, you can install them with:"
        log "sudo apt-get install curl grep sed sudo systemctl pgrep jq rm coreutils bash tee"
        log "On RHEL/CentOS systems, you can install them with:"
        log "sudo yum install curl grep sed sudo systemctl pgrep jq coreutils bash tee"
        exit 1
    fi
}

check_current_version() {
    local version response
    log "Checking current Dataverse version..."
    response=$(sudo -u dataverse $PAYARA/bin/asadmin list-applications)

    # Check if "No applications are deployed to this target server" is part of the response
    if [[ "$response" == *"No applications are deployed to this target server"* ]]; then
        log "No applications are deployed to this target server. Assuming upgrade is needed."
        return 0
    fi

    # If no such message, check the Dataverse version via the API
    version=$(curl -s "http://localhost:8080/api/info/version" | grep -oP '\d+\.\d+')

    # Check if the version matches the expected current version
    if [[ $version == "$CURRENT_VERSION" ]]; then
        log "Current version is $CURRENT_VERSION as expected. Proceeding with upgrade."
        return 0
    else
        log "Current Dataverse version is not $CURRENT_VERSION. Upgrade cannot proceed."
        return 1
    fi
}

# STEP 1: Undeploy the previous version
undeploy_dataverse() {
    if sudo -u dataverse $PAYARA/bin/asadmin list-applications | grep -q "dataverse-$CURRENT_VERSION"; then
        log "Undeploying current Dataverse version..."
        sudo -u dataverse $PAYARA/bin/asadmin undeploy dataverse-$CURRENT_VERSION || return 1
        log "Undeploy completed successfully."
    else
        log "Dataverse is not currently deployed. Skipping undeploy step."
    fi
}

# STEP 2: Stop Payara and remove directories
stop_payara() {
    if pgrep -f payara > /dev/null; then
        log "Stopping Payara service..."
        sudo systemctl stop payara || return 1
        log "Payara service stopped."
    else
        log "Payara is already stopped."
    fi
}

clean_payara_dirs() {
    log "Removing Payara generated directories..."
    if [ -d "$PAYARA/glassfish/domains/domain1/generated" ]; then
        rm -rf "$PAYARA/glassfish/domains/domain1/generated" || return 1
    fi
    
    if [ -d "$PAYARA/glassfish/domains/domain1/osgi-cache" ]; then
        rm -rf "$PAYARA/glassfish/domains/domain1/osgi-cache" || return 1
    fi
    
    if [ -d "$PAYARA/glassfish/domains/domain1/lib/databases" ]; then
        rm -rf "$PAYARA/glassfish/domains/domain1/lib/databases" || return 1
    fi
    
    log "Payara directories cleaned successfully."
    return 0
}

# Function to upgrade Payara to v6.2024.6
upgrade_payara() {
    log "Upgrading Payara to version 6.2024.6..."
    # Create a directory for temporary files if it doesn't exist
    mkdir -p tmp
    
    # Move current Payara directory out of the way
    log "Moving current Payara directory to $PAYARA.$OLD_PAYARA_VERSION_DATE"
    # If $PAYARA is a symlink, we need to follow it
    if [ -L "$PAYARA" ]; then
        sudo mv "$(readlink -f "$PAYARA")" "$PAYARA.$OLD_PAYARA_VERSION_DATE" || return 1
    else
        sudo mv "$PAYARA" "$PAYARA.$OLD_PAYARA_VERSION_DATE" || return 1
    fi
    
    # Download the new Payara version
    log "Downloading Payara 6.2024.6..."
    wget -P tmp "$PAYARA_DOWNLOAD_URL" || return 1
    # Verify the SHA1 hash of the downloaded file
    FILE_NAME=$(basename "$PAYARA_DOWNLOAD_URL")
    local CALCULATED_HASH=$(sha1sum tmp/$FILE_NAME | cut -d' ' -f1)
    if [ "$CALCULATED_HASH" != "$PAYARA_DOWNLOAD_HASH" ]; then
        log "ERROR: Payara download hash verification failed. Expected: $PAYARA_DOWNLOAD_HASH, got: $CALCULATED_HASH"
        rm -f tmp/$FILE_NAME
        return 1
    fi
    
    # Unzip the new version
    log "Extracting Payara 6.2024.6..."
    sudo unzip tmp/$FILE_NAME -d $(dirname "$PAYARA") || return 1
    
    # Rename the extracted directory if needed
    if [ "$(basename "$PAYARA")" != "payara6" ]; then
        sudo mv "$(dirname "$PAYARA")/payara6" "$PAYARA" || return 1
    fi
    
    # Preserve the old domain1
    log "Preserving the existing domain1 configuration..."
    sudo mv "$PAYARA/glassfish/domains/domain1" "$PAYARA/glassfish/domains/domain1_DIST" || return 1
    sudo mv "$PAYARA.$OLD_PAYARA_VERSION_DATE/glassfish/domains/domain1" "$PAYARA/glassfish/domains/" || return 1
    
    # Update domain.xml with required JVM options
    log "Updating domain.xml with required JVM options..."
    update_domain_xml_options || return 1
    
    log "Payara upgrade completed successfully."
    return 0
}

# Function to update domain.xml with required JVM options
update_domain_xml_options() {
    local DOMAIN_XML="$PAYARA/glassfish/domains/domain1/config/domain.xml"

    # Check if the file exists
    if [ ! -f "$DOMAIN_XML" ]; then
        log "ERROR: domain.xml not found at $DOMAIN_XML"
        return 1
    fi
    
    # Add required JVM options if not already present
    local REQUIRED_OPTIONS=(
        "--add-opens=java.management/javax.management=ALL-UNNAMED"
        "--add-opens=java.management/javax.management.openmbean=ALL-UNNAMED"
        "[17|]--add-opens=java.base/java.io=ALL-UNNAMED"
        "[21|]--add-opens=java.base/jdk.internal.misc=ALL-UNNAMED"
    )
    
    for OPTION in "${REQUIRED_OPTIONS[@]}"; do
        # Escape the option for grep
        ESCAPED_OPTION=$(echo "$OPTION" | sed 's/\[/\\[/g' | sed 's/\]/\\]/g' | sed 's/\./\\./g' | sed 's/\//\\\//g')
        
        # Check if the option already exists
        if ! grep -q "<jvm-options>$ESCAPED_OPTION</jvm-options>" "$DOMAIN_XML"; then
            # Replace any older version of the option (without the prefix) if it exists
            if [[ "$OPTION" == "[17|]--add-opens=java.base/java.io=ALL-UNNAMED" ]] && grep -q "<jvm-options>--add-opens=java.base/java.io=ALL-UNNAMED</jvm-options>" "$DOMAIN_XML"; then
                sudo sed -i 's|<jvm-options>--add-opens=java.base/java.io=ALL-UNNAMED</jvm-options>|<jvm-options>[17|]--add-opens=java.base/java.io=ALL-UNNAMED</jvm-options>|g' "$DOMAIN_XML"
            else
                # Insert the new option before the </java-config> tag
                sudo sed -i "s|</java-config>|    <jvm-options>$OPTION</jvm-options>\n</java-config>|" "$DOMAIN_XML"
            fi
            log "Added JVM option: $OPTION"
        else
            log "JVM option already exists: $OPTION"
        fi
    done
    
    return 0
}

# Function to deploy Dataverse 6.3
deploy_dataverse() {
    local DEPLOY_DIR=${DEPLOY_DIR:-tmp}
    mkdir -p "$DEPLOY_DIR"
    
    log "Downloading Dataverse 6.3 WAR file..."
    if [ ! -f "$DATAVERSE_WAR_FILE" ]; then
        wget -O "$DATAVERSE_WAR_FILE" "$DATAVERSE_WAR_URL" || return 1
        
        # Verify the SHA1 hash of the WAR file
        local CALCULATED_HASH=$(sha1sum "$DATAVERSE_WAR_FILE" | cut -d' ' -f1)
        if [ "$CALCULATED_HASH" != "$DATAVERSE_WAR_HASH" ]; then
            log "ERROR: WAR file hash verification failed. Expected: $DATAVERSE_WAR_HASH, got: $CALCULATED_HASH"
            rm -f "$DATAVERSE_WAR_FILE"
            return 1
        fi
    else
        log "WAR file already exists at $DATAVERSE_WAR_FILE. Skipping download."
    fi
    
    log "Deploying Dataverse 6.3..."
    sudo -u "$DATAVERSE_USER" "$PAYARA/bin/asadmin" deploy "$DATAVERSE_WAR_FILE" || return 1
    log "Dataverse 6.3 deployed successfully."
    return 0
}

# Function to update internationalization (optional)
update_internationalization() {
    log "NOTE: If you are using internationalization, please update translations via Dataverse language packs."
    log "This step must be performed manually as it depends on your specific language configuration."
    # Prompt the user if they'd like to continue
    read -p "Do you want to continue? (y/n): " CONTINUE
    if [[ "$CONTINUE" != [Yy] ]]; then
        log "Skipping internationalization update."
        return 0
    fi
    return 0
}

# Function to restart Payara
restart_payara() {
    log "Restarting Payara service..."
    sudo systemctl stop payara || return 1
    sleep 5
    sudo systemctl start payara || return 1
    
    # Wait for Payara to start
    log "Waiting for Payara to start..."
    local MAX_WAIT=300  # 5 minutes
    local COUNTER=0
    while [ $COUNTER -lt $MAX_WAIT ]; do
        if curl -s -f "http://localhost:8080/api/info/version" > /dev/null; then
            log "Payara started successfully."
            return 0
        fi
        sleep 5
        COUNTER=$((COUNTER + 5))
        log "Still waiting for Payara to start... ($COUNTER seconds)"
    done
    
    log "ERROR: Payara failed to start within $MAX_WAIT seconds."
    return 1
}

# Function to update metadata blocks
update_metadata_blocks() {
    log "Updating metadata blocks..."
    
    # Create a directory for temporary files if it doesn't exist
    mkdir -p tmp
    
    # Update citation.tsv
    log "Updating citation metadata block..."
    wget -O tmp/citation.tsv "$CITATION_TSV_URL" || return 1
    curl -s -f http://localhost:8080/api/admin/datasetfield/load -H "Content-type: text/tab-separated-values" -X POST --upload-file tmp/citation.tsv
    check_error "Failed to update citation metadata block"
    
    # Update biological.tsv
    log "Updating biological metadata block..."
    wget -O tmp/biological.tsv "$BIOLOGICAL_TSV_URL" || return 1
    curl -s -f http://localhost:8080/api/admin/datasetfield/load -H "Content-type: text/tab-separated-values" -X POST --upload-file tmp/biological.tsv
    check_error "Failed to update biological metadata block"
    
    # Ask if computational workflow metadata block is in use
    read -p "Are you using the optional computational workflow metadata block? (y/n): " USE_COMP_WORKFLOW
    if [[ "$USE_COMP_WORKFLOW" =~ ^[Yy]$ ]]; then
        log "Updating computational workflow metadata block..."
        wget -O tmp/computational_workflow.tsv "$COMPUTATIONAL_WORKFLOW_TSV_URL" || return 1
        curl -s -f http://localhost:8080/api/admin/datasetfield/load -H "Content-type: text/tab-separated-values" -X POST --upload-file tmp/computational_workflow.tsv
        check_error "Failed to update computational workflow metadata block"
    fi
    
    log "Metadata blocks updated successfully."
    return 0
}

# Function to upgrade Solr
upgrade_solr() {
    log "Upgrading Solr to version $SOLR_VERSION..."
    
    # Ask for Solr installation path
    read -p "Please enter the Solr installation directory (usually /usr/local/solr): " SOLR_DIR
    SOLR_DIR=${SOLR_DIR:-/usr/local/solr}
    
    # Check if Solr is installed
    if [ ! -d "$SOLR_DIR" ]; then
        log "ERROR: Solr directory not found at $SOLR_DIR"
        return 1
    fi
    
    # Create a directory for temporary files if it doesn't exist
    mkdir -p tmp
    
    # Download configuration files
    log "Downloading Solr configuration files..."
    wget -O tmp/solrconfig.xml "$SOLR_CONFIG_URL" || return 1
    wget -O tmp/schema.xml "$SOLR_SCHEMA_URL" || return 1
    
    # Copy configuration files
    log "Copying configuration files to Solr..."
    sudo cp tmp/solrconfig.xml tmp/schema.xml "$SOLR_DIR/solr-$SOLR_VERSION/server/solr/collection1/conf/" || return 1
    
    # Ask if there are custom or experimental metadata blocks
    read -p "Do you have custom or experimental metadata blocks? (y/n): " HAS_CUSTOM_METADATA
    if [[ "$HAS_CUSTOM_METADATA" =~ ^[Yy]$ ]]; then
        log "Stopping Solr service..."
        sudo systemctl stop solr || return 1
        
        log "Running update-fields.sh script..."
        wget -O tmp/update-fields.sh "$UPDATE_FIELDS_URL" || return 1
        chmod +x tmp/update-fields.sh
        curl -s "http://localhost:8080/api/admin/index/solr/schema" | tmp/update-fields.sh "$SOLR_DIR/solr-$SOLR_VERSION/server/solr/collection1/conf/schema.xml"
        check_error "Failed to update schema.xml with custom fields"
        
        log "Starting Solr service..."
        sudo systemctl start solr || return 1
    fi
    
    log "Solr upgraded successfully."
    return 0
}

# Function to enable metadata source facet (optional)
enable_metadata_source_facet() {
    log "Enabling metadata source facet is optional..."
    read -p "Do you want to enable the metadata source facet for harvested content? (y/n): " ENABLE_FACET
    
    if [[ "$ENABLE_FACET" =~ ^[Yy]$ ]]; then
        log "Enabling metadata source facet..."
        sudo -u "$DATAVERSE_USER" "$PAYARA/bin/asadmin" create-jvm-options "dataverse.feature.index-harvested-metadata-source=true" || return 1
        log "Metadata source facet enabled. A reindex will be required."
        REINDEX_REQUIRED=true
    else
        log "Skipping metadata source facet enablement."
    fi
    
    return 0
}

# Function to enable Solr optimizations (optional)
enable_solr_optimizations() {
    log "Enabling Solr optimizations is optional but recommended for large installations..."
    read -p "Do you want to enable Solr optimizations? (y/n): " ENABLE_OPTIMIZATIONS
    
    if [[ "$ENABLE_OPTIMIZATIONS" =~ ^[Yy]$ ]]; then
        log "Enabling Solr optimizations..."
        sudo -u "$DATAVERSE_USER" "$PAYARA/bin/asadmin" create-jvm-options "dataverse.feature.add-publicobject-solr-field=true" || return 1
        sudo -u "$DATAVERSE_USER" "$PAYARA/bin/asadmin" create-jvm-options "dataverse.feature.avoid-expensive-solr-join=true" || return 1
        sudo -u "$DATAVERSE_USER" "$PAYARA/bin/asadmin" create-jvm-options "dataverse.feature.reduce-solr-deletes=true" || return 1
        log "Solr optimizations enabled. A full reindex will be required."
        REINDEX_REQUIRED=true
    else
        log "Skipping Solr optimizations enablement."
    fi
    
    return 0
}

# Function to reindex Solr
reindex_solr() {
    if [ "$REINDEX_REQUIRED" = true ] || [ "$1" = "force" ]; then
        log "Reindexing Solr (this may take a while)..."
        curl -s -f http://localhost:8080/api/admin/index || return 1
        log "Solr reindexing initiated. Check server logs for progress."
    else
        log "Asking about Solr reindexing..."
        read -p "Do you want to reindex Solr? This is recommended if you upgraded Solr or enabled optional features. (y/n): " DO_REINDEX
        
        if [[ "$DO_REINDEX" =~ ^[Yy]$ ]]; then
            log "Reindexing Solr (this may take a while)..."
            curl -s -f http://localhost:8080/api/admin/index || return 1
            log "Solr reindexing initiated. Check server logs for progress."
        else
            log "Skipping Solr reindexing."
        fi
    fi
    
    return 0
}

# Function to migrate keywordTermURI (optional)
migrate_keyword_term_uri() {
    log "Data migration to the new keywordTermURI field is optional..."
    read -p "Do you want to check for and migrate keywordValue data containing URIs? (y/n): " MIGRATE_KEYWORDS
    
    if [[ "$MIGRATE_KEYWORDS" =~ ^[Yy]$ ]]; then
        log "Checking for keywordValue data containing URIs..."
        # This would require direct database access, so we'll provide instructions
        log "To view affected data, run this SQL query:"
        log "SELECT value FROM datasetfieldvalue dfv"
        log "INNER JOIN datasetfield df ON df.id = dfv.datasetfield_id"
        log "WHERE df.datasetfieldtype_id = (SELECT id FROM datasetfieldtype WHERE name = 'keywordValue')"
        log "AND value ILIKE 'http%';"
        
        log "To migrate the data, run this SQL query:"
        log "UPDATE datasetfield df"
        log "SET datasetfieldtype_id = (SELECT id FROM datasetfieldtype WHERE name = 'keywordTermURI')"
        log "FROM datasetfieldvalue dfv"
        log "WHERE dfv.datasetfield_id = df.id"
        log "AND df.datasetfieldtype_id = (SELECT id FROM datasetfieldtype WHERE name = 'keywordValue')"
        log "AND dfv.value ILIKE 'http%';"
        
        log "After migration, you must reindex Solr and run ReExportAll."
        read -p "Have you completed the database migration and want to reindex now? (y/n): " REINDEX_AFTER_MIGRATION
        
        if [[ "$REINDEX_AFTER_MIGRATION" =~ ^[Yy]$ ]]; then
            reindex_solr "force"
        fi
    else
        log "Skipping keywordTermURI data migration."
    fi
    
    return 0
}

# Function to verify upgrade
verify_upgrade() {
    log "Verifying upgrade..."
    
    # Check Dataverse version
    local VERSION=$(curl -s -f "http://localhost:8080/api/info/version" | grep -o '"version":"[^"]*' | cut -d'"' -f4)
    
    if [[ "$VERSION" == "$TARGET_VERSION"* ]]; then
        log "Dataverse version verified: $VERSION"
    else
        log "ERROR: Dataverse version verification failed. Expected: $TARGET_VERSION, got: $VERSION"
        return 1
    fi
    
    log "Upgrade verification completed successfully."
    return 0
}

# Function to perform rollback in case of failure
rollback_upgrade() {
    log "Rolling back the upgrade..."
    
    # Undeploy the new version
    log "Undeploying Dataverse $TARGET_VERSION..."
    sudo -u "$DATAVERSE_USER" "$PAYARA/bin/asadmin" undeploy dataverse-$TARGET_VERSION || true
    
    # Restore Payara from backup
    if [ -d "$PAYARA.$OLD_PAYARA_VERSION_DATE" ]; then
        log "Restoring Payara from backup..."
        sudo systemctl stop payara || true
        sudo rm -rf "$PAYARA"
        sudo mv "$PAYARA.$OLD_PAYARA_VERSION_DATE" "$PAYARA"
        sudo systemctl start payara || true
    fi
    
    log "Rollback completed. Please check the system and redeploy the previous version if necessary."
    return 0
}

# Main execution function
main() {
    log "Starting Dataverse upgrade from version $CURRENT_VERSION to $TARGET_VERSION..."
    
    # Check required commands
    check_required_commands
    check_error "Required commands check failed"
    
    # Check current version
    check_current_version
    check_error "Current version check failed"
    
    # Backup recommendation
    log "IMPORTANT: Before proceeding, ensure you have created backups of your database and Payara configuration."
    read -p "Have you created the necessary backups? (y/n): " HAS_BACKUP
    
    if [[ ! "$HAS_BACKUP" =~ ^[Yy]$ ]]; then
        log "Upgrade aborted. Please create backups before running this script again."
        exit 1
    fi
    
    # Initialize reindex flag
    REINDEX_REQUIRED=false
    
    # STEP 1: Undeploy the previous version
    undeploy_dataverse
    check_error "Failed to undeploy current Dataverse version"
    
    # STEP 2: Stop Payara and remove directories
    stop_payara
    check_error "Failed to stop Payara service"
    
    clean_payara_dirs
    check_error "Failed to clean Payara directories"
    
    # STEP 3: Upgrade Payara
    upgrade_payara
    check_error "Failed to upgrade Payara"
    
    # STEP 4: Deploy new version
    deploy_dataverse
    check_error "Failed to deploy new Dataverse version"
    
    # STEP 5: Update internationalization
    update_internationalization
    
    # STEP 6: Restart Payara
    restart_payara
    check_error "Failed to restart Payara service"
    
    # STEP 7: Update metadata blocks
    update_metadata_blocks
    check_error "Failed to update metadata blocks"
    
    # STEP 8: Upgrade Solr
    upgrade_solr
    check_error "Failed to upgrade Solr"
    
    # STEP 9: Enable optional features
    enable_metadata_source_facet
    enable_solr_optimizations
    
    # STEP 10: Reindex Solr
    reindex_solr
    
    # Optional: Data migration for keywordTermURI
    migrate_keyword_term_uri
    
    # Verify upgrade
    verify_upgrade
    if [ $? -ne 0 ]; then
        log "Upgrade verification failed. Do you want to roll back? (y/n): "
        read SHOULD_ROLLBACK
        
        if [[ "$SHOULD_ROLLBACK" =~ ^[Yy]$ ]]; then
            rollback_upgrade
            exit 1
        fi
    fi
    
    log "Dataverse upgrade from version $CURRENT_VERSION to $TARGET_VERSION completed successfully!"
    return 0
}

# Execute the main function
main
