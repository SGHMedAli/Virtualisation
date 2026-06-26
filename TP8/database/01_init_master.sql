-- Script d'initialisation du Master (db01)
-- TP8 - Scalabilité horizontale et Base répliquée
-- À exécuter sur db01 après installation de MariaDB

-- Création de l'utilisateur de réplication
-- Cet utilisateur se connecte depuis l'interface de réplication (192.168.102.31)
CREATE USER IF NOT EXISTS 'repl_user'@'192.168.102.31' IDENTIFIED BY 'replication_password_123';

-- Grant les privilèges de réplication
GRANT REPLICATION SLAVE ON *.* TO 'repl_user'@'192.168.102.31';

-- Création de l'utilisateur pour les applications web
-- Les web servers se connectent depuis le réseau applicatif (192.168.101.0/24)
CREATE USER IF NOT EXISTS 'webapp'@'192.168.101.%' IDENTIFIED BY 'webapp_password';

-- Grant les privilèges nécessaires pour l'application
GRANT SELECT, INSERT, UPDATE, DELETE ON appdb.* TO 'webapp'@'192.168.101.%';
GRANT SELECT ON testdb.* TO 'webapp'@'192.168.101.%';

-- Création de l'utilisateur pour les lectures (reporting/QA)
CREATE USER IF NOT EXISTS 'readonly'@'192.168.101.%' IDENTIFIED BY 'readonly_password';

GRANT SELECT ON appdb.* TO 'readonly'@'192.168.101.%';
GRANT SELECT ON testdb.* TO 'readonly'@'192.168.101.%';

-- Création de la base de données applicative
CREATE DATABASE IF NOT EXISTS appdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Création de la base de données de test
CREATE DATABASE IF NOT EXISTS testdb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Utiliser la base de données de test
USE testdb;

-- Création d'une table de test pour vérifier la réplication
CREATE TABLE IF NOT EXISTS test_table (
    id INT AUTO_INCREMENT PRIMARY KEY,
    hostname VARCHAR(255),
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    message TEXT
) ENGINE=InnoDB;

-- Insertion de données initiales
INSERT INTO test_table (hostname, message) VALUES ('db01-master', 'Initial data from master');

-- Utiliser la base de données applicative
USE appdb;

-- Création d'une table d'exemple pour l'application
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- Création d'une table de logs
CREATE TABLE IF NOT EXISTS access_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    server_name VARCHAR(100),
    client_ip VARCHAR(45),
    access_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    endpoint VARCHAR(255),
    status_code INT
) ENGINE=InnoDB;

-- Flush des logs pour obtenir la position binaire
FLUSH TABLES WITH READ LOCK;

-- Afficher le statut master pour configuration du slave
SHOW MASTER STATUS;

-- Note: Après avoir noté le File et Position, exécuter:
-- UNLOCK TABLES;
