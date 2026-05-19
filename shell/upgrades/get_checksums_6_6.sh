#!/bin/bash
# Helper script to obtain SHA256 checksums for Dataverse 6.5 to 6.6 upgrade
# Run this script to get the checksums needed for the upgrade script

set -e

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
echo "Dataverse 6.6 Upgrade - Checksum Helper"
echo "========================================"
echo ""

# URLs for the files we need to checksum
PAYARA_URL="https://nexus.payara.fish/repository/payara-community/fish/payara/distributions/payara/6.2025.2/payara-6.2025.2.zip"
DATAVERSE_URL="https://github.com/IQSS/dataverse/releases/download/v6.6/dataverse-6.6.war"

# Create temporary directory
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

echo "Downloading files to calculate checksums..."
echo "This may take a few minutes depending on your connection speed."
echo ""

# Download Payara
echo "1. Downloading Payara 6.2025.2..."
if wget -q --show-progress "$PAYARA_URL"; then
    PAYARA_SHA256=$(sha256sum payara-6.2025.2.zip | cut -d' ' -f1)
    echo "   ✓ Downloaded successfully"
else
    echo "   ✗ Download failed"
    PAYARA_SHA256="DOWNLOAD_FAILED"
fi

echo ""

# Download Dataverse WAR
echo "2. Downloading Dataverse 6.6 WAR..."
if wget -q --show-progress "$DATAVERSE_URL"; then
    DATAVERSE_SHA256=$(sha256sum dataverse-6.6.war | cut -d' ' -f1)
    echo "   ✓ Downloaded successfully"
else
    echo "   ✗ Download failed"
    DATAVERSE_SHA256="DOWNLOAD_FAILED"
fi

echo ""
echo "Results:"
echo "========"
echo ""

if [ "$PAYARA_SHA256" != "DOWNLOAD_FAILED" ]; then
    echo "Payara 6.2025.2 SHA256:"
    echo "PAYARA_SHA256=\"$PAYARA_SHA256\""
else
    echo "Payara 6.2025.2 SHA256: DOWNLOAD FAILED"
fi

echo ""

if [ "$DATAVERSE_SHA256" != "DOWNLOAD_FAILED" ]; then
    echo "Dataverse 6.6 WAR SHA256:"
    echo "DATAVERSE_WAR_SHA256=\"$DATAVERSE_SHA256\""
else
    echo "Dataverse 6.6 WAR SHA256: DOWNLOAD FAILED"
fi

echo ""
echo "Instructions:"
echo "============"
echo "1. Copy the SHA256 values above"
echo "2. Edit the upgrade_6_5_to_6_6.sh script"
echo "3. Replace the placeholder values with the checksums above:"
echo ""
echo "   # Replace these lines in the script:"
echo "   PAYARA_SHA256=\"REPLACE_WITH_OFFICIAL_PAYARA_6_2025_2_SHA256\""
echo "   DATAVERSE_WAR_SHA256=\"REPLACE_WITH_OFFICIAL_DATAVERSE_6_6_WAR_SHA256\""
echo ""
echo "   # With:"
if [ "$PAYARA_SHA256" != "DOWNLOAD_FAILED" ]; then
    echo "   PAYARA_SHA256=\"$PAYARA_SHA256\""
fi
if [ "$DATAVERSE_SHA256" != "DOWNLOAD_FAILED" ]; then
    echo "   DATAVERSE_WAR_SHA256=\"$DATAVERSE_SHA256\""
fi

echo ""
echo "4. Save the script and run the upgrade"

# Clean up
cd "$SCRIPT_DIR"
rm -rf "$TMP_DIR"

echo ""
echo "Temporary files cleaned up."
echo "Checksum generation complete!" 