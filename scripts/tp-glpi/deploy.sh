#!/usr/bin/env bash
set -euo pipefail

# ── Vérifications ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "ERREUR : root requis." >&2; exit 1
fi
if ! command -v pct &>/dev/null; then
  echo "ERREUR : lance ce script directement sur le nœud Proxmox." >&2; exit 1
fi

# ── Config CT ─────────────────────────────────────────────────────────────────
CT_HOSTNAME="glpi"
CT_PASSWORD="changeme"
CT_CORES=2
CT_RAM=2048
CT_DISK=15
CT_STORAGE="${CT_STORAGE:-local-lvm}"
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"

# ── ID automatique ────────────────────────────────────────────────────────────
echo "==> Recherche d'un ID CT libre..."
CT_ID=100
while pct status "$CT_ID" &>/dev/null 2>&1 || qm status "$CT_ID" &>/dev/null 2>&1; do
  CT_ID=$((CT_ID + 1))
done
echo "    ID retenu : ${CT_ID}"

# ── Template Debian 12 (détection automatique) ────────────────────────────────
echo "==> Mise à jour de la liste des templates..."
pveam update

echo "==> Recherche du template Debian 12 disponible..."
TEMPLATE=$(pveam available --section system 2>/dev/null \
  | awk '{print $2}' \
  | grep -i "^debian-12" \
  | sort -V | tail -1)

if [ -z "${TEMPLATE}" ]; then
  echo "ERREUR : aucun template Debian 12 trouvé dans pveam." >&2
  echo "  Templates disponibles :" >&2
  pveam available --section system 2>/dev/null | awk '{print "  " $2}' >&2
  exit 1
fi
echo "    Template retenu : ${TEMPLATE}"

if [ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]; then
  echo "==> Téléchargement du template..."
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
else
  echo "==> Template déjà disponible."
fi

# ── Création du CT ────────────────────────────────────────────────────────────
echo "==> Création du CT ${CT_ID} (${CT_HOSTNAME})..."
pct create "${CT_ID}" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname "${CT_HOSTNAME}" \
  --password "${CT_PASSWORD}" \
  --cores "${CT_CORES}" \
  --memory "${CT_RAM}" \
  --rootfs "${CT_STORAGE}:${CT_DISK}" \
  --net0 "name=eth0,bridge=${CT_BRIDGE},ip=dhcp" \
  --onboot 1 \
  --features nesting=1 \
  --unprivileged 1

echo "==> Démarrage du CT..."
pct start "${CT_ID}"
sleep 6

# ── Script d'installation à exécuter dans le CT ───────────────────────────────
cat > /tmp/glpi_inner.sh << 'INNER'
#!/usr/bin/env bash
set -euo pipefail

GLPI_VERSION="10.0.16"
GLPI_ARCHIVE="glpi-${GLPI_VERSION}.tgz"
GLPI_URL="https://github.com/glpi-project/glpi/releases/download/${GLPI_VERSION}/${GLPI_ARCHIVE}"
WEBROOT="/var/www/html/glpi"
DB_NAME="glpi"
DB_USER="glpi"
DB_PASS="glpi_password"

echo "[CT] Ajout des dépôts Debian complets..."
SOURCES="/etc/apt/sources.list"
if ! grep -q "deb.debian.org" "$SOURCES" 2>/dev/null; then
  cat >> "$SOURCES" << REPOS
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib
REPOS
fi

echo "[CT] Mise à jour..."
apt-get update -y -qq

echo "[CT] Installation Apache + MariaDB + PHP..."
apt-get install -y \
  apache2 mariadb-server \
  php php-mysql php-xml php-mbstring php-curl php-gd \
  php-intl php-zip php-bz2 php-cli php-ldap \
  wget tar

echo "[CT] Extensions optionnelles..."
for pkg in php-apcu; do
  apt-get install -y "$pkg" 2>/dev/null && echo "  ✓ $pkg" || echo "  - $pkg ignoré"
done

echo "[CT] Démarrage MariaDB..."
systemctl enable mariadb
systemctl start mariadb

echo "[CT] Création de la base de données..."
mysql -u root << SQL
CREATE DATABASE IF NOT EXISTS glpi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'glpi'@'localhost' IDENTIFIED BY 'glpi_password';
GRANT ALL PRIVILEGES ON glpi.* TO 'glpi'@'localhost';
FLUSH PRIVILEGES;
SQL

echo "[CT] Téléchargement de GLPI ${GLPI_VERSION}..."
wget -q --show-progress -O "/tmp/${GLPI_ARCHIVE}" "${GLPI_URL}"

echo "[CT] Extraction..."
tar -xzf "/tmp/${GLPI_ARCHIVE}" -C /var/www/html/
rm -f "/tmp/${GLPI_ARCHIVE}"

chown -R www-data:www-data "${WEBROOT}"
find "${WEBROOT}" -type d -exec chmod 755 {} \;
find "${WEBROOT}" -type f -exec chmod 644 {} \;

echo "[CT] Configuration Apache..."
cat > /etc/apache2/sites-available/glpi.conf << VHOST
<VirtualHost *:80>
    DocumentRoot /var/www/html/glpi/public
    <Directory /var/www/html/glpi/public>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/glpi_error.log
    CustomLog \${APACHE_LOG_DIR}/glpi_access.log combined
</VirtualHost>
VHOST

a2ensite glpi.conf
a2enmod rewrite
a2dissite 000-default.conf 2>/dev/null || true
systemctl enable apache2
systemctl restart apache2

echo "[CT] Installation terminée."
INNER

# ── Exécution dans le CT ──────────────────────────────────────────────────────
echo "==> Copie et exécution du script dans le CT ${CT_ID}..."
pct push "${CT_ID}" /tmp/glpi_inner.sh /tmp/install.sh --perms 0755
pct exec "${CT_ID}" -- bash /tmp/install.sh

# ── Résumé ────────────────────────────────────────────────────────────────────
CT_IP=$(pct exec "${CT_ID}" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "voir Proxmox")
echo ""
echo "============================================="
echo "  GLPI installé dans le CT ${CT_ID} !"
echo "============================================="
echo ""
echo "  CT ID           : ${CT_ID}"
echo "  URL GLPI        : http://${CT_IP}"
echo "  DB Name         : glpi"
echo "  DB User         : glpi"
echo "  DB Password     : glpi_password"
echo ""
echo "  Accès shell     : pct enter ${CT_ID}"
echo ""
