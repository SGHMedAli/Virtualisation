#!/bin/bash
# Script de provisionnement des VMs avec virsh
# TP8 - Scalabilité horizontale et Base répliquée

set -e

# Configuration
BASE_IMAGE="/var/lib/libvirt/images/ubuntu-22.04.qcow2"
VM_DISK_SIZE="20G"
VM_RAM="2048"
VM_VCPUS="2"
VM_DISK_PATH="/var/lib/libvirt/images"

echo "=== Provisionnement des VMs ==="

# Fonction pour créer une VM
create_vm() {
    local VM_NAME=$1
    local MAC_FRONT=$2
    local MAC_APP=$3
    local MAC_REPL=$4
    
    echo "Création de la VM: $VM_NAME"
    
    # Création du disque à partir de l'image de base
    qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$VM_DISK_PATH/${VM_NAME}.qcow2" "$VM_DISK_SIZE"
    
    # Définition XML de la VM
    cat > /tmp/${VM_NAME}.xml <<EOF
<domain type='kvm'>
  <name>${VM_NAME}</name>
  <memory unit='KiB'>$(($VM_RAM * 1024))</memory>
  <vcpu placement='static'>$VM_VCPUS</vcpu>
  <os>
    <type arch='x86_64' machine='pc'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='host-passthrough'/>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='${VM_DISK_PATH}/${VM_NAME}.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <interface type='network'>
      <mac address='${MAC_FRONT}'/>
      <source network='tp8-frontend'/>
      <model type='virtio'/>
    </interface>
    <interface type='network'>
      <mac address='${MAC_APP}'/>
      <source network='tp8-app'/>
      <model type='virtio'/>
    </interface>
    <interface type='network'>
      <mac address='${MAC_REPL}'/>
      <source network='tp8-replication'/>
      <model type='virtio'/>
    </interface>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <console type='pty'>
      <target type='virtio' port='1'/>
    </console>
  </devices>
</domain>
EOF
    
    # Définition et démarrage de la VM
    virsh define /tmp/${VM_NAME}.xml
    virsh start ${VM_NAME}
    echo "VM $VM_NAME créée et démarrée"
}

# Load Balancer (HAProxy)
# IP Frontend: 192.168.100.10
# IP App: 192.168.101.10
# Pas d'accès réseau réplication
create_vm "lb01" "52:54:00:00:01:01" "52:54:00:01:01:01" "52:54:00:02:01:01"

# Serveur Web 1
# IP Frontend: 192.168.100.20
# IP App: 192.168.101.20
# Pas d'accès réseau réplication
create_vm "web01" "52:54:00:00:02:01" "52:54:00:01:02:01" "52:54:00:02:02:01"

 Serveur Web 2
# IP Frontend: 192.168.100.21
# IP App: 192.168.101.21
# Pas d'accès réseau réplication
create_vm "web02" "52:54:00:00:02:02" "52:54:00:01:02:02" "52:54:00:02:02:02"

# Base de données principale (Master)
# IP App: 192.168.101.30
# IP Réplication: 192.168.102.30
create_vm "db01" "52:54:00:00:03:01" "52:54:00:01:03:01" "52:54:00:02:03:01"

# Base de données répliquée (Slave)
# IP App: 192.168.101.31
# IP Réplication: 192.168.102.31
create_vm "db02" "52:54:00:00:03:02" "52:54:00:01:03:02" "52:54:00:02:03:02"

echo "=== Toutes les VMs ont été créées ==="
virsh list --all
