#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "ERREUR : root requis." >&2
  exit 1
fi

if ! command -v pct >/dev/null 2>&1; then
  echo "ERREUR : lance ce script directement sur le noeud Proxmox." >&2
  exit 1
fi

CT_HOSTNAME="${CT_HOSTNAME:-dns-web}"
CT_PASSWORD="${CT_PASSWORD:-changeme}"
CT_CORES="${CT_CORES:-2}"
CT_RAM="${CT_RAM:-1024}"
CT_DISK="${CT_DISK:-6}"
CT_STORAGE="${CT_STORAGE:-local-lvm}"
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
LAB_DOMAIN="${LAB_DOMAIN:-lab.local}"
SITE_NAME="${SITE_NAME:-monsite}"
DNS_FORWARDER_1="${DNS_FORWARDER_1:-8.8.8.8}"
DNS_FORWARDER_2="${DNS_FORWARDER_2:-1.1.1.1}"

SITE_FQDN="${SITE_NAME}.${LAB_DOMAIN}"
NS_FQDN="ns.${LAB_DOMAIN}"

echo "==> Recherche d'un ID CT libre..."
CT_ID=100
while pct status "$CT_ID" >/dev/null 2>&1 || qm status "$CT_ID" >/dev/null 2>&1; do
  CT_ID=$((CT_ID + 1))
done
echo "    ID retenu : ${CT_ID}"

echo "==> Mise a jour de la liste des templates..."
pveam update

echo "==> Recherche du template Debian 12 disponible..."
TEMPLATE="$(
  pveam available --section system 2>/dev/null \
    | awk '{print $2}' \
    | grep -i '^debian-12' \
    | sort -V \
    | tail -1
)"

if [ -z "${TEMPLATE}" ]; then
  echo "ERREUR : aucun template Debian 12 trouve dans pveam." >&2
  exit 1
fi
echo "    Template retenu : ${TEMPLATE}"

if [ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]; then
  echo "==> Telechargement du template..."
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
else
  echo "==> Template deja disponible."
fi

echo "==> Creation du CT ${CT_ID} (${CT_HOSTNAME})..."
pct create "${CT_ID}" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname "${CT_HOSTNAME}" \
  --password "${CT_PASSWORD}" \
  --cores "${CT_CORES}" \
  --memory "${CT_RAM}" \
  --rootfs "${CT_STORAGE}:${CT_DISK}" \
  --net0 "name=eth0,bridge=${CT_BRIDGE},ip=dhcp" \
  --nameserver "${DNS_FORWARDER_1} ${DNS_FORWARDER_2}" \
  --searchdomain "${LAB_DOMAIN}" \
  --onboot 1 \
  --features nesting=1 \
  --unprivileged 1

echo "==> Demarrage du CT..."
pct start "${CT_ID}"
sleep 8

cat > /tmp/dns_apache_nginx_inner.sh <<INNER
#!/usr/bin/env bash
set -euo pipefail

LAB_DOMAIN="${LAB_DOMAIN}"
SITE_NAME="${SITE_NAME}"
SITE_FQDN="${SITE_FQDN}"
NS_FQDN="${NS_FQDN}"
DNS_FORWARDER_1="${DNS_FORWARDER_1}"
DNS_FORWARDER_2="${DNS_FORWARDER_2}"

echo "[CT] Mise a jour..."
apt-get update -y -qq

echo "[CT] Installation des paquets..."
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  bind9 bind9-utils bind9-dnsutils dnsutils \
  apache2 nginx curl

CT_IP=\$(hostname -I | awk '{print \$1}')
if [ -z "\${CT_IP}" ]; then
  echo "[CT] ERREUR : impossible de detecter l'adresse IP du CT." >&2
  exit 1
fi

IFS='.' read -r OCT1 OCT2 OCT3 OCT4 <<< "\${CT_IP}"
REV_ZONE="\${OCT3}.\${OCT2}.\${OCT1}.in-addr.arpa"
REV_FILE="/etc/bind/zones/db.\${OCT1}.\${OCT2}.\${OCT3}"
LAN_CIDR="\${OCT1}.\${OCT2}.\${OCT3}.0/24"
SERIAL=\$(date +%Y%m%d%H)

echo "[CT] Configuration BIND9 pour \${SITE_FQDN} -> \${CT_IP}..."
mkdir -p /etc/bind/zones

cat > /etc/bind/named.conf.options <<EOF
options {
    directory "/var/cache/bind";

    forwarders {
        ${DNS_FORWARDER_1};
        ${DNS_FORWARDER_2};
    };

    allow-query { localhost; \${LAN_CIDR}; };
    listen-on { any; };
    listen-on-v6 { any; };
    recursion yes;
    allow-recursion { localhost; \${LAN_CIDR}; };
    dnssec-validation no;
    forward only;
};
EOF

cat > /etc/bind/named.conf.local <<EOF
zone "${LAB_DOMAIN}" {
    type master;
    file "/etc/bind/zones/db.${LAB_DOMAIN}";
};

zone "\${REV_ZONE}" {
    type master;
    file "\${REV_FILE}";
};
EOF

cat > /etc/bind/zones/db.${LAB_DOMAIN} <<EOF
\$TTL    604800
@   IN  SOA     ${NS_FQDN}. admin.${LAB_DOMAIN}. (
                    \${SERIAL} ; Serial
                    604800     ; Refresh
                    86400      ; Retry
                    2419200    ; Expire
                    604800 )   ; Negative Cache TTL

@       IN  NS      ${NS_FQDN}.
ns      IN  A       \${CT_IP}
${SITE_NAME}  IN  A \${CT_IP}
www.${SITE_NAME} IN A \${CT_IP}
EOF

cat > "\${REV_FILE}" <<EOF
\$TTL    604800
@   IN  SOA     ${NS_FQDN}. admin.${LAB_DOMAIN}. (
                    \${SERIAL} ; Serial
                    604800     ; Refresh
                    86400      ; Retry
                    2419200    ; Expire
                    604800 )   ; Negative Cache TTL

@       IN  NS      ${NS_FQDN}.
\${OCT4}    IN  PTR     ${SITE_FQDN}.
EOF

named-checkconf
named-checkzone "${LAB_DOMAIN}" "/etc/bind/zones/db.${LAB_DOMAIN}"
named-checkzone "\${REV_ZONE}" "\${REV_FILE}"
systemctl enable bind9
systemctl restart bind9

echo "[CT] Resolver local..."
cat > /etc/resolv.conf <<EOF
nameserver 127.0.0.1
search ${LAB_DOMAIN}
EOF

echo "[CT] Configuration Apache2..."
mkdir -p /var/www/${SITE_NAME}
cat > /var/www/${SITE_NAME}/index.html <<EOF
<!doctype html>
<html lang="fr">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>${SITE_FQDN}</title>
    <style>
      body {
        margin: 0;
        min-height: 100vh;
        display: grid;
        place-items: center;
        background:
          radial-gradient(circle at top, rgba(59, 130, 246, 0.18), transparent 40%),
          linear-gradient(135deg, #0f172a, #111827 60%, #1e293b);
        color: #e5eefc;
        font-family: Arial, sans-serif;
      }
      main {
        width: min(760px, calc(100% - 32px));
        padding: 32px;
        border: 1px solid rgba(148, 163, 184, 0.25);
        border-radius: 24px;
        background: rgba(15, 23, 42, 0.88);
        box-shadow: 0 24px 80px rgba(15, 23, 42, 0.45);
      }
      h1 {
        margin-top: 0;
        font-size: clamp(2rem, 5vw, 3.4rem);
      }
      p {
        line-height: 1.7;
        color: #cbd5e1;
      }
      .stack {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        margin: 24px 0;
      }
      .pill {
        padding: 8px 14px;
        border-radius: 999px;
        background: rgba(59, 130, 246, 0.14);
        border: 1px solid rgba(96, 165, 250, 0.35);
      }
      code {
        color: #93c5fd;
      }
    </style>
  </head>
  <body>
    <main>
      <p>TP automatise</p>
      <h1>${SITE_FQDN}</h1>
      <p>
        Apache2 sert cette page sur le port 80, Nginx la publie en reverse proxy
        sur le port 8080, et BIND9 resout le nom de domaine local.
      </p>
      <div class="stack">
        <span class="pill">DNS: ${SITE_FQDN}</span>
        <span class="pill">IP: <code>\${CT_IP}</code></span>
        <span class="pill">Apache2:80</span>
        <span class="pill">Nginx:8080</span>
      </div>
      <p>Tests rapides :</p>
      <p><code>dig @127.0.0.1 ${SITE_FQDN}</code></p>
      <p><code>curl -I http://${SITE_FQDN}</code></p>
      <p><code>curl -I http://\${CT_IP}:8080</code></p>
    </main>
  </body>
</html>
EOF

cat > /etc/apache2/sites-available/${SITE_NAME}.conf <<EOF
<VirtualHost *:80>
    ServerName ${SITE_FQDN}
    ServerAlias www.${SITE_FQDN}

    DocumentRoot /var/www/${SITE_NAME}

    <Directory /var/www/${SITE_NAME}>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${SITE_NAME}_error.log
    CustomLog \${APACHE_LOG_DIR}/${SITE_NAME}_access.log combined
</VirtualHost>
EOF

a2dissite 000-default.conf >/dev/null 2>&1 || true
a2ensite ${SITE_NAME}.conf >/dev/null
apache2ctl configtest
systemctl enable apache2
systemctl reload apache2

echo "[CT] Configuration Nginx..."
rm -f /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/${SITE_NAME}-proxy.conf <<EOF
server {
    listen 8080;
    server_name ${SITE_FQDN} \${CT_IP};

    access_log /var/log/nginx/${SITE_NAME}_access.log;
    error_log  /var/log/nginx/${SITE_NAME}_error.log;

    location / {
        proxy_pass http://127.0.0.1:80;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/${SITE_NAME}-proxy.conf /etc/nginx/sites-enabled/${SITE_NAME}-proxy.conf
nginx -t
systemctl enable nginx
systemctl restart nginx

echo "[CT] Validations locales..."
dig @127.0.0.1 ${SITE_FQDN} +short
curl -fsSI "http://127.0.0.1" >/dev/null
curl -fsSI "http://\${CT_IP}:8080" >/dev/null

echo "[CT] Installation terminee."
INNER

echo "==> Copie et execution du script dans le CT ${CT_ID}..."
pct push "${CT_ID}" /tmp/dns_apache_nginx_inner.sh /tmp/install.sh --perms 0755
pct exec "${CT_ID}" -- bash /tmp/install.sh

CT_IP="$(pct exec "${CT_ID}" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "voir Proxmox")"

echo ""
echo "============================================="
echo "  TP DNS + Apache2 + Nginx installe !"
echo "============================================="
echo ""
echo "  CT ID             : ${CT_ID}"
echo "  Nom du CT         : ${CT_HOSTNAME}"
echo "  IP du CT          : ${CT_IP}"
echo "  DNS local         : ${SITE_FQDN}"
echo "  Apache2           : http://${SITE_FQDN}"
echo "  Reverse proxy     : http://${CT_IP}:8080"
echo ""
echo "  Tests utiles :"
echo "    pct enter ${CT_ID}"
echo "    dig @127.0.0.1 ${SITE_FQDN}"
echo "    curl -I http://${SITE_FQDN}"
echo "    curl -I http://${CT_IP}:8080"
echo ""
