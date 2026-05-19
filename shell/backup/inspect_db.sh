#!/bin/bash

# Database inspection script for PostgreSQL and MySQL
# Usage: ./inspect_db.sh [database_name] [database_type]
# Example: ./inspect_db.sh dvndb postgres
# Example: ./inspect_db.sh dvndb mysql
# If no database is specified, all databases will be inspected
# If no database type is specified, it will try to auto-detect

DB_NAME=$1
DB_TYPE=$2

# Get user's home directory
USER_HOME=$(eval echo ~$USER)

# Function to detect database type
detect_db_type() {
  # Check if PostgreSQL is available
  if command -v psql >/dev/null 2>&1; then
    # Try to connect to PostgreSQL
    if psql -c "SELECT 1;" >/dev/null 2>&1; then
      echo "postgres"
      return 0
    fi
  fi
  
  # Check if MySQL is available
  if command -v mysql >/dev/null 2>&1; then
    # Try to connect to MySQL
    if mysql -e "SELECT 1;" >/dev/null 2>&1; then
      echo "mysql"
      return 0
    fi
  fi
  
  echo "unknown"
  return 1
}

# Auto-detect database type if not specified
if [ -z "$DB_TYPE" ]; then
  DB_TYPE=$(detect_db_type)
  if [ "$DB_TYPE" = "unknown" ]; then
    echo "Error: Could not detect database type. Please specify 'postgres' or 'mysql' as the second argument."
    exit 1
  fi
  echo "Auto-detected database type: $DB_TYPE"
fi

# Ensure the script is run as the appropriate database user
if [ "$DB_TYPE" = "postgres" ] && [ "$(whoami)" != "postgres" ]; then
  # Re-execute the script as the postgres user, passing all original arguments
  sudo -u postgres "$0" "$@"
  exit $?
elif [ "$DB_TYPE" = "mysql" ] && [ "$(whoami)" != "mysql" ] && [ "$(whoami)" != "root" ]; then
  # For MySQL, we'll try to run as root or mysql user
  if sudo -u mysql "$0" "$@" 2>/dev/null; then
    exit $?
  elif sudo -u root "$0" "$@" 2>/dev/null; then
    exit $?
  else
    echo "Warning: Could not switch to mysql or root user. Continuing as current user."
  fi
fi

# Function to execute PostgreSQL queries
run_postgres_query() {
  local db=$1
  local query=$2
  psql -d "$db" -t -c "$query"
}

# Function to execute MySQL queries
run_mysql_query() {
  local db=$1
  local query=$2
  mysql -D "$db" -e "$query" 2>/dev/null
}

# Function to execute queries based on database type
run_query() {
  local db=$1
  local query=$2
  
  if [ "$DB_TYPE" = "postgres" ]; then
    run_postgres_query "$db" "$query"
  elif [ "$DB_TYPE" = "mysql" ]; then
    run_mysql_query "$db" "$query"
  fi
}

# Function to get database size (PostgreSQL)
get_postgres_db_size() {
  local db=$1
  run_postgres_query "$db" "SELECT pg_size_pretty(pg_database_size('$db'));"
}

# Function to get database size (MySQL)
get_mysql_db_size() {
  local db=$1
  run_mysql_query "$db" "
  SELECT 
    CONCAT(
      ROUND(SUM(data_length + index_length) / 1024 / 1024, 2), ' MB'
    ) AS 'Database Size'
  FROM information_schema.tables 
  WHERE table_schema = '$db';"
}

# Function to get database properties (PostgreSQL)
get_postgres_db_properties() {
  local db=$1
  run_postgres_query "$db" "
  SELECT
    'Encoding: ' || pg_encoding_to_char(encoding) || E'\n' ||
    'Collation: ' || datcollate || E'\n' ||
    'Character Type: ' || datctype
  FROM pg_database
  WHERE datname = '$db';"
}

# Function to get database properties (MySQL)
get_mysql_db_properties() {
  local db=$1
  run_mysql_query "$db" "
  SELECT 
    CONCAT('Default Collation: ', DEFAULT_COLLATION_NAME) AS 'Database Properties'
  FROM information_schema.SCHEMATA 
  WHERE SCHEMA_NAME = '$db';"
}

# Function to get table list (PostgreSQL)
get_postgres_tables() {
  local db=$1
  run_postgres_query "$db" "
  SELECT table_schema || '.' || table_name
  FROM information_schema.tables
  WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
    AND table_type = 'BASE TABLE'
  ORDER BY table_schema, table_name;"
}

# Function to get table list (MySQL)
get_mysql_tables() {
  local db=$1
  run_mysql_query "$db" "
  SELECT CONCAT(table_schema, '.', table_name) AS table_full_name
  FROM information_schema.tables
  WHERE table_schema = '$db'
    AND table_type = 'BASE TABLE'
  ORDER BY table_schema, table_name;"
}

# Function to get table information (PostgreSQL)
get_postgres_table_info() {
  local db=$1
  local schema=$2
  local table=$3
  run_postgres_query "$db" "
  SELECT
    'Description: ' || COALESCE(obj_description(pgc.oid, 'pg_class'), 'No description') || E'\n' ||
    'Size: ' || pg_size_pretty(pg_total_relation_size(pgc.oid)) || E'\n' ||
    'Last vacuum: ' || COALESCE(last_vacuum::text, 'never') || E'\n' ||
    'Last autovacuum: ' || COALESCE(last_autovacuum::text, 'never') || E'\n' ||
    'Last analyze: ' || COALESCE(last_analyze::text, 'never') || E'\n' ||
    'Last autoanalyze: ' || COALESCE(last_autoanalyze::text, 'never')
  FROM pg_class pgc
  LEFT JOIN pg_stat_user_tables psut ON pgc.relname = psut.relname
  WHERE pgc.relname = '$table';"
}

# Function to get table information (MySQL)
get_mysql_table_info() {
  local db=$1
  local schema=$2
  local table=$3
  run_mysql_query "$db" "
  SELECT 
    CONCAT(
      'Engine: ', ENGINE, '\n',
      'Row Format: ', ROW_FORMAT, '\n',
      'Table Rows: ', TABLE_ROWS, '\n',
      'Avg Row Length: ', AVG_ROW_LENGTH, '\n',
      'Data Length: ', ROUND(DATA_LENGTH/1024/1024, 2), ' MB\n',
      'Index Length: ', ROUND(INDEX_LENGTH/1024/1024, 2), ' MB\n',
      'Auto Increment: ', COALESCE(AUTO_INCREMENT, 'N/A'), '\n',
      'Create Time: ', CREATE_TIME, '\n',
      'Update Time: ', COALESCE(UPDATE_TIME, 'N/A'), '\n',
      'Table Comment: ', COALESCE(TABLE_COMMENT, 'No comment')
    ) AS 'Table Information'
  FROM information_schema.tables 
  WHERE table_schema = '$db' AND table_name = '$table';"
}

# Function to get column information (PostgreSQL)
get_postgres_columns() {
  local db=$1
  local schema=$2
  local table=$3
  run_postgres_query "$db" "
  SELECT
    '| ' || c.column_name ||
    ' | ' || c.data_type ||
    CASE WHEN c.character_maximum_length IS NOT NULL
         THEN '(' || c.character_maximum_length || ')'
         ELSE '' END ||
    ' | ' || c.is_nullable ||
    ' | ' || CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.key_column_usage kcu
      WHERE kcu.table_schema = c.table_schema
        AND kcu.table_name = c.table_name
        AND kcu.column_name = c.column_name
        AND kcu.position_in_unique_constraint IS NULL
    ) THEN '✓' ELSE '' END ||
    ' | ' || CASE WHEN EXISTS (
      SELECT 1 FROM information_schema.key_column_usage kcu
      WHERE kcu.table_schema = c.table_schema
        AND kcu.table_name = c.table_name
        AND kcu.column_name = c.column_name
        AND kcu.position_in_unique_constraint IS NOT NULL
    ) THEN '✓' ELSE '' END ||
    ' | ' || COALESCE(column_default, '') ||
    ' | ' || COALESCE(col_description(pgc.oid, c.ordinal_position), '') || ' |'
  FROM information_schema.columns c
  JOIN pg_class pgc ON c.table_name = pgc.relname
  WHERE c.table_schema = '$schema'
    AND c.table_name = '$table'
  ORDER BY c.ordinal_position;"
}

# Function to get column information (MySQL)
get_mysql_columns() {
  local db=$1
  local schema=$2
  local table=$3
  run_mysql_query "$db" "
  SELECT 
    CONCAT(
      '| ', COLUMN_NAME, ' | ',
      DATA_TYPE,
      CASE 
        WHEN CHARACTER_MAXIMUM_LENGTH IS NOT NULL 
        THEN CONCAT('(', CHARACTER_MAXIMUM_LENGTH, ')')
        WHEN NUMERIC_PRECISION IS NOT NULL AND NUMERIC_SCALE IS NOT NULL
        THEN CONCAT('(', NUMERIC_PRECISION, ',', NUMERIC_SCALE, ')')
        WHEN NUMERIC_PRECISION IS NOT NULL
        THEN CONCAT('(', NUMERIC_PRECISION, ')')
        ELSE ''
      END, ' | ',
      IS_NULLABLE, ' | ',
      CASE WHEN COLUMN_KEY = 'PRI' THEN '✓' ELSE '' END, ' | ',
      CASE WHEN COLUMN_KEY = 'MUL' THEN '✓' ELSE '' END, ' | ',
      COALESCE(COLUMN_DEFAULT, ''), ' | ',
      COALESCE(COLUMN_COMMENT, ''), ' |'
    ) AS 'Column Info'
  FROM information_schema.columns 
  WHERE table_schema = '$db' AND table_name = '$table'
  ORDER BY ORDINAL_POSITION;"
}

# Function to get foreign key relationships (PostgreSQL)
get_postgres_foreign_keys() {
  local db=$1
  local schema=$2
  local table=$3
  run_postgres_query "$db" "
  SELECT
    '  ' || kcu.column_name || ' -> ' ||
    ccu.table_schema || '.' || ccu.table_name || '.' || ccu.column_name ||
    ' (' || tc.constraint_name || ')'
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
  JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name
    AND ccu.table_schema = tc.table_schema
  WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = '$schema'
    AND tc.table_name = '$table';"
}

# Function to get foreign key relationships (MySQL)
get_mysql_foreign_keys() {
  local db=$1
  local schema=$2
  local table=$3
  run_mysql_query "$db" "
  SELECT 
    CONCAT(
      '  ', COLUMN_NAME, ' -> ',
      REFERENCED_TABLE_SCHEMA, '.', REFERENCED_TABLE_NAME, '.', REFERENCED_COLUMN_NAME,
      ' (', CONSTRAINT_NAME, ')'
    ) AS 'Foreign Key'
  FROM information_schema.KEY_COLUMN_USAGE 
  WHERE table_schema = '$db' 
    AND table_name = '$table' 
    AND REFERENCED_TABLE_NAME IS NOT NULL;"
}

# Function to get indexes (PostgreSQL)
get_postgres_indexes() {
  local db=$1
  local schema=$2
  local table=$3
  run_postgres_query "$db" "
  SELECT '  ' || indexname || ': ' || indexdef
  FROM pg_indexes
  WHERE schemaname = '$schema'
    AND tablename = '$table';"
}

# Function to get indexes (MySQL)
get_mysql_indexes() {
  local db=$1
  local schema=$2
  local table=$3
  run_mysql_query "$db" "
  SELECT 
    CONCAT(
      '  ', INDEX_NAME, ': ',
      CASE WHEN NON_UNIQUE = 0 THEN 'UNIQUE ' ELSE '' END,
      INDEX_TYPE, ' (', GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX), ')'
    ) AS 'Index Info'
  FROM information_schema.STATISTICS 
  WHERE table_schema = '$db' AND table_name = '$table'
  GROUP BY INDEX_NAME, NON_UNIQUE, INDEX_TYPE;"
}

# Function to get triggers (PostgreSQL)
get_postgres_triggers() {
  local db=$1
  local schema=$2
  local table=$3
  run_postgres_query "$db" "
  SELECT '  ' || tgname || ': ' || pg_get_triggerdef(oid)
  FROM pg_trigger
  WHERE tgrelid = '\"$schema\".\"$table\"'::regclass
  AND NOT tgisinternal;"
}

# Function to get triggers (MySQL)
get_mysql_triggers() {
  local db=$1
  local schema=$2
  local table=$3
  run_mysql_query "$db" "
  SELECT 
    CONCAT(
      '  ', TRIGGER_NAME, ': ',
      ACTION_TIMING, ' ', EVENT_MANIPULATION, ' ON ', EVENT_OBJECT_TABLE,
      ' FOR EACH ', ACTION_ORIENTATION, ' ', ACTION_STATEMENT
    ) AS 'Trigger Info'
  FROM information_schema.TRIGGERS 
  WHERE TRIGGER_SCHEMA = '$db' AND EVENT_OBJECT_TABLE = '$table';"
}

# Function to get table statistics (PostgreSQL)
get_postgres_statistics() {
  local db=$1
  local schema=$2
  local table=$3
  run_postgres_query "$db" "
  SELECT
    '  Row count: ' || reltuples::bigint || E'\n' ||
    '  Size: ' || pg_size_pretty(pg_total_relation_size('\"$schema\".\"$table\"'::regclass)) || E'\n' ||
    '  Table size: ' || pg_size_pretty(pg_relation_size('\"$schema\".\"$table\"'::regclass)) || E'\n' ||
    '  Index size: ' || pg_size_pretty(pg_total_relation_size('\"$schema\".\"$table\"'::regclass) - pg_relation_size('\"$schema\".\"$table\"'::regclass)) || E'\n' ||
    '  Toast size: ' || pg_size_pretty(pg_total_relation_size(reltoastrelid))
  FROM pg_class
  WHERE oid = '\"$schema\".\"$table\"'::regclass;"
}

# Function to get table statistics (MySQL)
get_mysql_statistics() {
  local db=$1
  local schema=$2
  local table=$3
  run_mysql_query "$db" "
  SELECT 
    CONCAT(
      '  Table Rows: ', TABLE_ROWS, '\n',
      '  Data Length: ', ROUND(DATA_LENGTH/1024/1024, 2), ' MB\n',
      '  Index Length: ', ROUND(INDEX_LENGTH/1024/1024, 2), ' MB\n',
      '  Total Size: ', ROUND((DATA_LENGTH + INDEX_LENGTH)/1024/1024, 2), ' MB\n',
      '  Avg Row Length: ', AVG_ROW_LENGTH, ' bytes'
    ) AS 'Statistics'
  FROM information_schema.tables 
  WHERE table_schema = '$db' AND table_name = '$table';"
}

# Function to process a single database
process_database() {
  local db=$1
  local output_file=$2

  echo "Inspecting database: $db"
  echo "Database: $db" >> "$output_file"
  echo "===========================================" >> "$output_file"
  echo "" >> "$output_file"

  # Get database size
  echo "Database Size:" >> "$output_file"
  if [ "$DB_TYPE" = "postgres" ]; then
    get_postgres_db_size "$db" >> "$output_file"
  else
    get_mysql_db_size "$db" >> "$output_file"
  fi
  echo "" >> "$output_file"

  # Get database properties
  echo "Database Properties:" >> "$output_file"
  if [ "$DB_TYPE" = "postgres" ]; then
    get_postgres_db_properties "$db" >> "$output_file"
  else
    get_mysql_db_properties "$db" >> "$output_file"
  fi
  echo "" >> "$output_file"

  # Get list of all tables
  echo "Gathering table list..."
  local TABLES
  if [ "$DB_TYPE" = "postgres" ]; then
    TABLES=$(get_postgres_tables "$db")
  else
    TABLES=$(get_mysql_tables "$db")
  fi

  # Process each table
  echo "$TABLES" | while read -r TABLE_FULL_NAME; do
    if [ -z "$TABLE_FULL_NAME" ]; then continue; fi

    SCHEMA=$(echo "$TABLE_FULL_NAME" | cut -d'.' -f1)
    TABLE=$(echo "$TABLE_FULL_NAME" | cut -d'.' -f2)

    echo "Processing table: $TABLE_FULL_NAME"

    # Write table header
    echo "Table: $TABLE_FULL_NAME" >> "$output_file"
    echo "-------------------------------------------" >> "$output_file"

    # Get table description and size
    echo "Basic Information:" >> "$output_file"
    if [ "$DB_TYPE" = "postgres" ]; then
      get_postgres_table_info "$db" "$SCHEMA" "$TABLE" >> "$output_file"
    else
      get_mysql_table_info "$db" "$SCHEMA" "$TABLE" >> "$output_file"
    fi
    echo "" >> "$output_file"

    # Get column information
    echo "Columns:" >> "$output_file"
    echo "| Column | Type | Nullable | PK | FK | Default | Description |" >> "$output_file"
    echo "|--------|------|----------|----|----|---------|-------------|" >> "$output_file"

    if [ "$DB_TYPE" = "postgres" ]; then
      get_postgres_columns "$db" "$SCHEMA" "$TABLE" >> "$output_file"
    else
      get_mysql_columns "$db" "$SCHEMA" "$TABLE" >> "$output_file"
    fi
    echo "" >> "$output_file"

    # Get foreign key relationships
    echo "Foreign Key Relationships:" >> "$output_file"
    if [ "$DB_TYPE" = "postgres" ]; then
      get_postgres_foreign_keys "$db" "$SCHEMA" "$TABLE" >> "$output_file"
    else
      get_mysql_foreign_keys "$db" "$SCHEMA" "$TABLE" >> "$output_file"
    fi
    echo "" >> "$output_file"

    # Get indexes
    echo "Indexes:" >> "$output_file"
    if [ "$DB_TYPE" = "postgres" ]; then
      get_postgres_indexes "$db" "$SCHEMA" "$TABLE" >> "$output_file"
    else
      get_mysql_indexes "$db" "$SCHEMA" "$TABLE" >> "$output_file"
    fi
    echo "" >> "$output_file"

    # Get triggers
    echo "Triggers:" >> "$output_file"
    if [ "$DB_TYPE" = "postgres" ]; then
      get_postgres_triggers "$db" "$SCHEMA" "$TABLE" >> "$output_file"
    else
      get_mysql_triggers "$db" "$SCHEMA" "$TABLE" >> "$output_file"
    fi
    echo "" >> "$output_file"

    # Add sample data count and size statistics
    echo "Statistics:" >> "$output_file"
    if [ "$DB_TYPE" = "postgres" ]; then
      get_postgres_statistics "$db" "$SCHEMA" "$TABLE" >> "$output_file"
    else
      get_mysql_statistics "$db" "$SCHEMA" "$TABLE" >> "$output_file"
    fi
    echo "" >> "$output_file"

    # Add separator between tables
    echo "==========================================" >> "$output_file"
    echo "" >> "$output_file"
  done
}

# Create output directory if it doesn't exist
OUTPUT_DIR="$USER_HOME/db_inspections"
mkdir -p "$OUTPUT_DIR"

# Get current timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ -z "$DB_NAME" ]; then
  echo "No database specified. Inspecting all databases..."

  # Get list of all databases
  if [ "$DB_TYPE" = "postgres" ]; then
    DATABASES=$(psql -t -c "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres') ORDER BY datname;")
  else
    DATABASES=$(mysql -e "SHOW DATABASES;" | grep -v "Database" | grep -v "information_schema" | grep -v "performance_schema" | grep -v "mysql" | grep -v "sys")
  fi

  # Create a master output file
  MASTER_OUTPUT="$OUTPUT_DIR/all_databases_inspection_${DB_TYPE}_$TIMESTAMP.txt"
  echo "Database Inspection Report ($DB_TYPE)" > "$MASTER_OUTPUT"
  echo "Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$MASTER_OUTPUT"
  echo "===========================================" >> "$MASTER_OUTPUT"
  echo "" >> "$MASTER_OUTPUT"

  # Process each database
  echo "$DATABASES" | while read -r db; do
    if [ -z "$db" ]; then continue; fi

    echo "Processing database: $db"
    DB_OUTPUT="$OUTPUT_DIR/${db}_inspection_${DB_TYPE}_$TIMESTAMP.txt"

    # Add database header to master file
    echo "Database: $db" >> "$MASTER_OUTPUT"
    echo "See detailed report: ${db}_inspection_${DB_TYPE}_$TIMESTAMP.txt" >> "$MASTER_OUTPUT"
    echo "-------------------------------------------" >> "$MASTER_OUTPUT"

    # Get database size and basic info for master file
    if [ "$DB_TYPE" = "postgres" ]; then
      run_postgres_query "$db" "
      SELECT
        'Size: ' || pg_size_pretty(pg_database_size('$db')) || E'\n' ||
        'Encoding: ' || pg_encoding_to_char(encoding) || E'\n' ||
        'Tables: ' || (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema'))
      FROM pg_database
      WHERE datname = '$db';" >> "$MASTER_OUTPUT"
    else
      run_mysql_query "$db" "
      SELECT 
        CONCAT(
          'Size: ', ROUND(SUM(data_length + index_length) / 1024 / 1024, 2), ' MB\n',
          'Tables: ', COUNT(*)
        ) AS 'Database Info'
      FROM information_schema.tables 
      WHERE table_schema = '$db';" >> "$MASTER_OUTPUT"
    fi
    echo "" >> "$MASTER_OUTPUT"

    # Process the database
    process_database "$db" "$DB_OUTPUT"
  done

  echo "Inspection complete. Results saved to:"
  echo "  Master report: $MASTER_OUTPUT"
  echo "  Individual reports in: $OUTPUT_DIR"
else
  # Process single database
  OUTPUT_FILE="$OUTPUT_DIR/${DB_NAME}_inspection_${DB_TYPE}_$TIMESTAMP.txt"
  echo "Database Inspection Report ($DB_TYPE)" > "$OUTPUT_FILE"
  echo "Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$OUTPUT_FILE"
  echo "===========================================" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"

  process_database "$DB_NAME" "$OUTPUT_FILE"
  echo "Inspection complete. Results saved to: $OUTPUT_FILE"
fi