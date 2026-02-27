#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Steam Wishlist Sales — Script d'installation
# ═══════════════════════════════════════════════════════════════
#
# Ce script installe et configure automatiquement le système
# de suivi des promotions Steam Wishlist.
#
# Usage :
#   sudo ./install.sh
#
# ═══════════════════════════════════════════════════════════════

set -e

# ── Couleurs ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; }

# ── Vérification root ─────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    err "Ce script doit être exécuté en tant que root."
    echo "Usage : sudo ./install.sh"
    exit 1
fi

# ── Bannière ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║   🎮  Steam Wishlist Sales — Installation    ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# ── Détection du répertoire du script ─────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Vérifier que les fichiers sources existent
if [ ! -f "$SCRIPT_DIR/scripts/steam-wishlist-sales.sh" ]; then
    err "Fichier scripts/steam-wishlist-sales.sh introuvable."
    err "Assurez-vous de lancer le script depuis le répertoire du projet."
    exit 1
fi

# ── Collecte des informations ─────────────────────────────────
echo -e "${BOLD}Configuration${NC}"
echo ""

# Steam ID
while true; do
    read -p "  Steam ID (ex: 76561198040773990) : " STEAM_ID
    if [[ "$STEAM_ID" =~ ^[0-9]{17}$ ]]; then
        break
    fi
    warn "Le Steam ID doit être un nombre de 17 chiffres."
    echo "  Trouvez-le sur : https://steamid.io/"
done

# Port Apache
read -p "  Port pour le serveur web [2251] : " PORT
PORT=${PORT:-2251}
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    warn "Port invalide, utilisation du port 2251."
    PORT=2251
fi

# Heures de scan
read -p "  Heures de scan auto (format cron) [1,7,13,19] : " CRON_HOURS
CRON_HOURS=${CRON_HOURS:-1,7,13,19}

echo ""
echo -e "${BOLD}Récapitulatif :${NC}"
echo "  Steam ID      : $STEAM_ID"
echo "  Port web      : $PORT"
echo "  Scans auto    : ${CRON_HOURS}h05"
echo ""
read -p "  Confirmer l'installation ? [O/n] : " CONFIRM
CONFIRM=${CONFIRM:-O}
if [[ ! "$CONFIRM" =~ ^[Oo]$ ]]; then
    echo "Installation annulée."
    exit 0
fi

echo ""

# ── Installation des dépendances ──────────────────────────────
log "Installation des dépendances..."

apt-get update -qq
apt-get install -y -qq curl jq bc apache2 php libapache2-mod-php sudo > /dev/null 2>&1

ok "Dépendances installées (curl, jq, bc, apache2, php, sudo)"

# ── Création des répertoires ──────────────────────────────────
log "Création des répertoires..."

INSTALL_DIR="/opt/steam-wishlist-sales"
WEB_DIR="/var/www/steam-wishlist-sales"

mkdir -p "$INSTALL_DIR"
mkdir -p "$WEB_DIR"

ok "Répertoires créés"

# ── Copie des fichiers ────────────────────────────────────────
log "Copie des fichiers..."

# Script principal
cp "$SCRIPT_DIR/scripts/steam-wishlist-sales.sh" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/steam-wishlist-sales.sh"

# Fichiers web
cp "$SCRIPT_DIR/web/run.php" "$WEB_DIR/"
cp "$SCRIPT_DIR/web/update.php" "$WEB_DIR/"

ok "Fichiers copiés"

# ── Configuration du Steam ID ─────────────────────────────────
log "Configuration du Steam ID..."

sed -i "s/^STEAM_ID=.*/STEAM_ID=\"${STEAM_ID}\"/" "$INSTALL_DIR/steam-wishlist-sales.sh"

ok "Steam ID configuré : $STEAM_ID"

# ── Configuration Apache ──────────────────────────────────────
log "Configuration d'Apache..."

VHOST_FILE="/etc/apache2/sites-available/steam-wishlist-sales.conf"

cat > "$VHOST_FILE" << EOF
Listen ${PORT}

<VirtualHost *:${PORT}>
    DocumentRoot ${WEB_DIR}
    DirectoryIndex index.html

    <Directory ${WEB_DIR}>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    # Désactiver le cache pour toujours avoir la dernière version
    <FilesMatch "\.(html|php)$">
        Header set Cache-Control "no-cache, no-store, must-revalidate"
        Header set Pragma "no-cache"
        Header set Expires "0"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/steam-wishlist-sales-error.log
    CustomLog \${APACHE_LOG_DIR}/steam-wishlist-sales-access.log combined
</VirtualHost>
EOF

# Activer les modules nécessaires
a2enmod headers > /dev/null 2>&1 || true
a2ensite steam-wishlist-sales > /dev/null 2>&1 || true

# Vérifier la config Apache
if apache2ctl configtest > /dev/null 2>&1; then
    systemctl restart apache2
    ok "Apache configuré sur le port $PORT"
else
    warn "Erreur dans la configuration Apache. Vérifiez manuellement."
fi

# ── Configuration sudoers ─────────────────────────────────────
log "Configuration des permissions..."

SUDOERS_FILE="/etc/sudoers.d/steam-wishlist-sales"
echo "www-data ALL=(ALL) NOPASSWD: ${INSTALL_DIR}/steam-wishlist-sales.sh" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"

ok "Permissions sudo configurées pour www-data"

# ── Configuration Crontab ─────────────────────────────────────
log "Configuration du cron..."

CRON_LINE="5 ${CRON_HOURS} * * * ${INSTALL_DIR}/steam-wishlist-sales.sh > /tmp/steam-wishlist-current.log 2>&1"

# Ajouter au crontab root sans doublonner
(crontab -l 2>/dev/null | grep -v "steam-wishlist-sales"; echo "$CRON_LINE") | crontab -

ok "Cron configuré : exécution à ${CRON_HOURS}h05"

# ── Permissions des fichiers ──────────────────────────────────
chown -R www-data:www-data "$WEB_DIR"

# ── Premier scan ──────────────────────────────────────────────
echo ""
read -p "  Lancer le premier scan maintenant ? [O/n] : " RUN_NOW
RUN_NOW=${RUN_NOW:-O}

if [[ "$RUN_NOW" =~ ^[Oo]$ ]]; then
    echo ""
    log "Premier scan en cours (environ 5 minutes)..."
    echo ""
    "$INSTALL_DIR/steam-wishlist-sales.sh" > /tmp/steam-wishlist-current.log 2>&1 &
    SCAN_PID=$!

    # Afficher la progression
    while kill -0 $SCAN_PID 2>/dev/null; do
        if [ -f /tmp/steam-wishlist-current.log ]; then
            LAST_LINE=$(tail -1 /tmp/steam-wishlist-current.log 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')
            if [ -n "$LAST_LINE" ]; then
                printf "\r  ⏳ %s" "$LAST_LINE"
                printf "%-20s" ""
            fi
        fi
        sleep 3
    done

    echo ""
    echo ""
    ok "Premier scan terminé !"
fi

# ── Résumé final ──────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║        ✅ Installation terminée !             ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo -e "  ${BOLD}Accès :${NC}"

# Détecter l'IP locale
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -n "$LOCAL_IP" ]; then
    echo -e "    http://${LOCAL_IP}:${PORT}/"
fi
echo -e "    http://localhost:${PORT}/"
echo ""
echo -e "  ${BOLD}Fichiers installés :${NC}"
echo "    Script    : ${INSTALL_DIR}/steam-wishlist-sales.sh"
echo "    Site web  : ${WEB_DIR}/"
echo "    Apache    : ${VHOST_FILE}"
echo "    Sudoers   : ${SUDOERS_FILE}"
echo ""
echo -e "  ${BOLD}Commandes utiles :${NC}"
echo "    Scan manuel     : ${INSTALL_DIR}/steam-wishlist-sales.sh"
echo "    Voir le cron    : crontab -l"
echo "    Logs Apache     : tail -f /var/log/apache2/steam-wishlist-sales-*.log"
echo "    Logs scan       : cat /tmp/steam-wishlist-current.log"
echo ""
echo -e "  ${BOLD}Désinstallation :${NC}"
echo "    sudo ./uninstall.sh"
echo ""
