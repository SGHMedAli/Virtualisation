# TP8 - Scalabilité horizontale et Base répliquée

Projet de TP8 pour le cours de DevOps/QA Automation. Ce projet implémente une architecture scalable avec load balancing, réplication de base de données et scalabilité automatique.

## Auteur

**Rahma Sghari** - QA Automation & DevOps

## Architecture

L'architecture se compose de :
- **3 réseaux virtuels** : Frontal, Applicatif, Réplication
- **5 machines virtuelles** : 1 Load Balancer, 2 Serveurs Web, 2 Bases de données
- **Scalabilité automatique** : Scale-out et Scale-in basés sur la charge
- **Réplication Master-Slave** : MariaDB avec réseau dédié

## Prérequis

- Ubuntu 22.04 LTS (hôte)
- KVM/QEMU avec libvirt
- Vagrant (optionnel)
- Ansible (optionnel)
- Apache Bench et Siege (pour les tests)

## Structure du projet

```
TP8_Folder/
├── TP8/
│   ├── networks/              # Réseaux KVM et provisionnement VM
│   │   ├── 01_create_networks.sh
│   │   ├── 02_provision_vms.sh
│   │   ├── 03_configure_network_interfaces.sh
│   │   └── Vagrantfile
│   ├── web-servers/           # Image modèle et clonage
│   │   ├── cloud-init-web-template.yaml
│   │   ├── ansible-playbook-web.yml
│   │   ├── clone_web_vms.sh
│   │   └── create_template_vm.sh
│   ├── database/              # Configuration MariaDB Master-Slave
│   │   ├── mariadb-master.cnf
│   │   ├── mariadb-slave.cnf
│   │   ├── 01_init_master.sql
│   │   ├── 02_init_slave.sql
│   │   ├── 03_qa_verification.sh
│   │   └── setup_databases.sh
│   ├── load-balancer/         # Configuration Load Balancer
│   │   ├── haproxy.cfg
│   │   ├── setup_haproxy.sh
│   │   ├── add_server_haproxy.sh
│   │   └── remove_server_haproxy.sh
│   └── scaling/               # Scripts de scalabilité
│       ├── scale-out.sh
│       ├── scale-in.sh
│       ├── load_test.sh
│       └── README_commands.md
├── RAPPORT_TP8.md            # Rapport du TP
└── README.md                 # Ce fichier
```

## Guide d'installation

### Étape 1: Création des réseaux virtuels

```bash
cd TP8/networks
sudo bash 01_create_networks.sh
```

Cela crée les 3 réseaux :
- `tp8-frontend` : 192.168.100.0/24
- `tp8-app` : 192.168.101.0/24
- `tp8-replication` : 192.168.102.0/24

### Étape 2: Provisionnement des VMs

**Option A: Avec Vagrant**
```bash
cd TP8/networks
vagrant up
```

**Option B: Avec virsh**
```bash
cd TP8/networks
sudo bash 02_provision_vms.sh
```

### Étape 3: Configuration des interfaces réseau

```bash
cd TP8/networks
sudo bash 03_configure_network_interfaces.sh
```

Copiez manuellement les fichiers netplan sur chaque VM et appliquez :
```bash
sudo netplan apply
```

### Étape 4: Création de l'image modèle web

```bash
cd TP8/web-servers
sudo bash create_template_vm.sh
```

Ou utilisez le fichier Cloud-init directement lors de la création de web01 et web02.

### Étape 5: Configuration des bases de données

```bash
cd TP8/database
sudo bash setup_databases.sh
```

### Étape 6: Configuration de HAProxy

```bash
cd TP8/load-balancer
sudo bash setup_haproxy.sh
```

### Étape 7: Vérification de la réplication

```bash
cd TP8/database
bash 03_qa_verification.sh
```

## Utilisation

### Test du Load Balancing

```bash
# Test avec curl
for i in {1..10}; do curl http://192.168.100.10/; echo "---"; done
```

### Scalabilité automatique

**Scale-out (ajout de serveurs)**
```bash
cd TP8/scaling
sudo bash scale-out.sh
```

Le script monitor la charge et ajoute automatiquement web03 puis web04 si nécessaire.

**Scale-in (retrait de serveurs)**
```bash
cd TP8/scaling
sudo bash scale-in.sh
```

Le script monitor la charge et retire proprement les serveurs en utilisant le mode drain.

### Tests de charge

```bash
cd TP8/scaling
bash load_test.sh
```

Ou utilisez les commandes manuelles :
```bash
# Apache Bench
ab -n 10000 -c 500 http://192.168.100.10/

# Siege
siege -c 500 -t 300S http://192.168.100.10/
```

## Configuration des adresses IP

| Machine | IP Frontal | IP Applicatif | IP Réplication |
|---------|-------------|---------------|----------------|
| lb01    | 192.168.100.10 | 192.168.101.10 | - |
| web01   | 192.168.100.20 | 192.168.101.20 | - |
| web02   | 192.168.100.21 | 192.168.101.21 | - |
| web03   | 192.168.100.22 | 192.168.101.22 | - |
| web04   | 192.168.100.23 | 192.168.101.23 | - |
| db01    | - | 192.168.101.30 | 192.168.102.30 |
| db02    | - | 192.168.101.31 | 192.168.102.31 |

## Statistiques HAProxy

- **URL** : http://192.168.100.10:8404/
- **Utilisateur** : admin
- **Mot de passe** : admin123

## Dépannage

### Les VMs ne démarrent pas
Vérifiez que KVM/libvirt est correctement installé :
```bash
sudo systemctl status libvirtd
virsh version
```

### La réplication ne fonctionne pas
1. Vérifiez que le réseau de réplication est correctement configuré
2. Vérifiez les logs MariaDB : `/var/log/mysql/error.log`
3. Exécutez le script de vérification QA : `TP8/database/03_qa_verification.sh`

### HAProxy ne démarre pas
Vérifiez la configuration :
```bash
sudo haproxy -c -f /etc/haproxy/haproxy.cfg
```

### Les scripts de scaling ne fonctionnent pas
1. Vérifiez que socat est installé sur le Load Balancer
2. Vérifiez que le socket admin est accessible : `/run/haproxy/admin.sock`
3. Vérifiez les permissions SSH entre l'hôte et les VMs

## Nettoyage

Pour supprimer toutes les VMs et réseaux :
```bash
# Arrêter et détruire les VMs
for vm in lb01 web01 web02 db01 db02 web03 web04; do
    virsh destroy $vm 2>/dev/null || true
    virsh undefine $vm 2>/dev/null || true
done

# Supprimer les réseaux
for net in tp8-frontend tp8-app tp8-replication; do
    virsh net-destroy $net 2>/dev/null || true
    virsh net-undefine $net 2>/dev/null || true
done

# Supprimer les disques
rm -f /var/lib/libvirt/images/*.qcow2
```

## Rapport

Le rapport détaillé du TP est disponible dans `RAPPORT_TP8.md`.

## Licence

Ce projet est réalisé à des fins pédagogiques dans le cadre du TP8.
