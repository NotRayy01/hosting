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

# Check if script is loaded, load if not from Ray's Repo
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
FQDN="${FQDN:-localhost}"
MYSQL_DB="${MYSQL_DB:-panel}"
MYSQL_USER="${MYSQL_USER:-pterodactyl}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(gen_passwd 64)}"
timezone="${timezone:-Europe/Stockholm}"
ASSUME_SSL="${ASSUME_SSL:-false}"
CONFIGURE_LETSENCRYPT="${CONFIGURE_LETSENCRYPT:-false}"
CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-false}"

email="${email:-}"
user_email="${user_email:-}"
user_username="${user_username:-}"
user_firstname="${user_firstname:-}"
user_lastname="${user_lastname:-}"
user_password="${user_password:-}"

missing=()
for var in email user_email user_username user_firstname user_lastname user_password; do
  if [[ -z "${!var}" ]]; then
    missing+=("$var")
  fi
done

if (( ${#missing[@]} > 0 )); then
  for m in "${missing[@]}"; do
    err "${m} is required"
  done
  exit 1
fi

# --------- Main installation functions -------- #

install_composer() {
  step "Installing composer.."
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  ok "Composer installed!"
}

ptdl_dl() {
  step "Downloading pterodactyl panel files .. "
  mkdir -p /var/www/pterodactyl
  cd /var/www/pterodactyl || exit

  curl -Lo panel.tar.gz "$PANEL_DL_URL"
  tar -xzvf panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/

  cp .env.example .env

  ok "Downloaded pterodactyl panel files!"
}

install_composer_deps() {
  step "Installing composer dependencies.."
  [ "$OS" == "rocky" ] || [ "$OS" == "almalinux" ] && export PATH=/usr/local/bin:$PATH
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
  ok "Installed composer dependencies!"
}

configure() {
  step "Configuring environment.."

  local app_url="http://$FQDN"
  [ "$ASSUME_SSL" == true ] && app_url="https://$FQDN"
  [ "$CONFIGURE_LETSENCRYPT" == true ] && app_url="https://$FQDN"

  php artisan key:generate --force
  php artisan p:environment:setup \
    --author="$email" --url="$app_url" --timezone="$timezone" \
    --cache="redis" --session="redis" --queue="redis" \
    --redis-host="localhost" --redis-pass="null" --redis-port="6379" --settings-ui=true

  php artisan p:environment:database \
    --host="127.0.0.1" --port="3306" --database="$MYSQL_DB" \
    --username="$MYSQL_USER" --password="$MYSQL_PASSWORD"

  php artisan migrate --seed --force

  php artisan p:user:make \
    --email="$user_email" --username="$user_username" \
    --name-first="$user_firstname" --name-last="$user_lastname" \
    --password="$user_password" --admin=1

  ok "Configured environment!"
}

set_folder_permissions() {
  case "$OS" in
  debian | ubuntu) chown -R www-data:www-data ./* ;;
  rocky | almalinux) chown -R nginx:nginx ./* ;;
  esac
}

insert_cronjob() {
  step "Installing cronjob.. "
  crontab -l | {
    cat
    echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1"
  } | crontab -
  ok "Cronjob installed!"
}

install_pteroq() {
  step "Installing pteroq service.."
  curl -o /etc/systemd/system/pteroq.service "$RAY_REPO/configs/pteroq.service"

  case "$OS" in
  debian | ubuntu) sed -i -e "s@<user>@www-data@g" /etc/systemd/system/pteroq.service ;;
  rocky | almalinux) sed -i -e "s@<user>@nginx@g" /etc/systemd/system/pteroq.service ;;
  esac

  systemctl enable pteroq.service
  systemctl start pteroq
  ok "Installed pteroq!"
}

# -------- OS specific install functions ------- #

enable_services() {
  case "$OS" in
  ubuntu | debian) systemctl enable redis-server && systemctl start redis-server ;;
  rocky | almalinux) systemctl enable redis && systemctl start redis ;;
  esac
  systemctl enable nginx
  systemctl enable mariadb
  systemctl start mariadb
}

selinux_allow() {
  setsebool -P httpd_can_network_connect 1 || true
  setsebool -P httpd_execmem 1 || true
  setsebool -P httpd_unified 1 || true
}

php_fpm_conf() {
  curl -o /etc/php-fpm.d/www-pterodactyl.conf "$RAY_REPO/configs/www-pterodactyl.conf"
  systemctl enable php-fpm
  systemctl start php-fpm
}

ubuntu_dep() {
  install_packages "software-properties-common apt-transport-https ca-certificates gnupg"
  add-apt-repository universe -y
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
}

debian_dep() {
  install_packages "dirmngr ca-certificates apt-transport-https lsb-release"
  curl -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
}

alma_rocky_dep() {
  install_packages "policycoreutils selinux-policy selinux-policy-targeted setroubleshoot-server setools setools-console mcstrans"
  install_packages "epel-release http://rpms.remirepo.net/enterprise/remi-release-$OS_VER_MAJOR.rpm"
  dnf module enable -y php:remi-8.3
}

dep_install() {
  step "Installing dependencies for $OS $OS_VER..."
  update_repos
  [ "$CONFIGURE_FIREWALL" == true ] && install_firewall && firewall_ports

  case "$OS" in
  ubuntu | debian)
    [ "$OS" == "ubuntu" ] && ubuntu_dep
    [ "$OS" == "debian" ] && debian_dep
    update_repos
    install_packages "php8.3 php8.3-{cli,common,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-common mariadb-server mariadb-client nginx redis-server zip unzip tar git cron"
    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot python3-certbot-nginx"
    ;;
  rocky | almalinux)
    alma_rocky_dep
    install_packages "php php-{common,fpm,cli,json,mysqlnd,mcrypt,gd,mbstring,pdo,zip,bcmath,dom,opcache,posix} mariadb mariadb-server nginx redis zip unzip tar git cronie"
    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot python3-certbot-nginx"
    selinux_allow
    php_fpm_conf
    ;;
  esac

  enable_services
  ok "Dependencies installed!"
}

firewall_ports() {
  step "Opening ports: 22 (SSH), 80 (HTTP) and 443 (HTTPS)"
  firewall_allow_ports "22 80 443"
  ok "Firewall ports opened!"
}

letsencrypt() {
  FAILED=false
  step "Configuring Let's Encrypt..."
  certbot --nginx --redirect --no-eff-email --email "$email" -d "$FQDN" || FAILED=true

  if [ ! -d "/etc/letsencrypt/live/$FQDN/" ] || [ "$FAILED" == true ]; then
    warn "Let's Encrypt certificate failed!"
    echo -n "ℹ️  Still assume SSL? (y/N): "
    read -r CONFIGURE_SSL
    if [[ "$CONFIGURE_SSL" =~ [Yy] ]]; then
      ASSUME_SSL=true
      CONFIGURE_LETSENCRYPT=false
      configure_nginx
    else
      ASSUME_SSL=false
      CONFIGURE_LETSENCRYPT=false
    fi
  else
    ok "Let's Encrypt certificate succeeded!"
  fi
}

configure_nginx() {
  step "Configuring nginx .."
  if [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then DL_FILE="nginx_ssl.conf"
  else DL_FILE="nginx.conf"; fi

  case "$OS" in
  ubuntu | debian)
    PHP_SOCKET="/run/php/php8.3-fpm.sock"
    CONFIG_PATH_AVAIL="/etc/nginx/sites-available"
    CONFIG_PATH_ENABL="/etc/nginx/sites-enabled"
    ;;
  rocky | almalinux)
    PHP_SOCKET="/var/run/php-fpm/pterodactyl.sock"
    CONFIG_PATH_AVAIL="/etc/nginx/conf.d"
    CONFIG_PATH_ENABL="$CONFIG_PATH_AVAIL"
    ;;
  esac

  rm -rf "$CONFIG_PATH_ENABL"/default
  curl -o "$CONFIG_PATH_AVAIL"/pterodactyl.conf "$RAY_REPO/configs/$DL_FILE"

  sed -i -e "s@<domain>@${FQDN}@g" "$CONFIG_PATH_AVAIL"/pterodactyl.conf
  sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" "$CONFIG_PATH_AVAIL"/pterodactyl.conf

  case "$OS" in
  ubuntu | debian) ln -sf "$CONFIG_PATH_AVAIL"/pterodactyl.conf "$CONFIG_PATH_ENABL"/pterodactyl.conf ;;
  esac

  if [ "$ASSUME_SSL" == false ] && [ "$CONFIGURE_LETSENCRYPT" == false ]; then systemctl restart nginx; fi
  ok "Nginx configured!"
}

perform_install() {
  step "Starting Panel installation.. this might take a while!"
  dep_install
  install_composer
  ptdl_dl
  install_composer_deps
  create_db_user "$MYSQL_USER" "$MYSQL_PASSWORD"
  create_db "$MYSQL_DB" "$MYSQL_USER"
  configure
  set_folder_permissions
  insert_cronjob
  install_pteroq
  configure_nginx
  [ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt
  return 0
}

perform_install