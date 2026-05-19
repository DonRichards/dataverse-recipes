# Code Style Guide for Upgrade README Documentation
If using an AI driven editor, use this style guide to ensure the documentation is consistent and easy to read.

## 1. Directory Documentation Structure

### 1.1 Header Format
```markdown
# Dataverse Upgrade Scripts

This directory contains scripts for upgrading Dataverse installations between different versions.
```

### 1.2 Available Scripts Section
List all upgrade scripts with links to their corresponding release notes:
```markdown
## Available Upgrade Scripts

- `script_name.sh` - Upgrades Dataverse from version X.Y to [Z.W](link-to-release-notes)
```

## 2. Prerequisites Section

### 2.1 System Requirements
List required system commands with installation instructions for different OS:
```markdown
## Prerequisites

1. Required system commands:
   \```bash
   # On Debian/Ubuntu:
   sudo apt-get install [required-packages]

   # On RHEL/CentOS:
   sudo yum install [required-packages]
   \```
```

### 2.2 Permissions and Configuration
Specify required permissions and configuration steps:
```markdown
2. Proper permissions:
   - [permission requirements]

3. Configuration:
   - [configuration steps]
```

## 3. Usage Section

### 3.1 Backup Instructions
```markdown
## Usage

1. Backup your system:
   ```bash
   # Backup commands
   ```
```

### 3.2 Upgrade Execution
```markdown
2. Run the appropriate upgrade script:
   ```bash
   ./script_name.sh
   ```

3. Monitoring instructions:
   - [monitoring steps]
```

## 4. Troubleshooting Section

### 4.1 Common Issues Format
```markdown
## Troubleshooting

Common issues and solutions:

1. Issue category:
   - Check specific logs
   - Verification steps
   - Solution steps
```

## 5. Rollback Section

### 5.1 Rollback Instructions Format
```markdown
## Rollback

If the upgrade fails:

1. Step category:
   ```bash
   # Command to execute
   ```
```

## 6. Implementation Notes Section

### 6.1 Component Upgrades Format
```markdown
# Component Name vX.Y Upgrade Implementation Notes

## Component Upgrades

### Component Name
- **Release Note**: [requirement]
- **Implementation**: `function_name()` [Line XXX]
- **Verification**: 
```bash
verification_command
```
```

### 6.2 Breaking Changes Format
```markdown
## Breaking Changes

### Change Name
- **Release Note**: [description]
- **Implementation**: `function_name()` [Line XXX]
- **Documentation**: [link to docs]
```

### 6.3 Migration Steps Format
```markdown
## Migration Steps

### Configuration Type
1. **Component Name**
   - **Implementation**: `function_name()` [Line XXX]
   - **Files Affected**: 
     - file1
     - file2
```

## 7. Known Issues Section

### 7.1 Issue Format
```markdown
## Known Issues

### Issue Name
- **Release Note**: [description]
- **Status**: [implementation status]
- **Required Action**: [manual steps if needed]
```

## 8. Testing & Verification Section

### 8.1 Version Verification Format
```markdown
## Testing & Verification

### Version Verification
- **Implementation**: `function_name()` [Line XXX]
- **Components Checked**:
  - Component 1
  - Component 2
```

### 8.2 Performance Monitoring Format
```markdown
### Performance Monitoring
- **Implementation**: `function_name()` [Line XXX]
- **Threshold**: value
- **Check Interval**: value
```

## 9. Contributing Section
```markdown
## Contributing

1. Fork instructions
2. Branch creation
3. Change process
4. Pull request submission

This style guide reflects the actual structure used in the Dataverse upgrade documentation, making it easier to:
1. Maintain consistency across upgrade documentation
2. Provide clear instructions for users
3. Track implementation details
4. Document troubleshooting steps
5. Include rollback procedures

When updating documentation:
- Follow the section order as shown above
- Include all required sections
- Maintain consistent formatting
- Include specific command examples
- Link to relevant external documentation
```

Instructions for the AI:

I have a script at @shell/upgrades/upgrade_6_5_to_6_6.sh that needs review. It should closely follow the release notes in @shell/upgrades/VERSION\ Release\ Notes.md. I've added a lot for verification and to address issues encountered during development.

Can you perform a thorough review of this upgrade script to ensure the following:
  • There are no syntax errors.
  • All function calls or command executions handle returned values or failures appropriately.
  • The script reliably exits when encountering errors or unexpected conditions.
  • It is idempotent where possible, so repeated runs don’t cause unintended effects.

This script upgrades Dataverse from one version to the next and will be shared with other institutions. It needs to be production-ready, resilient in irregular environments, and safe in cases of incomplete configurations.

During development, some placeholder or obsolete code may have crept in. Please distinguish these from intentional verification steps or complex logic outlined in the release notes. Avoid removing any such steps unless they are clearly redundant or broken. When in doubt, cross-reference with VERSION Release Notes.md.

This upgrade script is intended to be enterprise-grade and demonstrates:
  • Professional error handling with explicit exit behavior
  • Production-level resilience with fallback mechanisms
  • Safety-first design with thorough validation
  • Compatibility across institutions and deployment environments
  • Detailed logging and monitoring throughout the process
  • The ability to resume from the last successful step in case of interruption

Please ensure the script upholds these standards and is ready for reliable use in production Dataverse environments.