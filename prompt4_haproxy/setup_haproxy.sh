#!/bin/bash
# Script d'installation et configuration de HAProxy sur le Load Balancer
# TP8 - Scalabilité horizontale et Base répliquée

set -e

echo "=== Installation et Configuration de HAProxy ==="

# Installation de HAProxy
echo "Installation de HAProxy..."
apt update
apt install -y haproxy

# Sauvegarde de la configuration originale
echo "Sauvegarde de la configuration originale..."
cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.backup

# Copie de la nouvelle configuration
echo "Copie de la nouvelle configuration..."
cp haproxy.cfg /etc/haproxy/haproxy.cfg

# Création du répertoire pour les pages d'erreur
mkdir -p /etc/haproxy/errors

# Création des pages d'erreur personnalisées
cat > /etc/haproxy/errors/503.http <<EOF
HTTP/1.0 503 Service Unavailable
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body>
<h1>503 Service Unavailable</h1>
No server is available to handle this request.
</body></html>
EOF

# Vérification de la configuration
echo "Vérification de la configuration..."
haproxy -c -f /etc/haproxy/haproxy.cfg

if [ $? -eq 0 ]; then
    echo "Configuration valide"
else
    echo "Erreur de configuration"
    exit 1
fi

# Activation et démarrage de HAProxy
echo "Activation et démarrage de HAProxy..."
systemctl enable haproxy
systemctl restart haproxy

# Vérification du statut
echo "Statut de HAProxy:"
systemctl status haproxy --no-pager

echo ""
echo "=== HAProxy configuré avec succès ==="
echo "Statistiques disponibles sur: http://192.168.100.10:8404/"
echo "Utilisateur: admin / Mot de passe: admin123"
