#!/usr/bin/env bash
set -euo pipefail

GLPI_VERSION="10.0.16"
GLPI_ARCHIVE="glpi-${GLPI_VERSION}.tgz"
GLPI_URL="https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/${GLPI_ARCHIVE}"
WEBROOT="/var/www/html/glpi"

echo "==> Mise à jour des paquets..."
apt-get update -qq

echo "==> Installation d'Apache, PHP et MariaDB..."
apt-get install -y -qq \
  apache2 \
  mariadb-server \
  php php-mysql php-xml php-mbstring php-curl php-gd \
  php-intl php-zip php-cli \
  wget tar

echo "==> Installation des extensions PHP optionnelles..."
apt-get install -y -qq php-ldap php-apcu php-bz2 2>/dev/null || true

echo "==> Démarrage de MariaDB..."
systemctl enable --now mariadb

echo "==> Création de la base de données GLPI..."
mysql -u root <<'SQL'
CREATE DATABASE IF NOT EXISTS glpi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'glpi'@'localhost' IDENTIFIED BY 'glpi_password';
GRANT ALL PRIVILEGES ON glpi.* TO 'glpi'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "==> Téléchargement de GLPI ${GLPI_VERSION}..."
wget -qO "/tmp/${GLPI_ARCHIVE}" "${GLPI_URL}"

echo "==> Extraction dans ${WEBROOT}..."
tar -xzf "/tmp/${GLPI_ARCHIVE}" -C /var/www/html/
chown -R www-data:www-data "${WEBROOT}"
chmod -R 755 "${WEBROOT}"

echo "==> Configuration Apache..."
cat > /etc/apache2/sites-available/glpi.conf <<'VHOST'
<VirtualHost *:80>
    DocumentRoot /var/www/html/glpi/public
    <Directory /var/www/html/glpi/public>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
VHOST

a2ensite glpi.conf
a2enmod rewrite
a2dissite 000-default.conf
systemctl reload apache2

echo ""
echo "✓ GLPI installé. Ouvre http://<IP_DU_SERVEUR> pour finaliser la configuration."
echo "  Base de données : glpi | Utilisateur : glpi | Mot de passe : glpi_password"
