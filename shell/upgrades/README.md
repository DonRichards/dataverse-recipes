# Dataverse 6.5 to 6.6 Upgrade Script

This directory contains the upgrade script and configuration files for upgrading Dataverse from version 6.5 to 6.6.

## Files

- `upgrade_6_5_to_6_6.sh` - Main upgrade script
- `env.example` - Example environment configuration file
- `generate_env.sh` - Helper script to create .env file
- `README.md` - This documentation file

## Dynamic Configuration

The upgrade script now supports dynamic configuration of software metadata fields through environment variables. This makes the script more flexible and production-ready.

### How to Use

**Option 1: Use the helper script (recommended):**
```bash
./generate_env.sh
nano .env  # Edit the configuration
./upgrade_6_5_to_6_6.sh
```

**Option 2: Manual setup:**
```bash
cp env.example .env
nano .env  # Edit the configuration
./upgrade_6_5_to_6_6.sh
```

**Option 3: Use defaults (no .env file):**
```bash
./upgrade_6_5_to_6_6.sh  # Uses default values
```

### Configuration Options

Each software metadata field can be configured with one of these values:

- `true` - Field will be added as multi-valued (can contain multiple values)
- `false` - Field will be added as single-valued (can contain only one value)
- `disabled` - Field will be skipped entirely (not added to schema)

### Example Customizations

**Make swLicense multi-valued instead of single-valued:**
```bash
SOFTWARE_FIELD_SWLICENSE=true
```

**Disable a field entirely:**
```bash
SOFTWARE_FIELD_SWVERSION=disabled
```

**Change a multi-valued field to single-valued:**
```bash
SOFTWARE_FIELD_SWCONTRIBUTORNAME=false
```

### Fallback Behavior

If no `.env` file exists, the script will use the default values that match the original Dataverse 6.6 specification. This ensures backward compatibility.

### Benefits

1. **Flexibility**: Customize field behavior without modifying the script
2. **Environment-specific**: Different configurations for dev/staging/production
3. **Maintainable**: Easy to update field configurations
4. **Production-ready**: Supports different deployment scenarios
5. **Backward compatible**: Works with or without `.env` file

### Security Note

The `.env` file contains configuration only and no sensitive data. However, ensure proper file permissions:

```bash
chmod 600 .env
```

This prevents other users from reading your configuration. 