# Reconstitution des flux Airbyte

## Environnement

- Airbyte application/chart : 2.4.0
- abctl : v0.30.4
- Source S3 Riverlane : 4.16.1
- Interface Airbyte : http://localhost:8000
- Hôte Docker Compose vu depuis Airbyte : host.docker.internal
- PostgreSQL : port 5432, base warehouse, schéma bronze
- MariaDB : port 3306, base espocrm
- MinIO : port 9000, bucket dsid-raw

Les identifiants et mots de passe doivent être créés localement.
Aucun secret n'est fourni.

## Ordre de reprise

1. Démarrer Docker Compose selon README_DOCKER.md.
2. Installer Airbyte avec abctl.
3. Créer le bucket MinIO dsid-raw.
4. Importer airbyte/manifests/metriq.yaml dans le Connector Builder
   d'Airbyte.
5. Reconstituer les sources et destinations selon
   preuves/airbyte/config_summary.md.
6. Exécuter les cinq connexions de premier hop :
   - Metriq API vers MinIO : Full Refresh / Append
   - Riverlane accuracy vers MinIO : Full Refresh / Overwrite
   - Riverlane memory vers MinIO : Full Refresh / Overwrite
   - Riverlane d21 vers MinIO : Full Refresh / Overwrite
   - Riverlane d23 vers MinIO : Full Refresh / Overwrite
7. Exécuter les deux connexions S3 vers Bronze :
   - Metriq : Incremental / Append
   - Riverlane : Full Refresh / Overwrite
8. Créer dans EspoCRM un Account, deux Contacts et une Opportunity,
   puis synchroniser MariaDB vers PostgreSQL en Full Refresh / Overwrite.
9. Exécuter les scripts SQL Silver dans l'ordre 01, 02, 03.
10. Exécuter les trois scripts SQL de tests.

## Données Riverlane

Source : https://zenodo.org/records/11621878

Fichiers :
- fpga_accuracy_data.csv
- fpga_memory_data.csv
- noise_rate_sampling_full_d21.csv
- noise_rate_sampling_full_d23.csv

Les Airbyte File Sources utilisent l'option de lecture :
{"dtype":"string"}

Conserver les originaux dans :
raw/csv/riverlane/original/

Conserver les JSONL Airbyte dans :
raw/csv/riverlane/airbyte/

Les empreintes SHA-256 sont dans :
data/manifestes/riverlane/manifest.json

## Résultats de référence

Metriq : Bronze 413, Silver 408.
Riverlane : Bronze 77 / 9 / 1000000 / 1000000.
Riverlane Silver : 77 / 9 / 2000000.
CRM : 1 Account / 2 Contacts / 1 Opportunity.

Ces volumes ont été obtenus sur macOS puis retrouvés à l'identique sur
un second poste Windows le 13/11/2026 (voir preuves/windows/).
Les identifiants techniques Airbyte peuvent changer lors d'une nouvelle
ingestion.

## Limites

Les connexions ne sont pas restaurées par un export automatique : elles
sont recréées manuellement. Toutes les propriétés nécessaires (URL des
File Sources, globs des S3 Sources, path format des destinations S3,
paramètres MySQL et PostgreSQL, modes de synchronisation) sont relevées
dans preuves/airbyte/config_summary.md, section 4 ; seuls les secrets
sont à créer localement.

La procédure a été exécutée sur macOS et sur Windows ; Linux reste
documenté sans validation expérimentale.
