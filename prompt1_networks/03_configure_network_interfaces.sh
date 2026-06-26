#!/bin/bash
# Script de configuration des interfaces réseau statiques sur les VMs
# TP8 - Scalabilité horizontale et Base répliquée

set -e

echo "=== Configuration des interfaces réseau statiques ==="

# Configuration pour Load Balancer (lb01)
cat > /tmp/netplan-lb01.yaml <<'EOF'
network:
  version: 2
  ethernets:
    ens3:  # Frontend network
      dhcp4: no
      addresses:
        - 192.168.100.10/24
      gateway4: 192.168.100.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
    ens4:  # App network
      dhcp4: no
      addresses:
        - 192.168.101.10/24
EOF

# Configuration pour Web Servers (web01, web02)
cat > /tmp/netplan-web.yaml <<'EOF'
network:
  version: 2
  ethernets:
    ens3:  # Frontend network
      dhcp4: no
      addresses:
        - 192.168.100.20/24
      gateway4: 192.168.100.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
    ens4:  # App network
      dhcp4: no
      addresses:
        - 192.168.101.20/24
    # ens5 (Replication network) - NE PAS CONFIGURER sur les web servers
EOF

# Configuration pour DB Master (db01)
cat > /tmp/netplan-db01.yaml <<'EOF'
network:
  version: 2
  ethernets:
    ens4:  # App network
      dhcp4: no
      addresses:
        - 192.168.101.30/24
      gateway4: 192.168.101.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
    ens5:  # Replication network
      dhcp4: no
      addresses:
        - 192.168.102.30/24
      routes:
        - to: 192.168.102.0/24
          via: 192.168.102.1
EOF

# Configuration pour DB Slave (db02)
cat > /tmp/netplan-db02.yaml <<'EOF'
network:
  version: 2
  ethernets:
    ens4:  # App network
      dhcp4: no
      addresses:
        - 192.168.101.31/24
      gateway4: 192.168.101.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
    ens5:  # Replication network
      dhcp4: no
      addresses:
        - 192.168.102.31/24
      routes:
        - to: 192.168.102.0/24
          via: 192.168.102.1
EOF

echo "Fichiers netplan créés. Copiez-les sur les VMs correspondantes :"
echo "  - lb01: /tmp/netplan-lb01.yaml -> /etc/netplan/01-netcfg.yaml"
echo "  - web01: /tmp/netplan-web.yaml (modifier IP pour 192.168.100.20/192.168.101.20)"
echo "  - web02: /tmp/netplan-web.yaml (modifier IP pour 192.168.100.21/192.168.101.21)"
echo "  - db01: /tmp/netplan-db01.yaml -> /etc/netplan/01-netcfg.yaml"
echo "  - db02: /tmp/netplan-db02.yaml -> /etc/netplan/01-netcfg.yaml"
echo ""
echo "Puis appliquez avec: sudo netplan apply"
