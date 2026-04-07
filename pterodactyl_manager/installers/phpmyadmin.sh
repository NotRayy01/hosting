#!/bin/bash
set -e


RAY_REPO="https://raw.githubusercontent.com/NotRayy01/hosting/refs/heads/main/pterodactyl_manager"

fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  source <(curl -sSL "$RAY_REPO/lib/lib.sh")
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

# Override default lib functions with Ray UI
output() { step "$1"; }
success() { ok "$1"; }
error() { err "$1"; }
warning() { warn "$1"; }

PMA_DIR="/var/www/pterodactyl/public/pma"

main() {
  clear
  print_brake
  echo -e "${BOLD} 🐘 Ray PhpMyAdmin Installer ${NC}"
  echo -e " 👑 Developed by Ray | 🏢 Ray Industries"
  print_brake
  
  if [ ! -d "/var/www/pterodactyl/public" ]; then
      err "Pterodactyl Panel is not installed. Install it first!"
      exit 1
  fi

  if [ -d "$PMA_DIR" ]; then
      warn "PhpMyAdmin is already installed!"
      echo -e -n " ${CYAN}➤${NC} Do you want to reinstall/update it? (y/N): "
      read -r CONFIRM
      [[ ! "$CONFIRM" =~ [Yy] ]] && exit 0
      rm -rf "$PMA_DIR"
  fi

  step "Fetching latest phpMyAdmin release..."
  PMA_LATEST=$(curl -s "https://api.github.com/repos/phpmyadmin/phpmyadmin/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  PMA_VERSION=${PMA_LATEST#RELEASE_}
  PMA_VERSION=${PMA_VERSION//_/-}
  
  info "Latest version: $PMA_VERSION"

  step "Downloading and extracting..."
  cd /tmp
  wget -q "https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.zip"
  
  update_repos true
  install_packages "unzip" true

  unzip -q "phpMyAdmin-${PMA_VERSION}-all-languages.zip"
  mv "phpMyAdmin-${PMA_VERSION}-all-languages" "$PMA_DIR"
  rm "phpMyAdmin-${PMA_VERSION}-all-languages.zip"

  step "Configuring phpMyAdmin..."
  cp "$PMA_DIR/config.sample.inc.php" "$PMA_DIR/config.inc.php"
  
  # Generate a secure blowfish secret
  BLOWFISH=$(tr -dc 'a-zA-Z0-9~!@#$%^&*_()+}{?></";.,[]=-' < /dev/urandom | fold -w 32 | head -n 1)
  sed -i "s/\$cfg\['blowfish_secret'\] = '';/\$cfg\['blowfish_secret'\] = '${BLOWFISH}';/" "$PMA_DIR/config.inc.php"

  # Force PMA to use the local socket to match Pterodactyl's MariaDB
  echo "\$cfg['Servers'][\$i]['socket'] = '/run/mysqld/mysqld.sock';" >> "$PMA_DIR/config.inc.php"

  chown -R www-data:www-data "$PMA_DIR" 2>/dev/null || chown -R nginx:nginx "$PMA_DIR" 2>/dev/null
  
  echo ""
  print_brake
  ok "phpMyAdmin installed successfully!"
  info "You can access it by going to your panel URL and adding /pma at the end."
  info "Example: https://panel.yourdomain.com/pma"
  print_brake
}

main