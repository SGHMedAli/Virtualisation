#!/bin/bash
# Script de test de charge pour simuler des montées et baisses de charge
# TP8 - Scalabilité horizontale et Base répliquée
# Utilise Apache Bench (ab) et siege

set -e

# Configuration
LB_URL="http://192.168.100.10"
HEALTH_URL="${LB_URL}/health.php"
WEB_URL="${LB_URL}/"
DURATION=60
CONCURRENT_USERS_START=50
CONCURRENT_USERS_PEAK=500
RAMP_UP_TIME=30

echo "=== Script de Test de Charge ==="
echo "Load Balancer: $LB_URL"
echo ""

# Vérification des outils
check_tools() {
    echo "Vérification des outils de test..."
    
    if ! command -v ab &> /dev/null; then
        echo "Apache Bench (ab) non installé. Installation..."
        apt install -y apache2-utils
    fi
    
    if ! command -v siege &> /dev/null; then
        echo "Siege non installé. Installation..."
        apt install -y siege
    fi
    
    echo "✓ Outils de test disponibles"
}

# Test de santé initial
health_check() {
    echo "Test de santé initial..."
    response=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_URL")
    
    if [ "$response" = "200" ]; then
        echo "✓ Load Balancer opérationnel"
    else
        echo "✗ Load Balancer non opérationnel (HTTP $response)"
        exit 1
    fi
}

# Test de charge avec Apache Bench
test_with_ab() {
    local requests=$1
    local concurrent=$2
    
    echo "=== Test avec Apache Bench ==="
    echo "Requêtes: $requests"
    echo "Concurrent: $concurrent"
    echo ""
    
    ab -n "$requests" -c "$concurrent" -g ab_results.tsv "$WEB_URL"
    
    echo ""
    echo "Résultats sauvegardés dans ab_results.tsv"
}

# Test de charge avec Siege
test_with_siege() {
    local duration=$1
    local concurrent=$2
    
    echo "=== Test avec Siege ==="
    echo "Durée: ${duration}s"
    echo "Concurrent: $concurrent"
    echo ""
    
    siege -c "$concurrent" -t "${duration}s" -g --no-parser "$WEB_URL"
    
    echo ""
}

# Test progressif (ramp-up)
progressive_load_test() {
    echo "=== Test de charge progressif (Ramp-up) ==="
    echo "Simulation d'une montée en charge progressive..."
    echo ""
    
    local current_concurrent=$CONCURRENT_USERS_START
    local step=50
    local steps=$(( (CONCURRENT_USERS_PEAK - CONCURRENT_USERS_START) / step ))
    
    for i in $(seq 1 $steps); do
        echo "Étape $i/$steps - $current_concurrent utilisateurs concurrents"
        siege -c "$current_concurrent" -t 10s --no-parser "$WEB_URL"
        current_concurrent=$((current_concurrent + step))
        sleep 5
    done
    
    echo "Pic de charge atteint: $CONCURRENT_USERS_PEAK utilisateurs"
    siege -c "$CONCURRENT_USERS_PEAK" -t 30s --no-parser "$WEB_URL"
    
    echo "Descente progressive..."
    current_concurrent=$CONCURRENT_USERS_PEAK
    for i in $(seq 1 $steps); do
        current_concurrent=$((current_concurrent - step))
        echo "Étape $((steps - i + 1))/$steps - $current_concurrent utilisateurs concurrents"
        siege -c "$current_concurrent" -t 10s --no-parser "$WEB_URL"
        sleep 5
    done
}

# Test de charge continue pour trigger le scale-out
trigger_scale_out() {
    echo "=== Test pour déclencher le Scale-out ==="
    echo "Charge soutenue pendant 5 minutes..."
    echo ""
    
    # Lancer en arrière-plan
    siege -c "$CONCURRENT_USERS_PEAK" -t 300s --no-parser "$WEB_URL" &
    SIEGE_PID=$!
    
    echo "Siege lancé avec PID: $SIEGE_PID"
    echo "Surveillez les scripts de scaling..."
    echo ""
    echo "Pour arrêter: kill $SIEGE_PID"
    
    # Attendre
    wait $SIEGE_PID
}

# Test de charge réduite pour trigger le scale-in
trigger_scale_in() {
    echo "=== Test pour déclencher le Scale-in ==="
    echo "Charge réduite pendant 5 minutes..."
    echo ""
    
    siege -c 10 -t 300s --no-parser "$WEB_URL"
}

# Menu principal
main() {
    check_tools
    health_check
    
    echo ""
    echo "Choisissez le type de test:"
    echo "1) Test simple avec Apache Bench (1000 requêtes, 50 concurrent)"
    echo "2) Test simple avec Siege (60s, 50 concurrent)"
    echo "3) Test progressif (Ramp-up)"
    echo "4) Test pour déclencher Scale-out (charge élevée)"
    echo "5) Test pour déclencher Scale-in (charge réduite)"
    echo "6) Test personnalisé Apache Bench"
    echo "7) Test personnalisé Siege"
    read -p "Choix: " choice
    
    case $choice in
        1)
            test_with_ab 1000 50
            ;;
        2)
            test_with_siege 60 50
            ;;
        3)
            progressive_load_test
            ;;
        4)
            trigger_scale_out
            ;;
        5)
            trigger_scale_in
            ;;
        6)
            read -p "Nombre de requêtes: " req
            read -p "Utilisateurs concurrents: " conc
            test_with_ab "$req" "$conc"
            ;;
        7)
            read -p "Durée (secondes): " dur
            read -p "Utilisateurs concurrents: " conc
            test_with_siege "$dur" "$conc"
            ;;
        *)
            echo "Choix invalide"
            exit 1
            ;;
    esac
    
    echo ""
    echo "=== Test terminé ==="
}

# Exécution
main
