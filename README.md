# 🎮 Steam Wishlist Sales

Automatically monitors your Steam wishlist and displays games on sale on a sleek, self-hosted web page.

![Steam Wishlist Sales](screenshots/preview.png)

## Features

- **Automatic scanning** of your wishlist via the Steam API (every 6 hours by default)
- **Self-hosted web page** with a Steam-inspired design
- **Filters and sorting**: alphabetical, price ascending/descending, discount %
- **Real-time search** by game name
- **Manual refresh button** with live scan progress tracking
- **Statistics**: number of deals, best discount, lowest price, next scan countdown
- **Responsive**: adapts to mobile and desktop
- **Lightweight**: static HTML page, no database

## Prerequisites

- **Linux** (Debian/Ubuntu recommended)
- **Apache2** with **PHP 8.x**
- **curl**, **jq**, **bc**
- A **public Steam profile** with a **public wishlist**

## Quick Install

```bash
git clone https://github.com/YOUR_USER/steam-wishlist-sales.git
cd steam-wishlist-sales
sudo ./install.sh
```

The install script will ask you for:

| Parameter | Description | Example |
|---|---|---|
| **Steam ID** | Your 64-bit Steam identifier (17 digits) | `76561198040773990` |
| **Port** | Web server port | `2251` |
| **Scan hours** | Automatic scan hours (cron format) | `1,7,13,19` |

> 💡 **Find your Steam ID**: go to [steamid.io](https://steamid.io/) and enter your Steam profile URL.

> ⚠️ **Your profile and wishlist must be set to public** for the scan to work.

## Manual Installation

### 1. Install dependencies

```bash
sudo apt update
sudo apt install curl jq bc apache2 php libapache2-mod-php sudo
```

### 2. Copy files

```bash
# Main script
sudo mkdir -p /opt/steam-wishlist-sales
sudo cp scripts/steam-wishlist-sales.sh /opt/steam-wishlist-sales/
sudo chmod +x /opt/steam-wishlist-sales/steam-wishlist-sales.sh

# Web files
sudo mkdir -p /var/www/steam-wishlist-sales
sudo cp web/run.php web/update.php /var/www/steam-wishlist-sales/
```

### 3. Configure your Steam ID

Edit the script and replace the Steam ID:

```bash
sudo nano /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

```bash
STEAM_ID="YOUR_STEAM_ID_HERE"
```

### 4. Configure Apache

Create the file `/etc/apache2/sites-available/steam-wishlist-sales.conf`:

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

### 5. Configure permissions

Allow Apache (www-data) to execute the script:

```bash
echo "www-data ALL=(ALL) NOPASSWD: /opt/steam-wishlist-sales/steam-wishlist-sales.sh" | sudo tee /etc/sudoers.d/steam-wishlist-sales
sudo chmod 440 /etc/sudoers.d/steam-wishlist-sales
```

### 6. Configure cron

```bash
crontab -e
```

Add this line for a scan every 6 hours:

```
5 1,7,13,19 * * * /opt/steam-wishlist-sales/steam-wishlist-sales.sh > /tmp/steam-wishlist-current.log 2>&1
```

### 7. First scan

```bash
sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh
```

The first scan takes about 5 minutes for a wishlist of ~1300 games.

## Usage

### Access the page

Open your browser and go to:

```
http://YOUR_IP:2251/
```

### Manual refresh

Click the **↻ Refresh** button in the top right corner of the page. A progress page will show the scan log in real time, then automatically redirect to the results.

### Page features

- **Sort**: click the A→Z, Price ↑, Price ↓, % Discount buttons
- **Search**: type a game name in the search bar
- **Next scan**: displayed in the stats bar with a countdown timer
- **Steam link**: click a card to open the game's Steam store page

## Architecture

```
steam-wishlist-sales/
├── install.sh                     # Automated install script
├── uninstall.sh                   # Uninstall script
├── README.md                      # This file
├── LICENSE
├── screenshots/                   # Screenshots
│   └── preview.png
├── scripts/
│   └── steam-wishlist-sales.sh    # Main scan script
└── web/
    ├── run.php                    # Manual scan trigger
    └── update.php                 # Scan progress page
```

### How it works

The `steam-wishlist-sales.sh` script works in 5 steps:

1. **Wishlist** — Fetches the full list of app IDs via `IWishlistService/GetWishlist` (1 API call)
2. **Prices** — Fetches prices in batches of 30 via `appdetails?filters=price_overview` (~46 calls)
3. **Filtering** — Identifies games with `discount_percent > 0`
4. **Names** — Fetches names and images of discounted games via `appdetails` (1 call per game)
5. **HTML** — Generates the static `index.html` page with the results

### Scan duration

| Wishlist size | Price step | Names step | Estimated total |
|---|---|---|---|
| ~500 games | ~40s | ~1min | ~2min |
| ~1000 games | ~1min20 | ~2min | ~4min |
| ~1500 games | ~1min40 | ~3min | ~5min |

### Steam APIs used

| Endpoint | Purpose | Auth required |
|---|---|---|
| `IWishlistService/GetWishlist/v1/` | List of app IDs in the wishlist | No (public profile) |
| `store.steampowered.com/api/appdetails` | Prices, names, images | No |

## Troubleshooting

### Scan finds no games

- Make sure your **Steam profile is public** (Steam Settings → Privacy → Public profile)
- Make sure your **wishlist is public** (same section, Game details → Public)
- Test manually: `curl -sL "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=YOUR_ID"`

### Refresh button doesn't work

- Check sudo permissions: `sudo -u www-data sudo /opt/steam-wishlist-sales/steam-wishlist-sales.sh`
- Check logs: `tail -f /var/log/apache2/steam-wishlist-sales-error.log`
- Check PHP works: `curl -sL "http://localhost:YOUR_PORT/run.php"`

### HTTP 302 error during scan

Make sure the `-sL` flag is present in the script's curl calls (the `L` flag follows redirects).

### Prices show 0.00€

Some games (F2P, delisted, DLC) don't have a price. They are automatically excluded from the results.

## Uninstall

```bash
sudo ./uninstall.sh
```

Or manually:

```bash
sudo a2dissite steam-wishlist-sales
sudo systemctl restart apache2
sudo rm -rf /opt/steam-wishlist-sales
sudo rm -rf /var/www/steam-wishlist-sales
sudo rm -f /etc/apache2/sites-available/steam-wishlist-sales.conf
sudo rm -f /etc/sudoers.d/steam-wishlist-sales
crontab -l | grep -v "steam-wishlist-sales" | crontab -
```

## License

MIT — see [LICENSE](LICENSE)
