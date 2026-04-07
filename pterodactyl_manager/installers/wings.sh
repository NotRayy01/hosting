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

RAY_REPO="https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/pterodactyl_manager"

ok() { echo -e "${GREEN}✅ $1${NC}"; }
info() { echo -e "${CYAN}ℹ️  $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
err() { echo -e "${RED}❌ $1${NC}"; }
step() { echo -e "\n${MAGENTA}⚡ ${BOLD}$1${NC}"; }

fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  source <(curl -sSL "$RAY_REPO/lib/lib.sh")
  ! fn_exists lib_loaded && err "Could not load lib script from Ray CDN" && exit 1
fi

# Override default lib functions with Ray UI
output() { step "$1"; }
success() { ok "$1"; }
error() { err "$1"; }
warning() { warn "$1"; }

# ------------------ Variables ----------------- #
INSTALL_MARIADB="${INSTALL_MARIADB:-false}"
CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-false}"
CONFIGURE_LETSENCRYPT="${CONFIGURE_LETSENCRYPT:-false}"
FQDN="${FQDN:-}"
EMAIL="${EMAIL:-}"
CONFIGURE_DBHOST="${CONFIGURE_DBHOST:-false}"
CONFIGURE_DB_FIREWALL="${CONFIGURE_DB_FIREWALL:-false}"
MYSQL_DBHOST_HOST="${MYSQL_DBHOST_HOST:-127.0.0.1}"
MYSQL_DBHOST_USER="${MYSQL_DBHOST_USER:-pterodactyluser}"
MYSQL_DBHOST_PASSWORD="${MYSQL_DBHOST_PASSWORD:-}"

if [[ $CONFIGURE_DBHOST == true && -z "${MYSQL_DBHOST_PASSWORD}" ]]; then
  err "Mysql database host user password is required"
  exit 1
fi

# ----------- Installation functions ----------- #

enable_services() {
  [ "$INSTALL_MARIADB" == true ] && systemctl enable mariadb && systemctl start mariadb
  systemctl start docker
  systemctl enable docker
}

dep_install() {
  step "Installing dependencies for $OS $OS_VER..."
  [ "$CONFIGURE_FIREWALL" == true ] && install_firewall && firewall_ports

  case "$OS" in
  ubuntu | debian)
    install_packages "ca-certificates gnupg lsb-release"
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    ;;
  rocky | almalinux)
    install_packages "dnf-utils"
    dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "epel-release"
    install_packages "device-mapper-persistent-data lvm2"
    ;;
  esac

  update_repos
  install_packages "docker-ce docker-ce-cli containerd.io"
  [ "$INSTALL_MARIADB" == true ] && install_packages "mariadb-server"
  [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot"

  enable_services
  ok "Dependencies installed!"
}

ptdl_dl() {
  step "Downloading Pterodactyl Wings.. "
  mkdir -p /etc/pterodactyl
  curl -L -o /usr/local/bin/wings "$WINGS_DL_BASE_URL$ARCH"
  chmod u+x /usr/local/bin/wings
  ok "Pterodactyl Wings downloaded successfully"
}

systemd_file() {
  step "Installing systemd service.."
  curl -o /etc/systemd/system/wings.service "$RAY_REPO/configs/wings.service"
  systemctl daemon-reload
  systemctl enable wings
  ok "Installed systemd service!"
}

firewall_ports() {
  step "Opening port 22 (SSH), 8080 (Wings Port), 2022 (Wings SFTP Port)"
  [ "$CONFIGURE_LETSENCRYPT" == true ] && firewall_allow_ports "80 443"
  [ "$CONFIGURE_DB_FIREWALL" == true ] && firewall_allow_ports "3306"

  firewall_allow_ports "22 8080 2022"
  ok "Firewall ports opened!"
}

letsencrypt() {
  FAILED=false
  step "Configuring LetsEncrypt.."
  systemctl stop nginx || true
  certbot certonly --no-eff-email --email "$EMAIL" --standalone -d "$FQDN" || FAILED=true
  systemctl start nginx || true

  if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == true ]; then
    warn "Let's Encrypt certificate failed!"
  else
    ok "Let's Encrypt certificate succeeded!"
  fi
}

configure_mysql() {
  step "Configuring MySQL.."
  create_db_user "$MYSQL_DBHOST_USER" "$MYSQL_DBHOST_PASSWORD" "$MYSQL_DBHOST_HOST"
  grant_all_privileges "*" "$MYSQL_DBHOST_USER" "$MYSQL_DBHOST_HOST"

  if [ "$MYSQL_DBHOST_HOST" != "127.0.0.1" ]; then
    echo "* Changing MySQL bind address.."
    case "$OS" in
    debian | ubuntu) sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/mariadb.conf.d/50-server.cnf ;;
    rocky | almalinux) sed -ne 's/^#bind-address=0.0.0.0$/bind-address=0.0.0.0/' /etc/my.cnf.d/mariadb-server.cnf ;;
    esac
    systemctl restart mysqld
  fi
  ok "MySQL configured!"
}

perform_install() {
  step "Installing pterodactyl wings.."
  dep_install
  ptdl_dl
  systemd_file
  [ "$CONFIGURE_DBHOST" == true ] && configure_mysql
  [ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt
  return 0
}

perform_install