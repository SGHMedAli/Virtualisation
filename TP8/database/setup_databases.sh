#!/bin/bash
# Script d'installation et configuration de MariaDB Master-Slave
# TP8 - Scalabilité horizontale et Base répliquée

set -e

# Configuration
MASTER_IP="192.168.101.30"
SLAVE_IP="192.168.101.31"
REPL_MASTER_IP="192.168.102.30"
REPL_SLAVE_IP="192.168.102.31"
SSH_USER="root"

echo "=== Installation et Configuration MariaDB Master-Slave ==="
echo ""

# Installation sur le Master
echo "Installation sur le Master (db01)..."
ssh $SSH_USER@$MASTER_IP << 'EOF'
# Installation de MariaDB
apt update
apt install -y mariadb-server mariadb-client

# Arrêt du service pour configuration
systemctl stop mariadb

# Copie de la configuration master
cat > /etc/mysql/mariadb.conf.d/50-server.cnf << 'CNF'
[mysqld]
server-id = 1
bind-address = 0.0.0.0
log-bin = /var/log/mysql/mariadb-bin
binlog-format = ROW
expire_logs_days = 7
max_binlog_size = 100M
binlog-do-db = appdb
binlog-do-db = testdb
binlog-ignore-db = mysql
binlog-ignore-db = information_schema
binlog-ignore-db = performance_schema
sync_binlog = 1
innodb_flush_log_at_trx_commit = 1
max_connections = 200
innodb_buffer_pool_size = 256M
CNF

# Démarrage du service
systemctl start mariadb
systemctl enable mariadb

# Sécurisation initiale (root sans mot de passe pour l'automatisation)
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root_password';"
EOF

echo "Master installé"
echo ""

# Installation sur le Slave
echo "Installation sur le Slave (db02)..."
ssh $SSH_USER@$SLAVE_IP << 'EOF'
# Installation de MariaDB
apt update
apt install -y mariadb-server mariadb-client

# Arrêt du service pour configuration
systemctl stop mariadb

# Copie de la configuration slave
cat > /etc/mysql/mariadb.conf.d/50-server.cnf << 'CNF'
[mysqld]
server-id = 2
bind-address = 0.0.0.0
relay-log = /var/log/mysql/mariadb-relay-bin
relay-log-index = /var/log/mysql/mariadb-relay-bin.index
read-only = 1
super-read-only = 1
slave_skip_errors = all
slave_parallel_threads = 4
max_connections = 200
innodb_buffer_pool_size = 256M
CNF

# Démarrage du service
systemctl start mariadb
systemctl enable mariadb

# Sécurisation initiale
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY 'root_password';"
EOF

echo "Slave installé"
echo ""

# Configuration du Master
echo "Configuration du Master..."
scp 01_init_master.sql $SSH_USER@$MASTER_IP:/tmp/
ssh $SSH_USER@$MASTER_IP "mysql -uroot -proot_password < /tmp/01_init_master.sql"

# Récupération du statut master
echo "Récupération du statut Master..."
MASTER_STATUS=$(ssh $SSH_USER@$MASTER_IP "mysql -uroot -proot_password -e 'SHOW MASTER STATUS\\G'")
echo "$MASTER_STATUS"
echo ""

# Extraction du fichier et position
MASTER_LOG_FILE=$(echo "$MASTER_STATUS" | grep "File:" | awk '{print $2}')
MASTER_LOG_POS=$(echo "$MASTER_STATUS" | grep "Position:" | awk '{print $2}')

echo "Master Log File: $MASTER_LOG_FILE"
echo "Master Log Position: $MASTER_LOG_POS"
echo ""

# Configuration du Slave
echo "Configuration du Slave..."
scp 02_init_slave.sql $SSH_USER@$SLAVE_IP:/tmp/
ssh $SSH_USER@$SLAVE_IP "sed -i \"s/MASTER_LOG_FILE = 'mariadb-bin.000001'/MASTER_LOG_FILE = '$MASTER_LOG_FILE'/\" /tmp/02_init_slave.sql"
ssh $SSH_USER@$SLAVE_IP "sed -i \"s/MASTER_LOG_POS = 4/MASTER_LOG_POS = $MASTER_LOG_POS/\" /tmp/02_init_slave.sql"
ssh $SSH_USER@$SLAVE_IP "mysql -uroot -proot_password < /tmp/02_init_slave.sql"

echo ""
echo "=== Configuration terminée ==="
echo "Exécutez le script de vérification QA pour tester la réplication"
