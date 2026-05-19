# CORS Migration for Dataverse 6.7

## Overview

This document describes the CORS (Cross-Origin Resource Sharing) migration feature added to the Dataverse 6.6 to 6.7 upgrade script. This migration addresses CORS errors that can occur when uploading folders or making cross-origin API requests.

## Background

According to the [Filter-efficiency.md](https://raw.githubusercontent.com/GlobalDataverseCommunityConsortium/dataverse/refs/heads/develop/doc/release-notes/Filter-efficiency.md) release notes, Dataverse 6.7 introduces new JVM options for CORS configuration that replace the deprecated database settings. This change improves performance and provides more efficient per-request handling of CORS headers and API calls.

## What Changed

### Deprecated Database Settings
- `:AllowCors`
- `:BlockedApiPolicy`
- `:BlockedApiEndpoints`
- `:BlockedApiKey`

### New JVM Options
- `dataverse.cors.origin`: Allowed origins for CORS requests
- `dataverse.cors.methods`: Allowed HTTP methods for CORS requests
- `dataverse.cors.headers.allow`: Allowed headers for CORS requests
- `dataverse.cors.headers.expose`: Headers to expose in CORS responses
- `dataverse.api.blocked.policy`: Policy for blocking API endpoints
- `dataverse.api.blocked.endpoints`: List of API endpoints to be blocked
- `dataverse.api.blocked.key`: Key for unblocking API endpoints

## Usage

### Standalone CORS Migration

To migrate CORS settings without running the full upgrade:

```bash
./shell/upgrades/upgrade_6_6_to_6_7.sh --migrate-cors
```

This will:
1. Check if CORS migration is needed
2. Migrate settings from database to JVM options
3. Restart Payara to apply changes
4. Clean up old database settings
5. Verify the migration was successful

### Dataverse Uploader CORS Fix

To specifically fix CORS issues with the Dataverse Uploader (gdcc.github.io):

```bash
./shell/upgrades/upgrade_6_6_to_6_7.sh --fix-uploader-cors
```

This will:
1. Check current CORS configuration
2. Test CORS functionality for gdcc.github.io
3. Apply specific fixes for Dataverse Uploader compatibility
4. Ensure proper CORS headers for preflight requests
5. Test the fix and provide verification

### Full Upgrade (Includes CORS Migration)

The CORS migration is automatically included in the full upgrade process:

```bash
./shell/upgrades/upgrade_6_6_to_6_7.sh
```

### Check Migration Status

To check if CORS migration is needed:

```bash
# Check current JVM options
sudo -u dataverse /usr/local/payara6/bin/asadmin list-jvm-options | grep cors

# Check old database settings
curl -s http://localhost:8080/api/admin/settings/:AllowCors
```

## Configuration Details

### CORS Origin
- **Default**: `*` (allows all origins)
- **Setting**: `-Ddataverse.cors.origin=*`
- **Purpose**: Controls which domains can make cross-origin requests

### CORS Methods
- **Default**: `GET,POST,PUT,DELETE,OPTIONS`
- **Setting**: `-Ddataverse.cors.methods=GET,POST,PUT,DELETE,OPTIONS`
- **Purpose**: Specifies allowed HTTP methods for CORS requests

### CORS Headers
- **Default**: `Content-Type,X-Requested-With,Accept,Origin,Access-Control-Request-Method,Access-Control-Request-Headers,X-Dataverse-key,X-Dataverse-unblock-key`
- **Setting**: `-Ddataverse.cors.headers.allow=Content-Type,X-Requested-With,Accept,Origin,Access-Control-Request-Method,Access-Control-Request-Headers,X-Dataverse-key,X-Dataverse-unblock-key`
- **Purpose**: Specifies which headers are allowed in CORS requests

### CORS Exposed Headers
- **Default**: `Access-Control-Allow-Origin,Access-Control-Allow-Methods,Access-Control-Allow-Headers,X-Dataverse-key,X-Dataverse-unblock-key`
- **Setting**: `-Ddataverse.cors.headers.expose=Access-Control-Allow-Origin,Access-Control-Allow-Methods,Access-Control-Allow-Headers,X-Dataverse-key,X-Dataverse-unblock-key`
- **Purpose**: Specifies which headers are exposed in CORS responses (important for Dataverse Uploader)

## Troubleshooting

### CORS Errors After Migration

If you're still experiencing CORS errors after migration:

1. **Check browser console** for specific error messages
2. **Verify JVM options** are set correctly:
   ```bash
   sudo -u dataverse /usr/local/payara6/bin/asadmin list-jvm-options | grep cors
   ```
3. **Check Payara logs** for errors:
   ```bash
   tail -50 /usr/local/payara6/glassfish/domains/domain1/logs/server.log
   ```
4. **Restart Payara** if needed:
   ```bash
   sudo systemctl restart payara
   ```

### Manual CORS Configuration

If you need to manually configure CORS settings:

```bash
# Set CORS origin
sudo -u dataverse /usr/local/payara6/bin/asadmin create-jvm-options "-Ddataverse.cors.origin=*"

# Set CORS methods
sudo -u dataverse /usr/local/payara6/bin/asadmin create-jvm-options "-Ddataverse.cors.methods=GET,POST,PUT,DELETE,OPTIONS"

# Set CORS headers
sudo -u dataverse /usr/local/payara6/bin/asadmin create-jvm-options "-Ddataverse.cors.headers.allow=Content-Type,X-Requested-With,Accept,Origin,Access-Control-Request-Method,Access-Control-Request-Headers,X-Dataverse-key,X-Dataverse-unblock-key"

# Set CORS exposed headers (important for Dataverse Uploader)
sudo -u dataverse /usr/local/payara6/bin/asadmin create-jvm-options "-Ddataverse.cors.headers.expose=Access-Control-Allow-Origin,Access-Control-Allow-Methods,Access-Control-Allow-Headers,X-Dataverse-key,X-Dataverse-unblock-key"

# Restart Payara
sudo systemctl restart payara
```

### Specific Domain Configuration

If you need to restrict CORS to specific domains instead of allowing all origins:

```bash
# Replace * with your specific domain(s)
sudo -u dataverse /usr/local/payara6/bin/asadmin create-jvm-options "-Ddataverse.cors.origin=https://yourdomain.com,https://api.yourdomain.com"
```

### Dataverse Uploader Specific Configuration

For Dataverse Uploader compatibility, ensure gdcc.github.io is included:

```bash
# Include gdcc.github.io for Dataverse Uploader
sudo -u dataverse /usr/local/payara6/bin/asadmin create-jvm-options "-Ddataverse.cors.origin=*,https://gdcc.github.io"
```

## Migration Logic

The migration script follows this logic:

1. **Check current state**: Are new JVM options already configured?
2. **Read old settings**: Get current values from database settings
3. **Apply new settings**: Create JVM options based on old settings
4. **Clean up**: Remove old database settings
5. **Restart**: Restart Payara to apply changes
6. **Verify**: Confirm migration was successful

### CORS Origin Logic

- If `:AllowCors` is `true`, `null`, `{}`, or not set → Set `dataverse.cors.origin=*`
- If `:AllowCors` is `false` → Don't set CORS origin (CORS disabled)

## Security Considerations

- The default configuration allows all origins (`*`) which is suitable for most installations
- For production environments, consider restricting CORS origins to specific domains
- The migration preserves existing API blocking policies and keys
- Password aliases are used for secure storage of API keys

## References

- [Filter-efficiency.md Release Notes](https://raw.githubusercontent.com/GlobalDataverseCommunityConsortium/dataverse/refs/heads/develop/doc/release-notes/Filter-efficiency.md)
- [Dataverse API Documentation](https://guides.dataverse.org/en/latest/api/)
- [CORS Specification](https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS) 