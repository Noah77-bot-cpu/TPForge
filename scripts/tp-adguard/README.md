# TP AdGuard Home

Installe automatiquement **AdGuard Home** dans un conteneur LXC Debian 12 sur un nœud Proxmox VE.

---

## Qu'est-ce qu'AdGuard Home ?

AdGuard Home est un **serveur DNS filtrant** open-source. Contrairement à un bloqueur de publicités classique (extension navigateur), AdGuard agit au niveau du réseau entier : il intercepte toutes les requêtes DNS émises par les équipements du réseau local (PC, téléphones, TV connectées, consoles…) et bloque celles qui correspondent à des domaines publicitaires, de tracking ou malveillants, **avant même que la connexion ne soit établie**.

### Pourquoi c'est utile ?

| Sans AdGuard | Avec AdGuard |
|---|---|
| Les publicités se chargent sur tous les appareils | Les publicités sont bloquées sur tout le réseau |
| Les trackers collectent les données en arrière-plan | Les domaines de tracking sont coupés à la source |
| Chaque appareil doit avoir son propre bloqueur | Une seule instance protège tout le réseau |
| Les appareils IoT (TV, frigo…) peuvent tracker | Même les appareils sans navigateur sont filtrés |

AdGuard Home remplace le DNS fourni par votre box (ex: `192.168.1.1`) et filtre les requêtes selon des **listes de blocage** mises à jour régulièrement.

---

## Prérequis

- Être exécuté **directement sur le nœud Proxmox VE** (pas dans une VM ou CT)
- Avoir les droits **root**
- Accès internet depuis le nœud (pour télécharger le template et AdGuard)

---

## Comment lancer le script

Depuis le shell du nœud Proxmox :

```bash
curl -fsSL https://raw.githubusercontent.com/Noah77-bot-cpu/TPForge/main/scripts/tp-adguard/deploy.sh | bash
```

### Variables personnalisables

Par défaut le script utilise `local-lvm` comme stockage et `vmbr0` comme bridge réseau. Tu peux surcharger ces valeurs :

```bash
CT_STORAGE=local CT_BRIDGE=vmbr1 bash deploy.sh
```

---

## Fonctionnement détaillé du script

### 1. Vérifications initiales

```bash
if [ "$(id -u)" -ne 0 ]; then ...
if ! command -v pct &>/dev/null; then ...
```

Le script s'assure d'être lancé en **root** et que la commande `pct` (outil de gestion des conteneurs Proxmox) est disponible. Si l'une des deux conditions échoue, il s'arrête immédiatement avec un message d'erreur.

### 2. Configuration du conteneur

Les ressources du CT sont définies directement dans le script :

| Paramètre | Valeur |
|---|---|
| Hostname | `adguard` |
| Mot de passe root | `changeme` |
| CPU | 1 cœur |
| RAM | 512 Mo |
| Disque | 4 Go |
| Réseau | DHCP sur `vmbr0` |
| DNS | `8.8.8.8` et `8.8.4.4` |

### 3. Attribution automatique d'un ID libre

```bash
CT_ID=100
while pct status "$CT_ID" &>/dev/null 2>&1 || qm status "$CT_ID" &>/dev/null 2>&1; do
  CT_ID=$((CT_ID + 1))
done
```

Le script part de l'ID `100` et incrémente jusqu'à trouver un identifiant non utilisé, aussi bien par les CTs que par les VMs. Cela évite tout conflit sans intervention manuelle.

### 4. Détection et téléchargement du template Debian 12

```bash
pveam update
TEMPLATE=$(pveam available --section system | awk '{print $2}' | grep -i "^debian-12" | sort -V | tail -1)
```

- `pveam update` : rafraîchit la liste des templates disponibles depuis les dépôts Proxmox.
- `pveam available` : liste tous les templates téléchargeables.
- Le filtre `grep -i "^debian-12"` sélectionne uniquement les templates Debian 12, puis `sort -V | tail -1` retient le plus récent.
- Si le template est déjà présent dans `/var/lib/vz/template/cache/`, le téléchargement est sauté.

### 5. Création du conteneur LXC

```bash
pct create "${CT_ID}" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}" \
  --hostname adguard \
  --unprivileged 1 \
  --onboot 1 \
  ...
```

Le conteneur est créé en mode **non-privilégié** (`--unprivileged 1`) : les processus à l'intérieur tournent avec des UID/GID remappés, ce qui limite les risques de sécurité. L'option `--onboot 1` démarre automatiquement le CT au démarrage du nœud Proxmox.

### 6. Démarrage et attente

```bash
pct start "${CT_ID}"
sleep 6
```

Le CT est démarré, puis le script attend 6 secondes pour que les services réseau s'initialisent complètement avant d'exécuter des commandes à l'intérieur.

### 7. Script d'installation interne (heredoc)

```bash
cat > /tmp/adguard_inner.sh << 'INNER'
...
INNER
```

Un second script est généré à la volée sur le nœud hôte via un **heredoc**. Il contient les commandes à exécuter à l'intérieur du CT :

- `apt-get update` et installation de `curl` et `tar`
- Téléchargement et exécution du script officiel d'installation d'AdGuard Home depuis son dépôt GitHub

### 8. Injection et exécution dans le CT

```bash
pct push "${CT_ID}" /tmp/adguard_inner.sh /tmp/install.sh --perms 0755
pct exec "${CT_ID}" -- bash /tmp/install.sh
```

- `pct push` copie le script depuis le nœud hôte vers le système de fichiers du CT.
- `pct exec` exécute ce script à l'intérieur du CT, comme si on était connecté en SSH dedans.

### 9. Résumé final

Le script récupère l'adresse IP attribuée par DHCP via `hostname -I` et affiche l'URL d'accès à l'interface web d'AdGuard Home (`http://<IP>:3000`).

---

## Après l'installation

1. Ouvre `http://<IP_du_CT>:3000` dans ton navigateur
2. Suis l'assistant de configuration initiale d'AdGuard Home
3. Configure les appareils (ou le DHCP de ta box) pour utiliser l'IP du CT comme serveur DNS

### Commandes utiles

```bash
pct enter <CT_ID>        # Accès shell dans le CT
pct stop <CT_ID>         # Arrêter le CT
pct start <CT_ID>        # Démarrer le CT
pct destroy <CT_ID>      # Supprimer le CT
```
