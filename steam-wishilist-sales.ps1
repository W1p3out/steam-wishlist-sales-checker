<#
.SYNOPSIS
    Steam Wishlist Sales - Displays discounted games from your Steam wishlist.

.DESCRIPTION
    Fetches your Steam wishlist, identifies games on sale,
    generates an HTML page with genre filters and dual theme
    (Modern / Classic Steam), then opens it in your browser.
    Uses intelligent caching to speed up subsequent scans.

.PARAMETER SteamID
    Your 64-bit Steam ID (17 digits). Find it at https://steamid.io/

.PARAMETER Country
    Country code for pricing (fr, us, uk, de, etc.)

.PARAMETER OutputPath
    Path for the generated HTML file (optional)

.PARAMETER ClearCache
    Deletes the cache before scanning (forces a full refresh)

.EXAMPLE
    .\SteamWishlistSales.ps1 -SteamID 12345678901234567
    .\SteamWishlistSales.ps1 -SteamID 12345678901234567 -Country us
    .\SteamWishlistSales.ps1 12345678901234567 -ClearCache
#>

param(
    [Parameter(Position = 0)]
    [string]$SteamID,

    [Parameter()]
    [string]$Country = "fr",

    [Parameter()]
    [string]$OutputPath = "",

    [Parameter()]
    [switch]$ClearCache
)

# -- Configuration -------------------------------------------------
$BatchSize = 30
$DelayMs = 2000
$CurrencySymbols = @{
    "fr" = [char]0x20AC; "de" = [char]0x20AC; "it" = [char]0x20AC; "es" = [char]0x20AC
    "us" = "$"; "uk" = [char]0x00A3; "ca" = "CA$"; "au" = "A$"
    "jp" = [char]0x00A5; "br" = "R$"
}
$CurrSymbol = if ($CurrencySymbols.ContainsKey($Country)) { $CurrencySymbols[$Country] } else { [char]0x20AC }

# -- Utility functions ---------------------------------------------
function Write-Step { param($Msg) Write-Host '  [..] ' -NoNewline -ForegroundColor Cyan; Write-Host $Msg }
function Write-Ok   { param($Msg) Write-Host '  [OK] ' -NoNewline -ForegroundColor Green; Write-Host $Msg }
function Write-Warn { param($Msg) Write-Host '  [!!] ' -NoNewline -ForegroundColor Yellow; Write-Host $Msg }
function Write-Err  { param($Msg) Write-Host '  [ERR] ' -NoNewline -ForegroundColor Red; Write-Host $Msg }

# -- Banner --------------------------------------------------------
Write-Host ''
Write-Host '  +===============================================+' -ForegroundColor Cyan
Write-Host '  |    Steam Wishlist Sales Checker               |' -ForegroundColor Cyan
Write-Host '  +===============================================+' -ForegroundColor Cyan
Write-Host ''

# -- Ask for Steam ID if not provided -----------------------------
if (-not $SteamID) {
    Write-Host '  Enter your 64-bit Steam ID - 17 digits' -ForegroundColor White
    Write-Host '  Find it at: ' -NoNewline; Write-Host 'https://steamid.io/' -ForegroundColor Cyan
    Write-Host ''
    $SteamID = Read-Host '  Steam ID'
}

if ($SteamID -notmatch '^\d{17}$') {
    Write-Err "Steam ID invalide : '$SteamID' - doit contenir 17 chiffres"
    exit 1
}

# -- Output paths --------------------------------------------------
if (-not $OutputPath) {
    $OutputPath = Join-Path $env:TEMP 'steam-wishlist-sales.html'
}
$CacheDir = Join-Path $env:APPDATA 'SteamWishlistSales'
$CachePath = Join-Path $CacheDir "cache_$SteamID.json"

if (-not (Test-Path $CacheDir)) {
    New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
}

if ($ClearCache -and (Test-Path $CachePath)) {
    Remove-Item $CachePath -Force
    Write-Warn 'Cache supprime.'
}

# Load existing cache
$Cache = @{}
if (Test-Path $CachePath) {
    try {
        $CacheRaw = Get-Content $CachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $CacheRaw.PSObject.Properties) {
            $Cache[$prop.Name] = @{
                name   = $prop.Value.name
                img    = $prop.Value.img
                genres = $prop.Value.genres
            }
        }
    } catch {
        $Cache = @{}
    }
}

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# ==================================================================
# STEP 1: Fetch wishlist
# ==================================================================
Write-Step 'Recuperation de la wishlist...'

try {
    $WishlistUrl = "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=$SteamID"
    $WishlistData = Invoke-RestMethod -Uri $WishlistUrl -TimeoutSec 30
} catch {
    Write-Err 'Impossible de recuperer la wishlist. Verifiez que votre profil est public.'
    exit 1
}

$AppIDs = @($WishlistData.response.items | ForEach-Object { $_.appid })
$Total = $AppIDs.Count

if ($Total -eq 0) {
    Write-Err 'Wishlist vide ou inaccessible.'
    exit 1
}

Write-Ok "Wishlist recuperee : $Total jeux"

# ==================================================================
# STEP 2: Fetch prices in batches
# ==================================================================
Write-Step "Recuperation des prix par lots de $BatchSize..."

$AllPrices = @{}
$TotalBatches = [math]::Ceiling($Total / $BatchSize)

for ($i = 0; $i -lt $Total; $i += $BatchSize) {
    $BatchNum = [math]::Floor($i / $BatchSize) + 1
    $BatchIDs = ($AppIDs[$i..[math]::Min($i + $BatchSize - 1, $Total - 1)]) -join ','

    Write-Host "`r  [..] Lot $BatchNum/$TotalBatches..." -NoNewline

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
        # Batch failed, continue
    }

    if ($BatchNum -lt $TotalBatches) {
        Start-Sleep -Milliseconds $DelayMs
    }
}

Write-Host ''
$SaleCount = $AllPrices.Count
Write-Ok "Jeux en promotion : $SaleCount"

if ($SaleCount -eq 0) {
    Write-Warn 'Aucun jeu en promo dans votre wishlist.'
    Write-Host ''
    exit 0
}

# ==================================================================
# STEP 3: Fetch names/images/genres with SMART CACHE
# ==================================================================
$Games = @()
$MissingIDs = @()
$CachedCount = 0

foreach ($AppId in $AllPrices.Keys) {
    if ($Cache.ContainsKey($AppId) -and $Cache[$AppId].name -and $Cache[$AppId].name.Length -gt 0) {
        $CachedCount++
    } else {
        $MissingIDs += $AppId
    }
}

$MissingCount = $MissingIDs.Count
Write-Ok "Cache : $CachedCount en cache, $MissingCount a recuperer"

if ($MissingCount -gt 0) {
    Write-Step "Recuperation des noms/genres de $MissingCount nouveaux jeux..."

    $Done = 0
    foreach ($AppId in $MissingIDs) {
        $Done++
        if ($Done % 20 -eq 0) {
            Write-Host "`r  [..] $Done/$MissingCount noms recuperes..." -NoNewline
        }

        try {
            $Url = "https://store.steampowered.com/api/appdetails?appids=$AppId&cc=$Country"
            $Detail = Invoke-RestMethod -Uri $Url -TimeoutSec 15
            $AppData = $Detail.$AppId

            if ($AppData.success -and $AppData.data) {
                $AppName = if ($AppData.data.name) { $AppData.data.name } else { '' }
                $AppImg = if ($AppData.data.header_image) { $AppData.data.header_image } else { '' }
                $AppGenres = ''
                if ($AppData.data.genres) {
                    $AppGenres = ($AppData.data.genres | ForEach-Object { $_.description }) -join ','
                }

                $Cache[$AppId] = @{
                    name   = $AppName
                    img    = $AppImg
                    genres = $AppGenres
                }
            }
        } catch {
            # Continue
        }

        Start-Sleep -Milliseconds 1000
    }

    if ($MissingCount -ge 20) { Write-Host '' }
    Write-Ok "Nouveaux noms recuperes : $Done/$MissingCount"
} else {
    Write-Ok 'Tous les jeux sont en cache! Aucun appel API necessaire.'
}

# Save updated cache
$CacheExport = @{}
foreach ($key in $Cache.Keys) {
    $CacheExport[$key] = $Cache[$key]
}
$CacheExport | ConvertTo-Json -Depth 5 | Set-Content -Path $CachePath -Encoding UTF8
Write-Ok "Cache sauvegarde : $CachePath"

# Build enriched game list
foreach ($AppId in $AllPrices.Keys) {
    $PriceInfo = $AllPrices[$AppId]
    $CacheEntry = if ($Cache.ContainsKey($AppId)) { $Cache[$AppId] } else { $null }

    $Name = if ($CacheEntry -and $CacheEntry.name) { $CacheEntry.name } else { "App $AppId" }
    $Image = if ($CacheEntry -and $CacheEntry.img) { $CacheEntry.img } else {
        "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/$AppId/header.jpg"
    }
    $Genres = if ($CacheEntry -and $CacheEntry.genres) { $CacheEntry.genres } else { '' }

    $Games += [PSCustomObject]@{
        AppId       = $AppId
        Name        = $Name
        Image       = $Image
        NormalPrice = $PriceInfo.normal_price
        SalePrice   = $PriceInfo.sale_price
        DiscountPct = $PriceInfo.discount_pct
        Genres      = $Genres
    }
}

$Games = $Games | Sort-Object { $_.Name.ToLower() }

# ==================================================================
# STEP 4: Generate HTML page
# ==================================================================
Write-Step 'Generation de la page HTML...'

Add-Type -AssemblyName System.Web

$BestDiscount = ($Games | Measure-Object -Property DiscountPct -Maximum).Maximum
$CheapestPrice = ($Games | Measure-Object -Property SalePrice -Minimum).Minimum
$CheapestFmt = "{0:N2}" -f ($CheapestPrice / 100) -replace '\.', ','
$Now = Get-Date -Format 'dd/MM/yyyy HH:mm'
$Elapsed = $Stopwatch.Elapsed

# Extract unique genres for filter buttons
$AllGenres = @()
foreach ($Game in $Games) {
    if ($Game.Genres -and $Game.Genres.Length -gt 0) {
        $AllGenres += $Game.Genres -split ','
    }
}
$AllGenres = $AllGenres | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Sort-Object -Unique

$GenreButtonsHtml = ''
foreach ($Genre in $AllGenres) {
    $SafeGenre = [System.Web.HttpUtility]::HtmlEncode($Genre.Trim())
    $GenreButtonsHtml += "<button class=`"genre-btn`" data-genre=`"$SafeGenre`">$SafeGenre</button>"
}

# Generate card HTML
$CardsHtml = ''
foreach ($Game in $Games) {
    $NormalFmt = "{0:N2}" -f ($Game.NormalPrice / 100) -replace '\.', ','
    $SaleFmt = "{0:N2}" -f ($Game.SalePrice / 100) -replace '\.', ','
    $SafeName = [System.Web.HttpUtility]::HtmlEncode($Game.Name)
    $SafeNameAttr = $SafeName -replace '"', '&quot;'

    $GenreTagsHtml = ''
    $GenresData = ''
    if ($Game.Genres -and $Game.Genres.Length -gt 0) {
        $GenresData = $Game.Genres
        $GenreSplit = $Game.Genres -split ','
        foreach ($g in $GenreSplit) {
            $gt = $g.Trim()
            if ($gt.Length -gt 0) {
                $SafeG = [System.Web.HttpUtility]::HtmlEncode($gt)
                $GenreTagsHtml += "<span class=`"genre-tag`">$SafeG</span>"
            }
        }
    }

    $CardsHtml += @"
<a class="card" data-name="$SafeNameAttr" data-sale="$($Game.SalePrice)" data-disc="$($Game.DiscountPct)" data-genres="$GenresData" href="https://store.steampowered.com/app/$($Game.AppId)" target="_blank" rel="noopener">
<div class="img-wrap"><img src="$($Game.Image)" alt="$SafeNameAttr" loading="lazy" /><span class="badge">-$($Game.DiscountPct)%</span></div>
<div class="info"><div class="name">$SafeName</div><div class="genres-row">$GenreTagsHtml</div><div class="prices"><span class="old">$NormalFmt$CurrSymbol</span><span class="new">$SaleFmt$CurrSymbol</span></div></div></a>
"@
}

$SaleCountPlural = if ($SaleCount -gt 1) { 'x' } else { '' }
$ElapsedSec = [math]::Round($Elapsed.TotalSeconds)
$Html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Steam Wishlist &#8212; Promotions</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Exo+2:wght@400;600;800&family=Outfit:wght@300;400;600&display=swap" rel="stylesheet">
<style>
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #0a0e14; color: #c6d4df; font-family: 'Outfit', sans-serif; min-height: 100vh; overflow-x: hidden; }
    body::before { content: ''; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: radial-gradient(ellipse 80% 50% at 20% 10%, rgba(102,192,244,0.04) 0%, transparent 60%), radial-gradient(ellipse 60% 40% at 80% 90%, rgba(164,208,7,0.03) 0%, transparent 60%); pointer-events: none; z-index: 0; }
    .container { max-width: 1500px; margin: 0 auto; padding: 28px 24px; position: relative; z-index: 1; }
    .header { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 12px; margin-bottom: 20px; padding-bottom: 18px; border-bottom: 1px solid rgba(102,192,244,0.1); }
    .header h1 { font-family: 'Exo 2', sans-serif; font-size: 1.8rem; font-weight: 800; color: #fff; letter-spacing: -0.02em; display: flex; align-items: center; gap: 12px; }
    .header h1 .icon { font-size: 1.5rem; filter: drop-shadow(0 0 8px rgba(102,192,244,0.5)); }
    .header-right { display: flex; align-items: center; gap: 14px; font-size: 0.82rem; color: #5a6a78; flex-wrap: wrap; }
    .header-right .count { color: #66c0f4; font-weight: 600; font-size: 0.95rem; }
    .theme-btn { display: inline-flex; align-items: center; gap: 5px; background: rgba(164,208,7,0.08); border: 1px solid rgba(164,208,7,0.2); color: #a4d007; padding: 6px 14px; border-radius: 20px; font-size: 0.78rem; font-family: 'Outfit', sans-serif; cursor: pointer; transition: all 0.25s; }
    .theme-btn:hover { background: rgba(164,208,7,0.18); color: #fff; border-color: #a4d007; }
    .stats { display: flex; gap: 20px; flex-wrap: wrap; margin-bottom: 18px; padding: 14px 18px; background: rgba(255,255,255,0.02); border: 1px solid rgba(102,192,244,0.08); border-radius: 10px; font-size: 0.82rem; }
    .stats span { color: #8f98a0; } .stats .val { color: #66c0f4; font-weight: 600; } .stats .val-green { color: #a4d007; font-weight: 600; }
    .controls { display: flex; gap: 12px; margin-bottom: 14px; flex-wrap: wrap; align-items: center; }
    .search-box { flex: 1; min-width: 200px; max-width: 380px; }
    .search-box input { width: 100%; padding: 9px 18px; border-radius: 24px; border: 1px solid rgba(102,192,244,0.18); background: rgba(0,0,0,0.35); color: #c6d4df; font-size: 0.88rem; font-family: 'Outfit', sans-serif; outline: none; transition: border-color 0.25s, box-shadow 0.25s; }
    .search-box input:focus { border-color: #66c0f4; box-shadow: 0 0 12px rgba(102,192,244,0.15); }
    .search-box input::placeholder { color: #3e4f5e; }
    .toolbar { display: flex; gap: 6px; flex-wrap: wrap; }
    .toolbar button { background: rgba(102,192,244,0.06); border: 1px solid rgba(102,192,244,0.14); color: #8f98a0; padding: 7px 18px; border-radius: 24px; font-size: 0.82rem; cursor: pointer; transition: all 0.2s; font-family: 'Outfit', sans-serif; }
    .toolbar button:hover { background: rgba(102,192,244,0.14); color: #fff; }
    .toolbar button.active { background: linear-gradient(135deg, #66c0f4, #4a9fd4); color: #fff; border-color: transparent; font-weight: 600; box-shadow: 0 2px 12px rgba(102,192,244,0.25); }
    .genre-filters { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 18px; }
    .genre-btn { background: rgba(164,208,7,0.06); border: 1px solid rgba(164,208,7,0.12); color: #6a7a58; padding: 5px 14px; border-radius: 20px; font-size: 0.75rem; cursor: pointer; transition: all 0.2s; font-family: 'Outfit', sans-serif; }
    .genre-btn:hover { background: rgba(164,208,7,0.14); color: #a4d007; }
    .genre-btn.active { background: linear-gradient(135deg, #a4d007, #7aa800); color: #fff; border-color: transparent; font-weight: 600; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 14px; }
    .card { background: linear-gradient(160deg, #141c27 0%, #0f1923 100%); border-radius: 10px; overflow: hidden; text-decoration: none; color: inherit; transition: transform 0.25s ease, box-shadow 0.25s ease; display: flex; flex-direction: column; border: 1px solid rgba(102,192,244,0.05); opacity: 0; animation: fadeSlideUp 0.4s ease forwards; }
    .card:hover { transform: translateY(-5px) scale(1.01); box-shadow: 0 12px 35px rgba(0,0,0,0.5), 0 0 20px rgba(102,192,244,0.06); }
    .img-wrap { position: relative; aspect-ratio: 460/215; overflow: hidden; background: #080c12; }
    .img-wrap img { width: 100%; height: 100%; object-fit: cover; transition: transform 0.4s ease; }
    .card:hover .img-wrap img { transform: scale(1.07); }
    .badge { position: absolute; top: 0; right: 0; background: linear-gradient(135deg, #a4d007, #7aa800); color: #fff; font-family: 'Exo 2', sans-serif; font-weight: 800; font-size: 0.92rem; padding: 5px 12px 5px 14px; border-radius: 0 0 0 10px; letter-spacing: -0.03em; text-shadow: 0 1px 3px rgba(0,0,0,0.3); }
    .info { padding: 12px 14px 14px; display: flex; flex-direction: column; gap: 5px; flex: 1; }
    .name { font-size: 0.92rem; font-weight: 600; color: #fff; line-height: 1.3; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
    .genres-row { display: flex; gap: 4px; flex-wrap: wrap; min-height: 18px; }
    .genre-tag { font-size: 0.62rem; color: #6a7a88; background: rgba(255,255,255,0.04); padding: 1px 7px; border-radius: 8px; white-space: nowrap; }
    .prices { display: flex; align-items: center; gap: 10px; margin-top: auto; }
    .old { font-size: 0.8rem; color: #6a7a88; text-decoration: line-through; }
    .new { font-family: 'Exo 2', sans-serif; font-size: 1.08rem; font-weight: 800; color: #a4d007; text-shadow: 0 0 10px rgba(164,208,7,0.15); }
    @keyframes fadeSlideUp { from { opacity: 0; transform: translateY(18px); } to { opacity: 1; transform: translateY(0); } }
    @media (max-width: 640px) { .container { padding: 14px 10px; } .header h1 { font-size: 1.3rem; } .grid { grid-template-columns: repeat(auto-fill, minmax(165px, 1fr)); gap: 8px; } .info { padding: 8px 10px 10px; } .name { font-size: 0.82rem; } .badge { font-size: 0.8rem; padding: 3px 9px 3px 11px; } .stats { gap: 12px; font-size: 0.75rem; } }

    /* CLASSIC STEAM THEME */
    body.classic { background: #3b4a36; color: #d2d2d2; font-family: Tahoma, Verdana, Arial, sans-serif; }
    body.classic::before { background: linear-gradient(180deg, #4a5a42 0%, #3b4a36 40%, #2d3a28 100%); }
    body.classic .container { max-width: 1200px; padding: 12px 16px; }
    body.classic .header { background: linear-gradient(180deg, #5c7a49 0%, #4a6637 100%); border: 1px solid #6b8a56; border-bottom: 2px solid #2d3a28; border-radius: 0; padding: 8px 14px; margin-bottom: 10px; }
    body.classic .header h1 { font-family: Tahoma, Verdana, sans-serif; font-size: 1.15rem; font-weight: bold; color: #d2e8b0; letter-spacing: 0; text-shadow: 1px 1px 2px rgba(0,0,0,0.5); }
    body.classic .header h1 .icon { font-size: 1rem; filter: none; }
    body.classic .header-right { font-size: 0.72rem; color: #a0b890; }
    body.classic .header-right .count { color: #d2e8b0; font-size: 0.78rem; }
    body.classic .theme-btn { background: linear-gradient(180deg, #6b8a56 0%, #4a6637 100%); border: 1px solid #7a9a64; border-bottom: 1px solid #3a5228; color: #d2e8b0; border-radius: 3px; padding: 3px 12px; font-family: Tahoma, sans-serif; font-size: 0.72rem; }
    body.classic .theme-btn:hover { background: linear-gradient(180deg, #7a9a64 0%, #5a7a47 100%); color: #fff; }
    body.classic .stats { background: linear-gradient(180deg, #4a5a42 0%, #3e4e38 100%); border: 1px solid #5a6a52; border-radius: 0; padding: 8px 12px; font-size: 0.72rem; }
    body.classic .stats span { color: #a0b890; } body.classic .stats .val { color: #d2e8b0; } body.classic .stats .val-green { color: #a4d007; }
    body.classic .search-box input { border-radius: 2px; border: 1px solid #5a6a52; background: #2d3a28; color: #d2d2d2; font-family: Tahoma, sans-serif; font-size: 0.78rem; padding: 5px 10px; }
    body.classic .search-box input:focus { border-color: #7a9a64; box-shadow: none; }
    body.classic .search-box input::placeholder { color: #6a7a62; }
    body.classic .toolbar button { background: linear-gradient(180deg, #5c7a49 0%, #4a6637 100%); border: 1px solid #6b8a56; border-bottom: 1px solid #3a5228; color: #a0b890; border-radius: 2px; padding: 4px 12px; font-family: Tahoma, sans-serif; font-size: 0.72rem; }
    body.classic .toolbar button:hover { color: #d2e8b0; }
    body.classic .toolbar button.active { background: linear-gradient(180deg, #7a9a64 0%, #5a7a47 100%); color: #fff; border-color: #8aaa74; box-shadow: inset 0 1px 0 rgba(255,255,255,0.1); }
    body.classic .genre-btn { background: linear-gradient(180deg, #4a5a42 0%, #3e4e38 100%); border: 1px solid #5a6a52; color: #8a9a80; border-radius: 2px; padding: 3px 10px; font-family: Tahoma, sans-serif; font-size: 0.68rem; }
    body.classic .genre-btn:hover { color: #d2e8b0; }
    body.classic .genre-btn.active { background: linear-gradient(180deg, #7a9a64 0%, #5a7a47 100%); color: #fff; border-color: #8aaa74; }
    body.classic .grid { gap: 8px; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); }
    body.classic .card { background: linear-gradient(180deg, #4a5a42 0%, #3e4e38 100%); border: 1px solid #5a6a52; border-radius: 0; animation: none; opacity: 1; }
    body.classic .card:hover { transform: none; box-shadow: 0 0 0 1px #8aaa74; border-color: #8aaa74; }
    body.classic .card:hover .img-wrap img { transform: none; }
    body.classic .img-wrap { background: #2d3a28; }
    body.classic .badge { background: #4a7a20; border-radius: 0; font-family: Tahoma, sans-serif; font-size: 0.82rem; font-weight: bold; padding: 2px 8px; }
    body.classic .info { padding: 8px 10px 10px; gap: 4px; }
    body.classic .name { font-size: 0.8rem; font-weight: bold; font-family: Tahoma, sans-serif; color: #d2e8b0; }
    body.classic .genre-tag { font-size: 0.58rem; color: #8a9a80; background: rgba(0,0,0,0.2); border-radius: 2px; padding: 1px 5px; }
    body.classic .old { font-size: 0.72rem; color: #8a9a80; }
    body.classic .new { font-family: Tahoma, sans-serif; font-size: 0.88rem; font-weight: bold; color: #a4d007; text-shadow: none; }
</style>
</head>
<body>
<div class="container">
<div class="header">
    <h1><span class="icon">&#127918;</span> Steam Wishlist &#8212; Promos</h1>
    <div class="header-right">
        <span class="count" id="count">$SaleCount jeu$SaleCountPlural en promo</span>
        <span>Genere le $Now (${ElapsedSec}s)</span>
        <button class="theme-btn" id="themeToggle" onclick="toggleTheme()">&#128421; Classic Steam</button>
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
        <button class="active" data-sort="alpha">A&#8594;Z</button>
        <button data-sort="price_asc">Prix &#8593;</button>
        <button data-sort="price_desc">Prix &#8595;</button>
        <button data-sort="discount">% Promo</button>
    </div>
</div>
<div class="genre-filters" id="genreFilters">
    <button class="genre-btn active" data-genre="all">Tous</button>
    $GenreButtonsHtml
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
let activeGenre = 'all';
function applyFilters() {
    const q = document.getElementById('search').value.toLowerCase();
    let visible = 0;
    document.querySelectorAll('.card').forEach(c => {
        const name = c.querySelector('.name').textContent.toLowerCase();
        const genres = (c.dataset.genres || '').toLowerCase();
        const matchSearch = name.includes(q);
        const matchGenre = activeGenre === 'all' || genres.split(',').some(g => g.trim().toLowerCase() === activeGenre.toLowerCase());
        const show = matchSearch && matchGenre;
        c.style.display = show ? '' : 'none';
        if (show) visible++;
    });
    document.getElementById('count').textContent = visible + ' jeu' + (visible > 1 ? 'x' : '') + ' en promo';
}
document.getElementById('search').addEventListener('input', applyFilters);
document.querySelectorAll('.genre-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.genre-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        activeGenre = btn.dataset.genre;
        applyFilters();
    });
});
function toggleTheme() {
    const body = document.body;
    const btn = document.getElementById('themeToggle');
    if (body.classList.contains('classic')) {
        body.classList.remove('classic');
        btn.innerHTML = '&#128421; Classic Steam';
        document.cookie = 'theme=modern;path=/;max-age=31536000';
    } else {
        body.classList.add('classic');
        btn.innerHTML = '&#10024; Modern';
        document.cookie = 'theme=classic;path=/;max-age=31536000';
    }
}
(function() {
    const m = document.cookie.match(/theme=(\w+)/);
    if (m && m[1] === 'classic') {
        document.body.classList.add('classic');
        document.getElementById('themeToggle').innerHTML = '&#10024; Modern';
    }
})();
</script>
</div>
</body>
</html>
"@

[System.IO.File]::WriteAllText($OutputPath, $Html, [System.Text.Encoding]::UTF8)

$Stopwatch.Stop()
Write-Ok "Page generee : $OutputPath"
Write-Ok "Duree totale : $([math]::Round($Stopwatch.Elapsed.TotalSeconds))s"

# -- Open in browser -----------------------------------------------
Write-Host ''
Write-Host '  Ouverture dans le navigateur...' -ForegroundColor Cyan
Start-Process $OutputPath

Write-Host ''
Write-Host '  +===============================================+' -ForegroundColor Green
Write-Host '  |          [OK] Termine !                       |' -ForegroundColor Green
Write-Host '  +===============================================+' -ForegroundColor Green
Write-Host ''
