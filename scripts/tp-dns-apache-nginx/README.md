# TP DNS + Apache2 + Nginx

Déploie automatiquement un conteneur **Debian 12** sur **Proxmox VE** avec :

- **BIND9** pour la résolution DNS locale
- **Apache2** pour héberger `monsite.lab.local`
- **Nginx** en reverse proxy sur le port `8080`

Le script reprend l'esprit du guide manuel et automatise toute la mise en place dans un seul CT LXC.

---

## Ce que le script configure

- création d'un CT LXC Debian 12 avec ID libre automatique
- installation de `bind9`, `apache2`, `nginx`, `dnsutils`
- détection de l'IP du conteneur
- création d'une zone DNS locale `lab.local`
- création d'une zone inverse adaptée à l'IP réelle du CT
- publication d'une page web sur Apache2
- exposition de cette page via Nginx sur `:8080`
- vérifications de syntaxe et tests rapides en fin d'installation

---

## Prérequis

- exécuter le script **directement sur le noeud Proxmox**
- être **root**
- disposer d'un accès internet pour télécharger le template Debian et les paquets

---

## Lancer le script

```bash
curl -fsSL https://raw.githubusercontent.com/Noah77-bot-cpu/TPForge/main/scripts/tp-dns-apache-nginx/deploy.sh | bash
```

---

## Variables personnalisables

```bash
CT_STORAGE=local \
CT_BRIDGE=vmbr1 \
CT_HOSTNAME=dns-web \
SITE_NAME=portail \
LAB_DOMAIN=lab.local \
bash deploy.sh
```

Variables utiles :

- `CT_STORAGE` : stockage Proxmox du rootfs
- `CT_BRIDGE` : bridge réseau
- `CT_HOSTNAME` : nom du conteneur
- `SITE_NAME` : sous-domaine du site, par défaut `monsite`
- `LAB_DOMAIN` : domaine local, par défaut `lab.local`
- `DNS_FORWARDER_1` et `DNS_FORWARDER_2` : forwarders DNS

---

## Résultat attendu

À la fin, le script affiche :

- l'ID du conteneur
- son IP
- le FQDN local créé
- l'URL Apache2 sur le domaine local
- l'URL Nginx sur `http://IP:8080`

Exemples de tests :

```bash
pct enter <CT_ID>
dig @127.0.0.1 monsite.lab.local
curl -I http://monsite.lab.local
curl -I http://<IP_DU_CT>:8080
```

---

## Notes

- le script détecte automatiquement l'IP du CT et construit la zone inverse correspondante
- le réseau n'est donc pas limité à `192.168.1.0/24`, contrairement au guide initial
- le site s'affichera automatiquement dans TPForge dès que ce dossier sera poussé sur la branche `main`, car l'interface lit les dossiers présents dans `scripts/`
