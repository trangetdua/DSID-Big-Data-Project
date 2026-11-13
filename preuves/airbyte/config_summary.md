# Airbyte — configuration sanitised summary

This file documents the Airbyte configuration used by the project without
including passwords, access keys, client secrets or authentication tokens.

## Runtime

- Airbyte application: 2.4.0
- Airbyte Helm chart: 2.4.0
- abctl: v0.30.4
- Local UI: http://localhost:8000
- Deployment: Kubernetes-in-Docker via abctl
- Docker Compose services are reached from Airbyte through
  `host.docker.internal` on macOS.

---

## 1. Metriq API pipeline

### Source

Public API:

`https://unitaryfoundation.github.io/metriq-data/benchmark.latest.json`

Configuration:

- HTTP method: GET
- authentication: none
- pagination: none
- stream: `api_metriq_benchmark`
- source snapshot observed: 413 records

### Hop 1 — API to MinIO

Destination:

- S3-compatible storage: MinIO
- bucket: `dsid-raw`
- prefix: `raw/api/metriq`
- format: JSON Lines
- no flattening
- no compression

### Hop 2 — MinIO to PostgreSQL

- Airbyte S3 Source
- destination: PostgreSQL
- destination schema: `bronze`
- Bronze table: `bronze.api_metriq_benchmark`
- sync mode: Incremental | Append (cursor: `_ab_source_file_last_modified`)
- observed rows: 413

---

## 2. Riverlane CSV pipeline

Four CSV sources are ingested:

- `fpga_accuracy_data.csv`
- `fpga_memory_data.csv`
- `noise_rate_sampling_full_d21.csv`
- `noise_rate_sampling_full_d23.csv`

Airbyte File Sources use the public HTTPS files and reader option:

`{"dtype":"string"}`

Streams:

- `riverlane_fpga_accuracy`
- `riverlane_fpga_memory`
- `riverlane_syndrome_d21`
- `riverlane_syndrome_d23`

### Hop 1 — File Source to MinIO

Destination:

- MinIO
- bucket: `dsid-raw`
- prefix: `raw/csv/riverlane/airbyte`
- format: JSON Lines
- sync mode: Full Refresh | Overwrite

Observed loaded records:

- accuracy: 77
- memory: 9
- d21: 1,000,000
- d23: 1,000,000

The original source files are preserved separately under:

`raw/csv/riverlane/original/extraction_date=2026-11-09/`

This original zone is not the Airbyte overwrite target.

### Hop 2 — MinIO to PostgreSQL

- source: Airbyte S3 Source
- S3 Source connector used: 4.16.1
- destination: PostgreSQL
- destination schema: `bronze`
- sync mode: Full Refresh | Overwrite

Bronze streams:

- `bronze.riverlane_fpga_accuracy`
- `bronze.riverlane_fpga_memory`
- `bronze.riverlane_syndrome_d21`
- `bronze.riverlane_syndrome_d23`

Replay verification confirms that rerunning both Airbyte hops does not
additively accumulate business rows.

---

## 3. EspoCRM pipeline

Source system:

EspoCRM -> MariaDB

Airbyte reads MariaDB through a dedicated read-only account.

Selected streams:

- `account`
- `contact`
- `opportunity`

Pipeline:

MariaDB -> Airbyte MySQL Source -> PostgreSQL `bronze`

Sync mode:

Full Refresh | Overwrite

Observed Bronze rows:

- account: 1
- contact: 2
- opportunity: 1

The Airbyte MariaDB account was functionally verified:

- SELECT: allowed
- CREATE: denied

No credential value is included in this submission.

---

## 4. Propriétés détaillées des connecteurs (relevé de l'interface Airbyte, macOS)

Valeurs relevées dans les écrans Settings des sources, destinations et
connexions Airbyte. Les champs secrets (mots de passe, clés d'accès) sont
volontairement omis. Les hôtes et ports sont ceux du Compose du projet,
joints depuis Airbyte via `host.docker.internal`.

### 4.1 Sources

| Source | Connecteur / version | Propriétés |
|---|---|---|
| Metriq API Source | Déclaratif personnalisé « Metriq Benchmarks » (Connector Builder, manifeste 7.28.2) | `GET https://unitaryfoundation.github.io/metriq-data/benchmark.latest.json` ; en-tête `Accept: application/json` ; décodeur JSON ; extracteur `DpathExtractor` avec `field_path: []` (la réponse est la liste des enregistrements) ; aucun paginator ; aucune authentification ; schéma inline. Manifeste complet : `airbyte/manifests/metriq.yaml`. |
| Riverlane FPGA Accuracy | File v0.6.0 | Format `csv` ; fournisseur `HTTPS: Public Web` ; URL `https://zenodo.org/records/11621878/files/fpga_accuracy_data.csv?download=1` ; reader options `{"dtype":"string"}`. |
| Riverlane FPGA Memory | File v0.6.0 | Format `csv` ; `HTTPS: Public Web` ; URL `https://zenodo.org/records/11621878/files/fpga_memory_data.csv?download=1` ; reader options `{"dtype":"string"}`. |
| Riverlane Syndrome d21 | File v0.6.0 | Format `csv` ; `HTTPS: Public Web` ; URL `https://zenodo.org/records/11621878/files/noise_rate_sampling_full_d21.csv?download=1` ; reader options `{"dtype":"string"}`. |
| Riverlane Syndrome d23 | File v0.6.0 | Format `csv` ; `HTTPS: Public Web` ; URL `https://zenodo.org/records/11621878/files/noise_rate_sampling_full_d23.csv?download=1` ; reader options `{"dtype":"string"}`. |
| MinIO RAW Source (Metriq) | S3 v4.16.1 | Authentification IAM User (clés omises) ; bucket `dsid-raw` ; endpoint MinIO `http://host.docker.internal:9000` ; delivery method `Replicate Records`. Stream `api_metriq_benchmark` : format JSONL, glob `raw/api/metriq/extraction_date=*/api_metriq_benchmark/*.jsonl`, schemaless `true`, validation policy `Emit Record`, days to sync if history is full `3`. |
| MinIO Riverlane RAW Source | S3 v4.16.1 | Mêmes réglages d'accès (bucket `dsid-raw`, endpoint MinIO, `Replicate Records`). Quatre streams JSONL, schemaless, `Emit Record`, globs : `raw/csv/riverlane/airbyte/extraction_date=*/riverlane_fpga_accuracy/*.jsonl`, `…/riverlane_fpga_memory/*.jsonl`, `…/riverlane_syndrome_d21/*.jsonl`, `…/riverlane_syndrome_d23/*.jsonl`. |
| EspoCRM MariaDB | MySQL v3.53.5 | Hôte `host.docker.internal`, port `3306`, base `espocrm`, utilisateur `airbyte` (lecture seule, mot de passe omis) ; encryption `preferred` ; SSH tunnel `No Tunnel` ; update method `Scan Changes with User Defined Cursor` (pas de CDC). Les connexions utilisent néanmoins Full Refresh \| Overwrite (voir 4.3). |

### 4.2 Destinations

| Destination | Connecteur / version | Propriétés |
|---|---|---|
| MinIO RAW (Metriq) | S3 | Bucket `dsid-raw` ; préfixe `raw/api/metriq` ; région `us-east-1` (valeur requise par le connecteur, sans effet sur MinIO) ; endpoint `http://host.docker.internal:9000` ; format JSON Lines ; no compression ; no flattening ; path format `extraction_date=${YEAR}-${MONTH}-${DAY}/${STREAM_NAME}/${YEAR}_${MONTH}_${DAY}_${EPOCH}_`. |
| MinIO Riverlane RAW | S3 v1.9.10 | Bucket `dsid-raw` ; préfixe `raw/csv/riverlane/airbyte` ; mêmes région, endpoint, format JSON Lines, no compression et path format que ci-dessus. |
| PostgreSQL TP | Postgres v3.0.22 | Hôte `host.docker.internal`, port `5432`, base `warehouse`, schéma par défaut `bronze` (mot de passe omis) ; SSL mode `disable` ; SSH tunnel `No Tunnel` ; CDC deletion mode `Hard delete`. |

Les préfixes `raw/api/metriq` et `raw/csv/riverlane/airbyte` correspondent
aux clés d'objets observées dans MinIO (rapport, Tableau 5 et
`preuves/csv/replay_hop1_minio_state.txt`).

### 4.3 Connexions

| Connexion | Streams | Mode de synchronisation | Planification |
|---|---|---|---|
| Metriq API Source → MinIO RAW | `api_metriq_benchmark` | Full Refresh \| Append | Manual |
| MinIO RAW Source → PostgreSQL TP | `api_metriq_benchmark` | Incremental \| Append, curseur `_ab_source_file_last_modified` | Manual |
| Riverlane FPGA Accuracy → MinIO Riverlane RAW | `riverlane_fpga_accuracy` | Full Refresh \| Overwrite | Manual |
| Riverlane FPGA Memory → MinIO Riverlane RAW | `riverlane_fpga_memory` | Full Refresh \| Overwrite | Manual |
| Riverlane Syndrome d21 → MinIO Riverlane RAW | `riverlane_syndrome_d21` | Full Refresh \| Overwrite | Manual |
| Riverlane Syndrome d23 → MinIO Riverlane RAW | `riverlane_syndrome_d23` | Full Refresh \| Overwrite | Manual |
| MinIO Riverlane Accuracy → PostgreSQL Bronze | les quatre streams Riverlane | Full Refresh \| Overwrite | Manual |
| EspoCRM MariaDB → PostgreSQL TP | `account`, `contact`, `opportunity` | Full Refresh \| Overwrite | Manual |

Sous Windows, les mêmes propriétés ont été ressaisies ; seuls les noms
d'affichage de certaines connexions diffèrent (par exemple « PostgreSQL
Bronze » au lieu de « PostgreSQL TP »).

---

## Security

The submission intentionally excludes:

- `.env`
- Airbyte login credentials
- MariaDB passwords
- PostgreSQL passwords
- MinIO secret keys
- MinIO access credentials

Screenshots included in `preuves/airbyte/screenshots/` must not display
real passwords, secret keys, tokens or client secrets.
