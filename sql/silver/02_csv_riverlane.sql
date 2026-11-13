BEGIN;

CREATE SCHEMA IF NOT EXISTS silver;

-- ============================================================
-- 1. FPGA ACCURACY
-- Grain: one decoder accuracy experiment
-- ============================================================

DROP TABLE IF EXISTS silver.riverlane_fpga_accuracy;

CREATE TABLE silver.riverlane_fpga_accuracy AS
WITH base AS (
    SELECT
        data -> '_airbyte_data' AS src,
        data ->> '_airbyte_raw_id' AS source_airbyte_raw_id,

        CASE
            WHEN data ->> '_airbyte_extracted_at' IS NOT NULL
            THEN to_timestamp(
                (data ->> '_airbyte_extracted_at')::double precision / 1000.0
            )
        END AS csv_extracted_at_utc,

        _airbyte_raw_id AS bronze_airbyte_raw_id,
        _airbyte_extracted_at AS ingested_at_utc,
        _ab_source_file_url AS source_file_url,

        CASE
            WHEN NULLIF(_ab_source_file_last_modified, '') IS NOT NULL
            THEN _ab_source_file_last_modified::timestamptz
        END AS source_file_last_modified

    FROM bronze.riverlane_fpga_accuracy
)

SELECT
    concat(
        'riverlane_fpga_accuracy|',
        src ->> 'Unnamed: 0'
    ) AS source_record_id,

    (src ->> 'Unnamed: 0')::integer AS source_index,
    src ->> 'experiment_name' AS experiment_name,

    (src ->> 'd_h')::integer AS d_h,
    (src ->> 'd_v')::integer AS d_v,
    (src ->> 'rounds')::integer AS rounds,

    (src ->> 'p_physical')::numeric AS p_physical,

    (src ->> 'shots')::bigint AS shots,
    (src ->> 'fails')::bigint AS fails,

    (src ->> 'LER%')::numeric AS ler_percent,

    (src ->> 'gg_init')::numeric AS gg_init,
    (src ->> 'gg_grow')::numeric AS gg_grow,
    (src ->> 'gg_merge')::numeric AS gg_merge,
    (src ->> 'gg_match')::numeric AS gg_match,
    (src ->> 'gg_union')::numeric AS gg_union,

    src ->> 'hooks' AS hooks_status,

    (src ->> 'total_cycles')::numeric AS total_cycles,
    (src ->> 'time_per_round')::numeric AS time_per_round,

    (src ->> 'distance')::integer AS distance,
    (src ->> 'logical_error_rate')::numeric AS logical_error_rate,

    'riverlane'::text AS source_system,
    'fpga_accuracy_data.csv'::text AS source_dataset_file,

    source_airbyte_raw_id,
    bronze_airbyte_raw_id,
    source_file_url,
    source_file_last_modified,
    csv_extracted_at_utc,
    ingested_at_utc

FROM base;

ALTER TABLE silver.riverlane_fpga_accuracy
ADD CONSTRAINT riverlane_fpga_accuracy_pkey
PRIMARY KEY (source_record_id);


-- ============================================================
-- 2. FPGA MEMORY
-- Grain: one memory measurement per code distance
-- ============================================================

DROP TABLE IF EXISTS silver.riverlane_fpga_memory;

CREATE TABLE silver.riverlane_fpga_memory AS
WITH base AS (
    SELECT
        data -> '_airbyte_data' AS src,
        data ->> '_airbyte_raw_id' AS source_airbyte_raw_id,

        CASE
            WHEN data ->> '_airbyte_extracted_at' IS NOT NULL
            THEN to_timestamp(
                (data ->> '_airbyte_extracted_at')::double precision / 1000.0
            )
        END AS csv_extracted_at_utc,

        _airbyte_raw_id AS bronze_airbyte_raw_id,
        _airbyte_extracted_at AS ingested_at_utc,
        _ab_source_file_url AS source_file_url,

        CASE
            WHEN NULLIF(_ab_source_file_last_modified, '') IS NOT NULL
            THEN _ab_source_file_last_modified::timestamptz
        END AS source_file_last_modified

    FROM bronze.riverlane_fpga_memory
)

SELECT
    concat(
        'riverlane_fpga_memory|',
        src ->> 'distance'
    ) AS source_record_id,

    (src ->> 'distance')::integer AS distance,

    (src ->> 'Cluster stack')::numeric AS cluster_stack,
    (src ->> 'Parent table')::numeric AS parent_table,
    (src ->> 'Merge stack')::numeric AS merge_stack,

    'riverlane'::text AS source_system,
    'fpga_memory_data.csv'::text AS source_dataset_file,

    source_airbyte_raw_id,
    bronze_airbyte_raw_id,
    source_file_url,
    source_file_last_modified,
    csv_extracted_at_utc,
    ingested_at_utc

FROM base;

ALTER TABLE silver.riverlane_fpga_memory
ADD CONSTRAINT riverlane_fpga_memory_pkey
PRIMARY KEY (source_record_id);


-- ============================================================
-- 3. SYNDROME OBSERVATIONS
--
-- Grain: one sampled syndrome observation.
--
-- Repeated scientific values are VALID observations.
-- No DISTINCT and no aggregation.
--
-- source_airbyte_raw_id is retained for provenance.
-- source_record_id is a deterministic logical surrogate.
-- ============================================================

DROP TABLE IF EXISTS silver.riverlane_syndrome_observation;

CREATE TABLE silver.riverlane_syndrome_observation AS
WITH unioned AS (

    SELECT
        'riverlane_syndrome_d21'::text AS source_stream,
        'noise_rate_sampling_full_d21.csv'::text AS source_dataset_file,

        data -> '_airbyte_data' AS src,
        data ->> '_airbyte_raw_id' AS source_airbyte_raw_id,

        CASE
            WHEN data ->> '_airbyte_extracted_at' IS NOT NULL
            THEN to_timestamp(
                (data ->> '_airbyte_extracted_at')::double precision / 1000.0
            )
        END AS csv_extracted_at_utc,

        _airbyte_raw_id AS bronze_airbyte_raw_id,
        _airbyte_extracted_at AS ingested_at_utc,
        _ab_source_file_url AS source_file_url,

        CASE
            WHEN NULLIF(_ab_source_file_last_modified, '') IS NOT NULL
            THEN _ab_source_file_last_modified::timestamptz
        END AS source_file_last_modified

    FROM bronze.riverlane_syndrome_d21

    UNION ALL

    SELECT
        'riverlane_syndrome_d23',
        'noise_rate_sampling_full_d23.csv',

        data -> '_airbyte_data',
        data ->> '_airbyte_raw_id',

        CASE
            WHEN data ->> '_airbyte_extracted_at' IS NOT NULL
            THEN to_timestamp(
                (data ->> '_airbyte_extracted_at')::double precision / 1000.0
            )
        END,

        _airbyte_raw_id,
        _airbyte_extracted_at,
        _ab_source_file_url,

        CASE
            WHEN NULLIF(_ab_source_file_last_modified, '') IS NOT NULL
            THEN _ab_source_file_last_modified::timestamptz
        END

    FROM bronze.riverlane_syndrome_d23
),

numbered AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY
                source_stream,
                src ->> 'code',
                src ->> 'distance',
                src ->> 'noise_type',
                src ->> 'noise_rate',
                src ->> 'syndrome_weight'
            ORDER BY source_airbyte_raw_id
        ) AS occurrence_number
    FROM unioned
)

SELECT
    concat_ws(
        '|',
        source_stream,
        src ->> 'code',
        src ->> 'distance',
        src ->> 'noise_type',
        src ->> 'noise_rate',
        src ->> 'syndrome_weight',
        occurrence_number::text
    ) AS source_record_id,

    src ->> 'code' AS code,
    (src ->> 'distance')::integer AS distance,
    src ->> 'noise_type' AS noise_type,
    (src ->> 'noise_rate')::numeric AS noise_rate,
    (src ->> 'syndrome_weight')::integer AS syndrome_weight,

    occurrence_number,

    'riverlane'::text AS source_system,
    source_stream,
    source_dataset_file,

    source_airbyte_raw_id,
    bronze_airbyte_raw_id,
    source_file_url,
    source_file_last_modified,
    csv_extracted_at_utc,
    ingested_at_utc

FROM numbered;

ALTER TABLE silver.riverlane_syndrome_observation
ADD CONSTRAINT riverlane_syndrome_observation_pkey
PRIMARY KEY (source_record_id);

COMMIT;
