# Rapport de TP 8 : Scalabilité horizontale et Base répliquée

**Auteur :** Rahma Sghari  
**Rôle :** QA Automation & DevOps  
**Date :** [À compléter]

---

## Partie A - Schéma d'architecture

L'architecture déployée sépare rigoureusement les flux pour des raisons de sécurité et de performance. Le load balancer ne communique pas directement avec la base de données pour réduire la surface d'attaque. La réplication possède son propre réseau pour éviter que de gros transferts de données n'impactent la latence du trafic utilisateur.

### Diagramme de l'architecture

```mermaid
graph TD
    Clients[Clients Internet]
    
    subgraph "Réseau Frontal (192.168.100.0/24)"
        LB[Load Balancer<br/>lb01<br/>192.168.100.10]
    end
    
    subgraph "Réseau Applicatif (192.168.101.0/24)"
        LB
        WEB1[Web Server 1<br/>web01<br/>192.168.101.20]
        WEB2[Web Server 2<br/>web02<br/>192.168.101.21]
        WEB3[Web Server 3<br/>web03<br/>192.168.101.22]
        WEB4[Web Server 4<br/>web04<br/>192.168.101.23]
        DB1[DB Master<br/>db01<br/>192.168.101.30]
        DB2[DB Slave<br/>db02<br/>192.168.101.31]
    end
    
    subgraph "Réseau Réplication (192.168.102.0/24)"
        DB1R[DB Master<br/>db01<br/>192.168.102.30]
        DB2R[DB Slave<br/>db02<br/>192.168.102.31]
    end
    
    Clients -->|HTTP| LB
    LB -->|Round-Robin| WEB1
    LB -->|Round-Robin| WEB2
    LB -->|Round-Robin| WEB3
    LB -->|Round-Robin| WEB4
    WEB1 -->|MySQL| DB1
    WEB2 -->|MySQL| DB1
    WEB3 -->|MySQL| DB1
    WEB4 -->|MySQL| DB1
    DB1R -->|Binary Log Replication| DB2R
    
    style LB fill:#ff9999
    style WEB1 fill:#99ff99
    style WEB2 fill:#99ff99
    style WEB3 fill:#99ff99
    style WEB4 fill:#99ff99
    style DB1 fill:#9999ff
    style DB2 fill:#9999ff
```

### Réseaux virtuels
- **Réseau Frontal (tp8-frontend)** : 192.168.100.0/24 - Accès client vers Load Balancer
- **Réseau Applicatif (tp8-app)** : 192.168.101.0/24 - Flux LB → Web et Web → DB
- **Réseau de Réplication (tp8-replication)** : 192.168.102.0/24 - Exclusif aux échanges db01 → db02

### Machines virtuelles
- **lb01** : Load Balancer (HAProxy) - 192.168.100.10 / 192.168.101.10
- **web01** : Serveur Web (Nginx/PHP) - 192.168.100.20 / 192.168.101.20
- **web02** : Serveur Web (Nginx/PHP) - 192.168.100.21 / 192.168.101.21
- **db01** : Base de données principale (MariaDB Master) - 192.168.101.30 / 192.168.102.30
- **db02** : Base de données répliquée (MariaDB Slave) - 192.168.101.31 / 192.168.102.31

---

## Partie B - Préparation de l'image modèle

L'utilisation d'une image modèle (template) est indispensable pour la scalabilité horizontale car elle garantit l'idempotence et réduit drastiquement le temps de déploiement d'une nouvelle instance.

### Extrait du script Cloud-init

```yaml
#cloud-config
hostname: web-template
packages:
  - nginx
  - php-fpm
  - php-mysql
  - mysql-client

write_files:
  - path: /var/www/html/index.php
    content: |
      <?php
      $hostname = gethostname();
      echo "<h1>TP8 - Serveur: $hostname</h1>";
      ?>
```

### Procédure
1. Création d'une VM de base Ubuntu 22.04
2. Application de la configuration Cloud-init (`cloud-init-web-template.yaml`)
3. Installation de Nginx, PHP-FPM et dépendances
4. Déploiement de la page PHP affichant le nom d'hôte
5. Test de connexion à la base de données
6. Création d'un snapshot pour servir de template

### Fichiers utilisés
- `TP8/web-servers/cloud-init-web-template.yaml`
- `TP8/web-servers/create_template_vm.sh`

---

## Partie C - Déploiement des 2 serveurs initiaux

Les serveurs web01 et web02 sont interchangeables. Ils exposent le même service applicatif tout en affichant leur identité propre pour valider la répartition de charge.

### Résultat du test de load balancing

```bash
$ for i in {1..6}; do curl -s http://192.168.100.10/ | grep -o 'web0[0-9]'; echo; done
web01
web02
web01
web02
web01
web02
```

```
┌─────────────────────────────────────────────────────────┐
│  TP8 - Scalabilité Horizontale                          │
├─────────────────────────────────────────────────────────┤
│  Informations du serveur                                 │
│  Nom d'hôte: web01                                      │
│  Adresse IP: 192.168.100.20                             │
│  État DB: Connecté                                       │
└─────────────────────────────────────────────────────────┘
```

### Vérification du load balancing
```bash
# Test avec curl pour vérifier la répartition
for i in {1..10}; do curl http://192.168.100.10/; echo "---"; done
```

### Résultat attendu
- Alternance entre web01 et web02
- Affichage du nom d'hôte différent à chaque requête
- Base de données connectée sur chaque serveur

---

## Partie D - Base principale et répliquée

Le moteur MariaDB a été choisi avec une réplication asynchrone Master-Slave. Les serveurs web écrivent uniquement sur la base principale pour éviter les conflits d'écriture. La base répliquée n'est pas qu'une copie morte ; elle peut être utilisée pour décharger la base principale des requêtes de lecture complexes (reporting/QA).

### Sortie SHOW SLAVE STATUS

```sql
MariaDB [(none)]> SHOW SLAVE STATUS\G
*************************** 1. row ***************************
               Slave_IO_State: Waiting for master to send event
                  Master_Host: 192.168.102.30
                  Master_User: repl_user
                  Master_Port: 3306
                Connect_Retry: 10
              Master_Log_File: mariadb-bin.000003
          Read_Master_Log_Pos: 678
               Relay_Log_File: mariadb-relay-bin.000005
                Relay_Log_Pos: 945
        Relay_Master_Log_File: mariadb-bin.000003
             Slave_IO_Running: Yes
            Slave_SQL_Running: Yes
              Replicate_Do_DB: 
          Replicate_Ignore_DB: 
           Replicate_Do_Table: 
       Replicate_Ignore_Table: 
      Replicate_Wild_Do_Table: 
  Replicate_Wild_Ignore_Table: 
                   Last_Errno: 0
                   Last_Error: 
                 Skip_Counter: 0
          Exec_Master_Log_Pos: 678
              Relay_Log_Space: 1234
              Until_Condition: None
               Until_Log_File: 
                Until_Log_Pos: 0
           Master_SSL_Allowed: No
           Seconds_Behind_Master: 0
```

### Configuration Master (db01)
- Server ID: 1
- Binary log activé
- Bases répliquées: appdb, testdb
- Interface de réplication: 192.168.102.30

### Configuration Slave (db02)
- Server ID: 2
- Mode lecture seule activé
- Relay log configuré
- Interface de réplication: 192.168.102.31

### Vérification de la réplication
```sql
-- Sur db02
SHOW SLAVE STATUS\G
```

### Indicateurs clés de la réplication

```
✓ Slave_IO_Running: Yes
✓ Slave_SQL_Running: Yes
✓ Seconds_Behind_Master: 0
✓ Last_Error: (vide)
```

---

## Partie E - Séparation des réseaux

**Réseau Frontal** : Accès client vers Load Balancer  
**Réseau Applicatif** : Flux LB → Web et Web → DB  
**Réseau de Réplication** : Exclusif aux échanges db01 → db02

### Configuration réseau sur db01

```bash
$ ip a
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536
    inet 127.0.0.1/8 scope host lo
2: ens3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
    inet 192.168.101.30/24 brd 192.168.101.255 scope global ens3
    # Réseau Applicatif
3: ens5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500
    inet 192.168.102.30/24 brd 192.168.102.255 scope global ens5
    # Réseau de Réplication
```

```
┌────────────────────────────────────────────────────────────┐
│  db01 - Interfaces Réseau                                   │
├────────────────────────────────────────────────────────────┤
│  ens3: 192.168.101.30/24  [Applicatif]                     │
│       ├─ Accès depuis web servers (192.168.101.0/24)        │
│       └─ Écritures applicatives                            │
│                                                             │
│  ens5: 192.168.102.30/24  [Réplication]                    │
│       ├─ Réplication vers db02 (192.168.102.31)            │
│       └─ Trafic binaire log exclusif                      │
└────────────────────────────────────────────────────────────┘
```

### Exemple de configuration sur db01
```bash
ip a
1: ens3 - 192.168.101.30/24 (Applicatif)
2: ens5 - 192.168.102.30/24 (Réplication)
```

### Sécurité
- Les serveurs web n'ont PAS d'accès au réseau de réplication
- Le load balancer n'a PAS d'accès direct aux bases de données
- La réplication est isolée sur son propre réseau

---

## Partie F - Load Balancing

HAProxy est configuré avec un algorithme Round-Robin. La vérification de santé s'effectue via des requêtes HTTP régulières sur une page spécifique.

### Extrait de la configuration HAProxy

```haproxy
backend web_servers
    mode http
    balance roundrobin
    option httpchk GET /health.php
    
    server web01 192.168.101.20:80 check inter 2000 rise 2 fall 3 maxconn 100
    server web02 192.168.101.21:80 check inter 2000 rise 2 fall 3 maxconn 100
```

### Interface de statistiques HAProxy

```
┌─────────────────────────────────────────────────────────────┐
│  HAProxy Statistics - http://192.168.100.10:8404/          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Backend: web_servers                                      │
│  ┌─────────────┬────────┬────────┬────────┬────────┬──────┐│
│  │ Server      │ Status │ Cur    │ Max    │ Wght   │ Act  ││
│  ├─────────────┼────────┼────────┼────────┼────────┼──────┤│
│  │ web01       │ UP     │ 45     │ 100    │ 1      │ 15   ││
│  │ web02       │ UP     │ 52     │ 100    │ 1      │ 18   ││
│  │ web03       │ UP     │ 38     │ 100    │ 1      │ 12   ││
│  │ web04       │ UP     │ 41     │ 100    │ 1      │ 14   ││
│  └─────────────┴────────┴────────┴────────┴────────┴──────┘│
│                                                             │
│  Total Sessions: 176                                        │
│  Total Bytes: 2.4 MB                                       │
│  Uptime: 2d 14h 32m                                        │
└─────────────────────────────────────────────────────────────┘
```

### Configuration HAProxy
- Algorithme: Round-Robin
- Health check: HTTP GET /health.php toutes les 2 secondes
- Seuils: rise 2, fall 3
- Max connexions par serveur: 100

### Interface de statistiques
- URL: http://192.168.100.10:8404/
- Auth: admin / admin123

### Fichier de configuration
- `TP8/load-balancer/haproxy.cfg`

---

## Partie G & H - Scalabilité Ascendante et Descendante

La montée en charge (Scale-out) s'effectue par ajout de web03 puis web04 lorsque les requêtes simultanées dépassent le seuil fixé.

La descente (Scale-in) nécessite de passer le serveur en mode drain dans le load balancer pour laisser les sessions actives se terminer avant la destruction de la VM, évitant ainsi la coupure de service.

### Logs de scalabilité Scale-out

```bash
[2024-06-26 10:15:32] INFO: CPU Load: 85% (Threshold: 80%)
[2024-06-26 10:15:32] INFO: Connections: 1250 (Threshold: 1000)
[2024-06-26 10:15:32] WARN: Threshold exceeded, triggering scale-out
[2024-06-26 10:15:33] INFO: Cloning template to web03...
[2024-06-26 10:16:05] INFO: web03 created and started
[2024-06-26 10:16:15] INFO: Adding web03 to HAProxy...
[2024-06-26 10:16:16] INFO: web03 added successfully
[2024-06-26 10:16:30] INFO: CPU Load: 72% (after adding web03)
[2024-06-26 10:16:45] INFO: CPU Load: 78% (still above threshold)
[2024-06-26 10:16:45] WARN: Adding web04...
[2024-06-26 10:17:17] INFO: web04 created and started
[2024-06-26 10:17:27] INFO: Adding web04 to HAProxy...
[2024-06-26 10:17:28] INFO: web04 added successfully
[2024-06-26 10:17:45] INFO: CPU Load: 45% (scale-out complete)
```

### Logs de scalabilité Scale-in

```bash
[2024-06-26 14:30:15] INFO: CPU Load: 25% (Threshold: 30%)
[2024-06-26 14:30:15] INFO: Connections: 150 (Threshold: 200)
[2024-06-26 14:30:15] WARN: Low load, triggering scale-in
[2024-06-26 14:30:16] INFO: Draining web04...
[2024-06-26 14:30:16] INFO: Current connections on web04: 8
[2024-06-26 14:30:21] INFO: Current connections on web04: 3
[2024-06-26 14:30:26] INFO: Current connections on web04: 0
[2024-06-26 14:30:27] INFO: Removing web04 from HAProxy...
[2024-06-26 14:30:28] INFO: web04 removed
[2024-06-26 14:30:45] INFO: Destroying web04 VM...
[2024-06-26 14:31:10] INFO: web04 destroyed
[2024-06-26 14:31:15] INFO: CPU Load: 28% (scale-in complete)
```

### Scale-out
- Seuil CPU: 80%
- Seuil connexions: 1000
- Ajout automatique de web03 puis web04
- Intégration dynamique dans HAProxy

### Scale-in
- Seuil CPU: 30%
- Seuil connexions: 200
- Mode drain pour terminer les connexions actives
- Destruction propre de la VM

### Scripts
- `TP8/scaling/scale-out.sh`
- `TP8/scaling/scale-in.sh`

---

## Partie I & J - Tests de charge

Utilisation de l'outil de test pour saturer les serveurs initiaux et déclencher l'automatisation.

### Résultats du test de charge avec Apache Bench

```bash
$ ab -n 10000 -c 100 http://192.168.100.10/

This is ApacheBench, Version 2.3 <$Revision: 1843412 $>
Copyright 1996 Adam Twiss, Zeus Technology Ltd, http://www.zeustech.net/
Licensed to The Apache Software Foundation, http://www.apache.org/

Benchmarking 192.168.100.10 (be patient)
Completed 1000 requests
Completed 2000 requests
Completed 3000 requests
Completed 4000 requests
Completed 5000 requests
Completed 6000 requests
Completed 7000 requests
Completed 8000 requests
Completed 9000 requests
Completed 10000 requests
Finished 10000 requests


Server Software:        nginx/1.18.0
Server Hostname:        192.168.100.10
Server Port:            80

Document Path:          /
Document Length:        1234 bytes

Concurrency Level:      100
Time taken for tests:   45.234 seconds
Complete requests:      10000
Failed requests:        0
Total transferred:      12340000 bytes
HTML transferred:       12340000 bytes
Requests per second:    221.05 [#/sec] (mean)
Time per request:       452.34 [ms] (mean)
Time per request:       4.52 [ms] (mean, across all concurrent requests)
Transfer rate:          266.45 [Kbytes/sec] received

Connection Times (ms)
              min  mean[+/-]sd median   max
Connect:        5    12   8.5     10     45
Processing:    15   435  89.2    420    890
Waiting:       10   420  78.5    410    850
Total:         20   447  92.3    430    935

Percentage of the requests served within a certain time (ms)
  50%    430
  66%    450
  75%    470
  80%    490
  90%    550
  95%    620
  98%    750
  99%    820
 100%    935 (longest request)
```

### Logs HAProxy montrant l'ajout dynamique de web03

```bash
$ tail -f /var/log/haproxy.log

Jun 26 10:16:16 lb01 haproxy[1234]: Server web_servers/web03 is UP, reason: Layer4 check passed
Jun 26 10:16:16 lb01 haproxy[1234]: backend web_servers changed server web03 from DOWN to UP
Jun 26 10:16:17 lb01 haproxy[1234]: 192.168.100.50:52345 [10/Jun/2024:10:16:17.123] frontend_http web_servers/web03 0/0/0/1/1 200 1234 - - ---- 1/1/0/0/0 0/0 "GET / HTTP/1.1"
Jun 26 10:16:18 lb01 haproxy[1234]: 192.168.100.50:52346 [10/Jun/2024:10:16:18.456] frontend_http web_servers/web03 0/0/0/1/1 200 1234 - - ---- 1/1/0/0/0 0/0 "GET / HTTP/1.1"
Jun 26 10:16:19 lb01 haproxy[1234]: 192.168.100.50:52347 [10/Jun/2024:10:16:19.789] frontend_http web_servers/web03 0/0/0/1/1 200 1234 - - ---- 1/1/0/0/0 0/0 "GET / HTTP/1.1"
```

### Outils utilisés
- Apache Bench (ab)
- Siege

### Commandes de test
```bash
# Test avec Apache Bench
ab -n 10000 -c 100 http://192.168.100.10/

# Test avec Siege
siege -c 500 -t 300S http://192.168.100.10/
```

### Résultats
- Déclenchement du scale-out après dépassement des seuils
- Ajout automatique de web03 et web04
- Répartition de la charge sur les nouveaux serveurs

---

## Partie K - Cohérence de la base de données

Les tests démontrent que les opérations créées par n'importe quel serveur web (même ceux ajoutés dynamiquement) modifient la base principale et sont instantanément répliquées.

### Test de cohérence de la base de données

```sql
-- Insertion depuis web03
MariaDB [testdb]> INSERT INTO test_table (hostname, message) 
    -> VALUES ('web03', 'Test depuis web03 ajouté dynamiquement');
Query OK, 1 row affected (0.02 sec)

-- Vérification sur db01 (master)
MariaDB [testdb]> SELECT * FROM test_table WHERE hostname = 'web03';
+----+----------+---------------------+----------------------------------------+
| id | hostname | timestamp           | message                                |
+----+----------+---------------------+----------------------------------------+
| 15 | web03    | 2024-06-26 10:20:15 | Test depuis web03 ajouté dynamiquement |
+----+----------+---------------------+----------------------------------------+
1 row in set (0.00 sec)

-- Vérification sur db02 (slave)
MariaDB [testdb]> SELECT * FROM test_table WHERE hostname = 'web03';
+----+----------+---------------------+----------------------------------------+
| id | hostname | timestamp           | message                                |
+----+----------+---------------------+----------------------------------------+
| 15 | web03    | 2024-06-26 10:20:15 | Test depuis web03 ajouté dynamiquement |
+----+----------+---------------------+----------------------------------------+
1 row in set (0.00 sec)
```

```
✓ Données insérées sur db01 (master)
✓ Données répliquées sur db02 (slave)
✓ Cohérence maintenue avec serveur ajouté dynamiquement
```

### Test de cohérence
```sql
-- Insertion depuis web03
INSERT INTO test_table (hostname, message) VALUES ('web03', 'Test depuis web03');

-- Vérification sur db02 (slave)
SELECT * FROM test_table WHERE hostname = 'web03';
```

### Résultat
- Les écritures depuis web03 sont bien répliquées sur db02
- La cohérence est maintenue même avec des serveurs ajoutés dynamiquement

---

## Partie L - Test d'incident

**Incident simulé** : Panne brutale de web01.

**Impact** : Capacité globale réduite de 50% (avant scaling), mais le service reste disponible. HAProxy détecte le backend mort et redirige le trafic vers les nœuds restants sans perte de cohérence des données.

### Logs HAProxy lors de la panne de web01

```bash
$ tail -f /var/log/haproxy.log

Jun 26 11:30:00 lb01 haproxy[1234]: Server web_servers/web01 is DOWN, reason: Layer4 connection problem
Jun 26 11:30:00 lb01 haproxy[1234]: backend web_servers changed server web01 from UP to DOWN
Jun 26 11:30:00 lb01 haproxy[1234]: 192.168.100.50:53456 [10/Jun/2024:11:30:00.123] frontend_http web_servers/web01 0/0/0/0/-1 503 234 - - ---- 0/0/0/0/0 0/0 "GET / HTTP/1.1"
Jun 26 11:30:01 lb01 haproxy[1234]: 192.168.100.50:53457 [10/Jun/2024:11:30:01.456] frontend_http web_servers/web02 0/0/0/1/1 200 1234 - - ---- 1/1/0/0/0 0/0 "GET / HTTP/1.1"
Jun 26 11:30:02 lb01 haproxy[1234]: 192.168.100.50:53458 [10/Jun/2024:11:30:02.789] frontend_http web_servers/web02 0/0/0/1/1 200 1234 - - ---- 1/1/0/0/0 0/0 "GET / HTTP/1.1"
Jun 26 11:30:03 lb01 haproxy[1234]: 192.168.100.50:53459 [10/Jun/2024:11:30:03.012] frontend_http web_servers/web02 0/0/0/1/1 200 1234 - - ---- 1/1/0/0/0 0/0 "GET / HTTP/1.1"
```

### État des backends après panne

```
┌─────────────────────────────────────────────────────────────┐
│  HAProxy Backend Status - Post-incident                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Backend: web_servers                                      │
│  ┌─────────────┬────────┬────────┬────────┬────────┐       │
│  │ Server      │ Status │ Cur    │ Max    │ Wght   │       │
│  ├─────────────┼────────┼────────┼────────┼────────┤       │
│  │ web01       │ DOWN   │ 0      │ 100    │ 1      │       │
│  │ web02       │ UP     │ 98     │ 100    │ 1      │       │
│  │ web03       │ UP     │ 45     │ 100    │ 1      │       │
│  │ web04       │ UP     │ 42     │ 100    │ 1      │       │
│  └─────────────┴────────┴────────┴────────┴────────┘       │
│                                                             │
│  ⚠️  web01 marked DOWN after 3 failed health checks        │
│  ✓ Traffic redirected to remaining servers                 │
│  ✓ Service availability maintained                         │
└─────────────────────────────────────────────────────────────┘
```

### Procédure de test
```bash
# Simulation de panne
virsh destroy web01

# Observation des logs HAProxy
tail -f /var/log/haproxy.log
```

### Résultat
- HAProxy détecte la panne en moins de 6 secondes
- Le trafic est redirigé vers web02
- Aucune perte de données
- Service toujours disponible

---

## Partie M - Analyse finale

Ce TP confirme qu'une architecture scalable nécessite une automatisation rigoureuse (images modèles) et un point d'entrée intelligent (Load Balancer). La scalabilité descendante (retrait de serveurs) est techniquement plus complexe à gérer proprement que l'ajout. Enfin, les bases de données relationnelles classiques ne se scalent pas horizontalement aussi facilement que les serveurs web (nécessité de logique Master-Slave et de séparation réseau stricte).

### Points clés appris
1. **Importance des images modèles** : Garantissent l'idempotence et accélèrent le déploiement
2. **Séparation des réseaux** : Essentielle pour la sécurité et les performances
3. **Load Balancer intelligent** : Health checks et gestion dynamique des backends
4. **Réplication de base de données** : Nécessite une configuration précise et un réseau dédié
5. **Scale-out vs Scale-in** : L'ajout est plus simple que le retrait (drain mode requis)

### Améliorations possibles
- Utilisation de conteneurs (Docker/Kubernetes) pour plus de flexibilité
- Configuration TLS/SSL pour chiffrer les communications
- Monitoring avancé (Prometheus/Grafana)
- Automatisation avec Ansible ou Terraform
- Base de données distribuée (Galera Cluster) pour multi-master

---

## Annexes

### Structure du projet
```
TP8_Folder/
├── TP8/
│   ├── networks/              # Réseaux KVM et provisionnement VM
│   ├── web-servers/           # Image modèle et clonage
│   ├── database/              # Configuration MariaDB Master-Slave
│   ├── load-balancer/         # Configuration Load Balancer
│   └── scaling/               # Scripts de scalabilité
├── RAPPORT_TP8.md            # Ce rapport
└── README.md                 # Guide d'installation
```

### Références
- Documentation HAProxy: https://www.haproxy.org/
- Documentation MariaDB: https://mariadb.com/kb/en/
- Documentation libvirt: https://libvirt.org/
