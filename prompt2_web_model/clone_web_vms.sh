#!/bin/bash
# Script de clonage à chaud de l'image modèle web pour créer web03 et web04
# TP8 - Scalabilité horizontale et Base répliquée

set -e

# Configuration
TEMPLATE_VM="web-template"
VM_DISK_PATH="/var/lib/libvirt/images"
WEB03_IP_FRONT="192.168.100.22"
WEB03_IP_APP="192.168.101.22"
WEB04_IP_FRONT="192.168.100.23"
WEB04_IP_APP="192.168.101.23"
VM_RAM="1024"
VM_VCPUS="1"

echo "=== Clonage de l'image modèle web ==="

# Vérifier que le template existe
if ! virsh dominfo "$TEMPLATE_VM" &>/dev/null; then
    echo "Erreur: La VM template '$TEMPLATE_VM' n'existe pas."
    echo "Créez d'abord le template avec cloud-init ou Ansible."
    exit 1
fi

# Fonction pour cloner une VM
clone_web_vm() {
    local NEW_VM=$1
    local MAC_FRONT=$2
    local MAC_APP=$3
    local IP_FRONT=$4
    local IP_APP=$5
    
    echo "Clonage de $TEMPLATE_VM vers $NEW_VM..."
    
    # Arrêter le template si nécessaire (snapshot à chaud)
    echo "Création d'un snapshot du template..."
    virsh snapshot-create-as --domain "$TEMPLATE_VM" --name "clone-snapshot-$(date +%s)" --atomic
    
    # Cloner la VM
    virt-clone --original "$TEMPLATE_VM" \
               --name "$NEW_VM" \
               --file "$VM_DISK_PATH/${NEW_VM}.qcow2" \
               --mac "$MAC_FRONT" \
               --mac "$MAC_APP"
    
    # Démarrer la nouvelle VM
    echo "Démarrage de $NEW_VM..."
    virsh start "$NEW_VM"
    
    # Attendre que la VM démarre
    echo "Attente du démarrage de $NEW_VM (30 secondes)..."
    sleep 30
    
    # Configuration des IP statiques via netplan
    echo "Configuration des interfaces réseau pour $NEW_VM..."
    cat > /tmp/netplan-${NEW_VM}.yaml <<EOF
network:
  version: 2
  ethernets:
    ens3:  # Frontend network
      dhcp4: no
      addresses:
        - ${IP_FRONT}/24
      gateway4: 192.168.100.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
    ens4:  # App network
      dhcp4: no
      addresses:
        - ${IP_APP}/24
EOF
    
    # Copier le fichier netplan sur la VM (nécessite ssh)
    echo "Copie de la configuration réseau sur $NEW_VM..."
    scp /tmp/netplan-${NEW_VM}.yaml root@${IP_FRONT}:/tmp/netplan-config.yaml
    
    # Appliquer la configuration
    echo "Application de la configuration réseau sur $NEW_VM..."
    ssh root@${IP_FRONT} "mv /tmp/netplan-config.yaml /etc/netplan/01-netcfg.yaml && netplan apply"
    
    echo "VM $NEW_VM créée et configurée avec succès"
    echo "  - IP Frontend: $IP_FRONT"
    echo "  - IP App: $IP_APP"
}

# Cloner web03
clone_web_vm "web03" "52:54:00:00:02:03" "52:54:00:01:02:03" "$WEB03_IP_FRONT" "$WEB03_IP_APP"

# Cloner web04
clone_web_vm "web04" "52:54:00:00:02:04" "52:54:00:01:02:04" "$WEB04_IP_FRONT" "$WEB04_IP_APP"

echo "=== Clonage terminé avec succès ==="
virsh list --all | grep -E "web03|web04"

echo ""
echo "Prochaine étape: Ajouter web03 et web04 à la configuration HAProxy"
