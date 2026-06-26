#!/bin/bash
# Script pour créer la VM template à partir d'une image de base
# TP8 - Scalabilité horizontale et Base répliquée

set -e

# Configuration
BASE_IMAGE="/var/lib/libvirt/images/ubuntu-22.04.qcow2"
TEMPLATE_NAME="web-template"
VM_DISK_PATH="/var/lib/libvirt/images"
VM_DISK_SIZE="20G"
VM_RAM="1024"
VM_VCPUS="1"
CLOUD_INIT_FILE="cloud-init-web-template.yaml"

echo "=== Création de la VM template web ==="

# Vérifier que l'image de base existe
if [ ! -f "$BASE_IMAGE" ]; then
    echo "Erreur: L'image de base $BASE_IMAGE n'existe pas."
    echo "Téléchargez une image Ubuntu 22.04 cloud image:"
    echo "wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.qcow2"
    exit 1
fi

# Créer le disque de la template
echo "Création du disque pour $TEMPLATE_NAME..."
qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$VM_DISK_PATH/${TEMPLATE_NAME}.qcow2" "$VM_DISK_SIZE"

# Créer l'image cloud-init
echo "Création de l'image cloud-init..."
if [ -f "$CLOUD_INIT_FILE" ]; then
    cloud-localds "$VM_DISK_PATH/${TEMPLATE_NAME}-cloud-init.iso" "$CLOUD_INIT_FILE"
else
    echo "Avertissement: Fichier cloud-init non trouvé, création sans cloud-init"
fi

# Définir la VM
echo "Définition de la VM $TEMPLATE_NAME..."
virt-install \
    --name "$TEMPLATE_NAME" \
    --memory "$VM_RAM" \
    --vcpus "$VM_VCPUS" \
    --disk path="$VM_DISK_PATH/${TEMPLATE_NAME}.qcow2,format=qcow2,bus=virtio" \
    --disk path="$VM_DISK_PATH/${TEMPLATE_NAME}-cloud-init.iso,device=cdrom" \
    --network network=tp8-frontend,model=virtio,mac=52:54:00:00:02:00 \
    --network network=tp8-app,model=virtio,mac=52:54:00:01:02:00 \
    --os-variant ubuntu22.04 \
    --graphics none \
    --console pty,target_type=serial \
    --import \
    --noautoconsole

echo "Attente du démarrage de $TEMPLATE_NAME..."
sleep 30

# Vérifier l'état
echo "État de la VM:"
virsh dominfo "$TEMPLATE_NAME"

echo ""
echo "=== Template créée avec succès ==="
echo "La VM $TEMPLATE_NAME est maintenant prête à être clonée."
echo "Une fois la configuration terminée, vous pouvez l'utiliser comme template."
