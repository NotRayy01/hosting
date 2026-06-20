#!/bin/bash

# ==============================================================================
#  Script Name : RayBackup-Installer
#  Description : Automated Pterodactyl Node/Panel Backup Setup with Rclone & GDrive
#  Author      : Ray
#  Credit      : Ray
# ==============================================================================

# Colors & Symbols
GREEN='\033[0;32m'
COLOR_REG='\033[0;36m' # Cyan
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

TICK="[${GREEN}✓${NC}]"
ARROW="${COLOR_REG}➔${NC}"
INFO="[${YELLOW}ℹ${NC}]"
ERROR_SYM="[${RED}✗${NC}]"

clear
echo -e "${COLOR_REG}======================================================================${NC}"
echo -e "${YELLOW}               🚀 RAY AUTOMATED BACKUP INSTALLER 🚀                   ${NC}"
echo -e "${COLOR_REG}======================================================================${NC}"
echo -e "${GREEN}✨ Script Credit to: Ray ✨${NC}"
echo -e "${COLOR_REG}----------------------------------------------------------------------${NC}"

# 1. Rclone Installation
echo -e "\n${ARROW} Checking and Installing Rclone..."
if ! command -v rclone &> /dev/null; then
    echo -e "${INFO} Rclone not found. Installing..."
    curl https://rclone.org/install.sh | sudo bash &> /dev/null
    echo -e "${TICK} Rclone installed successfully!"
else
    echo -e "${TICK} Rclone is already installed."
fi

# 2. Cron Installation Check
if ! command -v crontab &> /dev/null; then
    echo -e "${INFO} Cron not found. Installing..."
    sudo apt update -y &> /dev/null
    sudo apt install cron -y &> /dev/null
    sudo systemctl enable cron &> /dev/null
    sudo systemctl start cron &> /dev/null
    echo -e "${TICK} Cron installed and enabled!"
fi

# 3. Google Drive Configuration via Token Input
echo -e "\n${COLOR_REG}======================================================================${NC}"
echo -e "${YELLOW}🔑 GOOGLE DRIVE AUTHENTICATION${NC}"
echo -e "${COLOR_REG}======================================================================${NC}"
echo -e "${INFO} Please run 'rclone authorize \"drive\" \"eyJzY29wZSI6ImRyaXZlIn0\"' on your PC."
echo -e "${ARROW} Paste the generated JSON Token below:"
echo -n "config_token> "
read -r DRIVER_TOKEN < /dev/tty

# Create rclone config folder if not exists
mkdir -p ~/.config/rclone/

# Write directly to rclone config file
cat <<EOF > ~/.config/rclone/rclone.conf
[gdrive]
type = drive
scope = drive
token = $DRIVER_TOKEN
EOF

echo -e "${TICK} Google Drive Configured successfully!"

# 4. Folder Name Input
echo -e "\n${ARROW} Enter the Folder Name for this VPS (e.g., RayNodeIN3):"
read -r FOLDER_NAME < /dev/tty
FOLDER_NAME="${FOLDER_NAME:-RayNode}"

# 5. Backup Type Selection
echo -e "\n${COLOR_REG}======================================================================${NC}"
echo -e "${YELLOW}📁 SELECT BACKUP TYPE${NC}"
echo -e "${COLOR_REG}======================================================================${NC}"
echo -e "1) Only Pterodactyl Node (Server Volumes)"
echo -e "2) Only Pterodactyl Panel (Database + Panel Files)"
echo -e "3) Both (Node & Panel)"
echo -n "Choose an option [1-3]: "
read -r BACKUP_OPTION < /dev/tty
BACKUP_OPTION="${BACKUP_OPTION:-1}"

# 6. Dynamically Generate the Final Backup Script
BACKUP_SCRIPT_PATH="/root/auto_backup.sh"

cat <<'EOF' > $BACKUP_SCRIPT_PATH
#!/bin/bash
DATE=$(date +%Y-%m-%d)
BACKUP_TEMP_DIR="/tmp/pterodactyl_backups"
GDRIVE_REMOTE="gdrive:backups"
EOF

# Inject variables into the generated script safely
sed -i "3i FOLDER_NAME=\"$FOLDER_NAME\"" $BACKUP_SCRIPT_PATH
sed -i "4i OPTION=\"$BACKUP_OPTION\"" $BACKUP_SCRIPT_PATH

# Append the logical part of the backup script with auto folder creation
cat <<'EOF' >> $BACKUP_SCRIPT_PATH

# Cleanup and setup temp dir
rm -rf "$BACKUP_TEMP_DIR"
mkdir -p "$BACKUP_TEMP_DIR"

# Google Drive par pehle hi directory structure bana dena taaki empty na dikhe
rclone mkdir "$GDRIVE_REMOTE/$FOLDER_NAME" --log-file=/var/log/rclone_backup.log

# --- NODE BACKUP ENGINE ---
if [ "$OPTION" -eq 1 ] || [ "$OPTION" -eq 3 ]; then
    NODE_DIR="/var/lib/pterodactyl/volumes"
    NODE_TEMP="$BACKUP_TEMP_DIR/node/servers"
    mkdir -p "$NODE_TEMP"
    rclone mkdir "$GDRIVE_REMOTE/$FOLDER_NAME/node/servers" 2>/dev/null
    
    if [ -d "$NODE_DIR" ]; then
        cd "$NODE_DIR" || exit
        for server_dir in *; do
            if [ -d "$server_dir" ]; then
                tar -czf "$NODE_TEMP/${server_dir}_$DATE.tar.gz" "$server_dir"
            fi
        done
    fi
fi

# --- PANEL BACKUP ENGINE ---
if [ "$OPTION" -eq 2 ] || [ "$OPTION" -eq 3 ]; then
    PANEL_DIR="/var/www/pterodactyl"
    PANEL_TEMP="$BACKUP_TEMP_DIR/panel"
    mkdir -p "$PANEL_TEMP"
    rclone mkdir "$GDRIVE_REMOTE/$FOLDER_NAME/panel" 2>/dev/null
    
    # 1. Zip Panel Files
    if [ -d "$PANEL_DIR" ]; then
        tar -czf "$PANEL_TEMP/panel_files_$DATE.tar.gz" -C /var/www pterodactyl
    fi
    
    # 2. Dump Panel Database
    if [ -f "$PANEL_DIR/.env" ]; then
        DB_PASSWORD=$(grep DB_PASSWORD "$PANEL_DIR/.env" | cut -d= -f2 | tr -d '"' | tr -d ' ')
        DB_DATABASE=$(grep DB_DATABASE "$PANEL_DIR/.env" | cut -d= -f2 | tr -d '"' | tr -d ' ')
        DB_USERNAME=$(grep DB_USERNAME "$PANEL_DIR/.env" | cut -d= -f2 | tr -d '"' | tr -d ' ')
        DB_HOST=$(grep DB_HOST "$PANEL_DIR/.env" | cut -d= -f2 | tr -d '"' | tr -d ' ')
        
        mysqldump -h "$DB_HOST" -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_DATABASE" > "$PANEL_TEMP/panel_db_$DATE.sql" 2>/dev/null
        tar -czf "$PANEL_TEMP/panel_db_$DATE.tar.gz" -C "$PANEL_TEMP" "panel_db_$DATE.sql"
        rm -f "$PANEL_TEMP/panel_db_$DATE.sql"
    fi
fi

# --- UPLOAD TO GDRIVE & AUTO-DELETE LOCAL ---
if [ -d "$BACKUP_TEMP_DIR" ]; then
    rclone move "$BACKUP_TEMP_DIR" "$GDRIVE_REMOTE/$FOLDER_NAME" --log-file=/var/log/rclone_backup.log
fi

# Final Hard Cleanup
rm -rf "$BACKUP_TEMP_DIR"
EOF

chmod +x $BACKUP_SCRIPT_PATH
echo -e "${TICK} Backup Script generated at ${YELLOW}$BACKUP_SCRIPT_PATH${NC}"

# 7. Setup Cron Job Automatically (Roz raat ko 2:00 baje)
(crontab -l 2>/dev/null | grep -v "$BACKUP_SCRIPT_PATH"; echo "0 2 * * * /bin/bash $BACKUP_SCRIPT_PATH > /dev/null 2>&1") | crontab -
echo -e "${TICK} Cron Job configured for daily automatic backup at 2:00 AM."

# 8. Test Prompt
echo -e "\n${COLOR_REG}======================================================================${NC}"
echo -e "${YELLOW}📊 SETUP COMPLETED SUCCESSFULLY BY RAY${NC}"
echo -e "${COLOR_REG}======================================================================${NC}"
echo -n -e "${ARROW} Do you want to test the backup system right now? (y/n): "
read -r TEST_NOW < /dev/tty

if [[ "$TEST_NOW" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "\n${INFO} Running backup test... Please wait..."
    /bin/bash $BACKUP_SCRIPT_PATH
    echo -e "${TICK} ${GREEN}Test finished! Check your Google Drive 'backups/$FOLDER_NAME/' folder!${NC}"
    echo -e "${TICK} Local temporary backup files have been cleared from VPS! 🎉\n"
else
    echo -e "\n${TICK} All set! Automatic backups will trigger daily at 2:00 AM.\n"
fi
