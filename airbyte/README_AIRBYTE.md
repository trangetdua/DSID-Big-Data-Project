# Airbyte — déploiement et configuration validée

Airbyte Open Source est déployé localement avec `abctl` dans
Kubernetes-in-Docker.

La stack PostgreSQL, MariaDB, EspoCRM, MinIO et Adminer est exécutée
séparément avec Docker Compose.

## Accès

Airbyte UI :

http://localhost:8000

Depuis Airbyte sous macOS, les services Docker Compose sont joints avec :

- PostgreSQL : `host.docker.internal:5432`
- MariaDB : `host.docker.internal:3306`
- MinIO : `host.docker.internal:9000`

## Flux validés

Les flux suivants ont été exécutés avec succès :

1. API Metriq -> MinIO
2. MinIO -> Airbyte S3 Source -> PostgreSQL Bronze
3. Riverlane File Source -> MinIO
4. Riverlane MinIO -> Airbyte S3 Source -> PostgreSQL Bronze
5. EspoCRM/MariaDB -> Airbyte MySQL Source -> PostgreSQL Bronze

Le flux MinIO -> PostgreSQL via Airbyte S3 Source a donc été validé
fonctionnellement dans l'environnement de ce projet.

Le connecteur S3 Source utilisé pour le flux Riverlane est la version 4.16.1.

Les preuves sont disponibles dans :

- `preuves/airbyte/`
- `preuves/csv/replay_hop2_bronze.txt`

## Sécurité

Aucun mot de passe, access key, client secret ou token réel n'est inclus
dans le dossier de rendu.

Les credentials restent uniquement dans l'environnement local.
