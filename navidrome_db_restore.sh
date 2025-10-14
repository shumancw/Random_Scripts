#!/bin/bash

# Navidrome Database Restore Script
# Location: /zoom/containers/navidrome

set -e  # Exit on error

# Configuration
COMPOSE_DIR="."
DATA_DIR="./data"
BACKUP_DIR="./data/backups"
DB_FILE="./data/navidrome.db"
CONTAINER_NAME="navidrome"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root or with sufficient permissions
if [ ! -w "$DATA_DIR" ]; then
    print_error "Insufficient permissions to write to $DATA_DIR"
    print_info "Try running with sudo: sudo $0"
    exit 1
fi

# Check if backup directory exists
if [ ! -d "$BACKUP_DIR" ]; then
    print_error "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

# Find all database backups
print_info "Scanning for database backups..."
mapfile -t BACKUPS < <(find "$BACKUP_DIR" -name "*.db" -type f | sort -r)

if [ ${#BACKUPS[@]} -eq 0 ]; then
    print_error "No database backups found in $BACKUP_DIR"
    exit 1
fi

# Display available backups in columnar format
echo ""
print_info "Available database backups:"
echo "============================================================================================================"
printf "${BLUE}%-4s %-40s %-12s %s${NC}\n" "ID" "Filename" "Size" "Modified"
echo "------------------------------------------------------------------------------------------------------------"
for i in "${!BACKUPS[@]}"; do
    backup_file="${BACKUPS[$i]}"
    filename=$(basename "$backup_file")
    filesize=$(du -h "$backup_file" | cut -f1)
    filedate=$(stat -c %y "$backup_file" 2>/dev/null || stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$backup_file" 2>/dev/null)
    # Extract just the date and time (first 19 characters)
    filedate_short=$(echo "$filedate" | cut -c1-19)
    printf "${GREEN}%-4d${NC} %-40s %-12s %s\n" $((i+1)) "$filename" "$filesize" "$filedate_short"
done
echo "============================================================================================================"
printf "${RED}%-4s${NC} Cancel restore\n" "0"
echo ""

# Prompt user for selection
while true; do
    read -p "Select backup to restore (0-${#BACKUPS[@]}): " selection

    if [ "$selection" = "0" ]; then
        print_info "Restore cancelled by user"
        exit 0
    elif [ "$selection" -ge 1 ] && [ "$selection" -le ${#BACKUPS[@]} ] 2>/dev/null; then
        SELECTED_BACKUP="${BACKUPS[$((selection-1))]}"
        break
    else
        print_error "Invalid selection. Please enter a number between 0 and ${#BACKUPS[@]}"
    fi
done

# Confirm selection
echo ""
print_warning "You selected: $(basename "$SELECTED_BACKUP")"
read -p "Are you sure you want to restore this backup? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    print_info "Restore cancelled by user"
    exit 0
fi

# Stop container using docker compose
print_info "Stopping Navidrome container..."
cd "$COMPOSE_DIR"
docker compose down
print_success "Container stopped"

# Backup current database if it exists
if [ -f "$DB_FILE" ]; then
    BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    CURRENT_BACKUP="$DATA_DIR/navidrome.db.before_restore_$BACKUP_TIMESTAMP"
    print_info "Backing up current database to: $(basename "$CURRENT_BACKUP")"
    cp "$DB_FILE" "$CURRENT_BACKUP"
    print_success "Current database backed up"
fi

# Restore the selected backup
print_info "Restoring database from backup..."
if cp "$SELECTED_BACKUP" "$DB_FILE"; then
    print_success "Database file copied successfully"
else
    print_error "Failed to restore database"
    exit 1
fi

# Set correct permissions
print_info "Setting file permissions..."
chown 1000:1000 "$DB_FILE" 2>/dev/null || true
chmod 644 "$DB_FILE"
print_success "File permissions set"

# Start container
echo ""
print_info "Starting Navidrome container..."
cd "$COMPOSE_DIR" || exit 1

if docker compose up -d; then
    print_success "Container started successfully"
else
    print_error "Failed to start container"
    exit 1
fi

echo ""
print_success "Restore complete!"
print_info "Check logs with: docker compose logs -f"
