<?php
// ═══════════════════════════════════════════════════════════
// update.php — Affiche la progression du scan en cours
// ═══════════════════════════════════════════════════════════

$currentLog = '/tmp/steam-wishlist-current.log';
$lockFile   = '/tmp/steam-wishlist-sales.lock';

$isRunning = file_exists($lockFile);

// Marqueur de démarrage : le script n'a pas encore créé le lock
$startingFile = '/tmp/steam-wishlist-starting';
if (!$isRunning && file_exists($startingFile)) {
    // Le script est en train de démarrer
    $startAge = time() - filemtime($startingFile);
    if ($startAge < 30) {
        $isRunning = true;
    } else {
        // Marqueur périmé
        unlink($startingFile);
    }
}

// Nettoyer le marqueur une fois le lock créé
if (file_exists($lockFile) && file_exists($startingFile)) {
    unlink($startingFile);
}
$logContent = file_exists($currentLog) ? file_get_contents($currentLog) : '';

// Nettoyer les codes ANSI
$logContent = preg_replace('/\033\[[0-9;]*m/', '', $logContent);
$logContent = htmlspecialchars($logContent, ENT_QUOTES, 'UTF-8');

// Coloriser les lignes
$lines = explode("\n", $logContent);
$coloredLines = [];
foreach ($lines as $line) {
    if (strpos($line, '[OK]') !== false) {
        $coloredLines[] = '<span class="log-ok">' . $line . '</span>';
    } elseif (strpos($line, '[WARN]') !== false) {
        $coloredLines[] = '<span class="log-warn">' . $line . '</span>';
    } elseif (strpos($line, '[ERR]') !== false) {
        $coloredLines[] = '<span class="log-err">' . $line . '</span>';
    } elseif (preg_match('/^\[[\d-]+ [\d:]+\]/', $line)) {
        $coloredLines[] = '<span class="log-info">' . $line . '</span>';
    } else {
        $coloredLines[] = $line;
    }
}
$logHtml = implode("\n", $coloredLines);

// Compter les lignes non vides pour la progression
$logLines = array_filter($lines, fn($l) => trim($l) !== '');
$lineCount = count($logLines);

// Temps écoulé depuis le lock
$elapsed = 0;
if (file_exists($lockFile)) {
    $elapsed = time() - filemtime($lockFile);
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<?php if ($isRunning): ?>
<meta http-equiv="refresh" content="5;url=update.php">
<?php endif; ?>
<title>Steam Wishlist — <?= $isRunning ? 'Mise à jour en cours' : 'Mise à jour terminée' ?></title>
<style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
        background: #0a0e14;
        color: #c6d4df;
        font-family: 'Segoe UI', sans-serif;
        min-height: 100vh;
        padding: 28px 24px;
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
        max-width: 900px;
        margin: 0 auto;
        position: relative;
        z-index: 1;
    }
    .header-bar {
        display: flex;
        align-items: center;
        gap: 14px;
        margin-bottom: 20px;
        padding-bottom: 16px;
        border-bottom: 1px solid rgba(102, 192, 244, 0.1);
    }
    .header-bar h1 {
        font-size: 1.4rem;
        color: #fff;
        font-weight: 700;
    }
    .spinner {
        width: 22px;
        height: 22px;
        border: 3px solid rgba(102, 192, 244, 0.2);
        border-top-color: #66c0f4;
        border-radius: 50%;
        animation: spin 0.8s linear infinite;
        flex-shrink: 0;
    }
    @keyframes spin { to { transform: rotate(360deg); } }

    .status-bar {
        display: flex;
        justify-content: center;
        align-items: center;
        margin-bottom: 18px;
        padding: 12px 18px;
        background: rgba(255,255,255,0.02);
        border: 1px solid rgba(102, 192, 244, 0.08);
        border-radius: 10px;
    }
    .timer {
        font-size: 0.85rem;
        color: #8f98a0;
    }
    .timer span {
        color: #66c0f4;
        font-weight: 600;
    }

    #log {
        background: rgba(0,0,0,0.35);
        border: 1px solid rgba(102, 192, 244, 0.08);
        border-radius: 10px;
        padding: 18px;
        font-family: 'Courier New', monospace;
        font-size: 0.78rem;
        line-height: 1.7;
        max-height: 55vh;
        overflow-y: auto;
        white-space: pre-wrap;
        word-break: break-all;
    }
    .log-ok { color: #a4d007; }
    .log-warn { color: #f0c040; }
    .log-err { color: #e05050; }
    .log-info { color: #66c0f4; }

    .done-box {
        margin-top: 20px;
        padding: 16px 24px;
        background: rgba(164, 208, 7, 0.08);
        border: 1px solid rgba(164, 208, 7, 0.2);
        border-radius: 10px;
        color: #a4d007;
        font-size: 0.95rem;
        display: flex;
        align-items: center;
        gap: 14px;
        flex-wrap: wrap;
    }
    .done-box a {
        color: #66c0f4;
        text-decoration: none;
        font-weight: 600;
    }
    .done-box a:hover { text-decoration: underline; }
    .countdown { color: #8f98a0; font-size: 0.85rem; }

    .refresh-note {
        margin-top: 14px;
        font-size: 0.75rem;
        color: #3e4f5e;
        text-align: center;
    }
</style>
</head>
<body>
<div class="container">

    <div class="header-bar">
        <?php if ($isRunning): ?>
            <div class="spinner"></div>
        <?php endif; ?>
        <h1>🎮 <?= $isRunning ? 'Mise à jour en cours' : 'Mise à jour terminée' ?></h1>
    </div>

    <div class="status-bar">
        <div class="timer">Temps écoulé : <span id="elapsed"><?php
            $m = floor($elapsed / 60);
            $s = $elapsed % 60;
            echo $m > 0 ? "{$m}min {$s}s" : "{$s}s";
        ?></span></div>
    </div>

    <div id="log"><?= $logHtml ?></div>

    <?php if (!$isRunning && $lineCount > 0): ?>
    <div class="done-box">
        ✅ Mise à jour terminée
        <a href="./">← Voir les promos</a>
        <span class="countdown" id="countdown"></span>
    </div>
    <script>
        let sec = 8;
        const cd = document.getElementById('countdown');
        cd.textContent = '— redirection dans ' + sec + 's';
        setInterval(() => {
            sec--;
            if (sec > 0) {
                cd.textContent = '— redirection dans ' + sec + 's';
            } else {
                window.location.href = './';
            }
        }, 1000);
    </script>
    <?php elseif ($isRunning): ?>
    <p class="refresh-note">Rafraîchissement automatique toutes les 5 secondes</p>
    <?php else: ?>
    <div class="done-box">
        Aucun scan en cours.
        <a href="./">← Retour aux promos</a>
    </div>
    <?php endif; ?>

</div>
<script>
    // Scroll en bas du log
    const log = document.getElementById('log');
    log.scrollTop = log.scrollHeight;
</script>
</body>
</html>
