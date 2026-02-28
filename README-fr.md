# 🎮 Steam Wishlist Sales Checker

Code généré par Claude (Anthropic). Ceci est un projet pour comprendre la possibilité de récupérer des informations avec la commande "curl" et "Invoke-RestMethod" via l'API Steam.
Une version exécutable pour Windows est également disponible sans aucune installation pour simplement vérifier les promotions de votre liste de souhaits Steam, dans la page "Releases".

Surveille automatiquement votre wishlist Steam et affiche les jeux en promotion sur une page web élégante, auto-hébergée.

![Steam Wishlist Sales](screenshots/result.png)
![Steam Wishlist Sales](screenshots/result-classic.png)

## Fonctionnalites

- **Scan automatique** de la wishlist via l'API Steam (toutes les 6h par defaut)
- **Cache intelligent** : seuls les nouveaux jeux en promo sont recuperes, les autres sont lus depuis le cache local (scan 5x plus rapide)
- **Filtres par genre** : Action, RPG, Indie... combinables avec la recherche textuelle
- **Double theme** : Modern (par defaut) ou Classic Steam retro (2004-2010), persistant via cookie
- **Page web auto-hebergee** avec un design inspire de Steam
- **Tri** : alphabetique, prix croissant/decroissant, % de promotion
- **Recherche** en temps reel par nom de jeu
- **Bouton d'actualisation manuelle** avec suivi en direct du scan
- **Statistiques** : nombre de promos, meilleure remise, prix le plus bas, prochain scan
- **Responsive** : s'adapte au mobile et au desktop
- **Leger** : page HTML statique, pas de base de donnees
- **Version Windows** : script PowerShell standalone inclus

## Prerequis

### Linux (version principale)

- **Linux** (Debian/Ubuntu recommande)
- **Apache2** avec **PHP 8.x**
- **curl**, **jq**, **bc**
- Un **profil Steam public** avec une **wishlist publique**

### Windows (version standalone)

- **Windows 10/11** avec **PowerShell 5.1+**
- Aucune autre dependance

## Installation rapide (Linux)

```bash
git clone https://github.com/VOTRE_USER/steam-wishlist-sales.git
cd steam-wishlist-sales
sudo ./install.sh
```

Le script d'installation vous demandera :

| Parametre | Description | Exemple |
|---|---|---|
| **Steam ID** | Votre identifiant Steam 64-bit (17 chiffres) | `76561198040773990` |
| **Port** | Port du serveur web | `2251` |
| **Heures de scan** | Heures de scan automatique (format cron) | `1,7,13,19` |

> 💡 **Trouver votre Steam ID** : rendez-vous sur [steamid.io](https://steamid.io/) et entrez votre profil Steam.

> ⚠️ **Votre profil et votre wishlist doivent etre publics** pour que le scan fonctionne.

## Utilisation Windows (PowerShell)

```powershell
.\SteamWishlistSales.ps1 -SteamID 76561198040773990
.\SteamWishlistSales.ps1 -SteamID 76561198040773990 -Country us
.\SteamWishlistSales.ps1 76561198040773990 -ClearCache
```

Le script genere un fichier HTML dans `%TEMP%` et l'ouvre automatiquement dans le navigateur. Le cache est stocke dans `%APPDATA%\SteamWishlistSales\`.

| Parametre | Description | Defaut |
|---|---|---|
| **SteamID** | Votre Steam ID 64-bit | (demande interactivement) |
| **Country** | Code pays pour les prix | `fr` |
| **OutputPath** | Chemin du HTML genere | `%TEMP%\steam-wishlist-sales.html` |
| **ClearCache** | Vider le cache avant le scan | desactive |

## Installation manuelle (Linux)

### 1. Installer les dependances

```bash
sudo apt update
sudo apt install curl jq bc apache2 php libapache2-mod-php sudo
```

### 2. Copier les fichiers

```bash
sudo mkdir -p /opt/steam-wishlist-sales
sudo cp scripts/steam-wishlist-sales.sh /opt/steam-wishlist-sales/
sudo chmod +x /opt/steam-wishlist-sales/steam-wishlist-sales.sh

sudo mkdir -p /var/www/steam-wishlist-sales
sudo cp web/run.php web/update.php /var/www/steam-wishlist-sales/

# Initialiser le cache
echo '{}' | sudo tee /var/www/steam-wishlist-sales/cache.json
sudo chmod 644 /var/www/steam-wishlist-sales/cache.json
sudo chown www-data:www-data /var/www/steam-wishlist-sales/cache.json
```

### 3. Configurer le Steam ID

```bash
sudo nano /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

```bash
STEAM_ID="VOTRE_STEAM_ID_ICI"
```

### 4. Configurer Apache

Creez le fichier `/etc/apache2/sites-available/steam-wishlist-sales.conf` :

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

```bash
echo "www-data ALL=(ALL) NOPASSWD: /opt/steam-wishlist-sales/steam-wishlist-sales.sh" | sudo tee /etc/sudoers.d/steam-wishlist-sales
sudo chmod 440 /etc/sudoers.d/steam-wishlist-sales
```

### 6. Configurer le cron

```bash
crontab -e
```

```
5 1,7,13,19 * * * /opt/steam-wishlist-sales/steam-wishlist-sales.sh > /tmp/steam-wishlist-current.log 2>&1
```

### 7. Premier scan

```bash
sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

Le premier scan recupere tous les jeux (~5 min pour ~1500 jeux). Les suivants sont bien plus rapides grace au cache.

## Utilisation

### Acceder a la page

```
http://VOTRE_IP:2251/
```

### Fonctionnalites de la page

- **Tri** : boutons A→Z, Prix ↑, Prix ↓, % Promo
- **Recherche** : barre de recherche en temps reel
- **Filtres genre** : cliquez sur un genre pour filtrer (combinable avec la recherche)
- **Theme** : bouton Classic Steam / Modern dans le header (sauvegarde via cookie)
- **Actualisation** : bouton ↻ Actualiser avec log en direct
- **Prochain scan** : compte a rebours dans la barre de statistiques
- **Lien Steam** : cliquez sur une carte pour ouvrir la page Steam du jeu

## Architecture

```
steam-wishlist-sales/
├── install.sh                     # Script d'installation automatique
├── uninstall.sh                   # Script de desinstallation
├── SteamWishlistSales.ps1         # Version Windows (standalone)
├── README.md                      # Ce fichier
├── README_EN.md                   # README en anglais
├── CHANGELOG.md                   # Historique des versions
├── LICENSE
├── screenshots/
│   └── preview.png
├── scripts/
│   └── steam-wishlist-sales.sh    # Script principal de scan
└── web/
    ├── run.php                    # Declencheur de scan manuel
    └── update.php                 # Page de suivi du scan en cours
```

### Fichiers generes a l'execution

```
/var/www/steam-wishlist-sales/
├── index.html                     # Page HTML generee
└── cache.json                     # Cache des noms/images/genres
```

### Fonctionnement technique

Le script `steam-wishlist-sales.sh` fonctionne en 5 etapes :

1. **Wishlist** — Recupere la liste complete des app IDs via `IWishlistService/GetWishlist` (1 appel API)
2. **Prix** — Recupere les prix par lots de 30 via `appdetails?filters=price_overview` (~46 appels)
3. **Filtrage** — Identifie les jeux ayant un `discount_percent > 0`
4. **Noms/Genres** — Consulte le cache, puis recupere uniquement les jeux manquants via `appdetails` (genres extraits de `.data.genres[]`)
5. **HTML** — Genere la page `index.html` avec grille, filtres genre, double theme CSS, et JavaScript interactif

### Duree d'un scan

| Wishlist | Premier scan | Scans suivants (cache) |
|---|---|---|
| ~500 jeux | ~2min | ~20s |
| ~1000 jeux | ~4min | ~30s |
| ~1500 jeux | ~5min | ~1min |

### API Steam utilisees

| Endpoint | Usage | Auth requise |
|---|---|---|
| `IWishlistService/GetWishlist/v1/` | Liste des app IDs de la wishlist | Non (profil public) |
| `store.steampowered.com/api/appdetails` | Prix, noms, images, genres | Non |

## Depannage

### Le scan ne trouve aucun jeu

- Verifiez que votre **profil Steam est public**
- Verifiez que votre **wishlist est publique**
- Testez : `curl -sL "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=VOTRE_ID"`

### Le cache semble corrompu

```bash
# Linux
sudo rm /var/www/steam-wishlist-sales/cache.json
echo '{}' | sudo tee /var/www/steam-wishlist-sales/cache.json
sudo chown www-data:www-data /var/www/steam-wishlist-sales/cache.json
```

```powershell
# Windows
.\SteamWishlistSales.ps1 76561198040773990 -ClearCache
```

### Le bouton Actualiser ne fonctionne pas

- Verifiez les permissions sudo : `sudo -u www-data sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh`
- Verifiez les logs : `tail -f /var/log/apache2/steam-wishlist-sales-error.log`

### Erreur de parsing PowerShell

Le script PowerShell doit etre encode en UTF-8 avec BOM. Si vous editez le fichier, sauvegardez-le en "UTF-8 with BOM" dans votre editeur.

## Desinstallation

```bash
sudo ./uninstall.sh
```

## Licence

MIT — voir [LICENSE](LICENSE)
