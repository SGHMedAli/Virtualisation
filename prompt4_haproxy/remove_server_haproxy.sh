#!/bin/bash
# Script pour retirer dynamiquement un serveur de HAProxy
# TP8 - Scalabilité horizontale et Base répliquée
# Utilisation: ./remove_server_haproxy.sh <server_name>

set -e

SERVER_NAME=$1

if [ -z "$SERVER_NAME" ]; then
    echo "Usage: $0 <server_name>"
    echo "Exemple: $0 web03"
    exit 1
fi

echo "=== Retrait de $SERVER_NAME de HAProxy ==="

# Mettre le serveur en mode drain (ne plus accepter de nouvelles connexions)
echo "Mise en mode drain de $SERVER_NAME..."
echo "set server web_servers/$SERVER_NAME state drain" | socat /run/haproxy/admin.sock -

# Attendre que les connexions actives se terminent
echo "Attente de la fin des connexions actives (30 secondes)..."
sleep 30

# Désactiver le serveur
echo "Désactivation de $SERVER_NAME..."
echo "set server web_servers/$SERVER_NAME state maint" | socat /run/haproxy/admin.sock -

# Supprimer le serveur du backend web_servers
echo "Suppression du backend web_servers..."
echo "del server web_servers/$SERVER_NAME" | socat /run/haproxy/admin.sock -

# Supprimer le serveur du backend health_backend
echo "Suppression du backend health_backend..."
echo "del server health_backend/$SERVER_NAME" | socat /run/haproxy/admin.sock -

echo ""
echo "=== Serveur $SERVER_NAME retiré avec succès ==="
