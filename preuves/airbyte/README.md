# Airbyte evidence

This directory contains sanitised Airbyte evidence.

## Configuration

`config_summary.md` documents the configuration without credentials.

## Screenshots

- `01_connections_overview.png`
  - workspace overview: 9 healthy connections, 8 of which belong to this project;
    the 9th (Aiven, from an earlier lab) is out of scope and is cropped out of
    Figure 3 in the report

- `02_metriq_api_to_minio_status.png`
  - Metriq API -> MinIO
  - 413 records loaded

- `03_metriq_api_to_minio_schema.png`
  - Metriq API stream
  - Full Refresh | Append

- `04_metriq_minio_to_bronze_status.png`
  - MinIO -> PostgreSQL Bronze
  - 413 Metriq records loaded

- `05_riverlane_file_to_minio_d23_status.png`
  - Riverlane d23 File Source -> MinIO
  - 1,000,000 records loaded

- `06_riverlane_minio_to_bronze_schema.png`
  - four Riverlane streams
  - Full Refresh | Overwrite

- `07_riverlane_minio_to_bronze_status.png`
  - Riverlane Bronze counts:
    77 / 9 / 1,000,000 / 1,000,000

- `08_crm_to_bronze_status.png`
  - EspoCRM/MariaDB -> PostgreSQL Bronze
  - account=1 / contact=2 / opportunity=1

No screenshot contains passwords, access keys, tokens or client secrets.
