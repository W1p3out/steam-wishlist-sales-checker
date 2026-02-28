# 🎮 Steam Wishlist Sales Checker

Code written with Claude (Anthropic). This is a learning project to see how "curl" and "Invoke-RestMethod" commands could grab informations from Steam API.
An executable is also available for Windows if you want to simply scan your wishlist sales without any installation in releases page.

Automatically monitors your Steam wishlist and displays games on sale on a sleek, self-hosted web page.

![Steam Wishlist Sales](screenshots/result.png)
![Steam Wishlist Sales](screenshots/result-classic.png)

## Features

- **Automatic scanning** of your wishlist via the Steam API (every 6 hours by default)
- **Smart cache**: only new sale entries trigger API calls; everything else is read from local cache (5x faster scans)
- **Genre filters**: Action, RPG, Indie... combinable with text search
- **Dual theme**: Modern (default) or Classic Steam retro (2004-2010), persisted via cookie
- **Self-hosted web page** with a Steam-inspired design
- **Sorting**: alphabetical, price ascending/descending, discount %
- **Real-time search** by game name
- **Manual refresh button** with live scan tracking
- **Statistics**: sale count, best discount, lowest price, next scan countdown
- **Responsive**: adapts to mobile and desktop
- **Lightweight**: static HTML page, no database required
- **Windows version**: standalone PowerShell script included and executable in 'Releases'

## Requirements

### Linux (main version)

- **Linux** (Debian/Ubuntu recommended)
- **Apache2** with **PHP 8.x**
- **curl**, **jq**, **bc**
- A **public Steam profile** with a **public wishlist**

### Windows (standalone version)

- **Windows 10/11** with **PowerShell 5.1+**
- No other dependencies

## Quick Install (Linux)

```bash
git clone https://github.com/W1p3out/steam-wishlist-sales-checker
cd steam-wishlist-sales-checker
chmod +x install.sh
./install.sh
```

The installer will ask for:

| Parameter | Description | Example |
|---|---|---|
| **Steam ID** | Your 64-bit Steam ID (17 digits) | `12345678901234567` |
| **Port** | Web server port | `2251` |
| **Scan hours** | Automatic scan schedule (cron format) | `1,7,13,19` |

> 💡 **Find your Steam ID**: visit [steamid.io](https://steamid.io/) and enter your Steam profile URL.

> ⚠️ **Your profile and wishlist must be public** for scanning to work.

## Windows Usage (PowerShell)

```powershell
.\SteamWishlistSales.ps1 -SteamID 12345678901234567
.\SteamWishlistSales.ps1 -SteamID 12345678901234567 -Country us
.\SteamWishlistSales.ps1 12345678901234567 -ClearCache
```

The script generates an HTML file in `%TEMP%` and opens it in your default browser. Cache is stored in `%APPDATA%\SteamWishlistSales\`.

| Parameter | Description | Default |
|---|---|---|
| **SteamID** | Your 64-bit Steam ID | (prompted interactively) |
| **Country** | Country code for pricing | `fr` |
| **OutputPath** | Path for generated HTML | `%TEMP%\steam-wishlist-sales.html` |
| **ClearCache** | Clear cache before scanning | disabled |

## Manual Install (Linux)

### 1. Install dependencies

```bash
sudo apt update
sudo apt install curl jq bc apache2 php libapache2-mod-php sudo
```

### 2. Copy files

```bash
sudo mkdir -p /opt/steam-wishlist-sales
sudo cp scripts/steam-wishlist-sales.sh /opt/steam-wishlist-sales/
sudo chmod +x /opt/steam-wishlist-sales/steam-wishlist-sales.sh

sudo mkdir -p /var/www/steam-wishlist-sales
sudo cp web/run.php web/update.php /var/www/steam-wishlist-sales/

# Initialize cache
echo '{}' | sudo tee /var/www/steam-wishlist-sales/cache.json
sudo chmod 644 /var/www/steam-wishlist-sales/cache.json
sudo chown www-data:www-data /var/www/steam-wishlist-sales/cache.json
```

### 3. Set your Steam ID

```bash
sudo nano /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

```bash
STEAM_ID="YOUR_STEAM_ID_HERE"
```

### 4. Configure Apache

Create `/etc/apache2/sites-available/steam-wishlist-sales.conf`:

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

### 5. Set permissions

```bash
echo "www-data ALL=(ALL) NOPASSWD: /opt/steam-wishlist-sales/steam-wishlist-sales.sh" | sudo tee /etc/sudoers.d/steam-wishlist-sales
sudo chmod 440 /etc/sudoers.d/steam-wishlist-sales
```

### 6. Set up cron

```bash
crontab -e
```

```
5 1,7,13,19 * * * /opt/steam-wishlist-sales/steam-wishlist-sales.sh > /tmp/steam-wishlist-current.log 2>&1
```

### 7. First scan

```bash
sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

The first scan fetches all games (~5 min for ~1500 games). Subsequent scans are much faster thanks to the cache.

## Usage

### Access the page

```
http://YOUR_IP:2251/
```

### Page features

- **Sort**: A-Z, Price Up, Price Down, Discount % buttons
- **Search**: real-time text search bar
- **Genre filters**: click a genre to filter (combinable with search)
- **Theme**: Classic Steam / Modern toggle button in the header (saved via cookie)
- **Refresh**: click the refresh button for a live-tracked manual scan
- **Next scan**: countdown displayed in the stats bar
- **Steam link**: click any card to open the game's Steam page

## Architecture

```
steam-wishlist-sales/
├── install.sh                     # Automated installer
├── uninstall.sh                   # Uninstaller
├── SteamWishlistSales.ps1         # Windows version (standalone)
├── README.md                      # French README
├── README_EN.md                   # This file
├── CHANGELOG.md                   # Version history
├── LICENSE
├── screenshots/
│   └── preview.png
├── scripts/
│   └── steam-wishlist-sales.sh    # Main scan script
└── web/
    ├── run.php                    # Manual scan trigger
    └── update.php                 # Live scan tracking page
```

### Generated files at runtime

```
/var/www/steam-wishlist-sales/
├── index.html                     # Generated HTML page
└── cache.json                     # Name/image/genre cache
```

### How it works

The `steam-wishlist-sales.sh` script runs in 5 steps:

1. **Wishlist** — Fetches the full list of app IDs via `IWishlistService/GetWishlist` (1 API call)
2. **Prices** — Fetches prices in batches of 30 via `appdetails?filters=price_overview` (~46 calls)
3. **Filtering** — Identifies games with `discount_percent > 0`
4. **Names/Genres** — Checks the cache, then fetches only missing games via `appdetails` (genres extracted from `.data.genres[]`)
5. **HTML** — Generates the `index.html` page with grid, genre filters, dual-theme CSS, and interactive JavaScript

### Scan duration

| Wishlist size | First scan | Subsequent scans (cached) |
|---|---|---|
| ~500 games | ~2min | ~20s |
| ~1000 games | ~4min | ~30s |
| ~1500 games | ~5min | ~1min |

### Steam APIs used

| Endpoint | Purpose | Auth required |
|---|---|---|
| `IWishlistService/GetWishlist/v1/` | List app IDs from wishlist | No (public profile) |
| `store.steampowered.com/api/appdetails` | Prices, names, images, genres | No |

## Troubleshooting

### Scan finds no games

- Make sure your **Steam profile is public**
- Make sure your **wishlist is public**
- Test manually: `curl -sL "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=YOUR_ID"`

### Cache appears corrupted

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

### Refresh button not working

- Check sudo permissions: `sudo -u www-data sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh`
- Check logs: `tail -f /var/log/apache2/steam-wishlist-sales-error.log`

### PowerShell parsing error

The PowerShell script must be UTF-8 encoded with BOM. If you edit the file, save it as "UTF-8 with BOM" in your editor.

## Uninstall

```bash
sudo ./uninstall.sh
```

## License

MIT — see [LICENSE](LICENSE)
