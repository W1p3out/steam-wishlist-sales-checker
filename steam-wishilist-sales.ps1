<#
.SYNOPSIS
    Steam Wishlist Sales — Affiche les jeux en promo de votre wishlist Steam.

.DESCRIPTION
    Récupère votre wishlist Steam, identifie les jeux en promotion,
    génère une page HTML et l'ouvre dans votre navigateur.

.PARAMETER SteamID
    Votre Steam ID 64-bit (17 chiffres). Trouvez-le sur https://steamid.io/

.PARAMETER Country
    Code pays pour les prix (fr, us, uk, de, etc.)

.PARAMETER OutputPath
    Chemin du fichier HTML généré (optionnel)

.EXAMPLE
    .\SteamWishlistSales.ps1 -SteamID XXXXXXXXXXXXXXXXX
    .\SteamWishlistSales.ps1 -SteamID XXXXXXXXXXXXXXXXX -Country us
    .\SteamWishlistSales.ps1 XXXXXXXXXXXXXXXXX
#>

param(
    [Parameter(Position = 0)]
    [string]$SteamID,

    [Parameter()]
    [string]$Country = "fr",

    [Parameter()]
    [string]$OutputPath = ""
)

# ── Configuration ─────────────────────────────────────────────
$BatchSize = 30
$DelayMs = 2000
$CurrencySymbols = @{
    "fr" = "€"; "de" = "€"; "it" = "€"; "es" = "€"
    "us" = "`$"; "uk" = "£"; "ca" = "CA`$"; "au" = "A`$"
    "jp" = "¥"; "br" = "R`$"
}
$CurrSymbol = if ($CurrencySymbols.ContainsKey($Country)) { $CurrencySymbols[$Country] } else { "€" }

# ── Fonctions utilitaires ─────────────────────────────────────
function Write-Step { param($Msg) Write-Host "  ⏳ " -NoNewline -ForegroundColor Cyan; Write-Host $Msg }
function Write-Ok   { param($Msg) Write-Host "  ✅ " -NoNewline -ForegroundColor Green; Write-Host $Msg }
function Write-Warn { param($Msg) Write-Host "  ⚠️  " -NoNewline -ForegroundColor Yellow; Write-Host $Msg }
function Write-Err  { param($Msg) Write-Host "  ❌ " -NoNewline -ForegroundColor Red; Write-Host $Msg }

# ── Bannière ──────────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║    🎮  Steam Wishlist Sales Checker           ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── Demander le Steam ID si non fourni ────────────────────────
if (-not $SteamID) {
    Write-Host "  Entrez votre Steam ID 64-bit (17 chiffres)" -ForegroundColor White
    Write-Host "  Trouvez-le sur : " -NoNewline; Write-Host "https://steamid.io/" -ForegroundColor Cyan
    Write-Host ""
    $SteamID = Read-Host "  Steam ID"
}

if ($SteamID -notmatch '^\d{17}$') {
    Write-Err "Steam ID invalide : '$SteamID' (doit être 17 chiffres)"
    exit 1
}

# ── Chemin de sortie ──────────────────────────────────────────
if (-not $OutputPath) {
    $OutputPath = Join-Path $env:TEMP "steam-wishlist-sales.html"
}

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 1 : Récupérer la wishlist
# ═══════════════════════════════════════════════════════════════
Write-Step "Récupération de la wishlist..."

try {
    $WishlistUrl = "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=$SteamID"
    $WishlistData = Invoke-RestMethod -Uri $WishlistUrl -TimeoutSec 30
} catch {
    Write-Err "Impossible de récupérer la wishlist. Vérifiez que votre profil est public."
    exit 1
}

$AppIDs = @($WishlistData.response.items | ForEach-Object { $_.appid })
$Total = $AppIDs.Count

if ($Total -eq 0) {
    Write-Err "Wishlist vide ou inaccessible."
    exit 1
}

Write-Ok "Wishlist récupérée : $Total jeux"

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 2 : Récupérer les prix par lots
# ═══════════════════════════════════════════════════════════════
Write-Step "Récupération des prix par lots de $BatchSize..."

$AllPrices = @{}
$TotalBatches = [math]::Ceiling($Total / $BatchSize)

for ($i = 0; $i -lt $Total; $i += $BatchSize) {
    $BatchNum = [math]::Floor($i / $BatchSize) + 1
    $BatchIDs = ($AppIDs[$i..[math]::Min($i + $BatchSize - 1, $Total - 1)]) -join ","

    Write-Host "`r  ⏳ Lot $BatchNum/$TotalBatches..." -NoNewline

    try {
        $Url = "https://store.steampowered.com/api/appdetails?appids=$BatchIDs&cc=$Country&filters=price_overview"
        $Response = Invoke-RestMethod -Uri $Url -TimeoutSec 30

        foreach ($prop in $Response.PSObject.Properties) {
            $AppId = $prop.Name
            $Data = $prop.Value
            if ($Data.success -and $Data.data -and $Data.data.price_overview) {
                $Price = $Data.data.price_overview
                if ($Price.discount_percent -gt 0) {
                    $AllPrices[$AppId] = @{
                        normal_price = $Price.initial
                        sale_price   = $Price.final
                        discount_pct = $Price.discount_percent
                    }
                }
            }
        }
    } catch {
        # Lot échoué, on continue
    }

    if ($BatchNum -lt $TotalBatches) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

Write-Host ""
$SaleCount = $AllPrices.Count
Write-Ok "Jeux en promotion : $SaleCount"

if ($SaleCount -eq 0) {
    Write-Warn "Aucun jeu en promo dans votre wishlist."
    Write-Host ""
    exit 0
}

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 3 : Récupérer les noms des jeux en promo
# ═══════════════════════════════════════════════════════════════
Write-Step "Récupération des noms des $SaleCount jeux en promo..."

$Games = @()
$Done = 0

foreach ($AppId in $AllPrices.Keys) {
    $Done++
    if ($Done % 20 -eq 0) {
        Write-Host "`r  ⏳ $Done/$SaleCount noms récupérés..." -NoNewline
    }

    $Name = "App $AppId"
    $Image = "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/$AppId/header.jpg"

    try {
        $Url = "https://store.steampowered.com/api/appdetails?appids=$AppId&cc=$Country"
        $Detail = Invoke-RestMethod -Uri $Url -TimeoutSec 15
        $AppData = $Detail.$AppId

        if ($AppData.success -and $AppData.data) {
            if ($AppData.data.name) { $Name = $AppData.data.name }
            if ($AppData.data.header_image) { $Image = $AppData.data.header_image }
        }
    } catch {
        # Nom non récupéré, on garde "App XXXX"
    }

    $PriceInfo = $AllPrices[$AppId]
    $Games += [PSCustomObject]@{
        AppId       = $AppId
        Name        = $Name
        Image       = $Image
        NormalPrice = $PriceInfo.normal_price
        SalePrice   = $PriceInfo.sale_price
        DiscountPct = $PriceInfo.discount_pct
    }

    Start-Sleep -Milliseconds 1000
}

Write-Host ""
Write-Ok "Noms récupérés : $Done/$SaleCount"

# Trier par nom
$Games = $Games | Sort-Object { $_.Name.ToLower() }

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 4 : Générer la page HTML
# ═══════════════════════════════════════════════════════════════
Write-Step "Génération de la page HTML..."

$BestDiscount = ($Games | Measure-Object -Property DiscountPct -Maximum).Maximum
$CheapestPrice = ($Games | Measure-Object -Property SalePrice -Minimum).Minimum
$CheapestFmt = "{0:N2}" -f ($CheapestPrice / 100) -replace '\.', ','
$Now = Get-Date -Format "dd/MM/yyyy à HH:mm"
$Elapsed = $Stopwatch.Elapsed

# Générer les cartes HTML
$CardsHtml = ""
foreach ($Game in $Games) {
    $NormalFmt = "{0:N2}" -f ($Game.NormalPrice / 100) -replace '\.', ','
    $SaleFmt = "{0:N2}" -f ($Game.SalePrice / 100) -replace '\.', ','
    $SafeName = [System.Web.HttpUtility]::HtmlEncode($Game.Name)
    $SafeNameAttr = $SafeName -replace '"', '&quot;'

    $CardsHtml += @"
<a class="card" data-name="$SafeNameAttr" data-sale="$($Game.SalePrice)" data-disc="$($Game.DiscountPct)" href="https://store.steampowered.com/app/$($Game.AppId)" target="_blank" rel="noopener">
<div class="img-wrap"><img src="$($Game.Image)" alt="$SafeNameAttr" loading="lazy" /><span class="badge">-$($Game.DiscountPct)%</span></div>
<div class="info"><div class="name">$SafeName</div><div class="prices"><span class="old">$NormalFmt$CurrSymbol</span><span class="new">$SaleFmt$CurrSymbol</span></div></div></a>
"@
}

$Html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Steam Wishlist — Promotions</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Exo+2:wght@400;600;800&family=Outfit:wght@300;400;600&display=swap" rel="stylesheet">
<style>
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #0a0e14; color: #c6d4df; font-family: 'Outfit', sans-serif; min-height: 100vh; overflow-x: hidden; }
    body::before { content: ''; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: radial-gradient(ellipse 80% 50% at 20% 10%, rgba(102,192,244,0.04) 0%, transparent 60%), radial-gradient(ellipse 60% 40% at 80% 90%, rgba(164,208,7,0.03) 0%, transparent 60%); pointer-events: none; z-index: 0; }
    .container { max-width: 1500px; margin: 0 auto; padding: 28px 24px; position: relative; z-index: 1; }
    .header { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 12px; margin-bottom: 20px; padding-bottom: 18px; border-bottom: 1px solid rgba(102,192,244,0.1); }
    .header h1 { font-family: 'Exo 2', sans-serif; font-size: 1.8rem; font-weight: 800; color: #fff; letter-spacing: -0.02em; display: flex; align-items: center; gap: 12px; }
    .header-right { display: flex; align-items: center; gap: 14px; font-size: 0.82rem; color: #5a6a78; }
    .header-right .count { color: #66c0f4; font-weight: 600; font-size: 0.95rem; }
    .stats { display: flex; gap: 20px; flex-wrap: wrap; margin-bottom: 18px; padding: 14px 18px; background: rgba(255,255,255,0.02); border: 1px solid rgba(102,192,244,0.08); border-radius: 10px; font-size: 0.82rem; }
    .stats span { color: #8f98a0; } .stats .val { color: #66c0f4; font-weight: 600; } .stats .val-green { color: #a4d007; font-weight: 600; }
    .controls { display: flex; gap: 12px; margin-bottom: 20px; flex-wrap: wrap; align-items: center; }
    .search-box { flex: 1; min-width: 200px; max-width: 380px; }
    .search-box input { width: 100%; padding: 9px 18px; border-radius: 24px; border: 1px solid rgba(102,192,244,0.18); background: rgba(0,0,0,0.35); color: #c6d4df; font-size: 0.88rem; font-family: 'Outfit', sans-serif; outline: none; transition: border-color 0.25s, box-shadow 0.25s; }
    .search-box input:focus { border-color: #66c0f4; box-shadow: 0 0 12px rgba(102,192,244,0.15); }
    .search-box input::placeholder { color: #3e4f5e; }
    .toolbar { display: flex; gap: 6px; flex-wrap: wrap; }
    .toolbar button { background: rgba(102,192,244,0.06); border: 1px solid rgba(102,192,244,0.14); color: #8f98a0; padding: 7px 18px; border-radius: 24px; font-size: 0.82rem; cursor: pointer; transition: all 0.2s; font-family: 'Outfit', sans-serif; }
    .toolbar button:hover { background: rgba(102,192,244,0.14); color: #fff; }
    .toolbar button.active { background: linear-gradient(135deg, #66c0f4, #4a9fd4); color: #fff; border-color: transparent; font-weight: 600; box-shadow: 0 2px 12px rgba(102,192,244,0.25); }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 14px; }
    .card { background: linear-gradient(160deg, #141c27 0%, #0f1923 100%); border-radius: 10px; overflow: hidden; text-decoration: none; color: inherit; transition: transform 0.25s ease, box-shadow 0.25s ease; display: flex; flex-direction: column; border: 1px solid rgba(102,192,244,0.05); opacity: 0; animation: fadeSlideUp 0.4s ease forwards; }
    .card:hover { transform: translateY(-5px) scale(1.01); box-shadow: 0 12px 35px rgba(0,0,0,0.5), 0 0 20px rgba(102,192,244,0.06); }
    .img-wrap { position: relative; aspect-ratio: 460/215; overflow: hidden; background: #080c12; }
    .img-wrap img { width: 100%; height: 100%; object-fit: cover; transition: transform 0.4s ease; }
    .card:hover .img-wrap img { transform: scale(1.07); }
    .badge { position: absolute; top: 0; right: 0; background: linear-gradient(135deg, #a4d007, #7aa800); color: #fff; font-family: 'Exo 2', sans-serif; font-weight: 800; font-size: 0.92rem; padding: 5px 12px 5px 14px; border-radius: 0 0 0 10px; letter-spacing: -0.03em; text-shadow: 0 1px 3px rgba(0,0,0,0.3); }
    .info { padding: 12px 14px 14px; display: flex; flex-direction: column; gap: 7px; flex: 1; }
    .name { font-size: 0.92rem; font-weight: 600; color: #fff; line-height: 1.3; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
    .prices { display: flex; align-items: center; gap: 10px; margin-top: auto; }
    .old { font-size: 0.8rem; color: #6a7a88; text-decoration: line-through; }
    .new { font-family: 'Exo 2', sans-serif; font-size: 1.08rem; font-weight: 800; color: #a4d007; text-shadow: 0 0 10px rgba(164,208,7,0.15); }
    @keyframes fadeSlideUp { from { opacity: 0; transform: translateY(18px); } to { opacity: 1; transform: translateY(0); } }
    @media (max-width: 640px) { .container { padding: 14px 10px; } .header h1 { font-size: 1.3rem; } .grid { grid-template-columns: repeat(auto-fill, minmax(165px, 1fr)); gap: 8px; } }
</style>
</head>
<body>
<div class="container">
<div class="header">
    <h1><span style="font-size:1.5rem;filter:drop-shadow(0 0 8px rgba(102,192,244,0.5))">🎮</span> Steam Wishlist — Promos</h1>
    <div class="header-right">
        <span class="count" id="count">$SaleCount jeu$(if($SaleCount -gt 1){'x'}) en promo</span>
        <span>Généré le $Now ($([math]::Round($Elapsed.TotalSeconds))s)</span>
    </div>
</div>
<div class="stats">
    <span>Wishlist : <span class="val">$Total jeux</span></span>
    <span>En promo : <span class="val-green">$SaleCount</span></span>
    <span>Meilleure remise : <span class="val-green">-$($BestDiscount)%</span></span>
    <span>Prix le plus bas : <span class="val-green">$CheapestFmt$CurrSymbol</span></span>
</div>
<div class="controls">
    <div class="search-box"><input type="text" id="search" placeholder="Rechercher un jeu..." /></div>
    <div class="toolbar">
        <button class="active" data-sort="alpha">A→Z</button>
        <button data-sort="price_asc">Prix ↑</button>
        <button data-sort="price_desc">Prix ↓</button>
        <button data-sort="discount">% Promo</button>
    </div>
</div>
<div class="grid" id="grid">
$CardsHtml
</div>
<script>
document.querySelectorAll('.card').forEach((c,i) => { c.style.animationDelay = Math.min(i*30,800)+'ms'; });
document.querySelectorAll('.toolbar button').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.toolbar button').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        const grid = document.getElementById('grid');
        const cards = Array.from(grid.querySelectorAll('.card'));
        const mode = btn.dataset.sort;
        cards.sort((a,b) => {
            switch(mode) {
                case 'alpha': return a.dataset.name.localeCompare(b.dataset.name, 'fr', {sensitivity:'base'});
                case 'price_asc': return Number(a.dataset.sale) - Number(b.dataset.sale);
                case 'price_desc': return Number(b.dataset.sale) - Number(a.dataset.sale);
                case 'discount': return Number(b.dataset.disc) - Number(a.dataset.disc);
            }
        });
        cards.forEach((c,i) => { c.style.animation='none'; c.offsetHeight; c.style.animation=''; c.style.animationDelay=Math.min(i*20,500)+'ms'; grid.appendChild(c); });
    });
});
document.getElementById('search').addEventListener('input', e => {
    const q = e.target.value.toLowerCase();
    let visible = 0;
    document.querySelectorAll('.card').forEach(c => {
        const show = c.querySelector('.name').textContent.toLowerCase().includes(q);
        c.style.display = show ? '' : 'none';
        if (show) visible++;
    });
    document.getElementById('count').textContent = visible + ' jeu' + (visible > 1 ? 'x' : '') + ' en promo';
});
</script>
</div>
</body>
</html>
"@

# Écrire le fichier
Add-Type -AssemblyName System.Web
[System.IO.File]::WriteAllText($OutputPath, $Html, [System.Text.Encoding]::UTF8)

$Stopwatch.Stop()
Write-Ok "Page générée : $OutputPath"
Write-Ok "Durée totale : $([math]::Round($Elapsed.TotalSeconds))s"

# ── Ouvrir dans le navigateur ─────────────────────────────────
Write-Host ""
Write-Host "  Ouverture dans le navigateur..." -ForegroundColor Cyan
Start-Process $OutputPath

Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║          ✅ Terminé !                         ║" -ForegroundColor Green
Write-Host "  ╚═══════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""