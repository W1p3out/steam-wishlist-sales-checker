<?php
// ═══════════════════════════════════════════════════════════
// run.php — Lance le script et redirige vers update.php
// ═══════════════════════════════════════════════════════════

$script     = '/opt/steam-wishlist-sales/steam-wishlist-sales.sh';
$indexFile  = __DIR__ . '/index.html';
$currentLog = '/tmp/steam-wishlist-current.log';
$lockFile   = '/tmp/steam-wishlist-sales.lock';

if (!file_exists($script)) {
    die("Erreur : script introuvable.");
}

// Si un scan tourne déjà, rediriger directement vers update.php
$startingFile = '/tmp/steam-wishlist-starting';
if (file_exists($lockFile) || file_exists($startingFile)) {
    header('Location: update.php');
    exit;
}

// Vider le log du scan en cours
file_put_contents($currentLog, "Démarrage du scan...\n");
chmod($currentLog, 0644);

// Créer un marqueur de démarrage (pour que update.php sache qu'un scan démarre)
touch($startingFile);

// Remplacer index.html par une redirection vers update.php
file_put_contents($indexFile, '<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0;url=update.php"></head><body></body></html>');

// Lancer le script en arrière-plan, sortie vers le log
exec("sudo $script > $currentLog 2>&1 &");

// Rediriger vers update.php
header('Location: update.php');
exit;
