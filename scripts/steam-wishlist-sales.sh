#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Steam Wishlist Sales - Générateur de page HTML statique
# ═══════════════════════════════════════════════════════════════
#
# Utilise l'API Steam :
#   1. IWishlistService/GetWishlist → récupère les app IDs
#   2. appdetails (par lots) → récupère les prix et promos
#   3. appdetails (individuel) → récupère les noms des jeux en promo
#
# Dépendances : curl, jq, bc
#   sudo apt install curl jq bc
#
# Usage :
#   ./steam-wishlist-sales.sh
#
# Cron (toutes les 6h à partir de 19h05) :
#   5 1,7,13,19 * * * /opt/steam-wishlist-sales/steam-wishlist-sales.sh >> /var/log/steam-wishlist-sales.log 2>&1
#
# ═══════════════════════════════════════════════════════════════

# ── Configuration ──────────────────────────────────────────────
STEAM_ID="VOTRE_STEAM_ID"
OUTPUT_DIR="/var/www/steam-wishlist-sales"
OUTPUT_FILE="${OUTPUT_DIR}/index.html"
TEMP_DIR="/tmp/steam-wishlist-$$"
LOCK_FILE="/tmp/steam-wishlist-sales.lock"
BATCH_SIZE=30
DELAY_SECONDS=2
COUNTRY_CODE="fr"

# ── Couleurs pour le log ──────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERR]${NC} $1"; }

# ── Vérification du lock ─────────────────────────────────────
if [ -f "$LOCK_FILE" ]; then
    LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_FILE") ))
    if [ "$LOCK_AGE" -lt 360 ]; then
        warn "Une mise à jour est déjà en cours (depuis ${LOCK_AGE}s). Abandon."
        exit 0
    fi
    warn "Lock périmé détecté (${LOCK_AGE}s), suppression."
    rm -f "$LOCK_FILE"
fi

touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"; rm -rf "$TEMP_DIR"' EXIT

# ── Vérification des dépendances ──────────────────────────────
for cmd in curl jq bc; do
    if ! command -v "$cmd" &>/dev/null; then
        err "Dépendance manquante : $cmd"
        exit 1
    fi
done

# ── Préparation ───────────────────────────────────────────────
mkdir -p "$TEMP_DIR"
mkdir -p "$OUTPUT_DIR"

START_TIME=$(date +%s)
log "Démarrage de la récupération de la wishlist Steam"
log "Steam ID : $STEAM_ID"

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 1 : Récupérer la liste des app IDs via IWishlistService
# ═══════════════════════════════════════════════════════════════
log "Récupération de la wishlist..."

WISHLIST_FILE="$TEMP_DIR/wishlist.json"
HTTP_CODE=$(curl -sL -o "$WISHLIST_FILE" -w "%{http_code}" \
    --connect-timeout 15 \
    --max-time 60 \
    "https://api.steampowered.com/IWishlistService/GetWishlist/v1/?steamid=${STEAM_ID}")

if [ "$HTTP_CODE" -ne 200 ]; then
    err "Impossible de récupérer la wishlist (HTTP $HTTP_CODE)"
    exit 1
fi

APP_IDS=($(jq -r '.response.items[].appid' "$WISHLIST_FILE" 2>/dev/null))
TOTAL=${#APP_IDS[@]}

if [ "$TOTAL" -eq 0 ]; then
    err "Wishlist vide ou inaccessible."
    exit 1
fi

ok "Wishlist récupérée : $TOTAL jeux"

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 2 : Récupérer les prix par lots via appdetails
# ═══════════════════════════════════════════════════════════════
log "Récupération des prix par lots de $BATCH_SIZE..."

PRICES_FILE="$TEMP_DIR/all_prices.json"
echo '{}' > "$PRICES_FILE"

BATCH_NUM=0
TOTAL_BATCHES=$(( (TOTAL + BATCH_SIZE - 1) / BATCH_SIZE ))

for (( i=0; i<TOTAL; i+=BATCH_SIZE )); do
    BATCH_NUM=$((BATCH_NUM + 1))

    BATCH_IDS=""
    for (( j=i; j<i+BATCH_SIZE && j<TOTAL; j++ )); do
        if [ -n "$BATCH_IDS" ]; then
            BATCH_IDS="${BATCH_IDS},"
        fi
        BATCH_IDS="${BATCH_IDS}${APP_IDS[$j]}"
    done

    BATCH_COUNT=$(( j - i ))
    log "Lot $BATCH_NUM/$TOTAL_BATCHES ($BATCH_COUNT jeux)..."

    BATCH_FILE="$TEMP_DIR/batch_${BATCH_NUM}.json"
    HTTP_CODE=$(curl -sL -o "$BATCH_FILE" -w "%{http_code}" \
        --connect-timeout 15 \
        --max-time 30 \
        "https://store.steampowered.com/api/appdetails?appids=${BATCH_IDS}&cc=${COUNTRY_CODE}&filters=price_overview")

    if [ "$HTTP_CODE" -eq 200 ]; then
            if jq -e 'type == "object"' "$BATCH_FILE" &>/dev/null; then
                jq -s '.[0] * .[1]' "$PRICES_FILE" "$BATCH_FILE" > "$TEMP_DIR/merged.json"
                mv "$TEMP_DIR/merged.json" "$PRICES_FILE"
            else
                warn "Lot $BATCH_NUM : réponse non-objet, ignoré."
            fi
    else
        warn "Lot $BATCH_NUM : HTTP $HTTP_CODE, ignoré."
    fi

    if [ $BATCH_NUM -lt $TOTAL_BATCHES ]; then
        sleep "$DELAY_SECONDS"
    fi
done

ok "Prix récupérés pour tous les lots."

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 3 : Filtrer les jeux en promotion
# ═══════════════════════════════════════════════════════════════
log "Filtrage des jeux en promotion..."

SALES_FILE="$TEMP_DIR/sales.json"

jq '
  [
    to_entries[]
    | select(.value | type == "object")
    | select(.value.success == true)
    | select(.value.data | type == "object")
    | select(.value.data.price_overview != null)
    | select(.value.data.price_overview | type == "object")
    | select(.value.data.price_overview.discount_percent > 0)
    | {
        appid: .key,
        name: ("App " + .key),
        capsule: ("https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/" + .key + "/header.jpg"),
        normal_price: .value.data.price_overview.initial,
        sale_price: .value.data.price_overview.final,
        discount_pct: .value.data.price_overview.discount_percent
      }
  ]
  | sort_by(.name | ascii_downcase)
' "$PRICES_FILE" > "$SALES_FILE" 2>/dev/null || echo '[]' > "$SALES_FILE"

SALE_COUNT=$(jq 'length' "$SALES_FILE" 2>/dev/null || echo "0")
SALE_COUNT=${SALE_COUNT:-0}
ok "Jeux en promotion : $SALE_COUNT"

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 4 : Récupérer les noms des jeux en promo (appel individuel)
# ═══════════════════════════════════════════════════════════════
if [ "$SALE_COUNT" -gt 0 ]; then
    log "Récupération des noms des $SALE_COUNT jeux en promo..."

    SALE_IDS=($(jq -r '.[].appid' "$SALES_FILE"))
    NAMES_FILE="$TEMP_DIR/names.json"
    echo '{}' > "$NAMES_FILE"

    DONE=0
    for APPID in "${SALE_IDS[@]}"; do
        DONE=$((DONE + 1))
        DETAIL_FILE="$TEMP_DIR/name_${APPID}.json"

        HTTP_CODE=$(curl -sL --compressed -o "$DETAIL_FILE" -w "%{http_code}" \
            --connect-timeout 10 \
            --max-time 15 \
            "https://store.steampowered.com/api/appdetails?appids=${APPID}&cc=${COUNTRY_CODE}")

        if [ "$HTTP_CODE" -eq 200 ] && jq -e 'type == "object"' "$DETAIL_FILE" &>/dev/null; then
            APP_NAME=$(jq -r --arg id "$APPID" '.[$id].data.name // empty' "$DETAIL_FILE" 2>/dev/null)
            APP_IMG=$(jq -r --arg id "$APPID" '.[$id].data.header_image // empty' "$DETAIL_FILE" 2>/dev/null)

            if [ -n "$APP_NAME" ]; then
                APP_NAME_ESCAPED=$(echo "$APP_NAME" | sed 's/"/\\"/g')
                APP_IMG_ESCAPED=$(echo "$APP_IMG" | sed 's/"/\\"/g')
                echo "{\"$APPID\":{\"name\":\"$APP_NAME_ESCAPED\",\"img\":\"$APP_IMG_ESCAPED\"}}" > "$TEMP_DIR/name_entry.json"
                jq -s '.[0] * .[1]' "$NAMES_FILE" "$TEMP_DIR/name_entry.json" > "$TEMP_DIR/names_merged.json"
                mv "$TEMP_DIR/names_merged.json" "$NAMES_FILE"
            fi
        fi

        if [ $((DONE % 20)) -eq 0 ]; then
            log "  $DONE/$SALE_COUNT noms récupérés..."
        fi

        sleep 1
    done

    ok "Noms récupérés : $DONE/$SALE_COUNT"

    ENRICHED_FILE="$TEMP_DIR/sales_enriched.json"
    jq --slurpfile names "$NAMES_FILE" '
      [
        .[] | . as $game |
        ($names[0][$game.appid] // null) as $detail |
        . + {
          name: (if $detail and $detail.name and ($detail.name | length > 0) then $detail.name else $game.name end),
          capsule: (if $detail and $detail.img and ($detail.img | length > 0) then $detail.img else $game.capsule end)
        }
      ]
      | sort_by(.name | ascii_downcase)
    ' "$SALES_FILE" > "$ENRICHED_FILE" 2>/dev/null
    mv "$ENRICHED_FILE" "$SALES_FILE"
fi

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 5 : Générer la page HTML finale
# ═══════════════════════════════════════════════════════════════
ELAPSED=$(( $(date +%s) - START_TIME ))
BEST_DISCOUNT=$(jq '[.[].discount_pct] | if length > 0 then max else 0 end' "$SALES_FILE" 2>/dev/null || echo "0")
CHEAPEST=$(jq '[.[].sale_price] | if length > 0 then min else 0 end' "$SALES_FILE" 2>/dev/null || echo "0")
CHEAPEST_FMT=$(echo "scale=2; ${CHEAPEST:-0} / 100" | bc 2>/dev/null | sed 's/\./,/' || echo "0,00")
NOW=$(date '+%d/%m/%Y à %H:%M')

CARDS_HTML=$(jq -r '
  .[] |
  "<a class=\"card\" data-name=\"\(.name | gsub("\""; "&quot;"))\" data-sale=\"\(.sale_price)\" data-disc=\"\(.discount_pct)\" href=\"https://store.steampowered.com/app/\(.appid)\" target=\"_blank\" rel=\"noopener\">"
  + "<div class=\"img-wrap\">"
  + "<img src=\"\(.capsule)\" alt=\"\(.name | gsub("\""; "&quot;"))\" loading=\"lazy\" />"
  + "<span class=\"badge\">-\(.discount_pct)%</span>"
  + "</div>"
  + "<div class=\"info\">"
  + "<div class=\"name\">\(.name | gsub("<"; "&lt;") | gsub(">"; "&gt;"))</div>"
  + "<div class=\"prices\">"
  + "<span class=\"old\">\(.normal_price / 100 | tostring | gsub("\\."; ",") | if test(",") then . else . + ",00" end)€</span>"
  + "<span class=\"new\">\(.sale_price / 100 | tostring | gsub("\\."; ",") | if test(",") then . else . + ",00" end)€</span>"
  + "</div>"
  + "</div></a>"
' "$SALES_FILE")

log "Génération de la page HTML..."

cat > "$OUTPUT_FILE" << 'HTMLHEAD'
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

    body {
        background: #0a0e14;
        color: #c6d4df;
        font-family: 'Outfit', sans-serif;
        min-height: 100vh;
        position: relative;
        overflow-x: hidden;
    }

    body::before {
        content: '';
        position: fixed;
        top: 0; left: 0; right: 0; bottom: 0;
        background:
            radial-gradient(ellipse 80% 50% at 20% 10%, rgba(102, 192, 244, 0.04) 0%, transparent 60%),
            radial-gradient(ellipse 60% 40% at 80% 90%, rgba(164, 208, 7, 0.03) 0%, transparent 60%);
        pointer-events: none;
        z-index: 0;
    }

    .container {
        max-width: 1500px;
        margin: 0 auto;
        padding: 28px 24px;
        position: relative;
        z-index: 1;
    }

    .header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        flex-wrap: wrap;
        gap: 12px;
        margin-bottom: 20px;
        padding-bottom: 18px;
        border-bottom: 1px solid rgba(102, 192, 244, 0.1);
    }
    .header h1 {
        font-family: 'Exo 2', sans-serif;
        font-size: 1.8rem;
        font-weight: 800;
        color: #fff;
        letter-spacing: -0.02em;
        display: flex;
        align-items: center;
        gap: 12px;
    }
    .header h1 .icon {
        font-size: 1.5rem;
        filter: drop-shadow(0 0 8px rgba(102, 192, 244, 0.5));
    }
    .header-right {
        display: flex;
        align-items: center;
        gap: 14px;
        font-size: 0.82rem;
        color: #5a6a78;
    }
    .header-right .count {
        color: #66c0f4;
        font-weight: 600;
        font-size: 0.95rem;
    }

    .refresh-btn {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        background: rgba(102, 192, 244, 0.08);
        border: 1px solid rgba(102, 192, 244, 0.2);
        color: #66c0f4;
        padding: 6px 16px;
        border-radius: 20px;
        font-size: 0.82rem;
        font-family: 'Outfit', sans-serif;
        cursor: pointer;
        transition: all 0.25s;
        text-decoration: none;
    }
    .refresh-btn:hover {
        background: rgba(102, 192, 244, 0.18);
        color: #fff;
        border-color: #66c0f4;
    }

    .stats {
        display: flex;
        gap: 20px;
        flex-wrap: wrap;
        margin-bottom: 18px;
        padding: 14px 18px;
        background: rgba(255,255,255,0.02);
        border: 1px solid rgba(102, 192, 244, 0.08);
        border-radius: 10px;
        font-size: 0.82rem;
    }
    .stats span { color: #8f98a0; }
    .stats .val { color: #66c0f4; font-weight: 600; }
    .stats .val-green { color: #a4d007; font-weight: 600; }

    .controls {
        display: flex;
        gap: 12px;
        margin-bottom: 20px;
        flex-wrap: wrap;
        align-items: center;
    }
    .search-box {
        flex: 1;
        min-width: 200px;
        max-width: 380px;
    }
    .search-box input {
        width: 100%;
        padding: 9px 18px;
        border-radius: 24px;
        border: 1px solid rgba(102, 192, 244, 0.18);
        background: rgba(0,0,0,0.35);
        color: #c6d4df;
        font-size: 0.88rem;
        font-family: 'Outfit', sans-serif;
        outline: none;
        transition: border-color 0.25s, box-shadow 0.25s;
    }
    .search-box input:focus {
        border-color: #66c0f4;
        box-shadow: 0 0 12px rgba(102, 192, 244, 0.15);
    }
    .search-box input::placeholder { color: #3e4f5e; }

    .toolbar {
        display: flex;
        gap: 6px;
        flex-wrap: wrap;
    }
    .toolbar button {
        background: rgba(102, 192, 244, 0.06);
        border: 1px solid rgba(102, 192, 244, 0.14);
        color: #8f98a0;
        padding: 7px 18px;
        border-radius: 24px;
        font-size: 0.82rem;
        cursor: pointer;
        transition: all 0.2s;
        font-family: 'Outfit', sans-serif;
    }
    .toolbar button:hover {
        background: rgba(102, 192, 244, 0.14);
        color: #fff;
    }
    .toolbar button.active {
        background: linear-gradient(135deg, #66c0f4, #4a9fd4);
        color: #fff;
        border-color: transparent;
        font-weight: 600;
        box-shadow: 0 2px 12px rgba(102, 192, 244, 0.25);
    }

    .grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
        gap: 14px;
    }

    .card {
        background: linear-gradient(160deg, #141c27 0%, #0f1923 100%);
        border-radius: 10px;
        overflow: hidden;
        text-decoration: none;
        color: inherit;
        transition: transform 0.25s ease, box-shadow 0.25s ease;
        display: flex;
        flex-direction: column;
        border: 1px solid rgba(102, 192, 244, 0.05);
        opacity: 0;
        animation: fadeSlideUp 0.4s ease forwards;
    }
    .card:hover {
        transform: translateY(-5px) scale(1.01);
        box-shadow:
            0 12px 35px rgba(0, 0, 0, 0.5),
            0 0 20px rgba(102, 192, 244, 0.06);
    }

    .img-wrap {
        position: relative;
        aspect-ratio: 460 / 215;
        overflow: hidden;
        background: #080c12;
    }
    .img-wrap img {
        width: 100%; height: 100%;
        object-fit: cover;
        transition: transform 0.4s ease;
    }
    .card:hover .img-wrap img { transform: scale(1.07); }

    .badge {
        position: absolute;
        top: 0; right: 0;
        background: linear-gradient(135deg, #a4d007, #7aa800);
        color: #fff;
        font-family: 'Exo 2', sans-serif;
        font-weight: 800;
        font-size: 0.92rem;
        padding: 5px 12px 5px 14px;
        border-radius: 0 0 0 10px;
        letter-spacing: -0.03em;
        text-shadow: 0 1px 3px rgba(0,0,0,0.3);
    }

    .info {
        padding: 12px 14px 14px;
        display: flex;
        flex-direction: column;
        gap: 7px;
        flex: 1;
    }
    .name {
        font-size: 0.92rem;
        font-weight: 600;
        color: #fff;
        line-height: 1.3;
        display: -webkit-box;
        -webkit-line-clamp: 2;
        -webkit-box-orient: vertical;
        overflow: hidden;
    }
    .prices {
        display: flex;
        align-items: center;
        gap: 10px;
        margin-top: auto;
    }
    .old {
        font-size: 0.8rem;
        color: #6a7a88;
        text-decoration: line-through;
    }
    .new {
        font-family: 'Exo 2', sans-serif;
        font-size: 1.08rem;
        font-weight: 800;
        color: #a4d007;
        text-shadow: 0 0 10px rgba(164, 208, 7, 0.15);
    }

    .empty {
        text-align: center;
        padding: 80px 20px;
        color: #3e4f5e;
        font-size: 1.1rem;
    }

    @keyframes fadeSlideUp {
        from { opacity: 0; transform: translateY(18px); }
        to   { opacity: 1; transform: translateY(0); }
    }

    @media (max-width: 640px) {
        .container { padding: 14px 10px; }
        .header h1 { font-size: 1.3rem; }
        .grid { grid-template-columns: repeat(auto-fill, minmax(165px, 1fr)); gap: 8px; }
        .info { padding: 8px 10px 10px; }
        .name { font-size: 0.82rem; }
        .badge { font-size: 0.8rem; padding: 3px 9px 3px 11px; }
        .stats { gap: 12px; font-size: 0.75rem; }
    }
</style>
</head>
<body>
<div class="container">

<div class="header">
    <h1><span class="icon">🎮</span> Steam Wishlist — Promos</h1>
    <div class="header-right">
HTMLHEAD

cat >> "$OUTPUT_FILE" << HTMLMETA
        <span class="count" id="count">${SALE_COUNT} jeu$([ "$SALE_COUNT" -gt 1 ] && echo "x") en promo</span>
        <span>Mis à jour le ${NOW} (${ELAPSED}s)</span>
        <a class="refresh-btn" href="run.php">
            <span class="refresh-icon">↻</span>
            Actualiser
        </a>
    </div>
</div>

<div class="stats">
    <span>Wishlist : <span class="val">${TOTAL} jeux</span></span>
    <span>En promo : <span class="val-green">${SALE_COUNT}</span></span>
    <span>Meilleure remise : <span class="val-green">-${BEST_DISCOUNT}%</span></span>
    <span>Prix le plus bas : <span class="val-green">${CHEAPEST_FMT}€</span></span>
    <span>Prochain scan auto : <span class="val" id="nextScan"></span></span>
</div>

<div class="controls">
    <div class="search-box">
        <input type="text" id="search" placeholder="Rechercher un jeu..." />
    </div>
    <div class="toolbar">
        <button class="active" data-sort="alpha">A→Z</button>
        <button data-sort="price_asc">Prix ↑</button>
        <button data-sort="price_desc">Prix ↓</button>
        <button data-sort="discount">% Promo</button>
    </div>
</div>
HTMLMETA

echo '<div class="grid" id="grid">' >> "$OUTPUT_FILE"
if [ "$SALE_COUNT" -gt 0 ]; then
    echo "$CARDS_HTML" >> "$OUTPUT_FILE"
else
    echo '<div class="empty">Aucun jeu en promotion dans votre wishlist pour le moment.</div>' >> "$OUTPUT_FILE"
fi
echo '</div>' >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'HTMLSCRIPT'

<script>
document.querySelectorAll('.card').forEach((c, i) => {
    c.style.animationDelay = Math.min(i * 30, 800) + 'ms';
});

document.querySelectorAll('.toolbar button').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.toolbar button').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');

        const grid = document.getElementById('grid');
        const cards = Array.from(grid.querySelectorAll('.card'));
        const mode = btn.dataset.sort;

        cards.sort((a, b) => {
            switch(mode) {
                case 'alpha': return a.dataset.name.localeCompare(b.dataset.name, 'fr', {sensitivity:'base'});
                case 'price_asc': return Number(a.dataset.sale) - Number(b.dataset.sale);
                case 'price_desc': return Number(b.dataset.sale) - Number(a.dataset.sale);
                case 'discount': return Number(b.dataset.disc) - Number(a.dataset.disc);
            }
        });

        cards.forEach((c, i) => {
            c.style.animation = 'none';
            c.offsetHeight;
            c.style.animation = '';
            c.style.animationDelay = Math.min(i * 20, 500) + 'ms';
            grid.appendChild(c);
        });
    });
});

document.getElementById('search').addEventListener('input', e => {
    const q = e.target.value.toLowerCase();
    const cards = document.querySelectorAll('.card');
    let visible = 0;
    cards.forEach(c => {
        const name = c.querySelector('.name').textContent.toLowerCase();
        const show = name.includes(q);
        c.style.display = show ? '' : 'none';
        if (show) visible++;
    });
    document.getElementById('count').textContent = visible + ' jeu' + (visible > 1 ? 'x' : '') + ' en promo';
});

// Calcul du prochain scan auto (1h05, 7h05, 13h05, 19h05)
(function() {
    const schedules = [1, 7, 13, 19];
    const now = new Date();
    let next = null;

    for (const h of schedules) {
        const candidate = new Date(now);
        candidate.setHours(h, 5, 0, 0);
        if (candidate > now) { next = candidate; break; }
    }
    if (!next) {
        next = new Date(now);
        next.setDate(next.getDate() + 1);
        next.setHours(schedules[0], 5, 0, 0);
    }

    const el = document.getElementById('nextScan');
    function update() {
        const diff = Math.max(0, Math.floor((next - new Date()) / 1000));
        const h = Math.floor(diff / 3600);
        const m = Math.floor((diff % 3600) / 60);
        const hh = String(next.getHours()).padStart(2, '0');
        const mm = String(next.getMinutes()).padStart(2, '0');
        el.textContent = hh + ':' + mm + ' (dans ' + h + 'h' + String(m).padStart(2,'0') + ')';
    }
    update();
    setInterval(update, 60000);
})();
</script>

</div>
</body>
</html>
HTMLSCRIPT

chmod 644 "$OUTPUT_FILE"
chown www-data:www-data "$OUTPUT_FILE"

ELAPSED=$(( $(date +%s) - START_TIME ))
ok "Page générée : $OUTPUT_FILE"
ok "Durée totale : ${ELAPSED}s"
log "Terminé !"
