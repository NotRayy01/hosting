#!/usr/bin/env bash

# ==============================================================================
#  Ray Hosting Manager — Smart Pterodactyl Backup System
#  Description : Safe Panel, database, node, and server backups to Google Drive
#  Author      : Ray
# ==============================================================================

set -uo pipefail
IFS=$'\n\t'

readonly INSTALL_PATH="/usr/local/sbin/rhm-backup"
readonly CONFIG_DIR="/etc/rhm-backup"
readonly CONFIG_FILE="$CONFIG_DIR/config"
readonly STATE_DIR="/var/lib/rhm-backup"
readonly INVENTORY_FILE="$STATE_DIR/server-inventory.json"
readonly PENDING_DIR="$STATE_DIR/pending-deletions"
readonly LOG_DIR="/var/log/rhm-backup"
readonly BACKUP_LOG="$LOG_DIR/backup.log"
readonly MONITOR_LOG="$LOG_DIR/monitor.log"
readonly TMP_ROOT="/var/tmp/rhm-backup"
readonly RCLONE_CONFIG="/root/.config/rclone/rclone.conf"
readonly RCLONE_REMOTE="gdrive"
readonly DRIVE_ROOT="RHM-Backups"
readonly SCRIPT_SOURCE_URL="https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/backup.sh"
readonly CRON_FILE="/etc/cron.d/rhm-backup"
readonly LOGROTATE_FILE="/etc/logrotate.d/rhm-backup"
readonly LOCK_FILE="/run/lock/rhm-backup.lock"
readonly LAST_RUN_FILE="$STATE_DIR/last-run.json"
readonly RECOVERY_STATE_FILE="$STATE_DIR/recovery-state.json"
readonly RECOVERY_LOG="$LOG_DIR/recovery.log"
readonly LEGACY_SCRIPT="/root/auto_backup.sh"
readonly LEGACY_TEMP_DIR="/tmp/pterodactyl_backups"
readonly LEGACY_LOG="/var/log/rclone_backup.log"

# Terminal colours
if [[ -t 1 && "${NO_COLOR:-0}" != "1" ]]; then
    readonly RESET='\033[0m'
    readonly BOLD='\033[1m'
    readonly DIM='\033[2m'
    readonly RED='\033[38;5;196m'
    readonly GREEN='\033[38;5;46m'
    readonly YELLOW='\033[38;5;220m'
    readonly BLUE='\033[38;5;39m'
    readonly PURPLE='\033[38;5;135m'
    readonly CYAN='\033[38;5;51m'
    readonly WHITE='\033[38;5;255m'
else
    readonly RESET='' BOLD='' DIM='' RED='' GREEN='' YELLOW=''
    readonly BLUE='' PURPLE='' CYAN='' WHITE=''
fi

# Saved configuration defaults
BACKUP_TYPE="node"
NODE_FOLDER="RayNode"
RETENTION_DAYS="7"
BACKUP_HOUR="2"
BACKUP_MINUTE="0"
PANEL_URL=""
PANEL_API_KEY=""
PANEL_NODE_ID=""
DISCORD_WEBHOOK=""
DISCORD_USER_ID=""
ENABLED="1"
LEGACY_CLEANUP_DONE="0"
BACKUP_NOTIFICATIONS="1"
OS_NAME="Unknown Linux"
OS_FAMILY="unknown"
OS_ARCH="$(uname -m 2>/dev/null || printf unknown)"

ok()    { printf '%b\n' "${GREEN}[✓]${RESET} $*"; }
info()  { printf '%b\n' "${CYAN}[➜]${RESET} $*"; }
warn()  { printf '%b\n' "${YELLOW}[!]${RESET} $*"; }
error() { printf '%b\n' "${RED}[✗]${RESET} $*" >&2; }
step()  { printf '%b\n' "${PURPLE}[◆]${RESET} ${BOLD}$*${RESET}"; }

log_line() {
    local level="$1"; shift
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
}

banner() {
    command -v clear >/dev/null 2>&1 && clear || true
    printf '%b\n' "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${RESET}"
    printf '%b\n' "${CYAN}║${RESET}  ${PURPLE}██████╗ ${BLUE}██╗  ██╗${CYAN}███╗   ███╗${RESET}     ${YELLOW}SMART CLOUD BACKUPS${RESET}      ${CYAN}║${RESET}"
    printf '%b\n' "${CYAN}║${RESET}  ${PURPLE}██╔══██╗${BLUE}██║  ██║${CYAN}████╗ ████║${RESET}     ${WHITE}Safe • Organized • Automatic${RESET} ${CYAN}║${RESET}"
    printf '%b\n' "${CYAN}║${RESET}  ${PURPLE}██████╔╝${BLUE}███████║${CYAN}██╔████╔██║${RESET}                                  ${CYAN}║${RESET}"
    printf '%b\n' "${CYAN}║${RESET}  ${PURPLE}██╔══██╗${BLUE}██╔══██║${CYAN}██║╚██╔╝██║${RESET}       ${GREEN}Ray Hosting Manager${RESET}       ${CYAN}║${RESET}"
    printf '%b\n' "${CYAN}║${RESET}  ${PURPLE}██║  ██║${BLUE}██║  ██║${CYAN}██║ ╚═╝ ██║${RESET}       ${DIM}Created by Ray${RESET}             ${CYAN}║${RESET}"
    printf '%b\n' "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${RESET}"
}

mini_animation() {
    [[ -t 1 ]] || return 0
    printf '%b' "${CYAN}Initializing RHM"
    local _
    for _ in 1 2 3; do printf '%b' "${PURPLE} ●${RESET}"; sleep 0.12; done
    printf '\n'
}

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        error "Please run this script as root: sudo bash $0"
        exit 1
    fi
}

ensure_dirs() {
    install -d -m 700 "$CONFIG_DIR" "$STATE_DIR" "$PENDING_DIR" "$TMP_ROOT"
    install -d -m 755 "$LOG_DIR"
    install -d -m 700 "$(dirname "$RCLONE_CONFIG")"
    [[ -f "$INVENTORY_FILE" ]] || printf '[]\n' > "$INVENTORY_FILE"
    chmod 600 "$INVENTORY_FILE"
}

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # The file is root-owned, mode 600, and written with shell escaping.
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi
}

write_config_value() {
    local key="$1" value="$2"
    printf '%s=%q\n' "$key" "$value"
}

save_config() {
    ensure_dirs
    local temp="$CONFIG_FILE.tmp"
    umask 077
    {
        write_config_value BACKUP_TYPE "$BACKUP_TYPE"
        write_config_value NODE_FOLDER "$NODE_FOLDER"
        write_config_value RETENTION_DAYS "$RETENTION_DAYS"
        write_config_value BACKUP_HOUR "$BACKUP_HOUR"
        write_config_value BACKUP_MINUTE "$BACKUP_MINUTE"
        write_config_value PANEL_URL "$PANEL_URL"
        write_config_value PANEL_API_KEY "$PANEL_API_KEY"
        write_config_value PANEL_NODE_ID "$PANEL_NODE_ID"
        write_config_value DISCORD_WEBHOOK "$DISCORD_WEBHOOK"
        write_config_value DISCORD_USER_ID "$DISCORD_USER_ID"
        write_config_value ENABLED "$ENABLED"
        write_config_value LEGACY_CLEANUP_DONE "$LEGACY_CLEANUP_DONE"
        write_config_value BACKUP_NOTIFICATIONS "$BACKUP_NOTIFICATIONS"
    } > "$temp"
    chmod 600 "$temp"
    mv -f "$temp" "$CONFIG_FILE"
}

read_tty() {
    local prompt="$1" default="${2:-}" answer
    if [[ -n "$default" ]]; then
        printf '%b' "${CYAN}➜${RESET} $prompt ${DIM}[$default]${RESET}: " > /dev/tty
    else
        printf '%b' "${CYAN}➜${RESET} $prompt: " > /dev/tty
    fi
    IFS= read -r answer < /dev/tty || answer=""
    printf '%s' "${answer:-$default}"
}

read_secret() {
    local prompt="$1" answer
    printf '%b' "${CYAN}➜${RESET} $prompt: " > /dev/tty
    IFS= read -r -s answer < /dev/tty || answer=""
    printf '\n' > /dev/tty
    printf '%s' "$answer"
}

normalize_drive_token() {
    local input="$1" compact decoded inner remainder padding

    # Raw OAuth token JSON.
    if jq -e 'type == "object" and (.access_token? != null or .refresh_token? != null)' \
        >/dev/null 2>&1 <<< "$input"; then
        jq -c . <<< "$input"
        return 0
    fi

    # Decoded rclone config object: {"token":"{...oauth json...}"}
    if jq -e 'type == "object" and (.token? != null)' >/dev/null 2>&1 <<< "$input"; then
        inner="$(jq -r 'if (.token | type) == "string" then .token else (.token | tojson) end' <<< "$input")"
        if jq -e 'type == "object" and (.access_token? != null or .refresh_token? != null)' \
            >/dev/null 2>&1 <<< "$inner"; then
            jq -c . <<< "$inner"
            return 0
        fi
    fi

    # rclone authorize commonly returns a Base64 config_token beginning with
    # eyJ..., not visible JSON. Strip labels/whitespace and decode it safely.
    compact="$input"
    if [[ "$compact" == *config_token\>* ]]; then
        compact="${compact#*config_token> }"
        compact="${compact#*config_token>}"
    fi
    compact="$(printf '%s' "$compact" | tr -d '[:space:]')"
    [[ "$compact" =~ ^[A-Za-z0-9_+/=-]+$ ]] || return 1
    compact="${compact//-/+}"
    compact="${compact//_/\/}"
    remainder=$((${#compact} % 4))
    case "$remainder" in
        0) padding="" ;;
        2) padding="==" ;;
        3) padding="=" ;;
        *) return 1 ;;
    esac
    decoded="$(printf '%s%s' "$compact" "$padding" | base64 --decode 2>/dev/null)" || return 1

    if jq -e 'type == "object" and (.access_token? != null or .refresh_token? != null)' \
        >/dev/null 2>&1 <<< "$decoded"; then
        jq -c . <<< "$decoded"
        return 0
    fi
    if jq -e 'type == "object" and (.token? != null)' >/dev/null 2>&1 <<< "$decoded"; then
        inner="$(jq -r 'if (.token | type) == "string" then .token else (.token | tojson) end' <<< "$decoded")"
        if jq -e 'type == "object" and (.access_token? != null or .refresh_token? != null)' \
            >/dev/null 2>&1 <<< "$inner"; then
            jq -c . <<< "$inner"
            return 0
        fi
    fi
    return 1
}

read_json_token() {
    local token="" line candidate normalized
    printf '%b\n' "${CYAN}┌──────────────── GOOGLE TOKEN INPUT ────────────────┐${RESET}" > /dev/tty
    printf '%b\n' "${WHITE}Paste the complete token shown after config_token>.${RESET}" > /dev/tty
    printf '%b\n' "${DIM}Encoded eyJ... tokens and raw JSON are both supported.${RESET}" > /dev/tty
    printf '%b\n' "${DIM}Single-line tokens are accepted immediately.${RESET}" > /dev/tty
    printf '%b\n' "${YELLOW}The token is visible while pasting, but will not be printed again.${RESET}" > /dev/tty
    printf '%b\n' "${CYAN}└─────────────────────────────────────────────────────┘${RESET}" > /dev/tty
    printf '%b' "${CYAN}token>${RESET} " > /dev/tty

    while IFS= read -r line < /dev/tty; do
        token+="${token:+$'\n'}$line"
        if normalized="$(normalize_drive_token "$token")"; then
            printf '%s' "$normalized"
            return 0
        fi
        [[ -n "$line" ]] || break
        printf '%b' "${CYAN}...>${RESET} " > /dev/tty
    done

    # If users accidentally include rclone's arrow/label lines, keep only the
    # JSON object between the first opening and last closing brace.
    if [[ "$token" == *'{'* && "$token" == *'}'* ]]; then
        candidate="{${token#*\{}"
        candidate="${candidate%\}*}}"
        if normalized="$(normalize_drive_token "$candidate")"; then
            printf '%s' "$normalized"
            return 0
        fi
    fi
    return 1
}

confirm() {
    local prompt="$1" default="${2:-n}" answer
    answer="$(read_tty "$prompt (y/n)" "$default")"
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

sanitize_name() {
    local value="$1"
    value="${value// /-}"
    value="$(printf '%s' "$value" | tr -cd 'A-Za-z0-9._-')"
    value="${value:0:80}"
    [[ -n "$value" ]] || value="Unnamed"
    printf '%s' "$value"
}

valid_integer() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

os_release_value() {
    local key="$1" value
    value="$(awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' /etc/os-release 2>/dev/null)"
    value="${value#\"}"; value="${value%\"}"
    value="${value#\'}"; value="${value%\'}"
    printf '%s' "$value"
}

detect_os() {
    local announce="${1:-0}" os_id os_like
    if [[ -r /etc/os-release ]]; then
        os_id="$(os_release_value ID)"
        os_like="$(os_release_value ID_LIKE)"
        OS_NAME="$(os_release_value NAME)"
        [[ -n "$OS_NAME" ]] || OS_NAME="$os_id"
        case " $os_id $os_like " in
            *" debian "*|*" ubuntu "*|*" linuxmint "*|*" pop "*) OS_FAMILY="debian" ;;
            *" rhel "*|*" fedora "*|*" centos "*|*" almalinux "*|*" rocky "*|*" ol "*) OS_FAMILY="rhel" ;;
            *) OS_FAMILY="unknown" ;;
        esac
    fi
    OS_ARCH="$(uname -m 2>/dev/null || printf unknown)"
    if [[ "$announce" == "1" ]]; then
        ok "Detected OS: ${OS_NAME:-Unknown Linux} ($OS_ARCH)"
        case "$OS_FAMILY" in
            debian) info "Debian-family package and cron handling selected." ;;
            rhel) info "RHEL-family package and cron handling selected." ;;
            *) warn "OS family is not recognized; safe package-manager fallback will be used." ;;
        esac
    fi
}

install_dependencies() {
    step "Checking required packages"
    detect_os 1
    local missing=0 cmd
    for cmd in curl jq tar gzip crontab flock sha256sum; do
        if command -v "$cmd" >/dev/null 2>&1; then
            ok "$cmd detected — reusing the existing installation."
        else
            warn "$cmd is missing — it will be installed automatically."
            missing=1
        fi
    done
    if command -v mysqldump >/dev/null 2>&1 || command -v mariadb-dump >/dev/null 2>&1; then
        ok "MySQL/MariaDB backup client detected — reusing it."
    else
        warn "MySQL/MariaDB backup client is missing — it will be installed automatically."
        missing=1
    fi

    if (( missing )); then
        info "Installing required system packages…"
        case "$OS_FAMILY" in
            debian)
                apt-get update -y
                DEBIAN_FRONTEND=noninteractive apt-get install -y \
                    curl jq tar gzip cron util-linux coreutils ca-certificates default-mysql-client
                ;;
            rhel)
                if command -v dnf >/dev/null 2>&1; then
                    dnf install -y curl jq tar gzip cronie util-linux coreutils ca-certificates mariadb
                else
                    yum install -y curl jq tar gzip cronie util-linux coreutils ca-certificates mariadb
                fi
                ;;
            *)
                if command -v apt-get >/dev/null 2>&1; then
                    apt-get update -y
                    DEBIAN_FRONTEND=noninteractive apt-get install -y \
                        curl jq tar gzip cron util-linux coreutils ca-certificates default-mysql-client
                elif command -v dnf >/dev/null 2>&1; then
                    dnf install -y curl jq tar gzip cronie util-linux coreutils ca-certificates mariadb
                elif command -v yum >/dev/null 2>&1; then
                    yum install -y curl jq tar gzip cronie util-linux coreutils ca-certificates mariadb
                else
                    error "Unsupported OS/package manager. Install curl, jq, tar, gzip, cron, flock and a MySQL client manually."
                    return 1
                fi
                ;;
        esac
    fi

    if ! command -v rclone >/dev/null 2>&1; then
        info "Installing rclone from its official installer…"
        local installer
        installer="$(mktemp)"
        if ! curl -fsSL https://rclone.org/install.sh -o "$installer"; then
            rm -f "$installer"
            error "Could not download the rclone installer."
            return 1
        fi
        bash "$installer"
        rm -f "$installer"
    else
        ok "rclone detected — reusing the existing installation."
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now cron >/dev/null 2>&1 || \
            systemctl enable --now crond >/dev/null 2>&1 || true
    else
        service cron start >/dev/null 2>&1 || service crond start >/dev/null 2>&1 || true
    fi

    for cmd in curl jq tar gzip crontab flock rclone sha256sum; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Required command is still missing: $cmd"
            return 1
        fi
    done
    if ! command -v mysqldump >/dev/null 2>&1 && ! command -v mariadb-dump >/dev/null 2>&1; then
        error "A MySQL/MariaDB backup client could not be installed."
        return 1
    fi
    ok "Dependencies are ready."
}

legacy_script_is_verified() {
    [[ -f "$LEGACY_SCRIPT" ]] || return 1
    grep -Fq 'BACKUP_TEMP_DIR="/tmp/pterodactyl_backups"' "$LEGACY_SCRIPT" && \
        grep -Fq 'GDRIVE_REMOTE="gdrive:backups"' "$LEGACY_SCRIPT"
}

remove_legacy_cron() {
    local current temp
    if [[ -e "$LEGACY_SCRIPT" ]] && ! legacy_script_is_verified; then
        return 2
    fi
    current="$(crontab -l 2>/dev/null || true)"
    grep -Fq "$LEGACY_SCRIPT" <<< "$current" || return 1
    temp="$(mktemp)"
    printf '%s\n' "$current" | grep -Fv "$LEGACY_SCRIPT" > "$temp" || true
    crontab "$temp"
    rm -f "$temp"
    ok "Removed legacy cron entry that executed $LEGACY_SCRIPT."
}

cleanup_legacy_install() {
    step "Scanning for the old Ray backup installation"
    local found=0 size answer

    remove_legacy_cron
    local cron_result=$?
    if (( cron_result == 0 )); then
        found=1
    elif (( cron_result == 2 )); then
        warn "A non-Ray script exists at $LEGACY_SCRIPT, so its cron entry was preserved."
    else
        info "No legacy /root/auto_backup.sh cron entry found."
    fi

    if legacy_script_is_verified; then
        rm -f -- "$LEGACY_SCRIPT"
        ok "Removed verified legacy backup engine: $LEGACY_SCRIPT"
        found=1
    elif [[ -e "$LEGACY_SCRIPT" ]]; then
        warn "$LEGACY_SCRIPT exists but does not match the old RayBackup signature; it was preserved for safety."
    else
        info "No legacy backup engine found."
    fi

    if [[ -f "$LEGACY_LOG" ]]; then
        rm -f -- "$LEGACY_LOG"
        ok "Removed legacy rclone log: $LEGACY_LOG"
        found=1
    fi

    if [[ -d "$LEGACY_TEMP_DIR" ]]; then
        if [[ -z "$(find "$LEGACY_TEMP_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]]; then
            rmdir -- "$LEGACY_TEMP_DIR" 2>/dev/null || true
            ok "Removed empty legacy temporary directory: $LEGACY_TEMP_DIR"
        else
            size="$(du -sh "$LEGACY_TEMP_DIR" 2>/dev/null | awk 'NR==1 {print $1}')"
            warn "Legacy temporary backup data found at $LEGACY_TEMP_DIR (${size:-unknown size})."
            warn "These files may be the only copy of a previously failed upload."
            answer="$(read_tty "Permanently delete this verified legacy temporary data? (y/n)" "n")"
            if [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]; then
                if [[ "$(readlink -f "$LEGACY_TEMP_DIR")" == "/tmp/pterodactyl_backups" ]]; then
                    rm -rf -- "$LEGACY_TEMP_DIR"
                    ok "Removed legacy temporary backup data: $LEGACY_TEMP_DIR"
                else
                    warn "Temporary path validation failed; nothing was deleted."
                fi
            else
                warn "Legacy temporary data was preserved. You can inspect it later at $LEGACY_TEMP_DIR."
            fi
        fi
        found=1
    fi

    if rclone_cmd listremotes 2>/dev/null | grep -qx 'gdrive:'; then
        info "Existing gdrive remote detected. Setup can reuse it or replace its account token."
        info "Other rclone remotes and their settings will remain untouched."
        found=1
    fi

    if (( found == 0 )); then
        ok "No old Ray backup installation was found; this is a clean setup."
    else
        ok "Legacy scan finished. Only verified Ray backup artifacts were removed."
    fi
    info "Existing Google Drive backup data was not deleted. New backups will use $DRIVE_ROOT."
    LEGACY_CLEANUP_DONE="1"
}

install_self() {
    local source_path="${BASH_SOURCE[0]}" downloaded_copy=""
    case "$source_path" in
        /dev/fd/*|/proc/*/fd/*)
            info "Process-substitution launch detected; downloading a stable installer copy…"
            downloaded_copy="$(mktemp)"
            if ! curl -fsSL --connect-timeout 15 --max-time 120 "$SCRIPT_SOURCE_URL" -o "$downloaded_copy"; then
                rm -f "$downloaded_copy"
                error "Could not download a stable installer copy from GitHub."
                return 1
            fi
            if ! bash -n "$downloaded_copy" || ! grep -Fq 'Ray Hosting Manager' "$downloaded_copy"; then
                rm -f "$downloaded_copy"
                error "The downloaded installer failed validation. Nothing was installed."
                return 1
            fi
            source_path="$downloaded_copy"
            ;;
        *)
            source_path="$(readlink -f "$source_path")"
            ;;
    esac

    if [[ "$source_path" != "$INSTALL_PATH" ]]; then
        if ! install -m 700 "$source_path" "$INSTALL_PATH"; then
            [[ -n "$downloaded_copy" ]] && rm -f "$downloaded_copy"
            error "Could not install the manager command at $INSTALL_PATH."
            return 1
        fi
    else
        chmod 700 "$INSTALL_PATH"
    fi
    [[ -n "$downloaded_copy" ]] && rm -f "$downloaded_copy"
    ok "Manager command installed: $INSTALL_PATH"

    cat > "$LOGROTATE_FILE" <<EOF
$LOG_DIR/*.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    copytruncate
}
EOF
    chmod 644 "$LOGROTATE_FILE"
}

remote_path() {
    printf '%s:%s/%s' "$RCLONE_REMOTE" "$DRIVE_ROOT" "$1"
}

rclone_cmd() {
    rclone --config "$RCLONE_CONFIG" "$@"
}

configure_drive() {
    local mode="${1:-setup}" token backup="" existed=0
    step "Connect a Google Drive account"
    install -d -m 700 "$(dirname "$RCLONE_CONFIG")"
    rclone_cmd listremotes 2>/dev/null | grep -qx 'gdrive:' && existed=1 || true

    if (( existed )) && [[ "$mode" != "change" ]] && \
       rclone_cmd lsd "$RCLONE_REMOTE:" --contimeout 10s --timeout 30s >/dev/null 2>&1; then
        ok "A working Google Drive configuration named gdrive is already available."
        if confirm "Reuse this existing Google Drive account without pasting JSON?" "y"; then
            if rclone_cmd mkdir "$RCLONE_REMOTE:$DRIVE_ROOT" >/dev/null 2>&1; then
                ok "Existing Google Drive account reused successfully."
                return 0
            fi
            error "The existing account could not create $DRIVE_ROOT. New authorization is required."
        fi
    fi

    printf '%b\n' "${WHITE}On your PC, run:${RESET}"
    printf '%b\n\n' "  ${YELLOW}rclone authorize \"drive\" \"eyJzY29wZSI6ImRyaXZlIn0\"${RESET}"
    info "Sign in to the Google account that should receive future backups."
    if ! token="$(read_json_token)"; then
        error "A complete Google Drive config token or OAuth JSON token was not detected. Google Drive was not changed."
        info "Tip: use right-click or Shift+Insert to paste in most VPS terminals."
        return 1
    fi

    if [[ -f "$RCLONE_CONFIG" ]]; then
        backup="$(mktemp)"
        cp -a "$RCLONE_CONFIG" "$backup"
    fi

    if (( existed )); then
        rclone_cmd config update "$RCLONE_REMOTE" scope drive token "$token" --non-interactive >/dev/null
    else
        rclone_cmd config create "$RCLONE_REMOTE" drive scope drive token "$token" --non-interactive >/dev/null
    fi
    chmod 600 "$RCLONE_CONFIG"

    info "Validating account and creating the protected root folder…"
    if ! rclone_cmd lsd "$RCLONE_REMOTE:" >/dev/null 2>&1 || \
       ! rclone_cmd mkdir "$RCLONE_REMOTE:$DRIVE_ROOT" >/dev/null 2>&1; then
        error "Authentication test failed. Restoring the previous Drive configuration."
        if [[ -n "$backup" ]]; then
            cp -a "$backup" "$RCLONE_CONFIG"
        else
            rclone_cmd config delete "$RCLONE_REMOTE" >/dev/null 2>&1 || true
        fi
        [[ -n "$backup" ]] && rm -f "$backup"
        return 1
    fi
    [[ -n "$backup" ]] && rm -f "$backup"
    ok "Google Drive connected. Future backups will use this account."
    warn "Changing accounts does not remove backups from the previous Google Drive."
}

api_collection() {
    local resource="$1" output="$2"
    [[ -n "$PANEL_URL" && -n "$PANEL_API_KEY" ]] || return 1
    local page=1 total_pages=1 response ndjson
    ndjson="$(mktemp)"
    : > "$ndjson"
    while (( page <= total_pages )); do
        if ! response="$(curl -fsS --connect-timeout 10 --max-time 45 \
            -H "Authorization: Bearer $PANEL_API_KEY" \
            -H 'Accept: Application/vnd.pterodactyl.v1+json' \
            "${PANEL_URL%/}/api/application/${resource}?per_page=100&page=${page}")"; then
            rm -f "$ndjson"
            return 1
        fi
        if ! jq -e '.data | type == "array"' >/dev/null 2>&1 <<< "$response"; then
            rm -f "$ndjson"
            return 1
        fi
        jq -c '.data[].attributes' <<< "$response" >> "$ndjson"
        total_pages="$(jq -r '.meta.pagination.total_pages // 1' <<< "$response")"
        valid_integer "$total_pages" || total_pages=1
        ((page++))
    done
    jq -s '.' "$ndjson" > "$output"
    rm -f "$ndjson"
}

detect_panel_node_id() {
    [[ -f /etc/pterodactyl/config.yml ]] || return 1
    local local_uuid nodes
    local_uuid="$(awk -F: '/^[[:space:]]*uuid:/{sub(/^[[:space:]]*/, "", $2); gsub(/[[:space:]\047\042]/, "", $2); print $2; exit}' /etc/pterodactyl/config.yml)"
    [[ -n "$local_uuid" ]] || return 1
    nodes="$(mktemp)"
    if ! api_collection nodes "$nodes"; then
        rm -f "$nodes"
        return 1
    fi
    PANEL_NODE_ID="$(jq -r --arg uuid "$local_uuid" '.[] | select(.uuid == $uuid) | .id' "$nodes" | head -n1)"
    rm -f "$nodes"
    [[ "$PANEL_NODE_ID" =~ ^[0-9]+$ ]]
}

configure_panel_integration() {
    step "Panel API and Discord deletion protection"
    info "An Application API key lets RHM obtain server names and safely confirm deletions."
    info "Create it in: Pterodactyl Admin → Application API → New Credentials."

    local value
    value="$(read_tty "Panel URL (example: https://panel.example.com)" "$PANEL_URL")"
    PANEL_URL="${value%/}"
    value="$(read_secret "Application API key (leave blank to keep the current key)")"
    [[ -n "$value" ]] && PANEL_API_KEY="$value"

    if [[ -n "$PANEL_URL" && -n "$PANEL_API_KEY" ]]; then
        info "Finding this Wings node on the Panel…"
        if detect_panel_node_id; then
            ok "Matched Panel node ID: $PANEL_NODE_ID"
        else
            warn "Automatic node matching failed."
            value="$(read_tty "Enter this node's numeric Panel ID" "$PANEL_NODE_ID")"
            if [[ "$value" =~ ^[0-9]+$ ]]; then
                PANEL_NODE_ID="$value"
            else
                PANEL_NODE_ID=""
                warn "Server-name organization and deletion monitoring will stay disabled until a valid node ID is set."
            fi
        fi
    fi

    value="$(read_secret "Discord webhook URL (leave blank to keep the current webhook)")"
    [[ -n "$value" ]] && DISCORD_WEBHOOK="$value"
    value="$(read_tty "Discord user ID to ping" "$DISCORD_USER_ID")"
    [[ -n "$value" ]] && DISCORD_USER_ID="$value"
    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        if confirm "Send a Discord summary after every backup?" "y"; then
            BACKUP_NOTIFICATIONS="1"
        else
            BACKUP_NOTIFICATIONS="0"
        fi
    fi
    save_config
}

configure_type() {
    local option
    printf '%b\n' "${WHITE}1)${RESET} Node only"
    printf '%b\n' "${WHITE}2)${RESET} Panel files + database only"
    printf '%b\n' "${WHITE}3)${RESET} Both Node and Panel"
    while true; do
        option="$(read_tty "Choose backup type [1-3]" "1")"
        case "$option" in
            1) BACKUP_TYPE="node"; break ;;
            2) BACKUP_TYPE="panel"; break ;;
            3) BACKUP_TYPE="both"; break ;;
            *) warn "Choose 1, 2, or 3." ;;
        esac
    done
}

configure_retention() {
    local value
    while true; do
        value="$(read_tty "Keep backups for how many days?" "$RETENTION_DAYS")"
        if valid_integer "$value" && (( value >= 1 && value <= 3650 )); then
            RETENTION_DAYS="$value"
            break
        fi
        warn "Enter a number from 1 to 3650."
    done
}

configure_time() {
    local value hour minute
    while true; do
        value="$(read_tty "Daily backup time in 24-hour format (HH:MM)" "$(printf '%02d:%02d' "$BACKUP_HOUR" "$BACKUP_MINUTE")")"
        if [[ "$value" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
            hour="${BASH_REMATCH[1]}"; minute="${BASH_REMATCH[2]}"
            BACKUP_HOUR="$((10#$hour))"
            BACKUP_MINUTE="$((10#$minute))"
            break
        fi
        warn "Use a valid time such as 02:00 or 23:30."
    done
}

write_cron() {
    cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${BACKUP_MINUTE} ${BACKUP_HOUR} * * * root ${INSTALL_PATH} --backup >> ${BACKUP_LOG} 2>&1
*/5 * * * * root ${INSTALL_PATH} --monitor >> ${MONITOR_LOG} 2>&1
EOF
    chmod 644 "$CRON_FILE"
}

stop_automation() {
    ENABLED="0"
    save_config
    [[ -f "$CRON_FILE" ]] && rm -f "$CRON_FILE"
    ok "Automatic backups and deletion monitoring are stopped. Existing backups were not touched."
}

resume_automation() {
    ENABLED="1"
    save_config
    write_cron
    ok "Automatic backups resumed."
}

toggle_backup_notifications() {
    if [[ "$BACKUP_NOTIFICATIONS" == "1" ]]; then
        BACKUP_NOTIFICATIONS="0"
        save_config
        ok "Routine backup success/error Discord messages are now stopped."
        info "Server-deletion warnings, cancellation alerts, and lifetime-backup deletion messages remain active."
    else
        if [[ -z "$DISCORD_WEBHOOK" ]]; then
            warn "Add a Discord webhook in option 6 before enabling backup messages."
            return 1
        fi
        BACKUP_NOTIFICATIONS="1"
        save_config
        ok "Routine backup success/error Discord messages are active again."
        info "Server-deletion protection remains active as before."
    fi
}

initial_setup() {
    banner
    mini_animation
    install_dependencies || return 1
    ensure_dirs
    cleanup_legacy_install
    install_self || return 1
    configure_drive || return 1

    step "Choose what RHM should protect"
    configure_type
    if [[ "$BACKUP_TYPE" == "node" || "$BACKUP_TYPE" == "both" ]]; then
        NODE_FOLDER="$(sanitize_name "$(read_tty "Custom node folder name" "$NODE_FOLDER")")"
        configure_panel_integration
    fi
    configure_retention
    configure_time
    ENABLED="1"
    save_config
    write_cron

    rclone_cmd mkdir "$(remote_path Panel)" >/dev/null 2>&1 || true
    rclone_cmd mkdir "$(remote_path Database)" >/dev/null 2>&1 || true
    rclone_cmd mkdir "$(remote_path "Nodes/$NODE_FOLDER/Servers")" >/dev/null 2>&1 || true
    rclone_cmd mkdir "$(remote_path "Nodes/$NODE_FOLDER/Node-Configuration")" >/dev/null 2>&1 || true

    printf '\n'
    ok "RHM Smart Backup System is installed."
    info "Immutable Drive root: $DRIVE_ROOT"
    info "Retention: latest $RETENTION_DAYS day(s)"
    info "Schedule: $(printf '%02d:%02d' "$BACKUP_HOUR" "$BACKUP_MINUTE") ($(date +%Z))"
    if confirm "Run the first backup now?" "y"; then
        run_backup 1
    fi
}

send_webhook() {
    local message="$1"
    [[ -n "$DISCORD_WEBHOOK" ]] || return 0
    # Existing notification templates use literal \n separators. Convert only
    # those separators to real newlines before JSON encoding for Discord.
    message="${message//\\n/$'\n'}"
    local payload
    payload="$(jq -cn --arg content "$message" '{content:$content,allowed_mentions:{parse:["users"]}}')"
    curl -fsS --connect-timeout 10 --max-time 25 \
        -H 'Content-Type: application/json' -d "$payload" "$DISCORD_WEBHOOK" >/dev/null 2>&1 || \
        log_line WARN "Discord webhook delivery failed."
}

discord_ping() {
    if [[ "$DISCORD_USER_ID" =~ ^[0-9]+$ ]]; then
        printf '<@%s>' "$DISCORD_USER_ID"
    else
        printf '@here'
    fi
}

record_run_status() {
    local status="$1" started="$2" finished="$3" note="$4" temp failed_count
    failed_count="$(failed_recovery_count)"
    temp="$(mktemp)"
    jq -n --arg status "$status" --arg type "$BACKUP_TYPE" --arg node "$NODE_FOLDER" \
        --arg note "$note" --arg hostname "$(hostname)" \
        --argjson started "$started" --argjson finished "$finished" \
        --argjson failed "${failed_count:-0}" \
        '{status:$status,started_at:$started,finished_at:$finished,hostname:$hostname,backup_type:$type,node_folder:$node,failed_local_archives:$failed,note:$note}' \
        > "$temp"
    mv -f "$temp" "$LAST_RUN_FILE"
    chmod 600 "$LAST_RUN_FILE"
}

notify_backup_result() {
    local status="$1" timestamp="$2" duration="$3" failed_count ping=""
    [[ "$BACKUP_NOTIFICATIONS" == "1" && -n "$DISCORD_WEBHOOK" ]] || return 0
    failed_count="$(failed_recovery_count)"
    if [[ "$status" == "success" ]]; then
        send_webhook "✅ **RHM backup completed**\nHost: **$(hostname)**\nType: **$BACKUP_TYPE**\nTime: **$timestamp**\nDuration: **${duration}s**\nRetention: **$RETENTION_DAYS day(s)**\nAll uploaded archives passed size verification and include SHA-256 checksums."
    else
        ping="$(discord_ping)"
        send_webhook "$ping ⚠️ **RHM backup completed with errors**\nHost: **$(hostname)**\nType: **$BACKUP_TYPE**\nTime: **$timestamp**\nDuration: **${duration}s**\nPending failed uploads: **${failed_count:-0}**\nNote: This number can be 0 when a backup task failed before upload.\nCheck: \`$BACKUP_LOG\`"
    fi
}

get_all_servers() {
    local output="$1"
    api_collection servers "$output"
}

upsert_inventory() {
    local uuid="$1" name="$2" folder="$3" temp
    temp="$(mktemp)"
    jq --arg uuid "$uuid" --arg name "$name" --arg folder "$folder" \
       'map(select(.uuid != $uuid)) + [{uuid:$uuid,name:$name,remote_folder:$folder}]' \
       "$INVENTORY_FILE" > "$temp" && mv -f "$temp" "$INVENTORY_FILE"
    chmod 600 "$INVENTORY_FILE"
}

remove_inventory() {
    local uuid="$1" temp
    temp="$(mktemp)"
    jq --arg uuid "$uuid" 'map(select(.uuid != $uuid))' "$INVENTORY_FILE" > "$temp" && \
        mv -f "$temp" "$INVENTORY_FILE"
    chmod 600 "$INVENTORY_FILE"
}

sync_current_servers() {
    local all_servers="$1" server_id uuid name safe_name new_folder old_folder old_path new_path
    [[ "$PANEL_NODE_ID" =~ ^[0-9]+$ ]] || return 1
    while IFS=$'\t' read -r server_id uuid name; do
        [[ -n "$uuid" ]] || continue
        safe_name="$(sanitize_name "$name")"
        new_folder="ID-${server_id}--${safe_name}--${uuid}"
        old_folder="$(jq -r --arg uuid "$uuid" '.[] | select(.uuid == $uuid) | .remote_folder' "$INVENTORY_FILE" | head -n1)"

        if [[ -n "$old_folder" && "$old_folder" != "$new_folder" ]]; then
            old_path="$(remote_path "Nodes/$NODE_FOLDER/Servers/$old_folder")"
            new_path="$(remote_path "Nodes/$NODE_FOLDER/Servers/$new_folder")"
            if rclone_cmd lsf "$old_path" >/dev/null 2>&1; then
                if rclone_cmd move "$old_path" "$new_path" --delete-empty-src-dirs >/dev/null 2>&1; then
                    log_line INFO "Renamed backup folder after server rename: $uuid"
                else
                    new_folder="$old_folder"
                    log_line WARN "Could not rename the Drive folder for server $uuid."
                fi
            fi
        fi
        upsert_inventory "$uuid" "$name" "$new_folder"
    done < <(jq -r --argjson node "$PANEL_NODE_ID" '.[] | select(.node == $node) | [.id,.uuid,.name] | @tsv' "$all_servers")
}

schedule_missing_servers() {
    local all_servers="$1" now uuid name folder pending due ping
    now="$(date +%s)"
    ping="$(discord_ping)"
    while IFS=$'\t' read -r uuid name folder; do
        [[ -n "$uuid" && -n "$folder" ]] || continue
        # A server moved to another node is still present globally and is never treated as deleted.
        if jq -e --arg uuid "$uuid" '.[] | select(.uuid == $uuid)' "$all_servers" >/dev/null; then
            if [[ -f "$PENDING_DIR/$uuid.json" ]]; then
                rm -f "$PENDING_DIR/$uuid.json"
                send_webhook "$ping ✅ **Backup deletion cancelled**\nServer **$name** (`$uuid`) is present on the Panel again. No backup was deleted."
            fi
            continue
        fi

        pending="$PENDING_DIR/$uuid.json"
        if [[ ! -f "$pending" ]]; then
            due=$((now + 86400))
            jq -n --arg uuid "$uuid" --arg name "$name" --arg folder "$folder" \
                --argjson detected "$now" --argjson due "$due" \
                '{uuid:$uuid,name:$name,remote_folder:$folder,detected_at:$detected,delete_after:$due}' > "$pending"
            chmod 600 "$pending"
            send_webhook "$ping ⚠️ **Pterodactyl server deleted**\nServer: **$name**\nUUID: \`$uuid\`\nIts Drive backup is scheduled for permanent deletion in **24 hours**. Restore the server before then to cancel deletion."
            log_line WARN "Server $uuid missing globally; backup deletion scheduled in 24 hours."
        fi
    done < <(jq -r '.[] | [.uuid,.name,.remote_folder] | @tsv' "$INVENTORY_FILE")
}

process_pending_deletions() {
    local all_servers="$1" now file uuid name folder due target ping
    now="$(date +%s)"
    ping="$(discord_ping)"
    shopt -s nullglob
    for file in "$PENDING_DIR"/*.json; do
        uuid="$(jq -r '.uuid' "$file")"
        name="$(jq -r '.name' "$file")"
        folder="$(jq -r '.remote_folder' "$file")"
        due="$(jq -r '.delete_after' "$file")"

        if jq -e --arg uuid "$uuid" '.[] | select(.uuid == $uuid)' "$all_servers" >/dev/null; then
            rm -f "$file"
            send_webhook "$ping ✅ **Backup deletion cancelled**\nServer **$name** (`$uuid`) exists on the Panel."
            continue
        fi
        valid_integer "$due" || continue
        (( now >= due )) || continue
        [[ "$uuid" =~ ^[A-Fa-f0-9-]{32,36}$ && "$folder" == *"$uuid"* && "$folder" =~ ^[A-Za-z0-9._-]+$ ]] || {
            log_line ERROR "Rejected unsafe pending deletion target for $uuid."
            continue
        }

        target="$(remote_path "Nodes/$NODE_FOLDER/Servers/$folder")"
        if rclone_cmd purge "$target" >/dev/null 2>&1 || \
           { rclone_cmd lsd "$RCLONE_REMOTE:$DRIVE_ROOT" >/dev/null 2>&1 && \
             ! rclone_cmd lsf "$target" >/dev/null 2>&1; }; then
            rm -f "$file"
            remove_inventory "$uuid"
            send_webhook "$ping 🗑️ **Lifetime backup deleted**\nThe 24-hour grace period ended for **$name** (`$uuid`). Only that server's backup folder was removed."
            log_line INFO "Deleted expired lifetime backup folder for server $uuid."
        else
            log_line ERROR "Could not delete the scheduled backup folder for $uuid; will retry."
        fi
    done
    shopt -u nullglob
}

run_monitor() {
    load_config
    [[ "$ENABLED" == "1" ]] || exit 0
    [[ "$BACKUP_TYPE" == "node" || "$BACKUP_TYPE" == "both" ]] || exit 0
    [[ -n "$PANEL_URL" && -n "$PANEL_API_KEY" && "$PANEL_NODE_ID" =~ ^[0-9]+$ ]] || exit 0
    ensure_dirs

    exec 9>"$LOCK_FILE"
    flock -n 9 || exit 0

    local all_servers
    all_servers="$(mktemp)"
    if ! get_all_servers "$all_servers"; then
        log_line WARN "Panel API unavailable; no deletion decisions were made."
        rm -f "$all_servers"
        exit 0
    fi

    sync_current_servers "$all_servers"
    schedule_missing_servers "$all_servers"
    process_pending_deletions "$all_servers"
    rm -f "$all_servers"
}

verify_and_remove_local() {
    local local_file="$1" remote_file="$2" local_size remote_size checksum_file metadata_file
    local checksum_remote remote_name
    checksum_file="${local_file}.sha256"
    metadata_file="${local_file}.rhm-destination"
    checksum_remote="${remote_file}.sha256"
    remote_name="${remote_file##*/}"

    if ! sha256sum "$local_file" | awk -v name="$remote_name" '{print $1 "  " name}' > "$checksum_file"; then
        printf '%s\n' "$remote_file" > "$metadata_file"
        chmod 600 "$metadata_file"
        log_line ERROR "Could not calculate SHA-256; local recovery archive kept at $local_file"
        return 1
    fi
    if ! rclone_cmd copyto "$local_file" "$remote_file" \
        --retries 3 --low-level-retries 10 --checksum --log-file "$BACKUP_LOG"; then
        printf '%s\n' "$remote_file" > "$metadata_file"
        chmod 600 "$metadata_file"
        log_line ERROR "Upload failed; local recovery archive kept at $local_file"
        return 1
    fi
    local_size="$(stat -c '%s' "$local_file" 2>/dev/null || printf 0)"
    remote_size="$(rclone_cmd size "$remote_file" --json 2>/dev/null | jq -r '.bytes // 0')"
    if [[ "$local_size" != "$remote_size" || "$local_size" == "0" ]]; then
        printf '%s\n' "$remote_file" > "$metadata_file"
        chmod 600 "$metadata_file"
        log_line ERROR "Upload verification failed; local recovery archive kept at $local_file"
        return 1
    fi
    if ! rclone_cmd copyto "$checksum_file" "$checksum_remote" \
        --retries 3 --low-level-retries 10 --checksum --log-file "$BACKUP_LOG"; then
        printf '%s\n' "$remote_file" > "$metadata_file"
        chmod 600 "$metadata_file"
        log_line ERROR "Checksum upload failed; local recovery archive kept at $local_file"
        return 1
    fi
    rm -f -- "$local_file" "$checksum_file" "$metadata_file"
    log_line INFO "Uploaded, size-verified, and SHA-256 protected: $remote_file"
}

retry_failed_uploads() {
    local metadata local_file remote_file retried=0 failed=0
    shopt -s nullglob
    for metadata in "$TMP_ROOT"/*/*.rhm-destination; do
        local_file="${metadata%.rhm-destination}"
        IFS= read -r remote_file < "$metadata" || remote_file=""
        if [[ ! -f "$local_file" ]]; then
            rm -f -- "$metadata"
            continue
        fi
        if [[ "$remote_file" != "$RCLONE_REMOTE:$DRIVE_ROOT/"* || "$remote_file" == *$'\n'* || \
              "$remote_file" == *'/../'* || "$remote_file" == *'/./'* ]]; then
            log_line ERROR "Rejected unsafe retry destination stored in $metadata"
            failed=$((failed + 1))
            continue
        fi
        retried=$((retried + 1))
        log_line INFO "Retrying previously failed upload: $local_file"
        verify_and_remove_local "$local_file" "$remote_file" || failed=$((failed + 1))
    done
    shopt -u nullglob
    (( retried > 0 )) && log_line INFO "Retried $retried previously failed upload(s)."
    return "$((failed > 0))"
}

failed_recovery_count() {
    find "$TMP_ROOT" -type f -name '*.rhm-destination' 2>/dev/null | wc -l | tr -d ' '
}

enough_temp_space() {
    local source_path="$1" source_bytes available_bytes reserve_bytes=$((256 * 1024 * 1024))
    source_bytes="$(du -s --block-size=1 "$source_path" 2>/dev/null | awk 'NR==1 {print $1}')"
    available_bytes="$(df --output=avail --block-size=1 "$TMP_ROOT" 2>/dev/null | awk 'NR==2 {print $1}')"
    valid_integer "${source_bytes:-}" || return 0
    valid_integer "${available_bytes:-}" || return 0
    if (( available_bytes < source_bytes + reserve_bytes )); then
        log_line ERROR "Not enough temporary disk space for $source_path (256 MiB safety reserve required)."
        return 1
    fi
}

create_node_backups() {
    local run_dir="$1" timestamp="$2" all_servers="$3"
    local volumes="/var/lib/pterodactyl/volumes"
    [[ -d "$volumes" ]] || { log_line ERROR "Node volume directory not found: $volumes"; return 1; }
    local uuid server_id name folder archive remote failures=0 tar_status

    shopt -s nullglob
    for server_dir in "$volumes"/*; do
        [[ -d "$server_dir" ]] || continue
        uuid="$(basename "$server_dir")"
        name=""
        server_id=""
        folder=""
        if [[ -s "$all_servers" ]]; then
            name="$(jq -r --arg uuid "$uuid" '.[] | select(.uuid == $uuid) | .name' "$all_servers" | head -n1)"
            server_id="$(jq -r --arg uuid "$uuid" '.[] | select(.uuid == $uuid) | .id' "$all_servers" | head -n1)"
        fi
        folder="$(jq -r --arg uuid "$uuid" '.[] | select(.uuid == $uuid) | .remote_folder' "$INVENTORY_FILE" | head -n1)"
        if [[ -z "$folder" ]]; then
            [[ -n "$name" ]] || name="Unknown-Server"
            if [[ "$server_id" =~ ^[0-9]+$ ]]; then
                folder="ID-${server_id}--$(sanitize_name "$name")--${uuid}"
            else
                folder="UUID-${uuid}--$(sanitize_name "$name")"
            fi
            upsert_inventory "$uuid" "$name" "$folder"
        fi

        archive="$run_dir/${uuid}_${timestamp}.tar.gz"
        log_line INFO "Archiving server: ${name:-$uuid}"
        if ! enough_temp_space "$server_dir"; then
            failures=$((failures + 1))
            continue
        fi
        tar --warning=no-file-changed -czf "$archive" -C "$volumes" "$uuid"
        tar_status=$?
        if (( tar_status > 1 )) || [[ ! -s "$archive" ]]; then
            log_line ERROR "Archive creation failed for server $uuid (tar exit $tar_status)."
            failures=$((failures + 1))
            continue
        elif (( tar_status == 1 )); then
            # GNU tar returns 1 when a live server changes files during the archive.
            log_line WARN "Files changed while archiving $uuid; consider stopping busy servers for a fully consistent backup."
        fi
        remote="$(remote_path "Nodes/$NODE_FOLDER/Servers/$folder/${timestamp}.tar.gz")"
        verify_and_remove_local "$archive" "$remote" || failures=$((failures + 1))
    done
    shopt -u nullglob
    return "$((failures > 0))"
}

create_node_configuration_backup() {
    local run_dir="$1" timestamp="$2" stage archive remote
    stage="$run_dir/node-configuration"
    install -d -m 700 "$stage"

    [[ -d /etc/pterodactyl ]] && cp -a /etc/pterodactyl "$stage/"
    [[ -f /etc/docker/daemon.json ]] && { mkdir -p "$stage/docker"; cp -a /etc/docker/daemon.json "$stage/docker/"; }
    [[ -f /etc/systemd/system/wings.service ]] && cp -a /etc/systemd/system/wings.service "$stage/"
    {
        printf 'Created: %s\n' "$(date --iso-8601=seconds)"
        printf 'Hostname: %s\n' "$(hostname)"
        printf 'Kernel: %s\n' "$(uname -a)"
        command -v wings >/dev/null 2>&1 && wings version 2>&1 || true
        command -v docker >/dev/null 2>&1 && docker version 2>&1 || true
    } > "$stage/system-information.txt"

    archive="$run_dir/node_configuration_${timestamp}.tar.gz"
    if tar -czf "$archive" -C "$stage" .; then
        remote="$(remote_path "Nodes/$NODE_FOLDER/Node-Configuration/$timestamp/node_configuration.tar.gz")"
        verify_and_remove_local "$archive" "$remote"
    else
        log_line ERROR "Node configuration archive failed."
        return 1
    fi
}

env_value() {
    local file="$1" key="$2" line value
    line="$(grep -m1 -E "^[[:space:]]*${key}=" "$file" || true)"
    value="${line#*=}"
    value="${value%$'\r'}"
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then value="${value:1:${#value}-2}"; fi
    if [[ "$value" == \'*\' && "$value" == *\' ]]; then value="${value:1:${#value}-2}"; fi
    printf '%s' "$value"
}

create_panel_backup() {
    local run_dir="$1" timestamp="$2" panel_dir="/var/www/pterodactyl"
    local archive remote tar_status
    [[ -d "$panel_dir" ]] || { log_line ERROR "Panel directory not found: $panel_dir"; return 1; }
    archive="$run_dir/panel_files_${timestamp}.tar.gz"
    log_line INFO "Archiving Pterodactyl Panel files."
    enough_temp_space "$panel_dir" || return 1
    tar --warning=no-file-changed -czf "$archive" -C /var/www pterodactyl
    tar_status=$?
    if (( tar_status <= 1 )) && [[ -s "$archive" ]]; then
        (( tar_status == 1 )) && log_line WARN "Panel files changed during the archive; the backup may reflect different moments in time."
        remote="$(remote_path "Panel/$timestamp/panel_files.tar.gz")"
        verify_and_remove_local "$archive" "$remote"
    else
        log_line ERROR "Panel archive failed."
        return 1
    fi
}

create_database_backup() {
    local run_dir="$1" timestamp="$2" env_file="/var/www/pterodactyl/.env"
    [[ -f "$env_file" ]] || { log_line ERROR "Panel .env was not found; database backup skipped."; return 1; }
    local dump_cmd db_host db_port db_name db_user db_password client_cnf sql_file archive remote
    local dump_error dump_ok=0 first_error
    local -a dump_options
    dump_cmd="$(command -v mysqldump || command -v mariadb-dump || true)"
    [[ -n "$dump_cmd" ]] || { log_line ERROR "mysqldump/mariadb-dump is not installed."; return 1; }

    db_host="$(env_value "$env_file" DB_HOST)"
    db_port="$(env_value "$env_file" DB_PORT)"
    db_name="$(env_value "$env_file" DB_DATABASE)"
    db_user="$(env_value "$env_file" DB_USERNAME)"
    db_password="$(env_value "$env_file" DB_PASSWORD)"
    [[ -n "$db_host" ]] || db_host="127.0.0.1"
    [[ "$db_port" =~ ^[0-9]+$ ]] || db_port="3306"
    [[ -n "$db_name" && -n "$db_user" ]] || { log_line ERROR "Database credentials are incomplete."; return 1; }

    client_cnf="$run_dir/mysql-client.cnf"
    umask 077
    {
        printf '[client]\n'
        printf 'host=%s\nport=%s\nuser=%s\npassword=%s\n' "$db_host" "$db_port" "$db_user" "$db_password"
    } > "$client_cnf"
    sql_file="$run_dir/panel_database_${timestamp}.sql"
    archive="$sql_file.gz"
    dump_error="$run_dir/database-dump-error.log"
    dump_options=(--single-transaction --quick --routines --triggers --events --hex-blob "$db_name")
    log_line INFO "Creating a consistent Panel database dump."
    if "$dump_cmd" --defaults-extra-file="$client_cnf" "${dump_options[@]}" \
        > "$sql_file" 2> "$dump_error" && [[ -s "$sql_file" ]]; then
        dump_ok=1
    else
        first_error="$(head -n1 "$dump_error" 2>/dev/null || true)"
        [[ -n "$first_error" ]] && log_line WARN "Configured database login failed: $first_error"

        # Ubuntu/Debian MariaDB commonly protects local root with unix_socket.
        # Because RHM itself requires OS root, a read-only local socket dump is
        # a safe fallback. It never changes users, passwords, grants, or .env.
        if [[ "$db_host" == "127.0.0.1" || "$db_host" == "localhost" || "$db_host" == "::1" ]] && \
           [[ ${EUID:-$(id -u)} -eq 0 ]]; then
            warn "Trying local MariaDB root socket authentication for this backup only."
            : > "$sql_file"
            if "$dump_cmd" --protocol=socket --user=root "${dump_options[@]}" \
                > "$sql_file" 2>> "$dump_error" && [[ -s "$sql_file" ]]; then
                dump_ok=1
                log_line INFO "Database dump succeeded through local root socket fallback."
            fi
        fi
    fi

    if (( dump_ok )); then
        gzip -f "$sql_file"
        rm -f "$client_cnf" "$dump_error"
        remote="$(remote_path "Database/$timestamp/panel_database.sql.gz")"
        verify_and_remove_local "$archive" "$remote"
    else
        rm -f "$client_cnf" "$sql_file" "$dump_error"
        log_line ERROR "Database dump failed; no empty backup was uploaded."
        return 1
    fi
}

apply_retention() {
    log_line INFO "Removing Drive backup files older than $RETENTION_DAYS day(s)."
    local target failed=0
    # Manual-Safety is intentionally excluded: automatic retention must never
    # remove rollback snapshots created before restore/shift operations.
    for target in Panel Database Nodes; do
        rclone_cmd mkdir "$RCLONE_REMOTE:$DRIVE_ROOT/$target" >/dev/null 2>&1 || { failed=1; continue; }
        rclone_cmd delete "$RCLONE_REMOTE:$DRIVE_ROOT/$target" --min-age "${RETENTION_DAYS}d" \
            --log-file "$BACKUP_LOG" || failed=1
    done
    if (( failed == 0 )); then
        rclone_cmd rmdirs "$RCLONE_REMOTE:$DRIVE_ROOT" --leave-root >/dev/null 2>&1 || true
        log_line INFO "Retention cleanup completed."
    else
        log_line ERROR "Retention cleanup failed; no local source data was affected."
        return 1
    fi
}

run_backup() {
    local force="${1:-0}"
    load_config
    if [[ "$ENABLED" != "1" && "$force" != "1" ]]; then
        log_line INFO "Backup skipped because automation is stopped."
        return 0
    fi
    ensure_dirs
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        log_line WARN "Another RHM task is running; this backup was skipped safely."
        return 0
    fi

    local timestamp run_dir all_servers result=0 started_epoch finished_epoch duration
    started_epoch="$(date +%s)"
    timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
    run_dir="$TMP_ROOT/$timestamp"
    install -d -m 700 "$run_dir"
    all_servers="$run_dir/all-servers.json"
    : > "$all_servers"
    log_line INFO "========== RHM backup started: $timestamp =========="

    if ! rclone_cmd mkdir "$RCLONE_REMOTE:$DRIVE_ROOT" >/dev/null 2>&1; then
        log_line ERROR "Google Drive is unavailable. Backup stopped before creating large local archives."
        finished_epoch="$(date +%s)"
        rm -rf -- "$run_dir"
        record_run_status "failed" "$started_epoch" "$finished_epoch" "Google Drive unavailable"
        notify_backup_result "failed" "$timestamp" "$((finished_epoch - started_epoch))"
        return 1
    fi

    retry_failed_uploads || result=1

    if [[ "$BACKUP_TYPE" == "node" || "$BACKUP_TYPE" == "both" ]]; then
        if get_all_servers "$all_servers"; then
            sync_current_servers "$all_servers"
        else
            log_line WARN "Panel API unavailable; cached server names will be used. No deletion decision was made."
        fi
        create_node_backups "$run_dir" "$timestamp" "$all_servers" || result=1
        create_node_configuration_backup "$run_dir" "$timestamp" || result=1
    fi
    if [[ "$BACKUP_TYPE" == "panel" || "$BACKUP_TYPE" == "both" ]]; then
        create_panel_backup "$run_dir" "$timestamp" || result=1
        create_database_backup "$run_dir" "$timestamp" || result=1
    fi

    apply_retention || result=1
    # Metadata and credential staging never remain locally. Failed archives are
    # deliberately kept for recovery; successful runs are removed completely.
    rm -rf -- "$run_dir/node-configuration"
    rm -f -- "$all_servers" "$run_dir/mysql-client.cnf"
    finished_epoch="$(date +%s)"
    duration="$((finished_epoch - started_epoch))"
    if (( result == 0 )); then
        rm -rf -- "$run_dir"
        find "$TMP_ROOT" -mindepth 1 -depth -type d -empty -delete 2>/dev/null || true
        record_run_status "success" "$started_epoch" "$finished_epoch" "Backup and verification completed"
        notify_backup_result "success" "$timestamp" "$duration"
        log_line INFO "========== Backup finished and verified successfully =========="
    else
        find "$run_dir" -depth -type d -empty -delete 2>/dev/null || true
        record_run_status "failed" "$started_epoch" "$finished_epoch" "One or more backup tasks failed"
        notify_backup_result "failed" "$timestamp" "$duration"
        log_line ERROR "Backup finished with errors. Check $BACKUP_LOG and $run_dir"
    fi
    return "$result"
}

run_database_only() {
    load_config
    ensure_dirs
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        warn "Another RHM task is running. Try again after it finishes."
        return 1
    fi

    local timestamp run_dir result=0
    timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
    run_dir="$TMP_ROOT/database-$timestamp"
    install -d -m 700 "$run_dir"
    log_line INFO "========== Database-only backup started: $timestamp =========="

    if ! rclone_cmd mkdir "$RCLONE_REMOTE:$DRIVE_ROOT" >/dev/null 2>&1; then
        rm -rf -- "$run_dir"
        error "Google Drive is unavailable; database backup was not started."
        return 1
    fi
    create_database_backup "$run_dir" "$timestamp" || result=1
    (( result == 0 )) && apply_retention || true
    rm -f -- "$run_dir/mysql-client.cnf" "$run_dir/database-dump-error.log"
    if (( result == 0 )); then
        rm -rf -- "$run_dir"
        ok "Database backup uploaded and verified successfully."
        log_line INFO "========== Database-only backup completed =========="
    else
        find "$run_dir" -depth -type d -empty -delete 2>/dev/null || true
        error "Database backup failed. Check $BACKUP_LOG."
    fi
    return "$result"
}

change_node_folder() {
    local old="$NODE_FOLDER" new old_path new_path
    new="$(sanitize_name "$(read_tty "New custom node folder name" "$NODE_FOLDER")")"
    [[ "$new" != "$old" ]] || { info "Node folder name is unchanged."; return 0; }
    old_path="$(remote_path "Nodes/$old")"
    new_path="$(remote_path "Nodes/$new")"
    if rclone_cmd lsf "$old_path" >/dev/null 2>&1; then
        info "Moving existing node backups to the new folder…"
        if ! rclone_cmd move "$old_path" "$new_path" --delete-empty-src-dirs --log-file "$BACKUP_LOG"; then
            error "Drive folder move failed. The saved folder name was not changed."
            return 1
        fi
    fi
    NODE_FOLDER="$new"
    save_config
    ok "Node folder changed to: $NODE_FOLDER"
}

system_health_check() {
    step "Running RHM system health checks"
    local failures=0 available_mb api_test

    if [[ -x "$INSTALL_PATH" ]]; then ok "Manager command is installed."; else error "Manager command is missing."; failures=$((failures + 1)); fi
    if [[ "$ENABLED" == "1" && -f "$CRON_FILE" ]]; then ok "Automatic schedule is installed."; else warn "Automatic schedule is stopped or missing."; fi
    if [[ -f "$CONFIG_FILE" && "$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null)" == "600" ]]; then
        ok "Secrets configuration is protected with mode 600."
    else
        error "Secrets configuration permissions need repair."
        failures=$((failures + 1))
    fi

    if rclone_cmd lsd "$RCLONE_REMOTE:$DRIVE_ROOT" --contimeout 10s --timeout 30s >/dev/null 2>&1; then
        ok "Google Drive and $DRIVE_ROOT are reachable."
    else
        error "Google Drive connection failed."
        failures=$((failures + 1))
    fi

    if [[ "$BACKUP_TYPE" == "node" || "$BACKUP_TYPE" == "both" ]]; then
        [[ -d /var/lib/pterodactyl/volumes ]] && ok "Pterodactyl server volumes are accessible." || { error "Node volume directory is missing."; failures=$((failures + 1)); }
        [[ -f /etc/pterodactyl/config.yml ]] && ok "Wings configuration is accessible." || warn "Wings configuration was not found."
        if [[ -n "$PANEL_URL" && -n "$PANEL_API_KEY" && "$PANEL_NODE_ID" =~ ^[0-9]+$ ]]; then
            api_test="$(mktemp)"
            if get_all_servers "$api_test"; then ok "Panel Application API connection is healthy."; else error "Panel Application API check failed."; failures=$((failures + 1)); fi
            rm -f "$api_test"
        else
            error "Panel API or numeric node ID is not fully configured."
            failures=$((failures + 1))
        fi
    fi

    if [[ "$BACKUP_TYPE" == "panel" || "$BACKUP_TYPE" == "both" ]]; then
        [[ -d /var/www/pterodactyl ]] && ok "Panel files are accessible." || { error "Panel directory is missing."; failures=$((failures + 1)); }
        [[ -f /var/www/pterodactyl/.env ]] && ok "Panel database configuration is accessible." || { error "Panel .env is missing."; failures=$((failures + 1)); }
    fi

    available_mb="$(df --output=avail -BM "$TMP_ROOT" 2>/dev/null | awk 'NR==2 {gsub(/M/, ""); print $1}')"
    if valid_integer "${available_mb:-}" && (( available_mb >= 512 )); then
        ok "Temporary storage has ${available_mb} MiB available."
    else
        error "Temporary storage has less than 512 MiB available."
        failures=$((failures + 1))
    fi

    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        if [[ "$DISCORD_WEBHOOK" =~ ^https://(canary\.|ptb\.)?(discord|discordapp)\.com/api/webhooks/ ]]; then
            ok "Discord webhook format is valid."
        else
            warn "Discord webhook URL format looks unusual."
        fi
    else
        warn "Discord webhook is not configured."
    fi

    if (( failures == 0 )); then
        ok "All required health checks passed."
    else
        error "$failures required health check(s) failed."
    fi
    return "$((failures > 0))"
}

show_status() {
    local drive_status="Not connected" cron_status="Stopped" deletion_status="Needs setup" pending_count=0
    local last_run="Never" failed_count notification_status="Off" recovery_status="None"
    rclone_cmd lsd "$RCLONE_REMOTE:$DRIVE_ROOT" >/dev/null 2>&1 && drive_status="Connected"
    [[ "$ENABLED" == "1" && -f "$CRON_FILE" ]] && cron_status="Running"
    if [[ -n "$PANEL_URL" && -n "$PANEL_API_KEY" && "$PANEL_NODE_ID" =~ ^[0-9]+$ && -n "$DISCORD_WEBHOOK" ]]; then
        deletion_status="Active (5-minute checks)"
    fi
    shopt -s nullglob
    local pending_files=("$PENDING_DIR"/*.json)
    pending_count="${#pending_files[@]}"
    shopt -u nullglob
    failed_count="$(failed_recovery_count)"
    [[ "$BACKUP_NOTIFICATIONS" == "1" && -n "$DISCORD_WEBHOOK" ]] && notification_status="On"
    if [[ -f "$LAST_RUN_FILE" ]] && jq -e . "$LAST_RUN_FILE" >/dev/null 2>&1; then
        local last_epoch last_result
        last_epoch="$(jq -r '.finished_at // 0' "$LAST_RUN_FILE")"
        last_result="$(jq -r '.status // "unknown"' "$LAST_RUN_FILE")"
        if valid_integer "$last_epoch" && (( last_epoch > 0 )); then
            last_run="${last_result^} — $(date -d "@$last_epoch" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || printf '%s' "$last_epoch")"
        fi
    fi
    if [[ -f "$RECOVERY_STATE_FILE" ]] && jq -e . "$RECOVERY_STATE_FILE" >/dev/null 2>&1; then
        recovery_status="$(jq -r '.status // "unknown"' "$RECOVERY_STATE_FILE")"
    fi

    printf '%b\n' "${CYAN}┌────────────────── RHM STATUS ──────────────────┐${RESET}"
    printf '%-24s %s (%s)\n' "Operating system" "$OS_NAME" "$OS_ARCH"
    printf '%-24s %s\n' "Automation" "$cron_status"
    printf '%-24s %s\n' "Google Drive" "$drive_status"
    printf '%-24s %s\n' "Drive root (fixed)" "$DRIVE_ROOT"
    printf '%-24s %s\n' "Backup type" "$BACKUP_TYPE"
    printf '%-24s %s\n' "Node folder" "$NODE_FOLDER"
    printf '%-24s %s day(s)\n' "Retention" "$RETENTION_DAYS"
    printf '%-24s %02d:%02d (%s)\n' "Daily schedule" "$BACKUP_HOUR" "$BACKUP_MINUTE" "$(date +%Z)"
    printf '%-24s %s\n' "Deletion protection" "$deletion_status"
    printf '%-24s %s\n' "Backup notifications" "$notification_status"
    printf '%-24s %s\n' "Last backup" "$last_run"
    printf '%-24s %s\n' "Last restore/shift" "$recovery_status"
    printf '%-24s %s\n' "Failed local retries" "$failed_count"
    printf '%-24s %s\n' "Integrity files" "SHA-256 enabled"
    printf '%-24s %s\n' "Deletion grace period" "24 hours"
    printf '%-24s %s\n' "Pending deletions" "$pending_count"
    printf '%b\n' "${CYAN}└─────────────────────────────────────────────────┘${RESET}"
    case "$recovery_status" in
        failed|applying|interrupted)
            warn "A $recovery_status recovery operation has a preserved rollback workspace."
            warn "Use manager option 16 before starting another restore or shift."
            ;;
    esac
}

valid_recovery_timestamp() {
    [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]
}

valid_server_uuid() {
    [[ "$1" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]]
}

safe_recovery_name() {
    [[ -n "$1" && "$1" != "." && "$1" != ".." && "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

drive_file_size() {
    local remote="$1"
    rclone_cmd size "$remote" --json --contimeout 10s --timeout 60s 2>/dev/null | jq -r '.bytes // empty'
}

drive_file_exists() {
    local size
    size="$(drive_file_size "$1")"
    valid_integer "${size:-}"
}

validate_tar_archive() {
    local archive="$1" entry
    gzip -t "$archive" >/dev/null 2>&1 || return 1
    while IFS= read -r entry; do
        [[ "$entry" == /* ]] && return 1
        [[ "/$entry/" == *'/../'* ]] && return 1
    done < <(tar -tzf "$archive" 2>/dev/null) || return 1
    tar -tzf "$archive" >/dev/null 2>&1
}

download_recovery_file() {
    local remote="$1" local_file="$2" kind="$3" size available required
    local checksum_file expected actual
    [[ "$remote" == "$RCLONE_REMOTE:$DRIVE_ROOT/"* ]] || {
        error "Rejected recovery source outside $DRIVE_ROOT."
        return 1
    }
    size="$(drive_file_size "$remote")"
    valid_integer "${size:-}" || { error "Backup file not found: $remote"; return 1; }
    available="$(df --output=avail --block-size=1 "$TMP_ROOT" 2>/dev/null | awk 'NR==2 {print $1}')"
    required=$((size * 2 + 512 * 1024 * 1024))
    if valid_integer "${available:-}" && (( available < required )); then
        error "Not enough local space to safely download and extract $(basename "$remote")."
        return 1
    fi
    install -d -m 700 "$(dirname "$local_file")"
    info "Downloading $(basename "$remote")…"
    if ! rclone_cmd copyto "$remote" "$local_file" --retries 3 --low-level-retries 10 \
        --log-file "$RECOVERY_LOG"; then
        error "Download failed: $remote"
        return 1
    fi
    [[ -s "$local_file" && "$(stat -c '%s' "$local_file")" == "$size" ]] || {
        error "Downloaded file size verification failed."
        return 1
    }

    checksum_file="${local_file}.sha256"
    if rclone_cmd copyto "${remote}.sha256" "$checksum_file" --retries 2 \
        --log-file "$RECOVERY_LOG" >/dev/null 2>&1; then
        expected="$(awk 'NR==1 {print $1}' "$checksum_file")"
        actual="$(sha256sum "$local_file" | awk '{print $1}')"
        if [[ ! "$expected" =~ ^[A-Fa-f0-9]{64}$ || "$actual" != "$expected" ]]; then
            error "SHA-256 verification failed for $(basename "$remote")."
            return 1
        fi
        ok "SHA-256 verified: $(basename "$remote")"
    else
        warn "No SHA-256 sidecar found; using archive integrity validation only."
    fi

    case "$kind" in
        tar) validate_tar_archive "$local_file" || { error "Unsafe or corrupted tar archive rejected."; return 1; } ;;
        database) gzip -t "$local_file" >/dev/null 2>&1 || { error "Corrupted database archive rejected."; return 1; } ;;
    esac
}

select_restore_point() {
    local root="$RCLONE_REMOTE:$DRIVE_ROOT" choice selected="" item index=1
    local -a points=()
    mapfile -t points < <(rclone_cmd lsf "$root" --recursive --files-only 2>/dev/null | \
        grep -Ev '^Manual-Safety/' | \
        grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}' | sort -ru)
    ((${#points[@]} > 0)) || { error "No dated RHM backups were found in Google Drive."; return 1; }

    printf '%b\n' "${WHITE}Available restore points (newest first):${RESET}" > /dev/tty
    for item in "${points[@]:0:20}"; do
        printf '  %2d) %s\n' "$index" "$item" > /dev/tty
        index=$((index + 1))
    done
    choice="$(read_tty "Choose number, full timestamp, or date (YYYY-MM-DD)" "1")"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#points[@]} )); then
        selected="${points[choice-1]}"
    elif valid_recovery_timestamp "$choice"; then
        selected="$choice"
    elif [[ "$choice" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        for item in "${points[@]}"; do
            [[ "$item" == "$choice"_* ]] && { selected="$item"; break; }
        done
    fi
    valid_recovery_timestamp "$selected" || { error "Invalid or unavailable restore date."; return 1; }
    printf '%s' "$selected"
}

select_remote_node() {
    local base="$RCLONE_REMOTE:$DRIVE_ROOT/Nodes" choice item index=1 selected=""
    local -a nodes=()
    mapfile -t nodes < <(rclone_cmd lsf "$base" --dirs-only 2>/dev/null | sed 's:/$::' | sort)
    ((${#nodes[@]} > 0)) || { error "No Node backup folders found in Drive."; return 1; }
    printf '%b\n' "${WHITE}Available Node backup folders:${RESET}" > /dev/tty
    for item in "${nodes[@]}"; do
        printf '  %2d) %s\n' "$index" "$item" > /dev/tty
        index=$((index + 1))
    done
    choice="$(read_tty "Choose source Node folder" "1")"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#nodes[@]} )); then
        selected="${nodes[choice-1]}"
    else
        selected="$choice"
    fi
    safe_recovery_name "$selected" || { error "Unsafe Node folder name rejected."; return 1; }
    printf '%s' "$selected"
}

select_remote_server() {
    local node="$1" base="$RCLONE_REMOTE:$DRIVE_ROOT/Nodes/$node/Servers"
    local choice item index=1 selected=""
    local -a servers=()
    mapfile -t servers < <(rclone_cmd lsf "$base" --dirs-only 2>/dev/null | sed 's:/$::' | sort)
    ((${#servers[@]} > 0)) || { error "No server backup folders found for $node."; return 1; }
    printf '%b\n' "${WHITE}Available server backup folders:${RESET}" > /dev/tty
    for item in "${servers[@]}"; do
        printf '  %2d) %s\n' "$index" "$item" > /dev/tty
        index=$((index + 1))
    done
    choice="$(read_tty "Choose server" "1")"
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#servers[@]} )); then
        selected="${servers[choice-1]}"
    else
        selected="$choice"
    fi
    safe_recovery_name "$selected" || { error "Unsafe server folder name rejected."; return 1; }
    printf '%s' "$selected"
}

select_recovery_scope() {
    local choice
    printf '%b\n' "${WHITE}1)${RESET} Complete Panel (files + database)" > /dev/tty
    printf '%b\n' "${WHITE}2)${RESET} Panel files only" > /dev/tty
    printf '%b\n' "${WHITE}3)${RESET} Database only" > /dev/tty
    printf '%b\n' "${WHITE}4)${RESET} Complete Node (all dated servers + configuration)" > /dev/tty
    printf '%b\n' "${WHITE}5)${RESET} All dated server volumes only" > /dev/tty
    printf '%b\n' "${WHITE}6)${RESET} Node configuration only" > /dev/tty
    printf '%b\n' "${WHITE}7)${RESET} One server only" > /dev/tty
    printf '%b\n' "${WHITE}8)${RESET} Everything (Panel + database + complete Node)" > /dev/tty
    choice="$(read_tty "Choose recovery scope [1-8]" "1")"
    case "$choice" in
        1) printf panel_all ;;
        2) printf panel ;;
        3) printf database ;;
        4) printf node_all ;;
        5) printf node_servers ;;
        6) printf node_config ;;
        7) printf server ;;
        8) printf everything ;;
        *) error "Invalid recovery scope."; return 1 ;;
    esac
}

scope_has_panel() { [[ "$1" == panel || "$1" == panel_all || "$1" == everything ]]; }
scope_has_database() { [[ "$1" == database || "$1" == panel_all || "$1" == everything ]]; }
scope_has_servers() { [[ "$1" == server || "$1" == node_servers || "$1" == node_all || "$1" == everything ]]; }
scope_has_node_config() { [[ "$1" == node_config || "$1" == node_all || "$1" == everything ]]; }

prepare_recovery_downloads() {
    local scope="$1" timestamp="$2" remote_node="$3" selected_server="$4" stage="$5"
    local source_dir="$stage/source" remote folder uuid local_file found=0
    install -d -m 700 "$source_dir/servers"
    : > "$source_dir/servers.tsv"

    if scope_has_panel "$scope"; then
        remote="$RCLONE_REMOTE:$DRIVE_ROOT/Panel/$timestamp/panel_files.tar.gz"
        download_recovery_file "$remote" "$source_dir/panel_files.tar.gz" tar || return 1
        tar -tzf "$source_dir/panel_files.tar.gz" | grep '^pterodactyl/' >/dev/null || {
            error "Panel archive does not contain the expected pterodactyl directory."
            return 1
        }
    fi
    if scope_has_database "$scope"; then
        remote="$RCLONE_REMOTE:$DRIVE_ROOT/Database/$timestamp/panel_database.sql.gz"
        download_recovery_file "$remote" "$source_dir/panel_database.sql.gz" database || return 1
    fi
    if scope_has_node_config "$scope"; then
        remote="$RCLONE_REMOTE:$DRIVE_ROOT/Nodes/$remote_node/Node-Configuration/$timestamp/node_configuration.tar.gz"
        download_recovery_file "$remote" "$source_dir/node_configuration.tar.gz" tar || return 1
        tar -tzf "$source_dir/node_configuration.tar.gz" | \
            grep -E '^(\./)?pterodactyl/config\.yml$' >/dev/null || {
            error "Node configuration archive does not contain pterodactyl/config.yml."
            return 1
        }
    fi
    if scope_has_servers "$scope"; then
        local -a folders=()
        if [[ "$scope" == "server" ]]; then
            folders=("$selected_server")
        else
            mapfile -t folders < <(rclone_cmd lsf "$RCLONE_REMOTE:$DRIVE_ROOT/Nodes/$remote_node/Servers" \
                --dirs-only 2>/dev/null | sed 's:/$::' | sort)
        fi
        for folder in "${folders[@]}"; do
            safe_recovery_name "$folder" || continue
            remote="$RCLONE_REMOTE:$DRIVE_ROOT/Nodes/$remote_node/Servers/$folder/$timestamp.tar.gz"
            drive_file_exists "$remote" || continue
            uuid="$(grep -Eo '[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}' <<< "$folder" | head -n1)"
            valid_server_uuid "$uuid" || { warn "Could not identify server UUID in $folder; skipped."; continue; }
            local_file="$source_dir/servers/${uuid}.tar.gz"
            download_recovery_file "$remote" "$local_file" tar || return 1
            tar -tzf "$local_file" | grep "^${uuid}/" >/dev/null || {
                error "Server archive root does not match UUID $uuid."
                return 1
            }
            printf '%s\t%s\t%s\n' "$uuid" "$folder" "$local_file" >> "$source_dir/servers.tsv"
            found=$((found + 1))
        done
        (( found > 0 )) || { error "No server archives exist for $timestamp in the selected Node folder."; return 1; }
    fi
    ok "All selected recovery archives were downloaded and validated before making changes."
}

dump_current_database_local() {
    local output_gz="$1" work_dir="$2" env_file="/var/www/pterodactyl/.env"
    [[ -f "$env_file" ]] || return 2
    local dump_cmd db_host db_port db_name db_user db_password cnf sql error_file dump_ok=0
    local -a options
    dump_cmd="$(command -v mysqldump || command -v mariadb-dump || true)"
    [[ -n "$dump_cmd" ]] || return 1
    db_host="$(env_value "$env_file" DB_HOST)"; [[ -n "$db_host" ]] || db_host="127.0.0.1"
    db_port="$(env_value "$env_file" DB_PORT)"; [[ "$db_port" =~ ^[0-9]+$ ]] || db_port="3306"
    db_name="$(env_value "$env_file" DB_DATABASE)"
    db_user="$(env_value "$env_file" DB_USERNAME)"
    db_password="$(env_value "$env_file" DB_PASSWORD)"
    [[ -n "$db_name" && -n "$db_user" ]] || return 1
    install -d -m 700 "$work_dir" "$(dirname "$output_gz")"
    cnf="$work_dir/safety-mysql.cnf"; sql="${output_gz%.gz}"; error_file="$work_dir/safety-db-error.log"
    umask 077
    {
        printf '[client]\n'
        printf 'host=%s\nport=%s\nuser=%s\npassword=%s\n' "$db_host" "$db_port" "$db_user" "$db_password"
    } > "$cnf"
    options=(--single-transaction --quick --routines --triggers --events --hex-blob "$db_name")
    if "$dump_cmd" --defaults-extra-file="$cnf" "${options[@]}" > "$sql" 2> "$error_file" && [[ -s "$sql" ]]; then
        dump_ok=1
    elif [[ "$db_host" == "127.0.0.1" || "$db_host" == "localhost" || "$db_host" == "::1" ]] && \
         [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        : > "$sql"
        "$dump_cmd" --protocol=socket --user=root "${options[@]}" > "$sql" 2>> "$error_file" && \
            [[ -s "$sql" ]] && dump_ok=1
    fi
    rm -f "$cnf" "$error_file"
    if (( dump_ok )); then
        gzip -f "$sql"
        [[ "$sql.gz" == "$output_gz" ]] || mv -f "$sql.gz" "$output_gz"
        return 0
    fi
    rm -f "$sql" "$output_gz"
    return 1
}

safety_upload_keep() {
    local local_file="$1" remote="$2" checksum_file local_size remote_size
    [[ "$remote" == "$RCLONE_REMOTE:$DRIVE_ROOT/Manual-Safety/"* ]] || {
        error "Rejected unsafe Manual-Safety destination."
        return 1
    }
    [[ -f "$local_file" ]] || return 1
    checksum_file="${local_file}.sha256"
    sha256sum "$local_file" | awk -v name="$(basename "$remote")" '{print $1 "  " name}' > "$checksum_file"
    rclone_cmd copyto "$local_file" "$remote" --retries 3 --low-level-retries 10 \
        --log-file "$RECOVERY_LOG" || return 1
    rclone_cmd copyto "$checksum_file" "${remote}.sha256" --retries 3 \
        --log-file "$RECOVERY_LOG" || return 1
    local_size="$(stat -c '%s' "$local_file")"
    remote_size="$(drive_file_size "$remote")"
    [[ "$local_size" == "$remote_size" ]]
}

safety_upload_marker() {
    local marker="$1" remote="$2"
    : > "$marker"
    [[ "$remote" == "$RCLONE_REMOTE:$DRIVE_ROOT/Manual-Safety/"* ]] || return 1
    rclone_cmd copyto "$marker" "$remote" --retries 3 --log-file "$RECOVERY_LOG"
}

create_manual_safety_snapshot() {
    local scope="$1" operation_id="$2" stage="$3" safety="$stage/safety"
    local host manual_root archive tar_status uuid folder source_file current_dir config_stage
    local db_result manifest
    host="$(sanitize_name "$(hostname)")"
    manual_root="$RCLONE_REMOTE:$DRIVE_ROOT/Manual-Safety/$host/$operation_id/$scope"
    install -d -m 700 "$safety/servers"
    : > "$safety/running_servers.txt"
    step "Creating mandatory Manual-Safety snapshot"

    if scope_has_panel "$scope"; then
        if [[ -d /var/www/pterodactyl ]]; then
            enough_temp_space /var/www/pterodactyl || return 1
            archive="$safety/panel_files.tar.gz"
            tar --warning=no-file-changed -czf "$archive" -C /var/www pterodactyl
            tar_status=$?
            (( tar_status <= 1 )) && [[ -s "$archive" ]] || return 1
            safety_upload_keep "$archive" "$manual_root/panel/panel_files.tar.gz" || return 1
        else
            safety_upload_marker "$safety/panel.absent" "$manual_root/panel/ABSENT" || return 1
        fi
    fi

    if scope_has_database "$scope"; then
        dump_current_database_local "$safety/panel_database.sql.gz" "$safety/db-work"
        db_result=$?
        if (( db_result == 0 )); then
            safety_upload_keep "$safety/panel_database.sql.gz" "$manual_root/database/panel_database.sql.gz" || return 1
        elif (( db_result == 2 )); then
            safety_upload_marker "$safety/database.absent" "$manual_root/database/ABSENT" || return 1
        else
            error "Current database safety dump failed. Recovery was cancelled before modifying anything."
            return 1
        fi
    fi

    if scope_has_servers "$scope"; then
        while IFS=$'\t' read -r uuid folder source_file; do
            valid_server_uuid "$uuid" || return 1
            current_dir="/var/lib/pterodactyl/volumes/$uuid"
            if command -v docker >/dev/null 2>&1 && \
               [[ "$(docker inspect -f '{{.State.Running}}' "$uuid" 2>/dev/null || true)" == "true" ]]; then
                printf '%s\n' "$uuid" >> "$safety/running_servers.txt"
            fi
            if [[ -d "$current_dir" ]]; then
                enough_temp_space "$current_dir" || return 1
                archive="$safety/servers/$uuid.tar.gz"
                tar --warning=no-file-changed -czf "$archive" -C /var/lib/pterodactyl/volumes "$uuid"
                tar_status=$?
                (( tar_status <= 1 )) && [[ -s "$archive" ]] || return 1
                safety_upload_keep "$archive" "$manual_root/node/servers/$uuid.tar.gz" || return 1
            else
                safety_upload_marker "$safety/servers/$uuid.absent" "$manual_root/node/servers/$uuid.ABSENT" || return 1
            fi
        done < "$stage/source/servers.tsv"
        safety_upload_keep "$safety/running_servers.txt" "$manual_root/node/running_servers.txt" || return 1
    fi

    if scope_has_node_config "$scope"; then
        if [[ -d /etc/pterodactyl ]]; then
            config_stage="$safety/node-config-stage"
            install -d -m 700 "$config_stage"
            cp -a /etc/pterodactyl "$config_stage/"
            [[ -f /etc/docker/daemon.json ]] && { mkdir -p "$config_stage/docker"; cp -a /etc/docker/daemon.json "$config_stage/docker/"; }
            [[ -f /etc/systemd/system/wings.service ]] && cp -a /etc/systemd/system/wings.service "$config_stage/"
            archive="$safety/node_configuration.tar.gz"
            tar -czf "$archive" -C "$config_stage" . || return 1
            safety_upload_keep "$archive" "$manual_root/node/node_configuration.tar.gz" || return 1
        else
            safety_upload_marker "$safety/node_configuration.absent" "$manual_root/node/configuration.ABSENT" || return 1
        fi
    fi

    manifest="$safety/manifest.json"
    jq -n --arg operation_id "$operation_id" --arg scope "$scope" --arg host "$(hostname)" \
        --arg created "$(date --iso-8601=seconds)" --arg source_date "$(jq -r '.source_timestamp // ""' "$RECOVERY_STATE_FILE" 2>/dev/null || true)" \
        '{operation_id:$operation_id,scope:$scope,hostname:$host,created_at:$created,source_timestamp:$source_date,purpose:"automatic pre-recovery rollback snapshot"}' \
        > "$manifest"
    safety_upload_keep "$manifest" "$manual_root/manifest.json" || return 1
    ok "Manual-Safety snapshot uploaded and retained at $manual_root"
}

write_recovery_state() {
    local mode="$1" scope="$2" source_timestamp="$3" remote_node="$4" selected_server="$5"
    local operation_id="$6" stage="$7" status="$8" temp
    temp="$(mktemp)"
    jq -n --arg mode "$mode" --arg scope "$scope" --arg source_timestamp "$source_timestamp" \
        --arg remote_node "$remote_node" --arg selected_server "$selected_server" \
        --arg operation_id "$operation_id" --arg stage "$stage" --arg status "$status" \
        --arg updated "$(date --iso-8601=seconds)" \
        '{mode:$mode,scope:$scope,source_timestamp:$source_timestamp,remote_node:$remote_node,selected_server:$selected_server,operation_id:$operation_id,stage:$stage,status:$status,updated_at:$updated}' \
        > "$temp"
    mv -f "$temp" "$RECOVERY_STATE_FILE"
    chmod 600 "$RECOVERY_STATE_FILE"
}

update_recovery_status() {
    local status="$1" temp
    [[ -f "$RECOVERY_STATE_FILE" ]] || return 1
    temp="$(mktemp)"
    jq --arg status "$status" --arg updated "$(date --iso-8601=seconds)" \
        '.status=$status | .updated_at=$updated' "$RECOVERY_STATE_FILE" > "$temp" && \
        mv -f "$temp" "$RECOVERY_STATE_FILE"
    chmod 600 "$RECOVERY_STATE_FILE"
}

recovery_preflight() {
    local mode="$1" scope="$2" failures=0
    step "Running destructive-operation preflight"
    command -v systemctl >/dev/null 2>&1 || { error "systemd is required for safe service control."; failures=$((failures + 1)); }
    if scope_has_panel "$scope" || scope_has_database "$scope"; then
        command -v php >/dev/null 2>&1 || { error "PHP CLI is required on the destination."; failures=$((failures + 1)); }
        command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1 || {
            error "MySQL/MariaDB client is required on the destination."
            failures=$((failures + 1))
        }
        [[ -d /var/www ]] || install -d -m 755 /var/www
        if [[ "$scope" == "database" && ! -f /var/www/pterodactyl/.env ]]; then
            error "Database-only recovery needs the destination Panel .env file."
            failures=$((failures + 1))
        fi
    fi
    if scope_has_servers "$scope" || scope_has_node_config "$scope"; then
        command -v docker >/dev/null 2>&1 || { error "Docker is required for Node recovery."; failures=$((failures + 1)); }
        command -v wings >/dev/null 2>&1 || { error "Wings must already be installed on the destination VPS."; failures=$((failures + 1)); }
        install -d -m 755 /var/lib/pterodactyl/volumes
        if [[ "$mode" == "shift" ]]; then
            warn "Shift mode restores a replacement Node identity. The old VPS Wings service must not run simultaneously."
        fi
    fi
    (( failures == 0 )) || return 1
    ok "Destination preflight passed."
}

stop_recovery_services() {
    local scope="$1"
    if scope_has_panel "$scope" || scope_has_database "$scope"; then
        [[ -f /var/www/pterodactyl/artisan ]] && \
            (cd /var/www/pterodactyl && php artisan down --no-interaction >/dev/null 2>&1) || true
        systemctl stop pteroq >/dev/null 2>&1 || true
    fi
    if scope_has_servers "$scope" || scope_has_node_config "$scope"; then
        systemctl stop wings >/dev/null 2>&1 || true
    fi
}

restore_panel_files_local() {
    local archive="$1" operation_id="$2" stage="$3"
    local rollback="$stage/rollback/pterodactyl-original"
    install -d -m 700 "$stage/rollback"
    if [[ -d /var/www/pterodactyl ]]; then
        mv /var/www/pterodactyl "$rollback" || return 1
    else
        : > "$stage/rollback/panel.was-absent"
    fi
    if ! tar -xzf "$archive" -C /var/www; then
        error "Panel archive extraction failed."
        return 1
    fi
    [[ -f /var/www/pterodactyl/.env && -f /var/www/pterodactyl/artisan ]] || {
        error "Restored Panel files are incomplete."
        return 1
    }
    local web_user="www-data"
    id -u www-data >/dev/null 2>&1 || { id -u nginx >/dev/null 2>&1 && web_user="nginx"; }
    chown -R "$web_user:$web_user" /var/www/pterodactyl
    chmod -R 755 /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache 2>/dev/null || true
    ok "Panel files restored from selected backup."
}

drop_database_by_name() {
    local db_name="$1" mysql_cmd
    [[ "$db_name" =~ ^[A-Za-z0-9_]+$ ]] || return 1
    mysql_cmd="$(command -v mariadb || command -v mysql || true)"
    [[ -n "$mysql_cmd" ]] || return 1
    "$mysql_cmd" --protocol=socket --user=root -e "DROP DATABASE IF EXISTS \`$db_name\`;" >/dev/null 2>&1
}

sql_literal_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\'/\'\'}"
    printf '%s' "$value"
}

restore_database_local() {
    local archive="$1" stage="$2" exact="${3:-1}" env_file="/var/www/pterodactyl/.env"
    [[ -f "$env_file" ]] || { error "Panel .env is required to identify the destination database."; return 1; }
    local mysql_cmd db_host db_port db_name db_user db_password escaped_password cnf root_socket=0 account_host
    mysql_cmd="$(command -v mariadb || command -v mysql || true)"
    [[ -n "$mysql_cmd" ]] || return 1
    db_host="$(env_value "$env_file" DB_HOST)"; [[ -n "$db_host" ]] || db_host="127.0.0.1"
    db_port="$(env_value "$env_file" DB_PORT)"; [[ "$db_port" =~ ^[0-9]+$ ]] || db_port="3306"
    db_name="$(env_value "$env_file" DB_DATABASE)"
    db_user="$(env_value "$env_file" DB_USERNAME)"
    db_password="$(env_value "$env_file" DB_PASSWORD)"
    [[ "$db_name" =~ ^[A-Za-z0-9_]+$ && "$db_user" =~ ^[A-Za-z0-9_.-]+$ ]] || {
        error "Unsafe or incomplete database configuration."
        return 1
    }
    printf '%s\n' "$db_name" > "$stage/restored-database-name"

    if [[ "$db_host" == "127.0.0.1" || "$db_host" == "localhost" || "$db_host" == "::1" ]] && \
       "$mysql_cmd" --protocol=socket --user=root -e 'SELECT 1;' >/dev/null 2>&1; then
        root_socket=1
    fi
    if (( root_socket )); then
        if [[ "$exact" == "1" ]]; then
            "$mysql_cmd" --protocol=socket --user=root \
                -e "DROP DATABASE IF EXISTS \`$db_name\`; CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || return 1
        else
            "$mysql_cmd" --protocol=socket --user=root \
                -e "CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" || return 1
        fi
        escaped_password="$(sql_literal_escape "$db_password")"
        for account_host in 127.0.0.1 localhost; do
            "$mysql_cmd" --protocol=socket --user=root -e \
                "CREATE USER IF NOT EXISTS '$db_user'@'$account_host' IDENTIFIED BY '$escaped_password'; ALTER USER '$db_user'@'$account_host' IDENTIFIED BY '$escaped_password'; GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'$account_host';" || return 1
        done
        "$mysql_cmd" --protocol=socket --user=root -e 'FLUSH PRIVILEGES;' || return 1
        if ! gzip -dc "$archive" | "$mysql_cmd" --protocol=socket --user=root "$db_name"; then
            error "Database import through local root socket failed."
            return 1
        fi
    else
        cnf="$stage/restore-mysql.cnf"
        umask 077
        {
            printf '[client]\n'
            printf 'host=%s\nport=%s\nuser=%s\npassword=%s\n' "$db_host" "$db_port" "$db_user" "$db_password"
        } > "$cnf"
        if ! gzip -dc "$archive" | "$mysql_cmd" --defaults-extra-file="$cnf" "$db_name"; then
            rm -f "$cnf"
            error "Database import with Panel credentials failed."
            return 1
        fi
        rm -f "$cnf"
    fi
    ok "Panel database restored successfully."
}

restore_node_configuration_local() {
    local archive="$1" operation_id="$2" stage="$3" extracted="$stage/node-config-restored"
    local rollback="/etc/pterodactyl.rhm-rollback-$operation_id"
    install -d -m 700 "$extracted"
    tar -xzf "$archive" -C "$extracted" || return 1
    [[ -d "$extracted/pterodactyl" ]] || { error "Node configuration archive is missing pterodactyl/config.yml."; return 1; }
    if [[ -d /etc/pterodactyl ]]; then
        mv /etc/pterodactyl "$rollback" || return 1
    else
        : > "$stage/rollback/node-config.was-absent"
    fi
    mv "$extracted/pterodactyl" /etc/pterodactyl || return 1
    chmod 600 /etc/pterodactyl/config.yml 2>/dev/null || true
    if [[ -f "$extracted/wings.service" ]]; then
        cp -a "$extracted/wings.service" /etc/systemd/system/wings.service
    fi
    if [[ -f "$extracted/docker/daemon.json" ]]; then
        install -d -m 755 /etc/docker
        cp -a "$extracted/docker/daemon.json" /etc/docker/daemon.json
        systemctl restart docker >/dev/null 2>&1 || return 1
    fi
    systemctl daemon-reload
    ok "Node/Wings configuration restored."
}

restore_server_volumes_local() {
    local stage="$1" operation_id="$2" uuid folder archive rollback
    while IFS=$'\t' read -r uuid folder archive; do
        valid_server_uuid "$uuid" && [[ "$archive" == "$stage/source/servers/"* ]] || return 1
        docker stop -t 60 "$uuid" >/dev/null 2>&1 || true
        rollback="/var/lib/pterodactyl/volumes/${uuid}.rhm-rollback-$operation_id"
        [[ -e "$rollback" ]] && { error "Rollback directory already exists for $uuid."; return 1; }
        if [[ -d "/var/lib/pterodactyl/volumes/$uuid" ]]; then
            mv "/var/lib/pterodactyl/volumes/$uuid" "$rollback" || return 1
        else
            : > "$stage/rollback/server-$uuid.was-absent"
        fi
        if ! tar -xzf "$archive" -C /var/lib/pterodactyl/volumes; then
            error "Failed to extract server volume $uuid."
            return 1
        fi
        [[ -d "/var/lib/pterodactyl/volumes/$uuid" ]] || return 1
        ok "Server volume restored: $folder"
    done < "$stage/source/servers.tsv"
}

start_recovery_services() {
    local scope="$1" stage="$2" uuid
    systemctl daemon-reload >/dev/null 2>&1 || true
    if scope_has_panel "$scope" || scope_has_database "$scope"; then
        if [[ -f /var/www/pterodactyl/artisan ]]; then
            (cd /var/www/pterodactyl && php artisan optimize:clear --no-interaction >/dev/null 2>&1) || true
            (cd /var/www/pterodactyl && php artisan queue:restart --no-interaction >/dev/null 2>&1) || true
            (cd /var/www/pterodactyl && php artisan up --no-interaction >/dev/null 2>&1) || true
        fi
        systemctl enable --now pteroq >/dev/null 2>&1 || true
    fi
    if scope_has_servers "$scope" || scope_has_node_config "$scope"; then
        systemctl enable --now wings >/dev/null 2>&1 || return 1
        if [[ -f "$stage/safety/running_servers.txt" ]]; then
            while IFS= read -r uuid; do
                valid_server_uuid "$uuid" && docker start "$uuid" >/dev/null 2>&1 || true
            done < "$stage/safety/running_servers.txt"
        fi
    fi
}

recovery_health_check() {
    local scope="$1" stage="$2" failures=0 uuid folder archive
    if scope_has_panel "$scope"; then
        [[ -f /var/www/pterodactyl/artisan && -f /var/www/pterodactyl/.env ]] || failures=$((failures + 1))
    fi
    if scope_has_database "$scope"; then
        if [[ -f /var/www/pterodactyl/artisan ]]; then
            (cd /var/www/pterodactyl && php artisan migrate:status --no-ansi >/dev/null 2>&1) || failures=$((failures + 1))
        else
            failures=$((failures + 1))
        fi
    fi
    if (scope_has_panel "$scope" || scope_has_database "$scope") && \
       systemctl list-unit-files pteroq.service --no-legend 2>/dev/null | grep -q '^pteroq.service'; then
        systemctl is-active --quiet pteroq || failures=$((failures + 1))
    fi
    if scope_has_node_config "$scope"; then
        systemctl is-active --quiet wings || failures=$((failures + 1))
        [[ -f /etc/pterodactyl/config.yml ]] || failures=$((failures + 1))
    fi
    if scope_has_servers "$scope"; then
        while IFS=$'\t' read -r uuid folder archive; do
            [[ -d "/var/lib/pterodactyl/volumes/$uuid" ]] || failures=$((failures + 1))
        done < "$stage/source/servers.tsv"
    fi
    (( failures == 0 )) || { error "$failures post-recovery health check(s) failed."; return 1; }
    ok "All post-recovery health checks passed."
}

rollback_recovery() {
    [[ -f "$RECOVERY_STATE_FILE" ]] || { error "No recovery state is available."; return 1; }
    local scope operation_id stage uuid folder archive rollback current_db=""
    scope="$(jq -r '.scope' "$RECOVERY_STATE_FILE")"
    operation_id="$(jq -r '.operation_id' "$RECOVERY_STATE_FILE")"
    stage="$(jq -r '.stage' "$RECOVERY_STATE_FILE")"
    valid_recovery_timestamp "$operation_id" || { error "Unsafe rollback operation ID."; return 1; }
    [[ "$stage" == "$TMP_ROOT/recovery-$operation_id" && -d "$stage" ]] || { error "Local rollback workspace is unavailable."; return 1; }
    step "Rolling back the last recovery operation"
    stop_recovery_services "$scope"
    [[ -f /var/www/pterodactyl/.env ]] && current_db="$(env_value /var/www/pterodactyl/.env DB_DATABASE)"

    if scope_has_panel "$scope"; then
        rm -rf -- /var/www/pterodactyl
        if [[ -d "$stage/rollback/pterodactyl-original" ]]; then
            mv "$stage/rollback/pterodactyl-original" /var/www/pterodactyl || return 1
        fi
    fi
    if scope_has_database "$scope"; then
        if [[ -f "$stage/safety/panel_database.sql.gz" ]]; then
            restore_database_local "$stage/safety/panel_database.sql.gz" "$stage" 1 || return 1
        elif [[ -f "$stage/safety/database.absent" && -n "$current_db" ]]; then
            drop_database_by_name "$current_db" || warn "Could not remove the newly restored database automatically."
        fi
    fi
    if scope_has_servers "$scope"; then
        while IFS=$'\t' read -r uuid folder archive; do
            valid_server_uuid "$uuid" || return 1
            rm -rf -- "/var/lib/pterodactyl/volumes/$uuid"
            rollback="/var/lib/pterodactyl/volumes/${uuid}.rhm-rollback-$operation_id"
            [[ -d "$rollback" ]] && mv "$rollback" "/var/lib/pterodactyl/volumes/$uuid"
        done < "$stage/source/servers.tsv"
    fi
    if scope_has_node_config "$scope"; then
        rm -rf -- /etc/pterodactyl
        rollback="/etc/pterodactyl.rhm-rollback-$operation_id"
        [[ -d "$rollback" ]] && mv "$rollback" /etc/pterodactyl
        if [[ -f "$stage/safety/node_configuration.tar.gz" ]]; then
            local extracted="$stage/safety/node-config-rollback"
            install -d -m 700 "$extracted"
            tar -xzf "$stage/safety/node_configuration.tar.gz" -C "$extracted" || return 1
            [[ -f "$extracted/wings.service" ]] && cp -a "$extracted/wings.service" /etc/systemd/system/wings.service
            [[ -f "$extracted/docker/daemon.json" ]] && cp -a "$extracted/docker/daemon.json" /etc/docker/daemon.json
            [[ -f "$extracted/docker/daemon.json" ]] && systemctl restart docker >/dev/null 2>&1 || true
        fi
    fi
    start_recovery_services "$scope" "$stage" || true
    update_recovery_status "rolled-back"
    ok "Rollback completed. Manual-Safety copy remains in Google Drive."
}

cleanup_recovery_success() {
    local scope="$1" operation_id="$2" stage="$3" uuid folder archive rollback
    [[ "$stage" == "$TMP_ROOT/recovery-$operation_id" ]] || return 1
    [[ -d "$stage/rollback/pterodactyl-original" ]] && rm -rf -- "$stage/rollback/pterodactyl-original"
    if scope_has_servers "$scope"; then
        while IFS=$'\t' read -r uuid folder archive; do
            valid_server_uuid "$uuid" || return 1
            rollback="/var/lib/pterodactyl/volumes/${uuid}.rhm-rollback-$operation_id"
            [[ -d "$rollback" ]] && rm -rf -- "$rollback"
        done < "$stage/source/servers.tsv"
    fi
    rollback="/etc/pterodactyl.rhm-rollback-$operation_id"
    [[ -d "$rollback" ]] && rm -rf -- "$rollback"
    update_recovery_status "success"
    rm -rf -- "$stage"
}

run_recovery() {
    local mode="$1" scope timestamp remote_node="" selected_server="" operation_id stage confirmation result=0
    local previous_status previous_stage
    [[ "$mode" == "restore" || "$mode" == "shift" ]] || return 1
    load_config
    ensure_dirs
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        error "Another backup/recovery task is already running."
        return 1
    fi
    if [[ -f "$RECOVERY_STATE_FILE" ]] && jq -e . "$RECOVERY_STATE_FILE" >/dev/null 2>&1; then
        previous_status="$(jq -r '.status // "unknown"' "$RECOVERY_STATE_FILE")"
        previous_stage="$(jq -r '.stage // ""' "$RECOVERY_STATE_FILE")"
        case "$previous_status" in
            failed|applying|interrupted)
                if [[ "$previous_stage" == "$TMP_ROOT/recovery-"* && -d "$previous_stage" ]]; then
                    error "A preserved $previous_status recovery must be rolled back before starting another operation."
                    info "Choose manager option 16 or run: $INSTALL_PATH --rollback"
                    return 1
                fi
                ;;
        esac
    fi
    if ! rclone_cmd lsd "$RCLONE_REMOTE:$DRIVE_ROOT" --contimeout 10s --timeout 30s >/dev/null 2>&1; then
        error "Google Drive or $DRIVE_ROOT is unavailable."
        return 1
    fi

    banner
    if [[ "$mode" == "shift" ]]; then
        step "SHIFT BACKUP — Google Drive migration to this VPS"
        warn "Run this on the destination VPS. Source VPS data will not be modified."
        warn "For a Node replacement, stop/power off old Wings before activating this destination."
    else
        step "RESTORE BACKUP — transactional recovery on this VPS"
    fi
    scope="$(select_recovery_scope)" || return 1
    timestamp="$(select_restore_point)" || return 1
    if scope_has_servers "$scope" || scope_has_node_config "$scope"; then
        remote_node="$(select_remote_node)" || return 1
    fi
    if [[ "$scope" == "server" ]]; then
        selected_server="$(select_remote_server "$remote_node")" || return 1
    fi

    printf '\n%b\n' "${WHITE}Operation summary:${RESET}"
    printf '  Mode:          %s\n' "$mode"
    printf '  Scope:         %s\n' "$scope"
    printf '  Backup date:   %s\n' "$timestamp"
    [[ -n "$remote_node" ]] && printf '  Source Node:   %s\n' "$remote_node"
    [[ -n "$selected_server" ]] && printf '  Server:        %s\n' "$selected_server"
    if ! confirm "Download and validate this recovery point?" "y"; then
        info "Recovery cancelled without changing anything."
        return 0
    fi

    operation_id="$(date '+%Y-%m-%d_%H-%M-%S')"
    stage="$TMP_ROOT/recovery-$operation_id"
    install -d -m 700 "$stage/rollback"
    write_recovery_state "$mode" "$scope" "$timestamp" "$remote_node" "$selected_server" \
        "$operation_id" "$stage" "downloading"

    if ! prepare_recovery_downloads "$scope" "$timestamp" "$remote_node" "$selected_server" "$stage"; then
        update_recovery_status "download-failed"
        rm -rf -- "$stage"
        error "Recovery stopped before touching live data."
        return 1
    fi
    if ! recovery_preflight "$mode" "$scope"; then
        update_recovery_status "preflight-failed"
        rm -rf -- "$stage"
        error "Destination is not safely prepared; no live data was changed."
        return 1
    fi
    update_recovery_status "creating-safety-snapshot"
    if ! create_manual_safety_snapshot "$scope" "$operation_id" "$stage"; then
        update_recovery_status "safety-snapshot-failed"
        rm -rf -- "$stage"
        error "Manual-Safety snapshot failed, so live restore was blocked."
        return 1
    fi

    if [[ "$mode" == "shift" ]]; then
        confirmation="$(read_tty "Type SHIFT to overwrite selected destination data" "")"
        [[ "$confirmation" == "SHIFT" ]] || {
            update_recovery_status "cancelled"
            rm -rf -- "$stage"
            info "Shift cancelled. Manual-Safety copy remains in Drive."
            return 0
        }
    else
        confirmation="$(read_tty "Type RESTORE to overwrite selected live data" "")"
        [[ "$confirmation" == "RESTORE" ]] || {
            update_recovery_status "cancelled"
            rm -rf -- "$stage"
            info "Restore cancelled. Manual-Safety copy remains in Drive."
            return 0
        }
    fi

    update_recovery_status "applying"
    stop_recovery_services "$scope"
    if scope_has_panel "$scope"; then
        restore_panel_files_local "$stage/source/panel_files.tar.gz" "$operation_id" "$stage" || result=1
    fi
    if (( result == 0 )) && scope_has_database "$scope"; then
        restore_database_local "$stage/source/panel_database.sql.gz" "$stage" 1 || result=1
    fi
    if (( result == 0 )) && scope_has_node_config "$scope"; then
        restore_node_configuration_local "$stage/source/node_configuration.tar.gz" "$operation_id" "$stage" || result=1
    fi
    if (( result == 0 )) && scope_has_servers "$scope"; then
        restore_server_volumes_local "$stage" "$operation_id" || result=1
    fi
    if (( result == 0 )); then
        start_recovery_services "$scope" "$stage" || result=1
    fi
    if (( result == 0 )); then
        recovery_health_check "$scope" "$stage" || result=1
    fi

    if (( result == 0 )); then
        cleanup_recovery_success "$scope" "$operation_id" "$stage"
        send_webhook "✅ **RHM ${mode^} completed**\nHost: **$(hostname)**\nScope: **$scope**\nSource backup: **$timestamp**\nAll post-operation health checks passed. Manual-Safety remains in Drive."
        ok "${mode^} completed successfully. Manual-Safety rollback snapshot remains in Google Drive."
        [[ "$mode" == "shift" ]] && warn "Update DNS/IP routing externally if this VPS replaces the old public endpoint."
        return 0
    fi

    update_recovery_status "failed"
    error "${mode^} failed. Local rollback workspace and Drive Manual-Safety snapshot were preserved."
    send_webhook "$(discord_ping) ❌ **RHM ${mode^} failed**\nHost: **$(hostname)**\nScope: **$scope**\nSource backup: **$timestamp**\nRollback is available in the manager."
    if confirm "Roll back automatically now?" "y"; then
        rollback_recovery
    else
        start_recovery_services "$scope" "$stage" || true
        warn "Partial recovery state preserved. Choose 'Rollback last failed operation' from the manager."
    fi
    return 1
}

rollback_last_recovery_menu() {
    if [[ ! -f "$RECOVERY_STATE_FILE" ]]; then
        info "No recovery operation is available for rollback."
        return 0
    fi
    local status
    status="$(jq -r '.status // "unknown"' "$RECOVERY_STATE_FILE")"
    case "$status" in
        failed|applying|interrupted)
            if confirm "Rollback the preserved $status recovery operation now?" "y"; then
                rollback_recovery
            fi
            ;;
        *) info "Last recovery state is '$status'; no emergency rollback is pending." ;;
    esac
}

show_recent_logs() {
    step "Recent backup activity"
    if [[ -s "$BACKUP_LOG" ]]; then
        tail -n 30 "$BACKUP_LOG"
    else
        info "No backup log entries are available yet."
    fi
    if [[ -s "$MONITOR_LOG" ]]; then
        printf '\n'
        step "Recent server-deletion monitor activity"
        tail -n 15 "$MONITOR_LOG"
    fi
    if [[ -s "$RECOVERY_LOG" ]]; then
        printf '\n'
        step "Recent restore and shift transfer activity"
        tail -n 20 "$RECOVERY_LOG"
    fi
}

manual_retry_failed_uploads() {
    ensure_dirs
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        warn "Another RHM task is running. Try again after it finishes."
        return 1
    fi
    if ! rclone_cmd mkdir "$RCLONE_REMOTE:$DRIVE_ROOT" >/dev/null 2>&1; then
        error "Google Drive is unavailable; retry was not started."
        return 1
    fi
    local before after
    before="$(failed_recovery_count)"
    if [[ "$before" == "0" ]]; then
        ok "No failed uploads are waiting."
        return 0
    fi
    retry_failed_uploads || true
    find "$TMP_ROOT" -mindepth 1 -depth -type d -empty -delete 2>/dev/null || true
    after="$(failed_recovery_count)"
    if [[ "$after" == "0" ]]; then
        ok "All failed uploads were recovered and local archives were cleaned."
    else
        warn "$after failed upload(s) are still waiting; check $BACKUP_LOG."
        return 1
    fi
}

manager_menu() {
    local choice
    while true; do
        banner
        show_status
        printf '\n%b\n' "${WHITE}1)${RESET} 🚀 Run backup now"
        printf '%b\n' "${WHITE}2)${RESET} 📧 Change Google Drive email/account"
        printf '%b\n' "${WHITE}3)${RESET} 📁 Change custom node folder name"
        printf '%b\n' "${WHITE}4)${RESET} 🧹 Change backup retention days"
        printf '%b\n' "${WHITE}5)${RESET} 🕑 Change daily backup time"
        printf '%b\n' "${WHITE}6)${RESET} 🔗 Panel API & Discord webhook settings"
        printf '%b\n' "${WHITE}7)${RESET} ⏹️  Stop automatic backups"
        printf '%b\n' "${WHITE}8)${RESET} ▶️  Resume automatic backups"
        printf '%b\n' "${WHITE}9)${RESET} ⚙️  Change backup type"
        printf '%b\n' "${WHITE}10)${RESET} 🩺 Run system health check"
        printf '%b\n' "${WHITE}11)${RESET} 📜 View recent logs"
        printf '%b\n' "${WHITE}12)${RESET} 🔄 Retry failed uploads only"
        printf '%b\n' "${WHITE}13)${RESET} 🗄️  Back up Panel database only"
        printf '%b\n' "${WHITE}14)${RESET} ♻️  Restore a backup"
        printf '%b\n' "${WHITE}15)${RESET} 🚚 Shift backup to this VPS"
        printf '%b\n' "${WHITE}16)${RESET} 🛟 Roll back last failed restore/shift"
        if [[ "$BACKUP_NOTIFICATIONS" == "1" ]]; then
            printf '%b\n' "${WHITE}17)${RESET} 🔕 Stop backup Discord messages"
        else
            printf '%b\n' "${WHITE}17)${RESET} 🔔 Resume backup Discord messages"
        fi
        printf '%b\n' "${WHITE}0)${RESET} Exit"
        printf '\n'
        choice="$(read_tty "Select an option" "1")"
        case "$choice" in
            1) run_backup 1 && ok "Backup completed." || error "Backup completed with errors. Check $BACKUP_LOG." ;;
            2) configure_drive "change" ;;
            3) change_node_folder ;;
            4) configure_retention; save_config; ok "Retention updated to $RETENTION_DAYS day(s)." ;;
            5) configure_time; save_config; [[ "$ENABLED" == "1" ]] && write_cron; ok "Backup schedule updated." ;;
            6) configure_panel_integration; [[ "$ENABLED" == "1" ]] && write_cron; ok "Integration settings updated." ;;
            7) stop_automation ;;
            8) resume_automation ;;
            9) configure_type; save_config; ok "Backup type updated to $BACKUP_TYPE." ;;
            10) system_health_check || true ;;
            11) show_recent_logs ;;
            12) manual_retry_failed_uploads || true ;;
            13) run_database_only || true ;;
            14) run_recovery restore || true ;;
            15) run_recovery shift || true ;;
            16) rollback_last_recovery_menu || true ;;
            17) toggle_backup_notifications || true ;;
            0) printf '%b\n' "${PURPLE}Goodbye, Ray. Your backups stay protected. 👋${RESET}"; return 0 ;;
            *) warn "Unknown option." ;;
        esac
        [[ "$choice" == "0" ]] || { printf '\n'; read_tty "Press Enter to continue" "" >/dev/null; }
    done
}

main() {
    require_root
    case "${1:-}" in
        --backup)
            ensure_dirs; load_config; run_backup 0
            ;;
        --monitor)
            ensure_dirs; load_config; run_monitor
            ;;
        --database)
            ensure_dirs; load_config; run_database_only
            ;;
        --restore)
            ensure_dirs; load_config; install_dependencies || exit 1; run_recovery restore
            ;;
        --shift)
            ensure_dirs; load_config; install_dependencies || exit 1; run_recovery shift
            ;;
        --rollback)
            ensure_dirs; load_config; install_dependencies || exit 1; rollback_last_recovery_menu
            ;;
        --help)
            printf 'Usage: %s [--backup|--monitor|--database|--restore|--shift|--rollback]\n' "$0"
            ;;
        "")
            ensure_dirs
            load_config
            if [[ ! -f "$CONFIG_FILE" ]]; then
                initial_setup || exit 1
                load_config
                manager_menu
            else
                install_dependencies || exit 1
                if [[ "$LEGACY_CLEANUP_DONE" != "1" ]]; then
                    cleanup_legacy_install
                    save_config
                fi
                install_self || exit 1
                manager_menu
            fi
            ;;
        *)
            error "Unknown option: $1"
            exit 2
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
