# 🎮 Steam Wishlist Sales

Surveille automatiquement votre wishlist Steam et affiche les jeux en promotion sur une page web élégante, auto-hébergée.

![Steam Wishlist Sales](screenshots/preview.png)

## Fonctionnalités

- **Scan automatique** de la wishlist via l'API Steam (toutes les 6h par défaut)
- **Page web auto-hébergée** avec un design inspiré de Steam
- **Filtres et tri** : alphabétique, prix croissant/décroissant, % de promotion
- **Recherche** en temps réel par nom de jeu
- **Bouton d'actualisation manuelle** avec suivi en direct du scan
- **Statistiques** : nombre de promos, meilleure remise, prix le plus bas, prochain scan
- **Responsive** : s'adapte au mobile et au desktop
- **Léger** : page HTML statique, pas de base de données

## Prérequis

- **Linux** (Debian/Ubuntu recommandé)
- **Apache2** avec **PHP 8.x**
- **curl**, **jq**, **bc**
- Un **profil Steam public** avec une **wishlist publique**

## Installation rapide

```bash
git clone https://github.com/VOTRE_USER/steam-wishlist-sales.git
cd steam-wishlist-sales
sudo ./install.sh
```

Le script d'installation vous demandera :

| Paramètre | Description | Exemple |
|---|---|---|
| **Steam ID** | Votre identifiant Steam 64-bit (17 chiffres) | `12345678901234567` |
| **Port** | Port du serveur web | `2251` |
| **Heures de scan** | Heures de scan automatique (format cron) | `1,7,13,19` |

> 💡 **Trouver votre Steam ID** : rendez-vous sur [steamid.io](https://steamid.io/) et entrez votre profil Steam.

> ⚠️ **Votre profil et votre wishlist doivent être publics** pour que le scan fonctionne.

## Installation manuelle

### 1. Installer les dépendances

```bash
sudo apt update
sudo apt install curl jq bc apache2 php libapache2-mod-php sudo
```

### 2. Copier les fichiers

```bash
# Script principal
sudo mkdir -p /opt/steam-wishlist-sales
sudo cp scripts/steam-wishlist-sales.sh /opt/steam-wishlist-sales/
sudo chmod +x /opt/steam-wishlist-sales/steam-wishlist-sales.sh

# Fichiers web
sudo mkdir -p /var/www/steam-wishlist-sales
sudo cp web/run.php web/update.php /var/www/steam-wishlist-sales/
```

### 3. Configurer le Steam ID

Éditez le script et remplacez le Steam ID :

```bash
sudo nano /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

```bash
STEAM_ID="VOTRE_STEAM_ID_ICI"
```

### 4. Configurer Apache

Créez le fichier `/etc/apache2/sites-available/steam-wishlist-sales.conf` :

```apache
Listen 2251

<VirtualHost *:2251>
    DocumentRoot /var/www/steam-wishlist-sales
    DirectoryIndex index.html

    <Directory /var/www/steam-wishlist-sales>
        Options -Indexes +FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>

    <FilesMatch "\.(html|php)$">
        Header set Cache-Control "no-cache, no-store, must-revalidate"
        Header set Pragma "no-cache"
        Header set Expires "0"
    </FilesMatch>

    ErrorLog ${APACHE_LOG_DIR}/steam-wishlist-sales-error.log
    CustomLog ${APACHE_LOG_DIR}/steam-wishlist-sales-access.log combined
</VirtualHost>
```

```bash
sudo a2enmod headers
sudo a2ensite steam-wishlist-sales
sudo systemctl restart apache2
```

### 5. Configurer les permissions

Permettre à Apache (www-data) d'exécuter le script :

```bash
echo "www-data ALL=(ALL) NOPASSWD: /opt/steam-wishlist-sales/steam-wishlist-sales.sh" | sudo tee /etc/sudoers.d/steam-wishlist-sales
sudo chmod 440 /etc/sudoers.d/steam-wishlist-sales
```

### 6. Configurer le cron

```bash
crontab -e
```

Ajoutez cette ligne pour un scan toutes les 6 heures :

```
5 1,7,13,19 * * * /opt/steam-wishlist-sales/steam-wishlist-sales.sh > /tmp/steam-wishlist-current.log 2>&1
```

### 7. Premier scan

```bash
sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

Le premier scan prend environ 5 minutes pour une wishlist de ~1300 jeux.

## Utilisation

### Accéder à la page

Ouvrez votre navigateur et rendez-vous sur :

```
http://VOTRE_IP:2251/
```

### Actualisation manuelle

Cliquez sur le bouton **↻ Actualiser** en haut à droite de la page. Une page de suivi s'affiche avec le log du scan en temps réel, puis redirige automatiquement vers les résultats.

### Fonctionnalités de la page

- **Tri** : cliquez sur les boutons A→Z, Prix ↑, Prix ↓, % Promo
- **Recherche** : tapez le nom d'un jeu dans la barre de recherche
- **Prochain scan** : affiché dans la barre de statistiques avec un compte à rebours
- **Lien Steam** : cliquez sur une carte pour ouvrir la page Steam du jeu

## Architecture

```
steam-wishlist-sales/
├── install.sh                     # Script d'installation automatique
├── uninstall.sh                   # Script de désinstallation
├── README.md                      # Ce fichier
├── LICENSE
├── screenshots/                   # Captures d'écran
│   └── preview.png
├── scripts/
│   └── steam-wishlist-sales.sh    # Script principal de scan
└── web/
    ├── run.php                    # Déclencheur de scan manuel
    └── update.php                 # Page de suivi du scan en cours
```

### Fonctionnement technique

Le script `steam-wishlist-sales.sh` fonctionne en 5 étapes :

1. **Wishlist** — Récupère la liste complète des app IDs via `IWishlistService/GetWishlist` (1 appel API)
2. **Prix** — Récupère les prix par lots de 30 via `appdetails?filters=price_overview` (~46 appels)
3. **Filtrage** — Identifie les jeux ayant un `discount_percent > 0`
4. **Noms** — Récupère les noms et images des jeux en promo via `appdetails` (1 appel par jeu)
5. **HTML** — Génère la page `index.html` statique avec les résultats

### Durée d'un scan

| Wishlist | Étape prix | Étape noms | Total estimé |
|---|---|---|---|
| ~500 jeux | ~40s | ~1min | ~2min |
| ~1000 jeux | ~1min20 | ~2min | ~4min |
| ~1500 jeux | ~1min40 | ~3min | ~5min |

### API Steam utilisées

| Endpoint | Usage | Auth requise |
|---|---|---|
| `IWishlistService/GetWishlist/v1/` | Liste des app IDs de la wishlist | Non (profil public) |
| `store.steampowered.com/api/appdetails` | Prix, noms, images des jeux | Non |

## Dépannage

### Le scan ne trouve aucun jeu

- Vérifiez que votre **profil Steam est public** (Paramètres Steam → Vie privée → Profil public)
- Vérifiez que votre **wishlist est publique** (même section, Détails du jeu → Public)
- Testez manuellement : `curl -sL "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=VOTRE_ID"`

### Le bouton Actualiser ne fonctionne pas

- Vérifiez les permissions sudo : `sudo -u www-data sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh`
- Vérifiez les logs : `tail -f /var/log/apache2/steam-wishlist-sales-error.log`
- Vérifiez que PHP fonctionne : `curl -sL "http://localhost:VOTRE_PORT/run.php"`

### Erreur HTTP 302 lors du scan

Vérifiez que le flag `-sL` est présent dans les appels curl du script (le `L` suit les redirections).

### Les prix affichent 0,00€

Certains jeux (F2P, retirés du store, DLC) n'ont pas de prix. Ils sont automatiquement exclus des résultats.

## Désinstallation

```bash
sudo ./uninstall.sh
```

Ou manuellement :

```bash
sudo a2dissite steam-wishlist-sales
sudo systemctl restart apache2
sudo rm -rf /opt/steam-wishlist-sales
sudo rm -rf /var/www/steam-wishlist-sales
sudo rm -f /etc/apache2/sites-available/steam-wishlist-sales.conf
sudo rm -f /etc/sudoers.d/steam-wishlist-sales
crontab -l | grep -v "steam-wishlist-sales" | crontab -
```

## Licence

MIT — voir [LICENSE](LICENSE)
