#!/bin/bash
# Script de vérification QA pour la réplication MariaDB
# TP8 - Scalabilité horizontale et Base répliquée

set -e

# Configuration
DB_MASTER_HOST="192.168.101.30"
DB_SLAVE_HOST="192.168.101.31"
DB_REPL_HOST="192.168.102.30"
DB_USER="webapp"
DB_PASS="webapp_password"
DB_NAME="testdb"

echo "=== Script de vérification QA - Réplication MariaDB ==="
echo ""

# Test 1: Connexion au Master
echo "Test 1: Connexion au Master (db01)"
mysql -h "$DB_MASTER_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 'Connexion Master OK' as status;"
echo ""

# Test 2: Connexion au Slave
echo "Test 2: Connexion au Slave (db02)"
mysql -h "$DB_SLAVE_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 'Connexion Slave OK' as status;"
echo ""

# Test 3: Vérifier que le Slave est en lecture seule
echo "Test 3: Vérification mode lecture seule sur Slave"
READ_ONLY=$(mysql -h "$DB_SLAVE_HOST" -u "$DB_USER" -p"$DB_PASS" -e "SHOW VARIABLES LIKE 'read_only';" | tail -n 1 | awk '{print $2}')
if [ "$READ_ONLY" = "ON" ]; then
    echo "✓ Slave est en lecture seule"
else
    echo "✗ Slave n'est PAS en lecture seule"
fi
echo ""

# Test 4: Insertion de données sur le Master
echo "Test 4: Insertion de données sur le Master"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
mysql -h "$DB_MASTER_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "INSERT INTO test_table (hostname, message) VALUES ('qa_test', 'Test insertion $TIMESTAMP');"
echo "Données insérées sur le Master"
echo ""

# Test 5: Attente de la réplication (5 secondes)
echo "Test 5: Attente de la réplication (5 secondes)..."
sleep 5
echo ""

# Test 6: Vérification de la réplication sur le Slave
echo "Test 6: Vérification de la réplication sur le Slave"
COUNT=$(mysql -h "$DB_SLAVE_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT COUNT(*) as count FROM test_table WHERE message LIKE '%$TIMESTAMP%';" | tail -n 1)
if [ "$COUNT" -gt 0 ]; then
    echo "✓ Réplication réussie: $COUNT enregistrement(s) trouvé(s) sur le Slave"
else
    echo "✗ Échec de la réplication: Aucun enregistrement trouvé sur le Slave"
fi
echo ""

# Test 7: Vérification du statut Slave
echo "Test 7: Statut détaillé du Slave"
mysql -h "$DB_SLAVE_HOST" -u "$DB_USER" -p"$DB_PASS" -e "SHOW SLAVE STATUS\G" | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master|Last_Error"
echo ""

# Test 8: Vérification que l'écriture est bloquée sur le Slave
echo "Test 8: Tentative d'écriture sur le Slave (doit échouer)"
if mysql -h "$DB_SLAVE_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "INSERT INTO test_table (hostname, message) VALUES ('slave_write', 'Ceci ne doit pas fonctionner');" 2>/dev/null; then
    echo "✗ Échec: L'écriture sur le Slave a réussi (ce ne devrait pas être le cas)"
else
    echo "✓ Succès: L'écriture sur le Slave est correctement bloquée"
fi
echo ""

# Test 9: Vérification du nombre total d'enregistrements
echo "Test 9: Comparaison du nombre d'enregistrements"
MASTER_COUNT=$(mysql -h "$DB_MASTER_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT COUNT(*) FROM test_table;" | tail -n 1)
SLAVE_COUNT=$(mysql -h "$DB_SLAVE_HOST" -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT COUNT(*) FROM test_table;" | tail -n 1)
echo "Master: $MASTER_COUNT enregistrements"
echo "Slave: $SLAVE_COUNT enregistrements"
if [ "$MASTER_COUNT" -eq "$SLAVE_COUNT" ]; then
    echo "✓ Les bases de données sont synchronisées"
else
    echo "✗ Désynchronisation détectée"
fi
echo ""

# Test 10: Vérification du réseau de réplication
echo "Test 10: Vérification que la réplication utilise le réseau dédié"
echo "Vérifiez manuellement que le trafic de réplication passe par 192.168.102.0/24"
echo "Sur db02: tcpdump -i ens5 port 3306"
echo ""

echo "=== Fin des tests QA ==="
