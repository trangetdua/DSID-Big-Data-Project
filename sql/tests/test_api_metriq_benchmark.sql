\pset pager off

\echo ''
\echo '============================================================'
\echo 'TEST 1 - PRIMARY KEY NOT NULL'
\echo '============================================================'

SELECT
    COUNT(*) AS silver_rows,
    COUNT(*) FILTER (
        WHERE source_record_id IS NULL
    ) AS null_keys,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE source_record_id IS NULL
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM silver.api_metriq_benchmark;


\echo ''
\echo '============================================================'
\echo 'TEST 2 - PRIMARY KEY UNIQUENESS'
\echo '============================================================'

SELECT
    COUNT(*) AS silver_rows,
    COUNT(DISTINCT source_record_id) AS distinct_keys,
    COUNT(*) - COUNT(DISTINCT source_record_id) AS duplicate_keys,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT source_record_id)
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM silver.api_metriq_benchmark;


\echo ''
\echo '============================================================'
\echo 'TEST 3 - DUPLICATES: BRONZE QUANTIFIED / SILVER = 0'
\echo '============================================================'

WITH bronze_stats AS (
    SELECT
        COUNT(*) AS bronze_rows,
        COUNT(DISTINCT data -> '_airbyte_data')
            AS bronze_distinct_source_records
    FROM bronze.api_metriq_benchmark
),
silver_stats AS (
    SELECT
        COUNT(*) AS silver_rows,
        COUNT(DISTINCT (
            device,
            job_type,
            source_timestamp_text
        )) AS silver_distinct_business_keys
    FROM silver.api_metriq_benchmark
)
SELECT
    bronze_rows,
    bronze_distinct_source_records,
    bronze_rows - bronze_distinct_source_records
        AS bronze_exact_duplicate_rows,

    silver_rows,
    silver_rows - silver_distinct_business_keys
        AS silver_duplicate_keys,

    CASE
        WHEN silver_rows - silver_distinct_business_keys = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM bronze_stats
CROSS JOIN silver_stats;


\echo ''
\echo '============================================================'
\echo 'TEST 4 - SNAKE_CASE COLUMN NAMES'
\echo '============================================================'

WITH bad_columns AS (
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'silver'
      AND table_name = 'api_metriq_benchmark'
      AND column_name !~ '^[a-z][a-z0-9_]*$'
)
SELECT
    COUNT(*) AS invalid_column_names,
    COALESCE(
        string_agg(column_name, ', ' ORDER BY column_name),
        'none'
    ) AS invalid_columns,
    CASE
        WHEN COUNT(*) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM bad_columns;


\echo ''
\echo '============================================================'
\echo 'TEST 5 - EXPECTED DATA TYPES'
\echo '============================================================'

WITH expected(column_name, expected_type) AS (
    VALUES
        ('source_record_id',       'text'),
        ('provider',               'text'),
        ('device',                 'text'),
        ('job_type',               'text'),
        ('source_timestamp_text',  'text'),
        ('benchmark_timestamp',    'timestamp without time zone'),
        ('params',                 'jsonb'),
        ('results',                'jsonb'),
        ('source_system',          'text'),
        ('source_file_last_modified', 'timestamp with time zone'),
        ('api_extracted_at_utc',   'timestamp with time zone'),
        ('ingested_at_utc',        'timestamp with time zone')
),
actual AS (
    SELECT column_name, data_type
    FROM information_schema.columns
    WHERE table_schema = 'silver'
      AND table_name = 'api_metriq_benchmark'
),
checks AS (
    SELECT
        e.column_name,
        e.expected_type,
        a.data_type AS actual_type
    FROM expected e
    LEFT JOIN actual a
        USING (column_name)
)
SELECT
    COUNT(*) FILTER (
        WHERE actual_type IS DISTINCT FROM expected_type
    ) AS type_mismatches,

    COALESCE(
        string_agg(
            column_name || ': expected=' || expected_type ||
            ', actual=' || COALESCE(actual_type, '<missing>'),
            '; '
            ORDER BY column_name
        ) FILTER (
            WHERE actual_type IS DISTINCT FROM expected_type
        ),
        'none'
    ) AS mismatch_details,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE actual_type IS DISTINCT FROM expected_type
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM checks;


\echo ''
\echo '============================================================'
\echo 'TEST 6 - BRONZE TO SILVER RECONCILIATION'
\echo '============================================================'

WITH bronze_stats AS (
    SELECT
        COUNT(*) AS bronze_rows,
        COUNT(DISTINCT data -> '_airbyte_data')
            AS bronze_distinct_records
    FROM bronze.api_metriq_benchmark
),
silver_stats AS (
    SELECT COUNT(*) AS silver_rows
    FROM silver.api_metriq_benchmark
)
SELECT
    bronze_rows,
    silver_rows,
    bronze_rows - silver_rows AS rows_removed,
    bronze_rows - bronze_distinct_records
        AS explained_exact_duplicates,

    CASE
        WHEN silver_rows = bronze_distinct_records
         AND bronze_rows - silver_rows
             = bronze_rows - bronze_distinct_records
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM bronze_stats
CROSS JOIN silver_stats;


\echo ''
\echo '============================================================'
\echo 'TEST 7 - TRACEABILITY / PROVENANCE'
\echo '============================================================'

SELECT
    COUNT(*) AS silver_rows,

    COUNT(*) FILTER (
        WHERE source_system IS NULL
           OR source_system <> 'metriq'
    ) AS invalid_source_system,

    COUNT(*) FILTER (
        WHERE source_record_id IS NULL
    ) AS missing_source_record_id,

    COUNT(*) FILTER (
        WHERE source_airbyte_raw_id IS NULL
    ) AS missing_source_airbyte_raw_id,

    COUNT(*) FILTER (
        WHERE bronze_airbyte_raw_id IS NULL
    ) AS missing_bronze_airbyte_raw_id,

    COUNT(*) FILTER (
        WHERE source_file_url IS NULL
    ) AS missing_source_file,

    COUNT(*) FILTER (
        WHERE api_extracted_at_utc IS NULL
    ) AS missing_api_extraction_time,

    COUNT(*) FILTER (
        WHERE ingested_at_utc IS NULL
    ) AS missing_bronze_ingestion_time,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE source_system IS NULL
               OR source_system <> 'metriq'
               OR source_record_id IS NULL
               OR source_airbyte_raw_id IS NULL
               OR bronze_airbyte_raw_id IS NULL
               OR source_file_url IS NULL
               OR api_extracted_at_utc IS NULL
               OR ingested_at_utc IS NULL
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM silver.api_metriq_benchmark;


\echo ''
\echo '============================================================'
\echo 'TEST 8 - SOURCE-SPECIFIC RULE: KNOWN PROVIDER ANOMALY PRESERVED'
\echo '============================================================'

SELECT
    COUNT(*) FILTER (
        WHERE device LIKE 'ibm_%'
          AND provider IS DISTINCT FROM 'ibm'
    ) AS ibm_device_non_ibm_provider_rows,

    COUNT(*) FILTER (
        WHERE device LIKE 'ibm_%'
          AND provider = 'local'
    ) AS known_local_rows,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE device LIKE 'ibm_%'
              AND provider IS DISTINCT FROM 'ibm'
        ) = 3

         AND COUNT(*) FILTER (
            WHERE device LIKE 'ibm_%'
              AND provider = 'local'
        ) = 3

        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM silver.api_metriq_benchmark;


\echo ''
\echo 'Known anomaly details:'

SELECT
    provider,
    device,
    job_type,
    source_timestamp_text,
    app_version
FROM silver.api_metriq_benchmark
WHERE device LIKE 'ibm_%'
  AND provider IS DISTINCT FROM 'ibm'
ORDER BY source_timestamp_text;

\echo ''
\echo '============================================================'
\echo 'TEST 3b - DUPLICATE KEY GROUPS / CONFLICTING CONTENT'
\echo '============================================================'

WITH k AS (
    SELECT
        data -> '_airbyte_data' ->> 'device'    AS device,
        data -> '_airbyte_data' ->> 'job_type'  AS job_type,
        data -> '_airbyte_data' ->> 'timestamp' AS ts,
        COUNT(*)                                AS n,
        COUNT(DISTINCT data -> '_airbyte_data') AS n_contents
    FROM bronze.api_metriq_benchmark
    GROUP BY 1, 2, 3
)
SELECT
    COUNT(*) FILTER (WHERE n > 1)          AS duplicated_key_groups,
    COALESCE(SUM(n - 1), 0)                AS excess_rows,
    COUNT(*) FILTER (WHERE n_contents > 1) AS keys_with_conflicting_content,
    CASE
        WHEN COUNT(*) FILTER (WHERE n_contents > 1) = 0
         AND SUM(n - 1) = 5
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM k;


\echo ''
\echo '============================================================'
\echo 'TEST 8b - BENCHMARK TIMESTAMP NOT NULL AFTER TYPING'
\echo '============================================================'

SELECT
    COUNT(*) FILTER (WHERE benchmark_timestamp IS NULL) AS null_benchmark_timestamps,
    CASE
        WHEN COUNT(*) FILTER (WHERE benchmark_timestamp IS NULL) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM silver.api_metriq_benchmark;


\echo ''
\echo '============================================================'
\echo 'SUMMARY'
\echo 'Expected current lot: Bronze=413 / Silver=408 / Removed=5'
\echo '============================================================'
