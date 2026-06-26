# Commandes de Test de Charge

## Apache Bench (ab)

### Installation
```bash
apt install apache2-utils
```

### Test simple
```bash
# 1000 requêtes, 50 utilisateurs concurrents
ab -n 1000 -c 50 http://192.168.100.10/

# Avec sortie en format TSV pour analyse
ab -n 1000 -c 50 -g results.tsv http://192.168.100.10/

# Test avec keep-alive
ab -n 1000 -c 50 -k http://192.168.100.10/

# Test avec timeout personnalisé
ab -n 1000 -c 50 -t 60 http://192.168.100.10/
```

### Test pour déclencher Scale-out
```bash
# Charge élevée sustained
ab -n 10000 -c 500 http://192.168.100.10/

# Test en continu (60 secondes)
ab -n 50000 -c 300 -t 60 http://192.168.100.10/
```

## Siege

### Installation
```bash
apt install siege
```

### Test simple
```bash
# 50 utilisateurs concurrents pendant 60 secondes
siege -c 50 -t 60S http://192.168.100.10/

# Mode internet (simulation de navigation réelle)
siege -c 50 -t 60S -i http://192.168.100.10/

# Avec logging
siege -c 50 -t 60S -l http://192.168.100.10/
```

### Test progressif (Ramp-up)
```bash
# Script bash pour ramp-up
for i in {50..500..50}; do
    echo "Testing with $i concurrent users"
    siege -c $i -t 30S http://192.168.100.10/
    sleep 10
done
```

### Test pour déclencher Scale-out
```bash
# Charge élevée sustained
siege -c 500 -t 300S http://192.168.100.10/

# En arrière-plan
siege -c 500 -t 300S -b http://192.168.100.10/ &
```

### Test pour déclencher Scale-in
```bash
# Charge réduite
siege -c 10 -t 300S http://192.168.100.10/
```

## Autres outils

### wrk (plus performant)
```bash
# Installation
apt install wrk

# Test simple
wrk -t4 -c100 -d30s http://192.168.100.10/

# Test avec script Lua
wrk -t4 -c100 -d30s -s script.lua http://192.168.100.10/
```

### hey (outil Go)
```bash
# Installation
go install github.com/rakyll/hey@latest

# Test simple
hey -n 1000 -c 50 http://192.168.100.10/
```

## Monitoring pendant les tests

### Surveiller HAProxy
```bash
# Via socket admin
echo "show stat" | socat /run/haproxy/admin.sock -

# Via interface web
curl http://192.168.100.10:8404/
```

### Surveiller les VMs
```bash
# CPU
virsh cpu-stats web01

# Mémoire
virsh dommemstat web01

# État général
virsh dominfo web01
```

### Surveiller le réseau
```bash
# Sur le LB
iftop -i ens3

# tcpdump pour le trafic HTTP
tcpdump -i ens3 port 80
```

## Analyse des résultats

### Apache Bench
- **Requests per second**: Nombre de requêtes traitées par seconde
- **Time per request**: Temps moyen par requête
- **Failed requests**: Nombre de requêtes échouées

### Siege
- **Transactions**: Nombre total de transactions
- **Availability**: Pourcentage de disponibilité
- **Response time**: Temps de réponse moyen
- **Data transferred**: Volume de données transférées
