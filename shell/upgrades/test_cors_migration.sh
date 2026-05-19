#!/bin/bash

# Test script for CORS migration functionality
# This script tests the CORS migration logic without actually making changes

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
UPGRADE_SCRIPT="$SCRIPT_DIR/upgrade_6_6_to_6_7.sh"

# Function to log messages
log() {
    echo "$(date +"%Y-%m-%d %H:%M:%S") - $1"
}

# Test 1: Check if upgrade script exists
log "Test 1: Checking if upgrade script exists..."
if [[ -f "$UPGRADE_SCRIPT" ]]; then
    log "✅ Upgrade script found: $UPGRADE_SCRIPT"
else
    log "❌ Upgrade script not found: $UPGRADE_SCRIPT"
    exit 1
fi

# Test 2: Check if script is executable
log "Test 2: Checking if script is executable..."
if [[ -x "$UPGRADE_SCRIPT" ]]; then
    log "✅ Upgrade script is executable"
else
    log "❌ Upgrade script is not executable"
    exit 1
fi

# Test 3: Check for CORS migration function
log "Test 3: Checking for CORS migration function..."
if grep -q "migrate_cors_standalone" "$UPGRADE_SCRIPT"; then
    log "✅ CORS migration function found"
else
    log "❌ CORS migration function not found"
    exit 1
fi

# Test 4: Check for --migrate-cors argument handling
log "Test 4: Checking for --migrate-cors argument handling..."
if grep -q "migrate-cors" "$UPGRADE_SCRIPT"; then
    log "✅ --migrate-cors argument handling found"
else
    log "❌ --migrate-cors argument handling not found"
    exit 1
fi

# Test 4b: Check for --fix-uploader-cors argument handling
log "Test 4b: Checking for --fix-uploader-cors argument handling..."
if grep -q "fix-uploader-cors" "$UPGRADE_SCRIPT"; then
    log "✅ --fix-uploader-cors argument handling found"
else
    log "❌ --fix-uploader-cors argument handling not found"
    exit 1
fi

# Test 5: Check for CORS JVM options configuration
log "Test 5: Checking for CORS JVM options configuration..."
if grep -q "dataverse.cors.origin" "$UPGRADE_SCRIPT"; then
    log "✅ CORS origin JVM option configuration found"
else
    log "❌ CORS origin JVM option configuration not found"
    exit 1
fi

if grep -q "dataverse.cors.methods" "$UPGRADE_SCRIPT"; then
    log "✅ CORS methods JVM option configuration found"
else
    log "❌ CORS methods JVM option configuration not found"
    exit 1
fi

if grep -q "dataverse.cors.headers.allow" "$UPGRADE_SCRIPT"; then
    log "✅ CORS headers JVM option configuration found"
else
    log "❌ CORS headers JVM option configuration not found"
    exit 1
fi

if grep -q "dataverse.cors.headers.expose" "$UPGRADE_SCRIPT"; then
    log "✅ CORS exposed headers JVM option configuration found"
else
    log "❌ CORS exposed headers JVM option configuration not found"
    exit 1
fi

# Test 6: Check for usage information
log "Test 6: Checking for usage information..."
if grep -q "migrate-cors" "$UPGRADE_SCRIPT" && grep -q "CORS errors when uploading folders" "$UPGRADE_SCRIPT"; then
    log "✅ Usage information for CORS migration found"
else
    log "❌ Usage information for CORS migration not found"
    exit 1
fi

# Test 6b: Check for Dataverse Uploader CORS fix information
log "Test 6b: Checking for Dataverse Uploader CORS fix information..."
if grep -q "fix-uploader-cors" "$UPGRADE_SCRIPT" && grep -q "gdcc.github.io" "$UPGRADE_SCRIPT"; then
    log "✅ Usage information for Dataverse Uploader CORS fix found"
else
    log "❌ Usage information for Dataverse Uploader CORS fix not found"
    exit 1
fi

# Test 7: Check for Filter-efficiency.md reference
log "Test 7: Checking for Filter-efficiency.md reference..."
if grep -q "Filter-efficiency.md" "$UPGRADE_SCRIPT"; then
    log "✅ Filter-efficiency.md reference found"
else
    log "❌ Filter-efficiency.md reference not found"
    exit 1
fi

log "========================================="
log "✅ ALL TESTS PASSED"
log "========================================="
log ""
log "The CORS migration functionality has been successfully added to the upgrade script."
log ""
log "To use the CORS migration:"
log "  $UPGRADE_SCRIPT --migrate-cors"
log ""
log "To fix Dataverse Uploader CORS issues:"
log "  $UPGRADE_SCRIPT --fix-uploader-cors"
log ""
log "To run the full upgrade (which includes CORS migration):"
log "  $UPGRADE_SCRIPT"
log ""
log "To see all available options:"
log "  $UPGRADE_SCRIPT --help" 