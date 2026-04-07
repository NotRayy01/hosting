#!/bin/bash
set -e


# ==============================================================================
# 🎨 RAY UI & STYLING OVERRIDES
# ==============================================================================
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
MAGENTA="\033[0;35m"
CYAN="\033[0;36m"
NC="\033[0m"
BOLD="\033[1m"

ok() { echo -e "${GREEN}✅ $1${NC}"; }
info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err() { echo -e "${RED}❌ $1${NC}"; }
step() { echo -e "\n${MAGENTA}⚡ ${BOLD}$1${NC}"; }

# Legacy function mappings to Ray UI
output() { step "$1"; }
success() { ok "$1"; }
error() { err "$1"; }
warning() { warn "$1"; }

# ------------------ Variables ----------------- #
export GITHUB_SOURCE=${GITHUB_SOURCE:-main}
export SCRIPT_RELEASE=${SCRIPT_RELEASE:-RayPro}

export PTERODACTYL_PANEL_VERSION=""
export PTERODACTYL_WINGS_VERSION=""

export PATH="$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

export OS=""
export OS_VER_MAJOR=""
export CPU_ARCHITECTURE=""
export ARCH=""
export SUPPORTED=false

export PANEL_DL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
export WINGS_DL_BASE_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_"
export MARIADB_URL="https://downloads.mariadb.com/MariaDB/mariadb_repo_setup"

# Hardcoded to Ray's Repo
export GITHUB_BASE_URL="https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main"
export GITHUB_URL="$GITHUB_BASE_URL/pterodactyl_manager"

email_regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"
password_charset='A-Za-z0-9!"#%&()*+,-./:;<=>?@[\]^_`{|}~'

# --------------------- Lib -------------------- #

lib_loaded() { return 0; }

print_brake() {
  echo -e "${CYAN}================================================================${NC}"
}

print_list() {
  print_brake
  for word in $1; do
    echo -e " ${BOLD}$word${NC}"
  done
  print_brake
  echo ""
}

hyperlink() {
  echo -e "\e]8;;${1}\a${1}\e]8;;\a"
}

welcome() {
  get_latest_versions
  clear
  print_brake
  echo -e "${BOLD} 🚀 Ray Pterodactyl Installer ($1)${NC}"
  echo -e " 👑 Developed by Ray | 🏢 Ray Industries | 📺 @RayVerse"
  print_brake
  echo -e " Running $OS version $OS_VER."
  if [ "$1" == "panel" ]; then
    echo -e " Deploying pterodactyl/panel $PTERODACTYL_PANEL_VERSION"
  elif [ "$1" == "wings" ]; then
    echo -e " Deploying pterodactyl/wings $PTERODACTYL_WINGS_VERSION"
  fi
  print_brake
}

# ---------------- Lib functions --------------- #

get_latest_release() {
  curl -sL "https://api.github.com/repos/$1/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

get_latest_versions() {
  PTERODACTYL_PANEL_VERSION=$(get_latest_release "pterodactyl/panel")
  PTERODACTYL_WINGS_VERSION=$(get_latest_release "pterodactyl/wings")
}

run_installer() {
  bash <(curl -sSL "$GITHUB_URL/installers/$1.sh")
}

run_ui() {
  bash <(curl -sSL "$GITHUB_URL/ui/$1.sh")
}

array_contains_element() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

valid_email() { [[ $1 =~ ${email_regex} ]]; }

invalid_ip() { ip route get "$1" >/dev/null 2>&1; echo $?; }

gen_passwd() {
  local length=$1
  local password=""
  while [ ${#password} -lt "$length" ]; do
    password=$(echo "$password""$(head -c 100 /dev/urandom | LC_ALL=C tr -dc "$password_charset")" | fold -w "$length" | head -n 1)
  done
  echo "$password"
}

# -------------------- MYSQL ------------------- #

create_db_user() {
  local db_user_name="$1"
  local db_user_password="$2"
  local db_host="${3:-127.0.0.1}"
  step "Creating database user $db_user_name..."
  mariadb -u root -e "CREATE USER IF NOT EXISTS '$db_user_name'@'$db_host' IDENTIFIED BY '$db_user_password';"
  mariadb -u root -e "FLUSH PRIVILEGES;"
  ok "Database user $db_user_name created"
}

grant_all_privileges() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"
  step "Granting all privileges on $db_name to $db_user_name..."
  mariadb -u root -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user_name'@'$db_host' WITH GRANT OPTION;"
  mariadb -u root -e "FLUSH PRIVILEGES;"
}

create_db() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"
  step "Creating database $db_name..."
  mariadb -u root -e "CREATE DATABASE IF NOT EXISTS $db_name;"
  grant_all_privileges "$db_name" "$db_user_name" "$db_host"
  ok "Database $db_name created"
}

# --------------- Package Manager -------------- #

update_repos() {
  local args=""
  [[ "$1" == true ]] && args="-qq"

  case "$OS" in
    ubuntu | debian)
      if ! apt-get update -y $args; then err "Failed to update repositories."; return 1; fi
      ;;
  esac
}

install_packages() {
  local args=""
  if [[ $2 == true ]]; then
    case "$OS" in
    ubuntu | debian) args="-qq" ;;
    *) args="-q" ;;
    esac
  fi

  case "$OS" in
  ubuntu | debian) eval apt-get -y $args install "$1" ;;
  rocky | almalinux) eval dnf -y $args install "$1" ;;
  esac
}

# ------------ User input functions ------------ #

required_input() {
  local __resultvar=$1
  local result=''
  while [ -z "$result" ]; do
    echo -e -n " ${CYAN}➤${NC} ${2}"
    read -r result
    if [ -z "${3}" ]; then
      [ -z "$result" ] && result="${4}"
    else
      [ -z "$result" ] && err "${3}"
    fi
  done
  eval "$__resultvar="'$result'""
}

email_input() {
  local __resultvar=$1
  local result=''
  while ! valid_email "$result"; do
    echo -e -n " ${CYAN}➤${NC} ${2}"
    read -r result
    valid_email "$result" || err "${3}"
  done
  eval "$__resultvar="'$result'""
}

password_input() {
  local __resultvar=$1
  local result=''
  local default="$4"
  while [ -z "$result" ]; do
    echo -e -n " ${CYAN}➤${NC} ${2}"
    while IFS= read -r -s -n1 char; do
      [[ -z $char ]] && { printf '\n'; break; }
      if [[ $char == $'\x7f' ]]; then
        if [ -n "$result" ]; then
          [[ -n $result ]] && result=${result%?}
          printf '\b \b'
        fi
      else
        result+=$char
        printf '*'
      fi
    done
    [ -z "$result" ] && [ -n "$default" ] && result="$default"
    [ -z "$result" ] && err "${3}"
  done
  eval "$__resultvar="'$result'""
}

# ------------------ Firewall ------------------ #

ask_firewall() {
  local __resultvar=$1
  echo -e -n " ${CYAN}➤${NC} Auto-configure firewall? (y/N): "
  read -r CONFIRM_FW
  if [[ "$CONFIRM_FW" =~ [Yy] ]]; then eval "$__resultvar="'true'""; fi
}

install_firewall() {
  case "$OS" in
  ubuntu | debian)
    step "Installing UFW (Firewall)"
    if ! [ -x "$(command -v ufw)" ]; then
      update_repos true
      install_packages "ufw" true
    fi
    ufw --force enable
    ok "UFW Enabled"
    ;;
  rocky | almalinux)
    step "Installing FirewallD"
    if ! [ -x "$(command -v firewall-cmd)" ]; then
      install_packages "firewalld" true
    fi
    systemctl --now enable firewalld >/dev/null
    ok "FirewallD Enabled"
    ;;
  esac
}

firewall_allow_ports() {
  case "$OS" in
  ubuntu | debian)
    for port in $1; do ufw allow "$port" >/dev/null; done
    ufw --force reload >/dev/null
    ;;
  rocky | almalinux)
    for port in $1; do firewall-cmd --zone=public --add-port="$port"/tcp --permanent >/dev/null; done
    firewall-cmd --reload -q
    ;;
  esac
}

# ---------------- System checks --------------- #

check_os_x86_64() {
  if [ "${ARCH}" != "amd64" ]; then
    warn "Detected CPU architecture $CPU_ARCHITECTURE"
    err "Installation aborted! Requires x86_64."
    exit 1
  fi
}

if [[ $EUID -ne 0 ]]; then err "Must execute as root."; exit 1; fi

if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$(echo "$ID" | awk '{print tolower($0)}')
  OS_VER=$VERSION_ID
fi

OS=$(echo "$OS" | awk '{print tolower($0)}')
OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
CPU_ARCHITECTURE=$(uname -m)

case "$CPU_ARCHITECTURE" in
x86_64) ARCH=amd64 ;;
arm64 | aarch64) ARCH=arm64 ;;
esac

case "$OS" in
ubuntu) [ "$OS_VER_MAJOR" == "22" ] || [ "$OS_VER_MAJOR" == "24" ] && SUPPORTED=true; export DEBIAN_FRONTEND=noninteractive ;;
debian) [ "$OS_VER_MAJOR" == "10" ] || [ "$OS_VER_MAJOR" == "11" ] || [ "$OS_VER_MAJOR" == "12" ] || [ "$OS_VER_MAJOR" == "13" ] && SUPPORTED=true; export DEBIAN_FRONTEND=noninteractive ;;
rocky | almalinux) [ "$OS_VER_MAJOR" == "8" ] || [ "$OS_VER_MAJOR" == "9" ] && SUPPORTED=true ;;
*) SUPPORTED=false ;;
esac

if [ "$SUPPORTED" == false ]; then err "Unsupported OS: $OS $OS_VER"; exit 1; fi