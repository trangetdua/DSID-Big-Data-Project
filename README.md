# Projet Big Data — M1 MIAGE 2026–2027

Ce projet met en œuvre une chaîne locale d’ingestion, de stockage et de préparation de données provenant de trois types de sources :

1. une API publique ;
2. un jeu de fichiers CSV scientifiques ;
3. une application CRM EspoCRM.

L’objectif est de construire des flux reproductibles jusqu’à une zone PostgreSQL `bronze`, puis de produire des tables `silver` typées, dédupliquées lorsque cela est nécessaire, traçables et contrôlées par des tests SQL versionnés.

---

## 1. Architecture générale

```text
                         ┌──────────────────────┐
                         │   Sources externes   │
                         └──────────┬───────────┘
                                    │
          ┌─────────────────────────┼────────────────────────┐
          │                         │                        │
          ▼                         ▼                        ▼
   API publique              CSV Riverlane              EspoCRM
      Metriq                  / Zenodo                  / MariaDB
          │                         │                        │
          ▼                         ▼                        ▼
       Airbyte              Airbyte File Source       Airbyte MySQL
          │                         │                        │
          ▼                         ▼                        │
        MinIO                     MinIO                      │
     RAW API              RAW Airbyte JSONL                 │
                                    │                        │
                                    ▼                        │
                            Airbyte S3 Source                │
          │                         │                        │
          └───────────────┬─────────┴────────────────────────┘
                          ▼
                PostgreSQL — schema bronze
                          │
                          ▼
                   SQL versionné
                          │
                          ▼
                PostgreSQL — schema silver
                          │
                          ▼
                     Tests SQL
```

Les trois sources restent indépendantes. Aucune jointure métier entre Metriq, Riverlane et EspoCRM n’est imposée dans ce projet.

---

## 2. Stack technique

La stack locale utilisée et validée est la suivante :

| Composant | Version / image |
|---|---|
| PostgreSQL | 18.6 |
| MariaDB | 11.8.9 |
| EspoCRM | 10.0.8 |
| Adminer | 6.1.0 |
| Airbyte | 2.4.0 |
| `abctl` | v0.30.4 |
| MinIO | build local depuis `RELEASE.2025-10-15T17-29-55Z` |

MinIO est compilé depuis les sources avec :

```text
github.com/minio/minio@RELEASE.2025-10-15T17-29-55Z
```

Le binaire compilé localement affiche `DEVELOPMENT.GOGET` lors de `minio --version`. La provenance exacte du build est conservée dans :

```text
Dockerfile.minio
preuves/system/minio_build_provenance.txt
```

---

## 3. Ports locaux

| Service | Adresse locale |
|---|---|
| Airbyte | `http://localhost:8000` |
| EspoCRM | `http://localhost:8081` |
| Adminer | `http://localhost:8082` |
| MinIO API | `http://localhost:9000` |
| MinIO Console | `http://localhost:9001` |
| PostgreSQL | `localhost:5432` |
| MariaDB | `localhost:3306` |

La liste exacte des conteneurs, images, versions, états et ports est conservée dans :

```text
preuves/system/versions_ports.txt
```

---

## 4. Prérequis

Le projet nécessite principalement :

- Docker Desktop ou Docker Engine ;
- Docker Compose v2 ;
- `abctl` pour Airbyte ;
- une connexion Internet lors du premier téléchargement ou build des composants ;
- des ressources suffisantes pour exécuter Airbyte et la stack Docker simultanément.

Sur macOS et Windows, les connecteurs Airbyte utilisent `host.docker.internal` pour joindre les services exposés par Docker Compose.

---

## 5. Configuration des variables d’environnement

Créer le fichier local `.env` à partir du modèle :

```bash
cp .env.example .env
```

Puis remplacer les valeurs `change_me_*` par des secrets locaux.

Le fichier `.env` ne doit jamais être versionné ou remis dans le dossier de rendu.

Le dépôt contient uniquement :

```text
.env.example
```

Le fichier `.gitignore` exclut notamment :

```text
.env
.DS_Store
*.log
```

---

## 6. Démarrage de la stack Docker

Depuis la racine du projet :

```bash
docker version
docker compose version

docker compose build minio
docker compose up -d
docker compose ps
```

Les services attendus sont :

```text
dsid-postgres
dsid-mariadb
dsid-minio
dsid-adminer
dsid-espocrm
dsid-espocrm-daemon
```

Ne pas utiliser :

```bash
docker compose down -v
```

car l’option `-v` supprime les volumes persistants et donc les données locales.

Pour arrêter temporairement les services :

```bash
docker compose stop
```

---

## 7. Airbyte

Airbyte est installé séparément de Docker Compose avec `abctl`.

Installation initiale :

```bash
abctl version
abctl local install
```

Vérification d’une installation existante :

```bash
abctl local status
```

L’interface est ensuite disponible sur :

```text
http://localhost:8000
```

Dans les connecteurs Airbyte utilisés sur macOS et sur Windows, les services Docker Compose sont adressés via :

```text
host.docker.internal
```

Exemples :

```text
PostgreSQL : host.docker.internal:5432
MariaDB    : host.docker.internal:3306
MinIO      : host.docker.internal:9000
```

Les mots de passe ou credentials Airbyte réels ne sont pas inclus dans ce rendu.

Configuration des sources, destinations et connexions :

1. importer `airbyte/manifests/metriq.yaml` dans le Connector Builder ;
2. créer les connexions dans l'ordre décrit par `airbyte/REPRISE_AIRBYTE.md` ;
3. reprendre les propriétés de chaque connecteur (URL, globs, path format,
   modes de synchronisation) dans `preuves/airbyte/config_summary.md`,
   section 4. Seuls les secrets sont à créer localement.

---

# 8. Flux API — Metriq

## 8.1 Source

La source est le dataset public Metriq de la Unitary Foundation :

```text
https://unitaryfoundation.github.io/metriq-data/benchmark.latest.json
```

Caractéristiques retenues :

```text
Méthode             GET
Authentification    aucune
Pagination          aucune
Grain logique       une mesure de benchmark
Clé logique         device + job_type + timestamp
```

Le snapshot étudié contient :

```text
413 enregistrements RAW
408 clés logiques uniques
5 observations excédentaires dues à des doublons exacts
```

Les valeurs sources sont préservées dans Bronze, y compris les anomalies observées dans la source.

---

## 8.2 Pipeline API

```text
Metriq API
    ↓
Airbyte HTTP / declarative source
    ↓
MinIO
raw/api/metriq/
    ↓
Airbyte S3 Source
    ↓
PostgreSQL
bronze.api_metriq_benchmark
    ↓
sql/silver/01_api_metriq_benchmark.sql
    ↓
silver.api_metriq_benchmark
```

Le lot RAW est décrit par `data/manifestes/metriq/manifest.json` : clé
objet MinIO, 336 196 octets, 413 enregistrements et SHA-256
`1561758954077096464acf2bdb671588c95b99858b98f5e71fd38e59d29e4f97`.
Ce manifeste a été établi a posteriori à partir de l'objet conservé dans
MinIO.

La table Silver contient :

```text
408 lignes
```

Le dédoublonnage est déterministe sur :

```text
device
job_type
timestamp
```

Les informations de provenance Airbyte sont conservées dans Silver.

---

## 8.3 Tests API

Les tests sont définis dans :

```text
sql/tests/test_api_metriq_benchmark.sql
```

Les contrôles couvrent notamment :

- clé non nulle ;
- unicité ;
- quantification des doublons ;
- noms de colonnes en `snake_case` ;
- types PostgreSQL ;
- réconciliation Bronze → Silver ;
- traçabilité ;
- règle spécifique à la source.

Résultat :

```text
8/8 contrôles PASS
```

Preuve :

```text
preuves/api/silver_tests_metriq.txt
```

Le flux API utilise un comportement d’ingestion différent du flux CSV. Il ne doit pas être relancé aveuglément en supposant les mêmes propriétés d’overwrite que Riverlane.

---

# 9. Flux CSV — Riverlane

## 9.1 Source scientifique

Dataset :

```text
Data supporting
“A real-time, scalable, fast and resource-efficient decoder
for a quantum computer”
```

Repository :

```text
Zenodo
DOI : 10.5281/zenodo.11621878
```

Licence vérifiée :

```text
Creative Commons Attribution 4.0 International
SPDX : CC-BY-4.0
```

Les métadonnées de licence et leurs sources de vérification sont documentées dans :

```text
data/manifestes/riverlane/manifest.json
preuves/csv/manifest_license_verification.txt
```

---

## 9.2 Fichiers utilisés

Quatre fichiers CSV sont ingérés :

```text
fpga_accuracy_data.csv
fpga_memory_data.csv
noise_rate_sampling_full_d21.csv
noise_rate_sampling_full_d23.csv
```

Un fichier supplémentaire est conservé pour la provenance mais n’est pas ingéré dans Bronze :

```text
stim_circuits.zip
```

Volumes de données CSV :

```text
fpga_accuracy_data.csv              77 lignes
fpga_memory_data.csv                 9 lignes
noise_rate_sampling_full_d21.csv     1 000 000 lignes
noise_rate_sampling_full_d23.csv     1 000 000 lignes
```

Total :

```text
2 000 086 lignes
```

---

## 9.3 Conservation RAW originale

Les fichiers téléchargés sont conservés byte-identiquement dans MinIO avant la sérialisation Airbyte :

```text
dsid-raw/
└── raw/
    └── csv/
        └── riverlane/
            └── original/
                └── extraction_date=2026-11-09/
                    ├── fpga_accuracy_data.csv
                    ├── fpga_memory_data.csv
                    ├── noise_rate_sampling_full_d21.csv
                    ├── noise_rate_sampling_full_d23.csv
                    ├── stim_circuits.zip
                    └── manifest.json
```

Le manifeste contient notamment :

- nom du dataset ;
- DOI ;
- date de récupération ;
- nom de chaque fichier ;
- taille exacte ;
- SHA-256 ;
- encodage ;
- séparateur CSV ;
- objet MinIO associé ;
- rôle du fichier ;
- licence.

Une vérification par re-téléchargement depuis MinIO a confirmé que les fichiers conservés sont byte-identiques aux originaux.

Preuve :

```text
preuves/csv/raw_original_verification.txt
```

---

## 9.4 Pipeline CSV obligatoire

Le flux utilisé est :

```text
CSV public
    ↓
Airbyte File Source
    ↓
MinIO S3 Destination
    ↓
JSON Lines Airbyte
    ↓
Airbyte S3 Source
    ↓
PostgreSQL Bronze
    ↓
SQL Silver
```

Les objets Airbyte courants sont stockés sous :

```text
raw/csv/riverlane/airbyte/
```

Cette zone est distincte de :

```text
raw/csv/riverlane/original/
```

La première représente la sortie technique Airbyte courante.

La seconde conserve les fichiers source originaux et leur intégrité.

---

## 9.5 Bronze Riverlane

Les tables Bronze sont :

```text
bronze.riverlane_fpga_accuracy
bronze.riverlane_fpga_memory
bronze.riverlane_syndrome_d21
bronze.riverlane_syndrome_d23
```

Comptages :

```text
riverlane_fpga_accuracy       77
riverlane_fpga_memory          9
riverlane_syndrome_d21   1 000 000
riverlane_syndrome_d23   1 000 000
```

Les observations répétées des fichiers syndrome ne sont pas automatiquement considérées comme des erreurs : elles représentent des répétitions expérimentales valides.

---

## 9.6 Silver Riverlane

Transformation :

```text
sql/silver/02_csv_riverlane.sql
```

Tables produites :

```text
silver.riverlane_fpga_accuracy
silver.riverlane_fpga_memory
silver.riverlane_syndrome_observation
```

Comptages :

```text
riverlane_fpga_accuracy             77
riverlane_fpga_memory                9
riverlane_syndrome_observation   2 000 000
```

Les 2 millions d’observations syndrome sont conservées.

Pour permettre une clé logique unique sans supprimer les répétitions scientifiques, la table Silver utilise un numéro d’occurrence déterministe au sein de chaque combinaison de valeurs source.

Les identifiants techniques Airbyte sont conservés séparément pour la traçabilité mais ne sont pas considérés comme des identifiants métier immuables.

---

## 9.7 Tests Riverlane

Tests :

```text
sql/tests/test_csv_riverlane.sql
```

Les contrôles couvrent :

1. clés non nulles ;
2. unicité ;
3. réconciliation Bronze → Silver ;
4. `snake_case` ;
5. types PostgreSQL ;
6. provenance ;
7. conservation exacte des multiplicités scientifiques ;
8. règles spécifiques au protocole expérimental ;
9. quantification des observations répétées.

Résultats principaux :

```text
Accuracy                  77 / PASS
Memory                     9 / PASS
Syndrome            2 000 000 / PASS

Combinaisons syndrome      2 855
Mismatch de multiplicité       0

Groupes expérimentaux         20
Taille attendue/groupe   100 000
Groupes incorrects             0
```

Les répétitions mesurées dans Bronze sont :

```text
d21 : 998 660 observations répétées
d23 : 998 485 observations répétées
```

Preuves :

```text
preuves/csv/silver_tests_riverlane.txt
preuves/csv/replay_silver_tests.txt
```

---

# 10. Replay et idempotence du pipeline Riverlane

Le flux Riverlane a été rejoué volontairement afin de vérifier le comportement d’un rechargement complet.

Stratégie :

```text
Airbyte File Source → MinIO
Full Refresh | Overwrite

Airbyte S3 Source → PostgreSQL Bronze
Full Refresh | Overwrite

Silver
DROP / CREATE déterministe depuis SQL versionné
```

Avant replay :

```text
CSV source
77 / 9 / 1 000 000 / 1 000 000

Bronze
77 / 9 / 1 000 000 / 1 000 000

Silver
77 / 9 / 2 000 000
```

Après replay du premier hop, MinIO contient toujours :

```text
Accuracy      77 lignes JSONL
Memory         9 lignes JSONL
d21       1 000 000 lignes JSONL
d23       1 000 000 lignes JSONL
```

Les deux gros streams syndrome sont physiquement répartis sur deux objets de 500 000 lignes chacun. Ce découpage correspond au chunking de sortie et non à une duplication.

Après replay du second hop, Bronze contient toujours :

```text
77
9
1 000 000
1 000 000
```

Après reconstruction Silver :

```text
77
9
2 000 000
```

Les neuf groupes de tests Silver repassent ensuite à `PASS`.

Les preuves complètes sont :

```text
preuves/csv/replay_before.txt
preuves/csv/replay_hop1_minio_state.txt
preuves/csv/replay_hop2_bronze.txt
preuves/csv/replay_silver_rebuild.txt
preuves/csv/replay_silver_tests.txt
```

Cette vérification montre que le rechargement `Full Refresh | Overwrite` du pipeline Riverlane ne provoque pas d’accumulation additive des lignes métier.

Les noms d’objets, timestamps d’extraction et identifiants techniques Airbyte peuvent naturellement changer entre deux exécutions.

---

# 10 bis. Comportement en cas de rejeu d'un lot

| Flux | Hop | Mode | Effet d'un rejeu |
|---|---|---|---|
| Metriq | API → MinIO | Full Refresh \| Append | Ajout : un nouveau lot daté est écrit dans `raw/api/metriq/` ; les lots précédents restent disponibles. |
| Metriq | MinIO → Bronze | Incremental \| Append (curseur `_ab_source_file_last_modified`) | Ajout : seuls les objets RAW nouveaux ou modifiés sont lus ; un lot déjà chargé n'est pas relu. |
| Metriq | Bronze → Silver | SQL `DROP` / `CREATE` | Dédoublonnage : une ligne par (`device`, `job_type`, `timestamp`), la plus récente selon `ingested_at_utc`. |
| Riverlane | File → MinIO et MinIO → Bronze | Full Refresh \| Overwrite | Remplacement : la zone `raw/csv/riverlane/airbyte/` et les tables Bronze sont remplacées ; la zone `original/` n'est jamais écrasée (voir section 10). |
| Riverlane | Bronze → Silver | SQL `DROP` / `CREATE` | Reconstruction à l'identique ; multiplicité des observations conservée. |
| CRM | MariaDB → Bronze | Full Refresh \| Overwrite | Remplacement : le snapshot Bronze reflète l'état courant de MariaDB. |
| CRM | Bronze → Silver | SQL `DROP` / `CREATE` | Une ligne par identifiant source, la version la plus récente selon `modified_at`. |

Les scripts Silver peuvent être exécutés plusieurs fois : chaque table est
supprimée puis recréée à partir de Bronze.

---

# 11. Flux CRM — EspoCRM

## 11.1 Source

EspoCRM fonctionne sur MariaDB.

Le flux est :

```text
EspoCRM
    ↓
MariaDB
    ↓
compte Airbyte read-only
    ↓
Airbyte MySQL Source
    ↓
PostgreSQL Bronze
    ↓
sql/silver/03_crm_espocrm.sql
    ↓
PostgreSQL Silver
```

Les objets métier utilisés sont :

```text
account
contact
opportunity
```

État observé :

```text
account       1
contact       2
opportunity   1
```

Ces mêmes volumes sont observés dans la source MariaDB, Bronze et Silver.

---

## 11.2 Sécurité du compte Airbyte MariaDB

Un utilisateur MariaDB spécifique est utilisé pour Airbyte.

Il possède uniquement un droit de lecture sur la base EspoCRM.

La validation fonctionnelle a confirmé :

```text
SELECT   autorisé
CREATE   refusé
```

Le test de création d’une table retourne une erreur de permission MariaDB, ce qui confirme que l’utilisateur d’ingestion n’a pas de droit d’écriture sur la base CRM.

Les mots de passe ne sont pas inclus dans les preuves remises.

---

## 11.3 Silver CRM

Transformation :

```text
sql/silver/03_crm_espocrm.sql
```

Tables :

```text
silver.crm_account
silver.crm_contact
silver.crm_opportunity
```

Le dédoublonnage est déterministe sur l’identifiant source, avec priorité à la version la plus récente selon les timestamps disponibles.

`_airbyte_raw_id` n’est utilisé qu’en dernier recours comme tie-breaker technique dans le snapshot Bronze courant.

Il n’est pas considéré comme l’identifiant métier du CRM.

---

## 11.4 Tests CRM

Tests :

```text
sql/tests/test_crm_espocrm.sql
```

Les contrôles incluent :

- clé primaire non nulle ;
- unicité ;
- quantification des versions Bronze ;
- sélection déterministe du gagnant ;
- qualité des identifiants Airbyte ;
- `snake_case` ;
- types PostgreSQL ;
- réconciliation Bronze → Silver ;
- provenance ;
- cohérence des relations CRM ;
- règles métier spécifiques.

Tous les contrôles exécutés sont à `PASS`.

Preuve :

```text
preuves/crm/silver_tests_espocrm.txt
```

Une preuve d’état montre également les mêmes volumes dans :

```text
MariaDB source
PostgreSQL Bronze
PostgreSQL Silver
```

Cette preuve ne prétend pas constituer un véritable snapshot « before / after », car aucun état indépendant antérieur à la création des enregistrements CRM n’avait été capturé.

L’état initial 0/0/0 est toutefois reconstitué a posteriori à partir des tables sources complètes et de leurs horodatages `created_at` : voir `preuves/crm/crm_initial_state_reconstructed.txt`.

Voir :

```text
preuves/crm/crm_delta_after_state.txt
```

---

# 12. Reconstruction des tables Silver

Les transformations Silver sont versionnées dans :

```text
sql/silver/
├── 01_api_metriq_benchmark.sql
├── 02_csv_riverlane.sql
└── 03_crm_espocrm.sql
```

Exécution :

```bash
docker exec -i dsid-postgres \
  psql -X -v ON_ERROR_STOP=1 \
  -U warehouse -d warehouse \
  < sql/silver/01_api_metriq_benchmark.sql
```

```bash
docker exec -i dsid-postgres \
  psql -X -v ON_ERROR_STOP=1 \
  -U warehouse -d warehouse \
  < sql/silver/02_csv_riverlane.sql
```

```bash
docker exec -i dsid-postgres \
  psql -X -v ON_ERROR_STOP=1 \
  -U warehouse -d warehouse \
  < sql/silver/03_crm_espocrm.sql
```

---

# 13. Exécution des tests

API :

```bash
docker exec -i dsid-postgres \
  psql -X -v ON_ERROR_STOP=1 \
  -U warehouse -d warehouse \
  < sql/tests/test_api_metriq_benchmark.sql
```

CSV :

```bash
docker exec -i dsid-postgres \
  psql -X -v ON_ERROR_STOP=1 \
  -U warehouse -d warehouse \
  < sql/tests/test_csv_riverlane.sql
```

CRM :

```bash
docker exec -i dsid-postgres \
  psql -X -v ON_ERROR_STOP=1 \
  -U warehouse -d warehouse \
  < sql/tests/test_crm_espocrm.sql
```

---

# 14. Organisation du dépôt

```text
.
├── .env.example
├── .gitignore
├── compose.yaml
├── Dockerfile.minio
├── README.md
├── README_DOCKER.md
│
├── airbyte/
│   ├── README_AIRBYTE.md
│   ├── REPRISE_AIRBYTE.md
│   └── manifests/
│       └── metriq.yaml
│
├── init/
│   ├── mariadb/
│   │   └── 01_airbyte_user.sh
│   └── postgres/
│       └── 00_schemas.sql
│
├── sql/
│   ├── silver/
│   │   ├── 01_api_metriq_benchmark.sql
│   │   ├── 02_csv_riverlane.sql
│   │   └── 03_crm_espocrm.sql
│   └── tests/
│       ├── test_api_metriq_benchmark.sql
│       ├── test_csv_riverlane.sql
│       └── test_crm_espocrm.sql
│
├── data/manifestes/
│   ├── metriq/
│   │   └── manifest.json
│   └── riverlane/
│       └── manifest.json
│
├── rapport/
│   └── rapport_projet_big_data.pdf
│
└── preuves/
    ├── airbyte/
    ├── api/
    ├── csv/
    ├── crm/
    ├── system/
    └── windows/
```

---

# 15. Traçabilité et preuves

Les sorties de validation ne sont pas seulement décrites dans le rapport : elles sont conservées dans `preuves/`.

Exemples :

```text
preuves/api/silver_tests_metriq.txt

preuves/csv/raw_original_verification.txt
preuves/csv/manifest_license_verification.txt
preuves/csv/replay_before.txt
preuves/csv/replay_hop1_minio_state.txt
preuves/csv/replay_hop2_bronze.txt
preuves/csv/replay_silver_rebuild.txt
preuves/csv/replay_silver_tests.txt
preuves/csv/silver_tests_riverlane.txt

preuves/crm/bronze_profile_crm.txt
preuves/crm/crm_delta_after_state.txt
preuves/crm/crm_initial_state_reconstructed.txt
preuves/crm/silver_tests_espocrm.txt

preuves/system/versions_ports.txt
preuves/system/minio_build_provenance.txt
```

---

# 16. Sécurité et règles de rendu

Le dossier remis ne contient pas :

```text
.env
mot de passe réel
credential Airbyte
secret MinIO
binary local mc
fichiers .DS_Store
fichiers SQL de travail ou backup
```

Les valeurs sensibles restent uniquement dans l’environnement local.

Le compte MariaDB utilisé par Airbyte est en lecture seule.

Les volumes Docker ne doivent pas être supprimés pendant les tests ou avant la collecte des preuves.

---

# 17. Limites connues

Plusieurs points sont volontairement documentés :

- les identifiants techniques Airbyte peuvent changer lors d’un replay ;
- les fichiers JSONL Airbyte ne sont donc pas supposés être byte-identiques entre deux chargements ;
- la conservation byte-identique concerne les fichiers source Riverlane placés dans la zone `original/` ;
- les répétitions scientifiques des données syndrome sont conservées et non supprimées ;
- les timestamps source du CRM sont manipulés selon les types fournis par MariaDB/PostgreSQL et ne reçoivent pas artificiellement une sémantique de fuseau horaire inexistante ;
- sur macOS, l’état initial du CRM n’a pas été capturé avant la saisie : il est reconstitué a posteriori à partir de `created_at` (`preuves/crm/crm_initial_state_reconstructed.txt`) ; lors de la reprise sous Windows, il a été mesuré directement avant saisie (`preuves/windows/crm_initial_state.txt`, 0/0/0 puis 1/2/1) ;
- les connexions Airbyte sont recréées manuellement à partir de la documentation remise, et non restaurées par un export automatique ; Linux reste documenté sans validation expérimentale ;
- aucun croisement analytique entre les trois sources n’est nécessaire au périmètre du projet.

---

# 18. Résumé des résultats

```text
API Metriq
RAW                     413
Silver                  408
Doublons supprimés        5
Tests                  PASS

Riverlane CSV
Bronze            2 000 086
Silver            2 000 086
Replay                  PASS
Tests                   PASS
RAW original SHA-256    PASS

EspoCRM
Account                    1
Contacts                   2
Opportunity                1
Tests                   PASS

Infrastructure
Docker stack             UP
Airbyte                  UP
Secrets dans rendu       NON
```

Le projet fournit ainsi une chaîne complète et vérifiable de collecte, stockage RAW, ingestion Bronze, transformation Silver, contrôle qualité, traçabilité et replay.

## Reconstitution des configurations Airbyte

Consulter `airbyte/REPRISE_AIRBYTE.md` pour l'ordre de reconstruction,
`airbyte/manifests/metriq.yaml` pour le connecteur Metriq et
`preuves/airbyte/config_summary.md` pour les paramètres et les flux
observés. Cette procédure a été suivie avec succès sur un second poste
Windows le 13/11/2026 ; les journaux correspondants sont dans
`preuves/windows/`.
