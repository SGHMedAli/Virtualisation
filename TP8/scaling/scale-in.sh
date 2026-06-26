#!/bin/bash
# Script de scalabilité descendante (Scale-in)
# TP8 - Scalabilité horizontale et Base répliquée
# Draine proprement les connexions avant de détruire les VMs

set -e

# Configuration
LB_HOST="192.168.100.10"
LB_SSH_USER="root"
WEB03_IP_FRONT="192.168.100.22"
WEB03_IP_APP="192.168.101.22"
WEB04_IP_FRONT="192.168.100.23"
WEB04_IP_APP="192.168.101.23"
CPU_THRESHOLD=30
CONNECTIONS_THRESHOLD=200
CHECK_INTERVAL=10

echo "=== Script de Scalabilité Descendante (Scale-in) ==="
echo "Monitoring de la charge..."
echo "Seuil CPU: $CPU_THRESHOLD%"
echo "Seuil Connexions: $CONNECTIONS_THRESHOLD"
echo "Intervalle de vérification: $CHECK_INTERVAL secondes"
echo ""

# Fonction pour obtenir la charge CPU moyenne
get_cpu_load() {
    ssh $LB_SSH_USER@$LB_HOST "top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - \$1}'"
}

# Fonction pour obtenir le nombre de connexions actives
get_connections() {
    ssh $LB_SSH_USER@$LB_HOST "echo 'show stat' | socat /run/haproxy/admin.sock - | grep web_servers | awk -F',' '{sum+=\$4} END {print sum}'"
}

# Fonction pour obtenir le nombre de connexions sur un serveur spécifique
get_server_connections() {
    local server_name=$1
    ssh $LB_SSH_USER@$LB_HOST "echo 'show stat' | socat /run/haproxy/admin.sock - | grep $server_name | awk -F',' '{print \$4}'"
}

# Fonction pour vérifier si une VM existe
vm_exists() {
    local vm_name=$1
    virsh dominfo "$vm_name" &>/dev/null
}

# Fonction pour mettre un serveur en mode drain
drain_server() {
    local server_name=$1
    echo "Mise en mode drain de $server_name..."
    ssh $LB_SSH_USER@$LB_HOST "echo 'set server web_servers/$server_name state drain' | socat /run/haproxy/admin.sock -"
}

# Fonction pour retirer un serveur de HAProxy
remove_from_haproxy() {
    local server_name=$1
    echo "Retrait de $server_name de HAProxy..."
    ssh $LB_SSH_USER@$LB_HOST << EOF
echo "set server web_servers/$server_name state maint" | socat /run/haproxy/admin.sock -
echo "del server web_servers/$server_name" | socat /run/haproxy/admin.sock -
echo "del server health_backend/$server_name" | socat /run/haproxy/admin.sock -
EOF
}

# Fonction pour détruire une VM
destroy_vm() {
    local vm_name=$1
    echo "Destruction de $vm_name..."
    
    # Arrêt propre
    virsh shutdown "$vm_name"
    
    # Attendre l'arrêt (timeout 60 secondes)
    local count=0
    while virsh domstate "$vm_name" | grep -q "running"; do
        sleep 5
        count=$((count + 5))
        if [ $count -ge 60 ]; then
            echo "Timeout, arrêt forcé..."
            virsh destroy "$vm_name"
            break
        fi
    done
    
    # Suppression de la VM
    virsh undefine "$vm_name"
    
    # Suppression du disque
    rm -f "/var/lib/libvirt/images/${vm_name}.qcow2"
    
    echo "✓ $vm_name détruite"
}

# Fonction pour effectuer le scale-in sur un serveur
scale_in_server() {
    local server_name=$1
    local ip_front=$2
    
    if ! vm_exists "$server_name"; then
        echo "$server_name n'existe pas, rien à faire"
        return
    fi
    
    echo "=== Scale-in de $server_name ==="
    
    # Vérifier les connexions actuelles
    local current_conn=$(get_server_connections "$server_name")
    echo "Connexions actuelles sur $server_name: $current_conn"
    
    # Mettre en mode drain
    drain_server "$server_name"
    
    # Attendre que les connexions se terminent
    echo "Attente de la fin des connexions (max 60 secondes)..."
    local count=0
    while [ $count -lt 60 ]; do
        current_conn=$(get_server_connections "$server_name")
        echo "Connexions restantes: $current_conn"
        
        if [ "$current_conn" -le 0 ]; then
            echo "Plus de connexions actives"
            break
        fi
        
        sleep 5
        count=$((count + 5))
    done
    
    # Retirer de HAProxy
    remove_from_haproxy "$server_name"
    
    # Détruire la VM
    destroy_vm "$server_name"
    
    echo "✓ Scale-in de $server_name terminé"
}

# Boucle de monitoring
while true; do
    echo "=== Vérification de la charge ($(date)) ==="
    
    # Obtention des métriques
    CPU_LOAD=$(get_cpu_load)
    CONNECTIONS=$(get_connections)
    
    echo "Charge CPU: ${CPU_LOAD}%"
    echo "Connexions actives: ${CONNECTIONS}"
    
    # Vérification si web04 existe et si la charge est faible
    if vm_exists "web04" && [ $(echo "$CPU_LOAD < $CPU_THRESHOLD" | bc) -eq 1 ] && [ "$CONNECTIONS" -lt "$CONNECTIONS_THRESHOLD" ]; then
        echo "⚠️  Charge faible, déclenchement du scale-in..."
        
        # Scale-in de web04
        scale_in_server "web04" "$WEB04_IP_FRONT"
        
        # Attendre avant la prochaine vérification
        sleep 60
        
        # Vérification après retrait de web04
        CPU_LOAD=$(get_cpu_load)
        CONNECTIONS=$(get_connections)
        
        echo "Après retrait de web04 - CPU: ${CPU_LOAD}%, Connexions: ${CONNECTIONS}"
        
        # Si toujours faible, retirer web03
        if vm_exists "web03" && [ $(echo "$CPU_LOAD < $CPU_THRESHOLD" | bc) -eq 1 ] && [ "$CONNECTIONS" -lt "$CONNECTIONS_THRESHOLD" ]; then
            echo "Toujours faible charge. Scale-in de web03..."
            scale_in_server "web03" "$WEB03_IP_FRONT"
        fi
        
        echo "Scale-in terminé. Nouvelle vérification dans 60 secondes..."
        sleep 60
    else
        echo "✓ Charge normale ou pas de VM supplémentaire à retirer"
    fi
    
    echo ""
    sleep $CHECK_INTERVAL
done
