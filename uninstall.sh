#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Steam Wishlist Sales — Script de désinstallation
# ═══════════════════════════════════════════════════════════════

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERR]${NC} Ce script doit être exécuté en tant que root."
    exit 1
fi

echo ""
echo -e "${BOLD}${RED}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║   🗑️  Steam Wishlist Sales — Désinstallation  ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "  Cette opération va supprimer :"
echo "    - /opt/steam-wishlist-sales/"
echo "    - /var/www/steam-wishlist-sales/"
echo "    - /etc/apache2/sites-available/steam-wishlist-sales.conf"
echo "    - /etc/sudoers.d/steam-wishlist-sales"
echo "    - L'entrée crontab"
echo ""
read -p "  Confirmer la désinstallation ? [o/N] : " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Oo]$ ]]; then
    echo "Désinstallation annulée."
    exit 0
fi

echo ""

# Désactiver le site Apache
a2dissite steam-wishlist-sales > /dev/null 2>&1 || true
systemctl restart apache2 2>/dev/null || true
echo -e "${GREEN}[OK]${NC} Site Apache désactivé"

# Supprimer les fichiers
rm -rf /opt/steam-wishlist-sales
echo -e "${GREEN}[OK]${NC} Script supprimé"

rm -rf /var/www/steam-wishlist-sales
echo -e "${GREEN}[OK]${NC} Fichiers web supprimés"

rm -f /etc/apache2/sites-available/steam-wishlist-sales.conf
echo -e "${GREEN}[OK]${NC} Configuration Apache supprimée"

rm -f /etc/sudoers.d/steam-wishlist-sales
echo -e "${GREEN}[OK]${NC} Configuration sudoers supprimée"

# Supprimer le cron
(crontab -l 2>/dev/null | grep -v "steam-wishlist-sales") | crontab - 2>/dev/null || true
echo -e "${GREEN}[OK]${NC} Entrée crontab supprimée"

# Nettoyage des fichiers temporaires
rm -f /tmp/steam-wishlist-sales.lock
rm -f /tmp/steam-wishlist-current.log
echo -e "${GREEN}[OK]${NC} Fichiers temporaires nettoyés"

echo ""
echo -e "${GREEN}${BOLD}  Désinstallation terminée.${NC}"
echo ""
echo "  Note : les dépendances (curl, jq, bc, apache2, php) n'ont pas été"
echo "  supprimées car elles peuvent être utilisées par d'autres programmes."
echo ""
