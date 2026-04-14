#!/usr/bin/env bash
set -euo pipefail

# ── Vérifications ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "ERREUR : ce script doit être lancé en root sur le nœud Proxmox." >&2
  exit 1
fi

if ! command -v pct &>/dev/null; then
  echo "ERREUR : commande 'pct' introuvable. Lance ce script directement sur Proxmox VE." >&2
  exit 1
fi

# ── Paramètres du CT (modifie selon tes besoins) ─────────────────────────────
CT_ID="${CT_ID:-200}"
CT_HOSTNAME="${CT_HOSTNAME:-mon-ct}"
CT_PASSWORD="${CT_PASSWORD:-changeme}"
CT_CORES="${CT_CORES:-2}"
CT_RAM="${CT_RAM:-2048}"       # en MB
CT_DISK="${CT_DISK:-10}"       # en GB
CT_STORAGE="${CT_STORAGE:-local-lvm}"
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"
CT_IP="${CT_IP:-dhcp}"         # ex: 192.168.1.100/24 ou dhcp
CT_GW="${CT_GW:-}"             # ex: 192.168.1.1 (vide si dhcp)
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
TEMPLATE_NAME="debian-12-standard_12.7-1_amd64.tar.zst"

# ── Téléchargement du template Debian 12 si absent ───────────────────────────
TEMPLATE_PATH="/var/lib/vz/template/cache/${TEMPLATE_NAME}"
if [ ! -f "${TEMPLATE_PATH}" ]; then
  echo "==> Téléchargement du template Debian 12..."
  pveam update
  pveam download "${TEMPLATE_STORAGE}" debian-12-standard_12.7-1_amd64.tar.zst
else
  echo "==> Template Debian 12 déjà présent."
fi

# ── Vérification que l'ID est libre ──────────────────────────────────────────
if pct status "${CT_ID}" &>/dev/null; then
  echo "ERREUR : le CT ${CT_ID} existe déjà. Change CT_ID avant de relancer." >&2
  exit 1
fi

# ── Construction des options réseau ──────────────────────────────────────────
if [ "${CT_IP}" = "dhcp" ]; then
  NET_OPTS="name=eth0,bridge=${CT_BRIDGE},ip=dhcp"
else
  NET_OPTS="name=eth0,bridge=${CT_BRIDGE},ip=${CT_IP}"
  [ -n "${CT_GW}" ] && NET_OPTS="${NET_OPTS},gw=${CT_GW}"
fi

# ── Création du CT ────────────────────────────────────────────────────────────
echo "==> Création du CT ${CT_ID} (${CT_HOSTNAME})..."
pct create "${CT_ID}" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_NAME}" \
  --hostname "${CT_HOSTNAME}" \
  --password "${CT_PASSWORD}" \
  --cores "${CT_CORES}" \
  --memory "${CT_RAM}" \
  --rootfs "${CT_STORAGE}:${CT_DISK}" \
  --net0 "${NET_OPTS}" \
  --onboot 1 \
  --features nesting=1 \
  --unprivileged 1 \
  --start 1

# ── Attente du démarrage ──────────────────────────────────────────────────────
echo "==> Démarrage du CT..."
sleep 3

# ── Mise à jour système dans le CT ───────────────────────────────────────────
echo "==> Mise à jour du système dans le CT..."
pct exec "${CT_ID}" -- bash -c "apt-get update -qq && apt-get upgrade -y -qq"

# ── Résumé ────────────────────────────────────────────────────────────────────
CT_REAL_IP=$(pct exec "${CT_ID}" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "voir interface Proxmox")
echo ""
echo "============================================="
echo "  CT ${CT_ID} créé et démarré !"
echo "============================================="
echo ""
echo "  ID          : ${CT_ID}"
echo "  Hostname    : ${CT_HOSTNAME}"
echo "  IP          : ${CT_REAL_IP}"
echo "  CPU         : ${CT_CORES} cœur(s)"
echo "  RAM         : ${CT_RAM} MB"
echo "  Disque      : ${CT_DISK} GB (${CT_STORAGE})"
echo ""
echo "  Accès shell : pct enter ${CT_ID}"
echo "  Démarrer    : pct start ${CT_ID}"
echo "  Arrêter     : pct stop ${CT_ID}"
echo "  Supprimer   : pct destroy ${CT_ID}"
echo ""
echo "  Pour personnaliser, relance avec des variables :"
echo "    CT_ID=201 CT_HOSTNAME=glpi CT_IP=192.168.1.50/24 CT_GW=192.168.1.1 \\"
echo "    bash deploy.sh"
echo ""
