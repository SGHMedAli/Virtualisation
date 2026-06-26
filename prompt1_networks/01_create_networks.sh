#!/bin/bash
# Script de création des 3 réseaux virtuels KVM/libvirt
# TP8 - Scalabilité horizontale et Base répliquée

set -e

echo "=== Création des réseaux virtuels KVM ==="

# Réseau 1: Frontal (Accès utilisateurs vers Load Balancer)
# Subnet: 192.168.100.0/24
cat > /tmp/network_frontend.xml <<EOF
<network>
  <name>tp8-frontend</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='virbr1' stp='on' delay='0'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.100.100' end='192.168.100.200'/>
    </dhcp>
  </ip>
</network>
EOF

# Réseau 2: Applicatif (LB -> Web -> DB)
# Subnet: 192.168.101.0/24
cat > /tmp/network_app.xml <<EOF
<network>
  <name>tp8-app</name>
  <forward mode='route'/>
  <bridge name='virbr2' stp='on' delay='0'/>
  <ip address='192.168.101.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.101.100' end='192.168.101.200'/>
    </dhcp>
  </ip>
</network>
EOF

# Réseau 3: Réplication (Exclusif DB -> DB)
# Subnet: 192.168.102.0/24
cat > /tmp/network_replication.xml <<EOF
<network>
  <name>tp8-replication</name>
  <forward mode='none'/>
  <bridge name='virbr3' stp='on' delay='0'/>
  <ip address='192.168.102.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.102.100' end='192.168.102.200'/>
    </dhcp>
  </ip>
</network>
EOF

# Définition et démarrage des réseaux
echo "Création du réseau frontend..."
virsh net-define /tmp/network_frontend.xml
virsh net-start tp8-frontend
virsh net-autostart tp8-frontend

echo "Création du réseau applicatif..."
virsh net-define /tmp/network_app.xml
virsh net-start tp8-app
virsh net-autostart tp8-app

echo "Création du réseau de réplication..."
virsh net-define /tmp/network_replication.xml
virsh net-start tp8-replication
virsh net-autostart tp8-replication

echo "=== Réseaux créés avec succès ==="
virsh net-list --all
