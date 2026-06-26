#!/bin/bash
# Script pour ajouter dynamiquement un serveur à HAProxy
# TP8 - Scalabilité horizontale et Base répliquée
# Utilisation: ./add_server_haproxy.sh <server_name> <ip_address>

set -e

SERVER_NAME=$1
IP_ADDRESS=$2

if [ -z "$SERVER_NAME" ] || [ -z "$IP_ADDRESS" ]; then
    echo "Usage: $0 <server_name> <ip_address>"
    echo "Exemple: $0 web03 192.168.101.22"
    exit 1
fi

echo "=== Ajout de $SERVER_NAME ($IP_ADDRESS) à HAProxy ==="

# Ajout du serveur via le socket admin
echo "Ajout du serveur dans le backend web_servers..."
echo "add server web_servers/$SERVER_NAME $IP_ADDRESS:80 check inter 2000 rise 2 fall 3 maxconn 100" | socat /run/haproxy/admin.sock -

# Ajout du serveur dans le backend health_backend
echo "Ajout du serveur dans le backend health_backend..."
echo "add server health_backend/$SERVER_NAME $IP_ADDRESS:80 check inter 2000 rise 2 fall 3" | socat /run/haproxy/admin.sock -

# Vérification
echo "Vérification de l'ajout..."
echo "show servers state" | socat /run/haproxy/admin.sock - | grep $SERVER_NAME

echo ""
echo "=== Serveur $SERVER_NAME ajouté avec succès ==="
