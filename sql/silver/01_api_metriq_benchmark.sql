CREATE SCHEMA IF NOT EXISTS silver;

DROP TABLE IF EXISTS silver.api_metriq_benchmark;

CREATE TABLE silver.api_metriq_benchmark AS
WITH base AS (
    SELECT
        -- Airbyte provenance: MinIO -> PostgreSQL
        b._airbyte_raw_id AS bronze_airbyte_raw_id,
        b._airbyte_extracted_at AS ingested_at_utc,

        -- MinIO RAW provenance
        b._ab_source_file_url AS source_file_url,
        NULLIF(b._ab_source_file_last_modified, '')::timestamptz
            AS source_file_last_modified,

        -- Airbyte provenance: API -> MinIO
        b.data ->> '_airbyte_raw_id' AS source_airbyte_raw_id,

        CASE
            WHEN b.data ? '_airbyte_extracted_at'
            THEN to_timestamp(
                (b.data ->> '_airbyte_extracted_at')::double precision / 1000.0
            )
        END AS api_extracted_at_utc,

        -- Actual Metriq source record
        b.data -> '_airbyte_data' AS src

    FROM bronze.api_metriq_benchmark AS b
),

ranked AS (
    SELECT
        -- Stable logical identifier for the current source contract
        concat_ws(
            '|',
            src ->> 'device',
            src ->> 'job_type',
            src ->> 'timestamp'
        ) AS source_record_id,

        src ->> 'provider'    AS provider,
        src ->> 'device'      AS device,
        src ->> 'job_type'    AS job_type,
        src ->> 'app_version' AS app_version,
        src ->> 'suite_id'    AS suite_id,

        -- Preserve source representation because it contains no timezone
        src ->> 'timestamp' AS source_timestamp_text,

        -- Typed timestamp WITHOUT timezone: no UTC assumption
        (src ->> 'timestamp')::timestamp without time zone
            AS benchmark_timestamp,

        -- Sparse fields: preserve NULL when absent
        src ->> 'outcome'        AS outcome,
        src ->> 'outcome_detail' AS outcome_detail,

        -- Benchmark-dependent structures: preserve as JSONB
        src -> 'params'                  AS params,
        src -> 'results'                 AS results,
        src -> 'device_metadata'         AS device_metadata,
        src -> 'errors'                  AS errors,
        src -> 'directions'              AS directions,
        src -> 'metriq_score'            AS metriq_score,
        src -> 'normalization_baselines' AS normalization_baselines,
        src -> 'normalized_scores'       AS normalized_scores,

        'metriq'::text AS source_system,

        source_airbyte_raw_id,
        bronze_airbyte_raw_id,
        source_file_url,
        source_file_last_modified,
        api_extracted_at_utc,
        ingested_at_utc,

        ROW_NUMBER() OVER (
            PARTITION BY
                src ->> 'device',
                src ->> 'job_type',
                src ->> 'timestamp'
            ORDER BY
                ingested_at_utc DESC,
                bronze_airbyte_raw_id DESC
        ) AS rn

    FROM base
)

SELECT
    source_record_id,
    provider,
    device,
    job_type,
    app_version,
    suite_id,

    source_timestamp_text,
    benchmark_timestamp,

    outcome,
    outcome_detail,

    params,
    results,
    device_metadata,
    errors,
    directions,
    metriq_score,
    normalization_baselines,
    normalized_scores,

    source_system,

    source_airbyte_raw_id,
    bronze_airbyte_raw_id,
    source_file_url,
    source_file_last_modified,
    api_extracted_at_utc,
    ingested_at_utc

FROM ranked
WHERE rn = 1;

ALTER TABLE silver.api_metriq_benchmark
    ADD CONSTRAINT api_metriq_benchmark_pkey
    PRIMARY KEY (source_record_id);
