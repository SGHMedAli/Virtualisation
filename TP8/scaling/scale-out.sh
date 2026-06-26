#!/bin/bash
# Script de scalabilité ascendante (Scale-out)
# TP8 - Scalabilité horizontale et Base répliquée
# Monitor la charge et ajoute web03 puis web04 si nécessaire

set -e

# Configuration
LB_HOST="192.168.100.10"
LB_SSH_USER="root"
TEMPLATE_VM="web-template"
WEB03_IP_FRONT="192.168.100.22"
WEB03_IP_APP="192.168.101.22"
WEB04_IP_FRONT="192.168.100.23"
WEB04_IP_APP="192.168.101.23"
CPU_THRESHOLD=80
CONNECTIONS_THRESHOLD=1000
CHECK_INTERVAL=10

echo "=== Script de Scalabilité Ascendante (Scale-out) ==="
echo "Monitoring de la charge..."
echo "Seuil CPU: $CPU_THRESHOLD%"
echo "Seuil Connexions: $CONNECTIONS_THRESHOLD"
echo "Intervalle de vérification: $CHECK_INTERVAL secondes"
echo ""

# Fonction pour obtenir la charge CPU moyenne
get_cpu_load() {
    # Utilisation de SSH pour obtenir la charge CPU depuis le LB
    ssh $LB_SSH_USER@$LB_HOST "top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\([0-9.]*\)%* id.*/\1/' | awk '{print 100 - \$1}'"
}

# Fonction pour obtenir le nombre de connexions actives
get_connections() {
    # Utilisation de HAProxy stats pour obtenir le nombre de connexions
    ssh $LB_SSH_USER@$LB_HOST "echo 'show stat' | socat /run/haproxy/admin.sock - | grep web_servers | awk -F',' '{sum+=\$4} END {print sum}'"
}

# Fonction pour vérifier si une VM existe
vm_exists() {
    local vm_name=$1
    virsh dominfo "$vm_name" &>/dev/null
}

# Fonction pour cloner une VM
clone_web_vm() {
    local new_vm=$1
    local mac_front=$2
    local mac_app=$3
    local ip_front=$4
    local ip_app=$5
    
    echo "Clonage de $TEMPLATE_VM vers $new_vm..."
    
    # Création d'un snapshot
    virsh snapshot-create-as --domain "$TEMPLATE_VM" --name "clone-snapshot-$(date +%s)" --atomic
    
    # Clonage
    virt-clone --original "$TEMPLATE_VM" \
               --name "$new_vm" \
               --file "/var/lib/libvirt/images/${new_vm}.qcow2" \
               --mac "$mac_front" \
               --mac "$mac_app"
    
    # Démarrage
    virsh start "$new_vm"
    
    # Attente du démarrage
    sleep 30
    
    # Configuration réseau
    cat > /tmp/netplan-${new_vm}.yaml <<EOF
network:
  version: 2
  ethernets:
    ens3:
      dhcp4: no
      addresses:
        - ${ip_front}/24
      gateway4: 192.168.100.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
    ens4:
      dhcp4: no
      addresses:
        - ${ip_app}/24
EOF
    
    scp /tmp/netplan-${new_vm}.yaml root@${ip_front}:/tmp/netplan-config.yaml
    ssh root@${ip_front} "mv /tmp/netplan-config.yaml /etc/netplan/01-netcfg.yaml && netplan apply"
    
    echo "VM $new_vm créée et configurée"
}

# Fonction pour ajouter un serveur à HAProxy
add_to_haproxy() {
    local server_name=$1
    local ip_address=$2
    
    echo "Ajout de $server_name à HAProxy..."
    ssh $LB_SSH_USER@$LB_HOST << EOF
echo "add server web_servers/$server_name $ip_address:80 check inter 2000 rise 2 fall 3 maxconn 100" | socat /run/haproxy/admin.sock -
echo "add server health_backend/$server_name $ip_address:80 check inter 2000 rise 2 fall 3" | socat /run/haproxy/admin.sock -
EOF
}

# Boucle de monitoring
while true; do
    echo "=== Vérification de la charge ($(date)) ==="
    
    # Obtention des métriques
    CPU_LOAD=$(get_cpu_load)
    CONNECTIONS=$(get_connections)
    
    echo "Charge CPU: ${CPU_LOAD}%"
    echo "Connexions actives: ${CONNECTIONS}"
    
    # Vérification des seuils
    if [ $(echo "$CPU_LOAD > $CPU_THRESHOLD" | bc) -eq 1 ] || [ "$CONNECTIONS" -gt "$CONNECTIONS_THRESHOLD" ]; then
        echo "⚠️  Seuil dépassé! Déclenchement du scale-out..."
        
        # Ajout de web03
        if ! vm_exists "web03"; then
            echo "Création de web03..."
            clone_web_vm "web03" "52:54:00:00:02:03" "52:54:00:01:02:03" "$WEB03_IP_FRONT" "$WEB03_IP_APP"
            sleep 10
            add_to_haproxy "web03" "$WEB03_IP_APP"
            echo "✓ web03 ajouté"
        else
            echo "web03 existe déjà"
        fi
        
        # Vérification après ajout de web03
        sleep 30
        CPU_LOAD=$(get_cpu_load)
        CONNECTIONS=$(get_connections)
        
        echo "Après ajout de web03 - CPU: ${CPU_LOAD}%, Connexions: ${CONNECTIONS}"
        
        # Si toujours au-dessus du seuil, ajouter web04
        if [ $(echo "$CPU_LOAD > $CPU_THRESHOLD" | bc) -eq 1 ] || [ "$CONNECTIONS" -gt "$CONNECTIONS_THRESHOLD" ]; then
            echo "Toujours au-dessus du seuil. Création de web04..."
            
            if ! vm_exists "web04"; then
                clone_web_vm "web04" "52:54:00:00:02:04" "52:54:00:01:02:04" "$WEB04_IP_FRONT" "$WEB04_IP_APP"
                sleep 10
                add_to_haproxy "web04" "$WEB04_IP_APP"
                echo "✓ web04 ajouté"
            else
                echo "web04 existe déjà"
            fi
        fi
        
        echo "Scale-out terminé. Nouvelle vérification dans 60 secondes..."
        sleep 60
    else
        echo "✓ Charge normale"
    fi
    
    echo ""
    sleep $CHECK_INTERVAL
done
