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
CT_HOSTNAME="adguard"
CT_PASSWORD="changeme"
CT_CORES=1
CT_RAM=512
CT_DISK=4
CT_STORAGE="${CT_STORAGE:-local-lvm}"
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"

# ── ID automatique ────────────────────────────────────────────────────────────
echo "==> Recherche d'un ID CT libre..."
CT_ID=100
while pct status "$CT_ID" &>/dev/null 2>&1 || qm status "$CT_ID" &>/dev/null 2>&1; do
  CT_ID=$((CT_ID + 1))
done
echo "    ID retenu : ${CT_ID}"

# ── Template Debian 12 ────────────────────────────────────────────────────────
if [ ! -f "/var/lib/vz/template/cache/${TEMPLATE}" ]; then
  echo "==> Téléchargement du template Debian 12..."
  pveam update
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
else
  echo "==> Template Debian 12 déjà disponible."
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
  --unprivileged 1

echo "==> Démarrage du CT..."
pct start "${CT_ID}"
sleep 6

# ── Script d'installation à exécuter dans le CT ───────────────────────────────
cat > /tmp/adguard_inner.sh << 'INNER'
#!/usr/bin/env bash
set -euo pipefail

echo "[CT] Installation des dépendances..."
apt-get update -y -qq
apt-get install -y curl tar

echo "[CT] Installation d'AdGuard Home..."
curl -fsSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v

echo "[CT] Installation terminée."
INNER

# ── Exécution dans le CT ──────────────────────────────────────────────────────
echo "==> Copie et exécution du script dans le CT ${CT_ID}..."
pct push "${CT_ID}" /tmp/adguard_inner.sh /tmp/install.sh --perms 0755
pct exec "${CT_ID}" -- bash /tmp/install.sh

# ── Résumé ────────────────────────────────────────────────────────────────────
CT_IP=$(pct exec "${CT_ID}" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "voir Proxmox")
echo ""
echo "============================================="
echo "  AdGuard Home installé dans le CT ${CT_ID} !"
echo "============================================="
echo ""
echo "  CT ID              : ${CT_ID}"
echo "  Interface web      : http://${CT_IP}:3000"
echo "  DNS à configurer   : ${CT_IP}"
echo ""
echo "  Accès shell        : pct enter ${CT_ID}"
echo ""
