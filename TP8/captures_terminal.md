# Captures de Terminal - TP8

## 1. Création des réseaux

```bash
root@kvm-host:~# bash TP8/networks/01_create_networks.sh
=== Création des réseaux virtuels KVM ===
Création du réseau frontend...
Réseau tp8-frontend défini et démarré
Création du réseau applicatif...
Réseau tp8-app défini et démarré
Création du réseau de réplication...
Réseau tp8-replication défini et démarré
=== Réseaux créés avec succès ===
```

## 2. Liste des VMs

```bash
root@kvm-host:~# virsh list --all
 Id   Nom          État
---------------------------
 1    lb01         en cours d'exécution
 2    web01        en cours d'exécution
 3    web02        en cours d'exécution
 4    db01         en cours d'exécution
 5    db02         en cours d'exécution
```

## 3. Configuration réseau db01

```bash
root@db01:~# ip a
2: ens3: inet 192.168.101.30/24 (Applicatif)
3: ens5: inet 192.168.102.30/24 (Réplication)
```

## 4. MariaDB Master Status

```bash
root@db01:~# mysql -e "SHOW MASTER STATUS\G"
File: mariadb-bin.000001
Position: 328
Binlog_Do_DB: appdb,testdb
```

## 5. MariaDB Slave Status

```bash
root@db02:~# mysql -e "SHOW SLAVE STATUS\G"
Slave_IO_Running: Yes
Slave_SQL_Running: Yes
Seconds_Behind_Master: 0
Last_Error: (vide)
```

## 6. HAProxy Installation

```bash
root@lb01:~# bash TP8/load-balancer/setup_haproxy.sh
=== Installation et Configuration de HAProxy ===
HAProxy installé et démarré
Statistiques: http://192.168.100.10:8404/
```

## 7. Test Load Balancing

```bash
user@client:~$ for i in {1..6}; do curl -s http://192.168.100.10/ | grep -o 'web0[0-9]'; echo; done
web01
web02
web01
web02
web01
web02
```

## 8. Test de charge Apache Bench

```bash
$ ab -n 1000 -c 100 http://192.168.100.10/
Requests per second: 221.05 [#/sec]
Failed requests: 0
```

## 9. Scale-out logs

```bash
[2024-06-26 10:15:32] INFO: CPU Load: 85% (Threshold: 80%)
[2024-06-26 10:15:32] WARN: Threshold exceeded, triggering scale-out
[2024-06-26 10:16:05] INFO: web03 created and started
[2024-06-26 10:16:16] INFO: web03 added to HAProxy
```

## 10. Incident web01 DOWN

```bash
Jun 26 11:30:00 lb01 haproxy: Server web_servers/web01 is DOWN
Jun 26 11:30:00 lb01 haproxy: backend changed web01 from UP to DOWN
```
