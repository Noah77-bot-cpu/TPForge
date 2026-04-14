#!/usr/bin/env bash
set -euo pipefail

echo "==> Installation d'AdGuard Home..."
curl -fsSL https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v

echo ""
echo "✓ AdGuard Home installé et démarré."
echo "  Interface web : http://<IP_DU_SERVEUR>:3000"
echo "  Configure ton DNS sur tes appareils ou ta box pour pointer vers cette IP."
