#!/usr/bin/env bash
# ==============================================================================
#   ██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗
#   ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗
#   ██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝
#   ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝
#   ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║
#   ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝
#   Auto VPS Backup System — Ray Industries
# ==============================================================================
#   👑 Developed by Ray
#   🏢 Ray Industries  |  📺 YouTube: @RayVerse
# ==============================================================================
set -euo pipefail
IFS=$'\n\t'

# ── Colors ─────────────────────────────────────────────────────────────────────
RED="\033[0;31m";    GREEN="\033[0;32m";    YELLOW="\033[1;33m"
BLUE="\033[0;34m";   MAGENTA="\033[0;35m"; CYAN="\033[0;36m"
WHITE="\033[1;37m";  DIM="\033[2m";        BOLD="\033[1m"; NC="\033[0m"
BG_MAGENTA="\033[45m"; BG_CYAN="\033[46m"; BG_BLUE="\033[44m"
BG_GREEN="\033[42m"; BG_RED="\033[41m";    BG_YELLOW="\033[43m"

ok()   { echo -e "  ${GREEN}✔  $1${NC}"; }
info() { echo -e "  ${CYAN}ℹ  $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠  $1${NC}"; }
err()  { echo -e "  ${RED}✖  $1${NC}"; }
step() { echo -e "\n  ${MAGENTA}${BOLD}⚡  $1${NC}"; }
pause() { echo -e "\n  ${DIM}Press [ENTER] to continue...${NC}"; read -r -s; }
divider() { echo -e "  ${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

spinner() {
    local pid=$1 msg=$2
    local f=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏'); local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${f[$i]}${NC}  ${WHITE}%s${NC}   " "$msg"
        i=$(( (i+1) % 10 )); sleep 0.08
    done
    printf "\r  ${GREEN}✔${NC}  ${WHITE}%s${NC}   \n" "$msg"
}

# ── Config file location ───────────────────────────────────────────────────────
CONFIG_FILE="/etc/ray-backup/config.conf"
BACKUP_SCRIPT="/usr/local/bin/ray-backup-run"
LOG_FILE="/var/log/ray-backup.log"
TMP_DIR="/tmp/ray-backup-tmp"

# ── Banner ─────────────────────────────────────────────────────────────────────
show_banner() {
    clear; echo ""
    echo -e "${MAGENTA}${BOLD}"
    echo "  ██████╗  █████╗  ██████╗██╗  ██╗██╗   ██╗██████╗ "
    echo "  ██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██║   ██║██╔══██╗"
    echo "  ██████╔╝███████║██║     █████╔╝ ██║   ██║██████╔╝"
    echo "  ██╔══██╗██╔══██║██║     ██╔═██╗ ██║   ██║██╔═══╝ "
    echo "  ██████╔╝██║  ██║╚██████╗██║  ██╗╚██████╔╝██║     "
    echo "  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝     "
    echo -e "${NC}"
    divider
    echo -e "  ${WHITE}${BOLD}  Auto VPS Backup System${NC}  ${DIM}Pro Edition  |  Ray Industries${NC}"
    divider
    echo -e "  ${DIM}  👑 Ray  |  🏢 Ray Industries  |  📺 @RayVerse${NC}"
    divider
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 1 — Install rclone
# ══════════════════════════════════════════════════════════════════════════════
install_rclone() {
    show_banner
    echo -e "  ${BG_MAGENTA}${WHITE}${BOLD}  STEP 1 — Installing rclone  ${NC}"
    echo ""

    if command -v rclone >/dev/null 2>&1; then
        ok "rclone already installed: $(rclone --version | head -1)"
        return 0
    fi

    info "rclone is the backbone — supports Google Drive, S3, Dropbox, SFTP & more."
    echo ""

    (curl -fsSL https://rclone.org/install.sh | bash >/dev/null 2>&1) &
    spinner $! "Downloading & installing rclone..."

    if command -v rclone >/dev/null 2>&1; then
        ok "rclone installed: $(rclone --version | head -1)"
    else
        err "rclone installation failed!"
        exit 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 2 — Select Cloud Storage Provider
# ══════════════════════════════════════════════════════════════════════════════
setup_remote() {
    show_banner
    echo -e "  ${BG_CYAN}${WHITE}${BOLD}  STEP 2 — Configure Cloud Storage  ${NC}"
    echo ""

    # Show existing remotes
    EXISTING=$(rclone listremotes 2>/dev/null | sed 's|:||g' | tr '\n' ' ')
    if [ -n "$EXISTING" ]; then
        echo -e "  ${GREEN}${BOLD}Existing rclone remotes detected:${NC}"
        rclone listremotes 2>/dev/null | while IFS= read -r r; do
            echo -e "  ${WHITE}  ✔  ${CYAN}${r}${NC}"
        done
        echo ""
        echo -ne "  ${CYAN}❯ ${NC}Use an existing remote? (y/N): "; read -r USE_EXISTING
        if [[ "$USE_EXISTING" =~ [Yy] ]]; then
            echo -ne "  ${CYAN}❯ ${NC}Enter remote name (without colon): "; read -r REMOTE_NAME
            if rclone listremotes | grep -q "^${REMOTE_NAME}:"; then
                ok "Using existing remote: ${REMOTE_NAME}"
                echo "REMOTE_NAME=${REMOTE_NAME}" >> "$CONFIG_FILE"
                return 0
            else
                warn "Remote '${REMOTE_NAME}' not found. Setting up new one..."
            fi
        fi
    fi

    echo ""
    echo -e "  ${YELLOW}${BOLD}🌐 Select Cloud Storage Provider:${NC}"
    echo ""
    echo -e "  ${WHITE}  1)${NC}  ${GREEN}▶${NC}  Google Drive           ${DIM}(Recommended)${NC}"
    echo -e "  ${WHITE}  2)${NC}  ${BLUE}▶${NC}  Dropbox"
    echo -e "  ${WHITE}  3)${NC}  ${YELLOW}▶${NC}  Amazon S3 / Wasabi / R2"
    echo -e "  ${WHITE}  4)${NC}  ${CYAN}▶${NC}  OneDrive"
    echo -e "  ${WHITE}  5)${NC}  ${MAGENTA}▶${NC}  SFTP / Remote Server"
    echo -e "  ${WHITE}  6)${NC}  ${WHITE}▶${NC}  Backblaze B2"
    echo -e "  ${WHITE}  7)${NC}  ${WHITE}▶${NC}  Other (manual rclone config)"
    echo ""
    echo -ne "  ${CYAN}❯ ${NC}Select [1-7]: "; read -r PROVIDER_CHOICE

    echo ""
    echo -ne "  ${CYAN}❯ ${NC}Give this remote a name (e.g. gdrive, mybackup): "; read -r REMOTE_NAME
    [ -z "$REMOTE_NAME" ] && REMOTE_NAME="ray-backup"

    case "$PROVIDER_CHOICE" in
        1)
            echo ""
            echo -e "  ${YELLOW}${BOLD}📋 Google Drive Setup Instructions:${NC}"
            divider
            echo -e "  ${WHITE}  1)${NC}  rclone will open an interactive config"
            echo -e "  ${WHITE}  2)${NC}  Select ${BOLD}drive${NC} as the storage type"
            echo -e "  ${WHITE}  3)${NC}  Leave client_id & client_secret ${DIM}BLANK${NC} (press Enter)"
            echo -e "  ${WHITE}  4)${NC}  Select scope: ${BOLD}1${NC} (full access)"
            echo -e "  ${WHITE}  5)${NC}  Use auto config: ${BOLD}y${NC} if on desktop, ${BOLD}n${NC} if on headless server"
            echo -e "  ${WHITE}     ${NC}  If headless → copy the URL → open in browser → paste code back"
            divider
            echo ""
            pause
            rclone config create "$REMOTE_NAME" drive scope drive 2>/dev/null || \
            rclone config
            ;;
        2)
            echo ""
            info "Starting Dropbox config..."
            rclone config create "$REMOTE_NAME" dropbox 2>/dev/null || rclone config
            ;;
        3)
            echo ""
            echo -ne "  ${CYAN}❯ ${NC}S3 Endpoint (leave blank for AWS): "; read -r S3_ENDPOINT
            echo -ne "  ${CYAN}❯ ${NC}Access Key ID: "; read -r S3_KEY
            echo -ne "  ${CYAN}❯ ${NC}Secret Access Key: "; read -rs S3_SECRET; echo ""
            echo -ne "  ${CYAN}❯ ${NC}Region [us-east-1]: "; read -r S3_REGION
            [ -z "$S3_REGION" ] && S3_REGION="us-east-1"
            if [ -n "$S3_ENDPOINT" ]; then
                rclone config create "$REMOTE_NAME" s3 \
                    provider=Other endpoint="$S3_ENDPOINT" \
                    access_key_id="$S3_KEY" secret_access_key="$S3_SECRET" \
                    region="$S3_REGION" 2>/dev/null || rclone config
            else
                rclone config create "$REMOTE_NAME" s3 \
                    provider=AWS access_key_id="$S3_KEY" \
                    secret_access_key="$S3_SECRET" region="$S3_REGION" 2>/dev/null || rclone config
            fi
            ;;
        4)
            info "Starting OneDrive config..."
            rclone config create "$REMOTE_NAME" onedrive 2>/dev/null || rclone config
            ;;
        5)
            echo ""
            echo -ne "  ${CYAN}❯ ${NC}SFTP Host: "; read -r SFTP_HOST
            echo -ne "  ${CYAN}❯ ${NC}SFTP Port [22]: "; read -r SFTP_PORT
            [ -z "$SFTP_PORT" ] && SFTP_PORT=22
            echo -ne "  ${CYAN}❯ ${NC}SFTP Username: "; read -r SFTP_USER
            echo -ne "  ${CYAN}❯ ${NC}SFTP Password: "; read -rs SFTP_PASS; echo ""
            rclone config create "$REMOTE_NAME" sftp \
                host="$SFTP_HOST" port="$SFTP_PORT" \
                user="$SFTP_USER" pass="$(rclone obscure "$SFTP_PASS")" 2>/dev/null
            ;;
        6)
            echo ""
            echo -ne "  ${CYAN}❯ ${NC}B2 Account ID: "; read -r B2_ACCT
            echo -ne "  ${CYAN}❯ ${NC}B2 Application Key: "; read -rs B2_KEY; echo ""
            rclone config create "$REMOTE_NAME" b2 \
                account="$B2_ACCT" key="$B2_KEY" 2>/dev/null
            ;;
        7)
            info "Launching full rclone interactive config..."
            rclone config
            echo -ne "  ${CYAN}❯ ${NC}Enter the remote name you just configured: "; read -r REMOTE_NAME
            ;;
        *)
            err "Invalid choice!"; exit 1 ;;
    esac

    # Verify remote works
    echo ""
    step "Testing remote connection..."
    if rclone lsd "${REMOTE_NAME}:" >/dev/null 2>&1; then
        ok "Remote '${REMOTE_NAME}' connected successfully!"
    else
        warn "Could not verify remote — it may still work. Continuing..."
    fi

    echo "REMOTE_NAME=${REMOTE_NAME}" >> "$CONFIG_FILE"
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 3 — Backup folder name & remote path
# ══════════════════════════════════════════════════════════════════════════════
setup_folder() {
    show_banner
    echo -e "  ${BG_BLUE}${WHITE}${BOLD}  STEP 3 — Backup Folder Configuration  ${NC}"
    echo ""

    source "$CONFIG_FILE"

    info "Your backups will be saved inside a 'backups' folder on your cloud storage."
    info "Then inside that, a subfolder with the name you choose."
    echo ""
    echo -e "  ${DIM}  Structure: ${CYAN}${REMOTE_NAME}:/backups/<your-folder>/<date>/...${NC}"
    echo ""
    echo -ne "  ${CYAN}❯ ${NC}Enter your backup folder name (e.g. my-vps, node1, rayserver): "; read -r FOLDER_NAME
    [ -z "$FOLDER_NAME" ] && FOLDER_NAME="vps-backup"

    # Sanitize folder name
    FOLDER_NAME=$(echo "$FOLDER_NAME" | tr ' ' '-' | tr -cd '[:alnum:]-_')

    # Check/create parent backups folder on remote
    step "Checking 'backups' folder on remote..."
    if rclone lsd "${REMOTE_NAME}:backups" >/dev/null 2>&1; then
        ok "'backups' folder already exists on remote."
    else
        rclone mkdir "${REMOTE_NAME}:backups" 2>/dev/null && \
            ok "Created 'backups' folder on remote." || \
            warn "Could not pre-create folder — will be created on first backup."
    fi

    # Save to config
    echo "FOLDER_NAME=${FOLDER_NAME}" >> "$CONFIG_FILE"
    echo "REMOTE_PATH=${REMOTE_NAME}:backups/${FOLDER_NAME}" >> "$CONFIG_FILE"

    ok "Backup path set to: ${CYAN}${REMOTE_NAME}:backups/${FOLDER_NAME}${NC}"
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 4 — What to backup
# ══════════════════════════════════════════════════════════════════════════════
setup_backup_targets() {
    show_banner
    echo -e "  ${BG_MAGENTA}${WHITE}${BOLD}  STEP 4 — Select Backup Targets  ${NC}"
    echo ""

    echo -e "  ${YELLOW}${BOLD}What do you want to backup?${NC}"
    echo ""
    echo -e "  ${WHITE}  1)${NC}  🦖  Pterodactyl Node Only      ${DIM}(server files + each server zipped separately)${NC}"
    echo -e "  ${WHITE}  2)${NC}  🖥  Pterodactyl Panel Only     ${DIM}(panel files + MySQL database)${NC}"
    echo -e "  ${WHITE}  3)${NC}  🚀  Both Panel + Node          ${DIM}(full backup — recommended)${NC}"
    echo -e "  ${WHITE}  4)${NC}  🔮  Reviactyl Node Only"
    echo -e "  ${WHITE}  5)${NC}  🔮  Reviactyl Panel Only"
    echo -e "  ${WHITE}  6)${NC}  🌐  Custom Directory           ${DIM}(any path you specify)${NC}"
    echo ""
    echo -ne "  ${CYAN}❯ ${NC}Select [1-6]: "; read -r TARGET_CHOICE

    BACKUP_NODE=false
    BACKUP_PANEL=false
    BACKUP_CUSTOM=false
    PANEL_DIR=""
    NODE_DIR=""
    DB_NAME=""
    DB_USER=""
    DB_PASS=""
    CUSTOM_DIR=""
    IS_REVIACTYL=false

    case "$TARGET_CHOICE" in
        1) BACKUP_NODE=true;  NODE_DIR="/var/lib/pterodactyl/volumes" ;;
        2) BACKUP_PANEL=true; PANEL_DIR="/var/www/pterodactyl" ;;
        3) BACKUP_NODE=true;  BACKUP_PANEL=true; NODE_DIR="/var/lib/pterodactyl/volumes"; PANEL_DIR="/var/www/pterodactyl" ;;
        4) BACKUP_NODE=true;  NODE_DIR="/var/lib/reviactyl/volumes"; IS_REVIACTYL=true ;;
        5) BACKUP_PANEL=true; PANEL_DIR="/var/www/reviactyl"; IS_REVIACTYL=true ;;
        6)
            BACKUP_CUSTOM=true
            echo -ne "  ${CYAN}❯ ${NC}Enter full path to directory: "; read -r CUSTOM_DIR
            [ ! -d "$CUSTOM_DIR" ] && warn "Directory does not exist — it will be skipped if missing at backup time."
            ;;
        *) err "Invalid!"; exit 1 ;;
    esac

    # Database config (if panel backup)
    if [ "$BACKUP_PANEL" == "true" ]; then
        echo ""
        echo -e "  ${YELLOW}${BOLD}🗄  Database Backup Configuration:${NC}"
        echo ""

        # Try to auto-detect from .env
        ENV_FILE=""
        [ -f "/var/www/pterodactyl/.env" ]  && ENV_FILE="/var/www/pterodactyl/.env"
        [ -f "/var/www/reviactyl/.env" ]    && ENV_FILE="/var/www/reviactyl/.env"

        if [ -n "$ENV_FILE" ]; then
            # Added || true to prevent set -e from crashing the script if grep fails
            AUTO_DB=$(grep "^DB_DATABASE=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true)
            AUTO_USER=$(grep "^DB_USERNAME=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true)
            AUTO_PASS=$(grep "^DB_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'" || true)
            
            echo -ne "  ${CYAN}❯ ${NC}Database name [${AUTO_DB}]: "; read -r DB_NAME
            [ -z "$DB_NAME" ] && DB_NAME="$AUTO_DB"
            echo -ne "  ${CYAN}❯ ${NC}DB Username [${AUTO_USER}]: "; read -r DB_USER
            [ -z "$DB_USER" ] && DB_USER="$AUTO_USER"
            echo -ne "  ${CYAN}❯ ${NC}DB Password [auto-detected]: "; read -rs DB_PASS; echo ""
            [ -z "$DB_PASS" ] && DB_PASS="$AUTO_PASS"
            ok "Database config auto-detected from .env"
        else
            echo -ne "  ${CYAN}❯ ${NC}Database name [panel]: "; read -r DB_NAME
            [ -z "$DB_NAME" ] && DB_NAME="panel"
            echo -ne "  ${CYAN}❯ ${NC}DB Username [pterodactyl]: "; read -r DB_USER
            [ -z "$DB_USER" ] && DB_USER="pterodactyl"
            echo -ne "  ${CYAN}❯ ${NC}DB Password: "; read -rs DB_PASS; echo ""
        fi
    fi

    # Save to config
    {
        echo "BACKUP_NODE=${BACKUP_NODE}"
        echo "BACKUP_PANEL=${BACKUP_PANEL}"
        echo "BACKUP_CUSTOM=${BACKUP_CUSTOM}"
        echo "NODE_DIR=${NODE_DIR}"
        echo "PANEL_DIR=${PANEL_DIR}"
        echo "CUSTOM_DIR=${CUSTOM_DIR}"
        echo "DB_NAME=${DB_NAME}"
        echo "DB_USER=${DB_USER}"
        echo "DB_PASS=${DB_PASS}"
        echo "IS_REVIACTYL=${IS_REVIACTYL}"
    } >> "$CONFIG_FILE"

    ok "Backup targets configured."
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 5 — Schedule (cron)
# ══════════════════════════════════════════════════════════════════════════════
setup_schedule() {
    show_banner
    echo -e "  ${BG_CYAN}${WHITE}${BOLD}  STEP 5 — Backup Schedule  ${NC}"
    echo ""

    echo -e "  ${YELLOW}${BOLD}⏰ When should backups run automatically?${NC}"
    echo ""
    echo -e "  ${WHITE}  1)${NC}  🌅  Daily at Midnight        ${DIM}(0 0 * * *)${NC}"
    echo -e "  ${WHITE}  2)${NC}  ☀  Daily at 3 AM            ${DIM}(0 3 * * *) — Recommended${NC}"
    echo -e "  ${WHITE}  3)${NC}  🌙  Daily at 6 AM            ${DIM}(0 6 * * *)${NC}"
    echo -e "  ${WHITE}  4)${NC}  🔄  Every 6 Hours            ${DIM}(0 */6 * * *)${NC}"
    echo -e "  ${WHITE}  5)${NC}  📅  Weekly (Sunday 3 AM)     ${DIM}(0 3 * * 0)${NC}"
    echo -e "  ${WHITE}  6)${NC}  ✏   Custom cron expression"
    echo ""
    echo -ne "  ${CYAN}❯ ${NC}Select [1-6]: "; read -r SCHED_CHOICE

    case "$SCHED_CHOICE" in
        1) CRON_EXPR="0 0 * * *" ;;
        2) CRON_EXPR="0 3 * * *" ;;
        3) CRON_EXPR="0 6 * * *" ;;
        4) CRON_EXPR="0 */6 * * *" ;;
        5) CRON_EXPR="0 3 * * 0" ;;
        6)
            echo -ne "  ${CYAN}❯ ${NC}Enter cron expression (e.g. 30 2 * * *): "; read -r CRON_EXPR
            [ -z "$CRON_EXPR" ] && CRON_EXPR="0 3 * * *"
            ;;
        *) CRON_EXPR="0 3 * * *" ;;
    esac

    echo "CRON_EXPR=${CRON_EXPR}" >> "$CONFIG_FILE"
    ok "Backup scheduled: ${BOLD}${CRON_EXPR}"
}

# ══════════════════════════════════════════════════════════════════════════════
#  GENERATE THE ACTUAL BACKUP RUNNER SCRIPT
# ══════════════════════════════════════════════════════════════════════════════
generate_backup_script() {
    source "$CONFIG_FILE"

    cat > "$BACKUP_SCRIPT" <<'BACKUPEOF'
#!/usr/bin/env bash
# ==============================================================================
#  Ray Auto Backup Runner — Generated by Ray Industries
#  DO NOT EDIT MANUALLY — Re-run ray-backup.sh to reconfigure
# ==============================================================================
set -euo pipefail

CONFIG_FILE="/etc/ray-backup/config.conf"
LOG_FILE="/var/log/ray-backup.log"
TMP_DIR="/tmp/ray-backup-tmp"

source "$CONFIG_FILE"

DATE=$(date +%Y-%m-%d_%H-%M)
DEST="${REMOTE_PATH}/${DATE}"
ERRORS=0

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }
log_ok()   { log "✔ $1"; }
log_err()  { log "✖ ERROR: $1"; ERRORS=$((ERRORS+1)); }
log_info() { log "ℹ $1"; }

log_info "========================================================"
log_info " Ray Auto Backup Started — $DATE"
log_info " Destination: ${DEST}"
log_info "========================================================"

mkdir -p "$TMP_DIR"

# ── Panel Backup ───────────────────────────────────────────────────────────────
if [ "${BACKUP_PANEL}" == "true" ] && [ -d "${PANEL_DIR}" ]; then
    log_info "Starting Panel backup..."

    PANEL_TMP="${TMP_DIR}/panel"
    mkdir -p "$PANEL_TMP"

    # Database dump
    if [ -n "${DB_NAME}" ] && [ -n "${DB_USER}" ]; then
        log_info "Dumping database: ${DB_NAME}..."
        if mysqldump -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" > "${PANEL_TMP}/database_${DB_NAME}.sql" 2>/dev/null; then
            log_ok "Database dumped: database_${DB_NAME}.sql"
        else
            log_err "Database dump failed for ${DB_NAME}"
        fi
    fi

    # Panel files (exclude node_modules, cache, etc.)
    log_info "Zipping panel files..."
    if tar -czf "${PANEL_TMP}/panel-files.tar.gz" \
        --exclude="${PANEL_DIR}/node_modules" \
        --exclude="${PANEL_DIR}/vendor" \
        --exclude="${PANEL_DIR}/storage/logs" \
        --exclude="${PANEL_DIR}/bootstrap/cache" \
        -C "$(dirname "${PANEL_DIR}")" "$(basename "${PANEL_DIR}")" 2>/dev/null; then
        log_ok "Panel files zipped."
    else
        log_err "Panel files zip failed."
    fi

    # Upload to cloud
    log_info "Uploading panel backup to cloud..."
    if rclone copy "${PANEL_TMP}/" "${DEST}/panel/" --log-level ERROR; then
        log_ok "Panel backup uploaded to ${DEST}/panel/"
        rm -rf "${PANEL_TMP}"
        log_info "Cleaned up local panel tmp files."
    else
        log_err "Panel upload failed."
    fi
fi

# ── Node Backup (per-server zip) ───────────────────────────────────────────────
if [ "${BACKUP_NODE}" == "true" ] && [ -d "${NODE_DIR}" ]; then
    log_info "Starting Node backup (per-server zip)..."

    NODE_TMP="${TMP_DIR}/node"
    mkdir -p "$NODE_TMP"

    SERVER_COUNT=0
    FAIL_COUNT=0

    # Each subfolder in volumes = one server (UUID-named)
    for SERVER_PATH in "${NODE_DIR}"/*/; do
        [ -d "$SERVER_PATH" ] || continue
        SERVER_UUID=$(basename "$SERVER_PATH")
        ZIP_NAME="${SERVER_UUID}.tar.gz"

        log_info "Zipping server: ${SERVER_UUID}..."
        if tar -czf "${NODE_TMP}/${ZIP_NAME}" -C "${NODE_DIR}" "${SERVER_UUID}" 2>/dev/null; then
            log_ok "Server zipped: ${ZIP_NAME}"
            SERVER_COUNT=$((SERVER_COUNT+1))
        else
            log_err "Failed to zip server: ${SERVER_UUID}"
            FAIL_COUNT=$((FAIL_COUNT+1))
        fi
    done

    log_info "Zipped ${SERVER_COUNT} servers (${FAIL_COUNT} failed)."

    # Upload all zips
    log_info "Uploading server backups to cloud..."
    if rclone copy "${NODE_TMP}/" "${DEST}/servers/" --log-level ERROR; then
        log_ok "All server backups uploaded to ${DEST}/servers/"
        rm -rf "${NODE_TMP}"
        log_info "Cleaned up local node tmp files."
    else
        log_err "Node upload failed."
    fi
fi

# ── Custom Dir Backup ──────────────────────────────────────────────────────────
if [ "${BACKUP_CUSTOM}" == "true" ] && [ -d "${CUSTOM_DIR}" ]; then
    log_info "Starting custom dir backup: ${CUSTOM_DIR}..."

    CUSTOM_TMP="${TMP_DIR}/custom"
    mkdir -p "$CUSTOM_TMP"
    CUSTOM_NAME="custom-$(basename "${CUSTOM_DIR}").tar.gz"

    if tar -czf "${CUSTOM_TMP}/${CUSTOM_NAME}" -C "$(dirname "${CUSTOM_DIR}")" "$(basename "${CUSTOM_DIR}")" 2>/dev/null; then
        log_ok "Custom dir zipped: ${CUSTOM_NAME}"
        if rclone copy "${CUSTOM_TMP}/" "${DEST}/custom/" --log-level ERROR; then
            log_ok "Custom backup uploaded."
            rm -rf "${CUSTOM_TMP}"
        else
            log_err "Custom upload failed."
        fi
    else
        log_err "Custom dir zip failed."
    fi
fi

# ── Cleanup TMP ────────────────────────────────────────────────────────────────
rm -rf "$TMP_DIR"

# ── Summary ────────────────────────────────────────────────────────────────────
log_info "========================================================"
if [ "$ERRORS" -eq 0 ]; then
    log_ok "Backup COMPLETED successfully — ${DATE}"
else
    log_err "Backup completed WITH ${ERRORS} ERROR(S) — check log: ${LOG_FILE}"
fi
log_info "========================================================"
BACKUPEOF

    chmod +x "$BACKUP_SCRIPT"
    ok "Backup runner script created at: ${BOLD}$BACKUP_SCRIPT"
}

# ══════════════════════════════════════════════════════════════════════════════
#  STEP 6 — Register cron job
# ══════════════════════════════════════════════════════════════════════════════
register_cron() {
    source "$CONFIG_FILE"

    step "Registering cron job..."

    # Remove old ray-backup cron if any
    crontab -l 2>/dev/null | grep -v "ray-backup-run" | crontab - 2>/dev/null || true

    # Add new cron
    (crontab -l 2>/dev/null; echo "${CRON_EXPR} /usr/local/bin/ray-backup-run >> /var/log/ray-backup.log 2>&1") | crontab -

    ok "Cron job registered: ${BOLD}${CRON_EXPR}"
    info "Logs will be saved to: ${BOLD}${LOG_FILE}"
}

# ══════════════════════════════════════════════════════════════════════════════
#  SUMMARY & TEST RUN
# ══════════════════════════════════════════════════════════════════════════════
show_summary() {
    source "$CONFIG_FILE"

    show_banner
    echo -e "  ${BG_GREEN}${WHITE}${BOLD}  ✨ BACKUP SYSTEM CONFIGURED SUCCESSFULLY ✨  ${NC}"
    echo ""
    divider
    echo -e "  ${WHITE}${BOLD}  Configuration Summary${NC}"
    divider
    echo ""
    echo -e "  ${CYAN}  Remote:${NC}         ${WHITE}${BOLD}${REMOTE_NAME}${NC}"
    echo -e "  ${CYAN}  Backup Path:${NC}    ${WHITE}${BOLD}${REMOTE_PATH}/<date>/${NC}"
    echo -e "  ${CYAN}  Schedule:${NC}       ${WHITE}${BOLD}${CRON_EXPR}${NC}"
    echo -e "  ${CYAN}  Panel Backup:${NC}   ${WHITE}${BOLD}${BACKUP_PANEL}${NC}"
    [ "${BACKUP_PANEL}" == "true" ] && \
    echo -e "  ${CYAN}  Panel Dir:${NC}      ${WHITE}${BOLD}${PANEL_DIR}${NC}"
    echo -e "  ${CYAN}  Node Backup:${NC}    ${WHITE}${BOLD}${BACKUP_NODE}${NC}"
    [ "${BACKUP_NODE}" == "true" ] && \
    echo -e "  ${CYAN}  Node Dir:${NC}       ${WHITE}${BOLD}${NODE_DIR}${NC}"
    [ "${BACKUP_CUSTOM}" == "true" ] && \
    echo -e "  ${CYAN}  Custom Dir:${NC}     ${WHITE}${BOLD}${CUSTOM_DIR}${NC}"
    [ "${BACKUP_PANEL}" == "true" ] && [ -n "${DB_NAME}" ] && \
    echo -e "  ${CYAN}  Database:${NC}       ${WHITE}${BOLD}${DB_NAME}${NC}"
    echo ""
    divider
    echo ""

    echo -e "  ${YELLOW}${BOLD}📋 Useful Commands:${NC}"
    echo ""
    echo -e "  ${WHITE}  Run backup now:${NC}      ${CYAN}ray-backup-run${NC}"
    echo -e "  ${WHITE}  View logs:${NC}           ${CYAN}tail -f /var/log/ray-backup.log${NC}"
    echo -e "  ${WHITE}  View cron jobs:${NC}      ${CYAN}crontab -l${NC}"
    echo -e "  ${WHITE}  List remote files:${NC}   ${CYAN}rclone lsd ${REMOTE_NAME}:backups${NC}"
    echo -e "  ${WHITE}  Reconfigure:${NC}         ${CYAN}bash ray-backup.sh${NC}"
    echo ""
    divider
    echo ""

    # Modified to default to YES if the user just presses Enter
    echo -ne "  ${YELLOW}❯ ${NC}Run a test backup RIGHT NOW? (Y/n): "; read -r DO_TEST
    if [[ -z "$DO_TEST" || "$DO_TEST" =~ [Yy] ]]; then
        echo ""
        step "Running test backup..."
        echo ""
        bash "$BACKUP_SCRIPT" && echo "" && ok "Test backup completed! Check your cloud storage." || \
            err "Test backup had errors. Check: ${LOG_FILE}"
    fi

    echo ""
    echo -e "  ${MAGENTA}${BOLD}  Thank you for using Ray Industries! 🚀  ${NC}"
    echo -e "  ${DIM}  📺 Subscribe: @RayVerse${NC}"
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
#  MAIN FLOW
# ══════════════════════════════════════════════════════════════════════════════

# Root check
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✖  Please run as root (sudo su)${NC}"
    exit 1
fi

# Init config
mkdir -p /etc/ray-backup "$(dirname "$LOG_FILE")"
> "$CONFIG_FILE"  # Reset config
chmod 600 "$CONFIG_FILE"

show_banner
echo -e "  ${DIM}  Welcome to Ray Auto Backup System!"
echo -e "  This wizard will walk you through setting up automated cloud backups."
echo -e "  Your VPS files will be backed up daily to your chosen cloud storage.${NC}"
echo ""
pause

install_rclone
setup_remote
setup_folder
setup_backup_targets
setup_schedule
generate_backup_script
register_cron
show_summary
