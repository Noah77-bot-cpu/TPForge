#!/usr/bin/env bash
set -euo pipefail

# ── Variables ────────────────────────────────────────────────────────────────
GLPI_VERSION="10.0.16"
GLPI_ARCHIVE="glpi-${GLPI_VERSION}.tgz"
GLPI_URL="https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/${GLPI_ARCHIVE}"
WEBROOT="/var/www/html/glpi"
DB_NAME="glpi"
DB_USER="glpi"
DB_PASS="glpi_password"

# ── Vérifications ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "ERREUR : ce script doit être lancé en root." >&2
  exit 1
fi

# ── Dépôts Debian (Proxmox n'active pas toujours les dépôts complets) ────────
echo "==> Vérification des dépôts Debian..."
SOURCES="/etc/apt/sources.list"
if ! grep -q "^deb http://deb.debian.org/debian bookworm main" "$SOURCES" 2>/dev/null; then
  echo "deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware" >> "$SOURCES"
  echo "deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware" >> "$SOURCES"
  echo "deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware" >> "$SOURCES"
  echo "  Dépôts Debian ajoutés."
fi

echo "==> Mise à jour des paquets..."
apt-get update -y

# ── Apache + MariaDB + PHP ────────────────────────────────────────────────────
echo "==> Installation d'Apache, MariaDB et PHP..."
apt-get install -y \
  apache2 \
  mariadb-server \
  php \
  php-mysql \
  php-xml \
  php-mbstring \
  php-curl \
  php-gd \
  php-intl \
  php-zip \
  php-bz2 \
  php-cli \
  php-ldap \
  wget \
  tar

# Extensions vraiment optionnelles
echo "==> Extensions PHP optionnelles (ignorées si absentes)..."
for pkg in php-apcu php-imap; do
  if apt-get install -y "$pkg" 2>/dev/null; then
    echo "  ✓ $pkg installé"
  else
    echo "  - $pkg non disponible, ignoré"
  fi
done

# ── MariaDB ───────────────────────────────────────────────────────────────────
echo "==> Démarrage de MariaDB..."
systemctl enable mariadb
systemctl start mariadb

echo "==> Création de la base de données GLPI..."
mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# ── GLPI ──────────────────────────────────────────────────────────────────────
echo "==> Téléchargement de GLPI ${GLPI_VERSION}..."
wget -q --show-progress -O "/tmp/${GLPI_ARCHIVE}" "${GLPI_URL}"

echo "==> Extraction dans ${WEBROOT}..."
tar -xzf "/tmp/${GLPI_ARCHIVE}" -C /var/www/html/
rm -f "/tmp/${GLPI_ARCHIVE}"

echo "==> Application des permissions..."
chown -R www-data:www-data "${WEBROOT}"
find "${WEBROOT}" -type d -exec chmod 755 {} \;
find "${WEBROOT}" -type f -exec chmod 644 {} \;

# ── Apache ────────────────────────────────────────────────────────────────────
echo "==> Configuration d'Apache..."
cat > /etc/apache2/sites-available/glpi.conf <<'VHOST'
<VirtualHost *:80>
    DocumentRoot /var/www/html/glpi/public
    <Directory /var/www/html/glpi/public>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog ${APACHE_LOG_DIR}/glpi_error.log
    CustomLog ${APACHE_LOG_DIR}/glpi_access.log combined
</VirtualHost>
VHOST

a2ensite glpi.conf
a2enmod rewrite
a2dissite 000-default.conf 2>/dev/null || true

systemctl enable apache2
systemctl restart apache2

# ── Résumé ────────────────────────────────────────────────────────────────────
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "============================================="
echo "  GLPI ${GLPI_VERSION} installé avec succès !"
echo "============================================="
echo ""
echo "  URL             : http://${IP}"
echo "  Hôte DB         : localhost"
echo "  Nom DB          : ${DB_NAME}"
echo "  Utilisateur DB  : ${DB_USER}"
echo "  Mot de passe DB : ${DB_PASS}"
echo ""
echo "  Ouvre l'URL dans un navigateur pour finaliser l'installation."
echo ""
