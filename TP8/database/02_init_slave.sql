-- Script d'initialisation du Slave (db02)
-- TP8 - Scalabilité horizontale et Base répliquée
-- À exécuter sur db02 après installation de MariaDB

-- Arrêter le slave s'il existe déjà
STOP SLAVE;

-- Reset de la configuration slave
RESET SLAVE ALL;

-- Configuration de la réplication vers le master
-- IMPORTANT: Le trafic de réplication passe par l'interface dédiée (192.168.102.30)
CHANGE MASTER TO
    MASTER_HOST = '192.168.102.30',
    MASTER_USER = 'repl_user',
    MASTER_PASSWORD = 'replication_password_123',
    MASTER_PORT = 3306,
    MASTER_LOG_FILE = 'mariadb-bin.000001',
    MASTER_LOG_POS = 4,
    MASTER_CONNECT_RETRY = 10;

-- Note: MASTER_LOG_FILE et MASTER_LOG_POS doivent être récupérés depuis
-- le résultat de SHOW MASTER STATUS sur db01

-- Démarrer le slave
START SLAVE;

-- Vérifier le statut du slave
SHOW SLAVE STATUS\G

-- Vérifications importantes:
-- Slave_IO_Running: Yes
-- Slave_SQL_Running: Yes
-- Seconds_Behind_Master: 0 (ou proche de 0)
-- Last_Error: (doit être vide)

-- Si tout est OK, la réplication est active
