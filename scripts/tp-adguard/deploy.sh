#!/usr/bin/env bash
set -euo pipefail

# ── Vérifications ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "ERREUR : ce script doit être lancé en root." >&2
  exit 1
fi

# ── Dépendances ───────────────────────────────────────────────────────────────
echo "==> Vérification des dépendances..."
apt-get update -y -qq
apt-get install -y curl tar

# ── Installation d'AdGuard Home ───────────────────────────────────────────────
echo "==> Téléchargement et installation d'AdGuard Home..."
curl -fsSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v

# ── Résumé ────────────────────────────────────────────────────────────────────
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "============================================="
echo "  AdGuard Home installé avec succès !"
echo "============================================="
echo ""
echo "  Interface web      : http://${IP}:3000"
echo "  DNS à configurer   : ${IP}"
echo ""
echo "  1. Ouvre http://${IP}:3000 pour configurer AdGuard Home."
echo "  2. Configure tes appareils ou ta box DHCP pour utiliser ${IP} comme DNS."
echo ""
