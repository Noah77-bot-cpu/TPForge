# TP GLPI

Installe automatiquement **GLPI** avec Apache, MariaDB et PHP dans un conteneur LXC Debian 12 sur un nœud Proxmox VE.

---

## Qu'est-ce que GLPI ?

GLPI (**Gestionnaire Libre de Parc Informatique**) est une application web open-source de **gestion de parc informatique et de helpdesk**. Utilisé par des milliers d'entreprises, d'écoles et de collectivités, il permet de centraliser la gestion de tous les équipements et des demandes d'assistance d'une infrastructure IT.

### Ce que GLPI permet de faire

**Gestion du parc :**
- Inventorier tous les équipements (PC, serveurs, imprimantes, téléphones, licences logicielles…)
- Suivre les contrats de maintenance et les garanties
- Gérer les finances (coût d'achat, amortissement)

**Helpdesk / support :**
- Ouvrir des tickets d'incident ou de demande
- Assigner les tickets à des techniciens
- Suivre l'historique de toutes les interventions
- Générer des statistiques de résolution

**Qui l'utilise ?**
GLPI est particulièrement présent dans les DSI (Directions des Systèmes d'Information) de lycées, universités, administrations et PME. C'est souvent l'outil de référence dans les formations BTS SIO et en milieu professionnel IT.

---

## Prérequis

- Être exécuté **directement sur le nœud Proxmox VE** (pas dans une VM ou CT)
- Avoir les droits **root**
- Accès internet depuis le nœud (pour télécharger le template, les paquets et GLPI)

---

## Comment lancer le script

Depuis le shell du nœud Proxmox :

```bash
curl -fsSL https://raw.githubusercontent.com/Noah77-bot-cpu/TPForge/main/scripts/tp-glpi/deploy.sh | bash
```

### Variables personnalisables

```bash
CT_STORAGE=local CT_BRIDGE=vmbr1 bash deploy.sh
```

---

## Fonctionnement détaillé du script

Le script fonctionne en deux phases : une phase **hôte** (exécutée sur le nœud Proxmox) qui crée le CT, et une phase **interne** (exécutée dans le CT) qui installe GLPI.

---

### Phase 1 — Sur le nœud Proxmox

#### 1. Vérifications initiales

```bash
if [ "$(id -u)" -ne 0 ]; then ...
if ! command -v pct &>/dev/null; then ...
```

Le script vérifie qu'il est lancé en **root** sur un nœud Proxmox (présence de la commande `pct`). Sans ces conditions, l'exécution s'arrête immédiatement.

#### 2. Configuration du conteneur

Les ressources allouées à GLPI sont plus importantes qu'AdGuard car GLPI est une application web complète avec base de données :

| Paramètre | Valeur |
|---|---|
| Hostname | `glpi` |
| Mot de passe root | `changeme` |
| CPU | 2 cœurs |
| RAM | 2048 Mo (2 Go) |
| Disque | 15 Go |
| Réseau | DHCP sur `vmbr0` |
| DNS | `8.8.8.8` et `8.8.4.4` |
| Nesting | Activé (`--features nesting=1`) |

> L'option `nesting=1` est nécessaire pour permettre à systemd de fonctionner correctement dans le CT, ce qui est requis pour démarrer Apache et MariaDB.

#### 3. Attribution automatique d'un ID libre

```bash
CT_ID=100
while pct status "$CT_ID" &>/dev/null || qm status "$CT_ID" &>/dev/null; do
  CT_ID=$((CT_ID + 1))
done
```

Même logique que les autres scripts : on part de 100 et on incrémente jusqu'à trouver un ID non utilisé par un CT ou une VM.

#### 4. Détection et téléchargement du template Debian 12

```bash
pveam update
TEMPLATE=$(pveam available --section system | awk '{print $2}' | grep -i "^debian-12" | sort -V | tail -1)
```

- `pveam update` rafraîchit la liste des templates.
- Le filtre sélectionne la **version la plus récente** de Debian 12 disponible.
- Le template est téléchargé uniquement s'il n'est pas déjà en cache.

#### 5. Création du conteneur LXC

```bash
pct create "${CT_ID}" ... --unprivileged 1 --onboot 1 --features nesting=1
```

Le CT est créé non-privilégié avec démarrage automatique et nesting activé. Il reçoit une IP en DHCP et utilise les DNS Google pour la résolution de noms.

#### 6. Démarrage du CT

```bash
pct start "${CT_ID}"
sleep 6
```

Le CT démarre et on attend 6 secondes pour que le réseau et les services de base soient prêts.

#### 7. Génération du script interne

```bash
cat > /tmp/glpi_inner.sh << 'INNER'
...
INNER
```

Un script complet est écrit dans `/tmp/glpi_inner.sh` sur le nœud hôte via heredoc. Ce script sera ensuite poussé et exécuté à l'intérieur du CT.

#### 8. Injection et exécution dans le CT

```bash
pct push "${CT_ID}" /tmp/glpi_inner.sh /tmp/install.sh --perms 0755
pct exec "${CT_ID}" -- bash /tmp/install.sh
```

- `pct push` transfère le script dans le système de fichiers du CT.
- `pct exec` le lance dans le contexte du CT.

---

### Phase 2 — Dans le conteneur (script interne)

#### 9. Ajout des dépôts Debian complets

```bash
cat >> /etc/apt/sources.list << REPOS
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
...
REPOS
```

Les templates LXC Proxmox ont parfois des dépôts incomplets. Ce bloc s'assure que les dépôts `main`, `contrib` et `non-free` de Debian 12 (bookworm) sont bien configurés pour que tous les paquets PHP soient accessibles.

#### 10. Installation des paquets

```bash
apt-get install -y apache2 mariadb-server \
  php php-mysql php-xml php-mbstring php-curl php-gd \
  php-intl php-zip php-bz2 php-cli php-ldap wget tar
```

- **Apache2** : serveur web qui sert l'interface GLPI
- **MariaDB** : base de données qui stocke toutes les données GLPI
- **PHP et ses extensions** : GLPI est une application PHP, les extensions couvrent le XML, les images (GD), le chiffrement (mbstring), les connexions LDAP/Active Directory, les archives ZIP, etc.

#### 11. Création de la base de données MariaDB

```bash
mysql -u root << SQL
CREATE DATABASE IF NOT EXISTS glpi CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'glpi'@'localhost' IDENTIFIED BY 'glpi_password';
GRANT ALL PRIVILEGES ON glpi.* TO 'glpi'@'localhost';
FLUSH PRIVILEGES;
SQL
```

- Crée la base `glpi` en **UTF-8 complet** (utf8mb4), nécessaire pour gérer correctement les caractères spéciaux et les emojis.
- Crée un utilisateur dédié `glpi` avec accès uniquement à cette base.

| Paramètre | Valeur |
|---|---|
| Base de données | `glpi` |
| Utilisateur BDD | `glpi` |
| Mot de passe BDD | `glpi_password` |

#### 12. Téléchargement et extraction de GLPI

```bash
GLPI_VERSION="10.0.16"
wget -q -O "/tmp/${GLPI_ARCHIVE}" "${GLPI_URL}"
tar -xzf "/tmp/${GLPI_ARCHIVE}" -C /var/www/html/
```

L'archive officielle de GLPI est téléchargée depuis GitHub et extraite dans `/var/www/html/glpi`. Les permissions sont ensuite appliquées pour que le serveur Apache (`www-data`) puisse lire et écrire les fichiers.

#### 13. Configuration Apache

```bash
cat > /etc/apache2/sites-available/glpi.conf << VHOST
<VirtualHost *:80>
    DocumentRoot /var/www/html/glpi/public
    ...
</VirtualHost>
VHOST

a2ensite glpi.conf
a2enmod rewrite
a2dissite 000-default.conf
```

- Un VirtualHost est créé pour GLPI avec le `DocumentRoot` pointant sur `/glpi/public` (depuis GLPI 10, seul ce dossier doit être exposé au web pour des raisons de sécurité).
- Le module `rewrite` d'Apache est activé (nécessaire pour les URLs propres de GLPI).
- Le site par défaut d'Apache est désactivé.

---

## Après l'installation

1. Ouvre `http://<IP_du_CT>` dans ton navigateur
2. Suis l'assistant d'installation web de GLPI :
   - Serveur BDD : `localhost`
   - Utilisateur BDD : `glpi`
   - Mot de passe BDD : `glpi_password`
   - Base de données : `glpi`
3. Connecte-toi avec les identifiants par défaut : `glpi` / `glpi`

> **Important :** Change le mot de passe par défaut après la première connexion.

### Commandes utiles

```bash
pct enter <CT_ID>        # Accès shell dans le CT
pct stop <CT_ID>         # Arrêter le CT
pct start <CT_ID>        # Démarrer le CT
pct destroy <CT_ID>      # Supprimer le CT
```
