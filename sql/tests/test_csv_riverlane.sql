\pset pager off

\echo '============================================================'
\echo 'TEST 1 - PRIMARY KEY NOT NULL'
\echo '============================================================'

SELECT
    table_name,
    rows,
    null_keys,
    CASE WHEN null_keys = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
    SELECT
        'riverlane_fpga_accuracy' AS table_name,
        COUNT(*) AS rows,
        COUNT(*) FILTER (WHERE source_record_id IS NULL) AS null_keys
    FROM silver.riverlane_fpga_accuracy

    UNION ALL

    SELECT
        'riverlane_fpga_memory',
        COUNT(*),
        COUNT(*) FILTER (WHERE source_record_id IS NULL)
    FROM silver.riverlane_fpga_memory

    UNION ALL

    SELECT
        'riverlane_syndrome_observation',
        COUNT(*),
        COUNT(*) FILTER (WHERE source_record_id IS NULL)
    FROM silver.riverlane_syndrome_observation
) x
ORDER BY table_name;


\echo ''
\echo '============================================================'
\echo 'TEST 2 - PRIMARY KEY UNIQUENESS'
\echo '============================================================'

SELECT
    table_name,
    rows,
    distinct_keys,
    rows - distinct_keys AS duplicate_keys,
    CASE WHEN rows = distinct_keys THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
    SELECT
        'riverlane_fpga_accuracy' AS table_name,
        COUNT(*) AS rows,
        COUNT(DISTINCT source_record_id) AS distinct_keys
    FROM silver.riverlane_fpga_accuracy

    UNION ALL

    SELECT
        'riverlane_fpga_memory',
        COUNT(*),
        COUNT(DISTINCT source_record_id)
    FROM silver.riverlane_fpga_memory

    UNION ALL

    SELECT
        'riverlane_syndrome_observation',
        COUNT(*),
        COUNT(DISTINCT source_record_id)
    FROM silver.riverlane_syndrome_observation
) x
ORDER BY table_name;


\echo ''
\echo '============================================================'
\echo 'TEST 3 - BRONZE TO SILVER RECONCILIATION'
\echo '============================================================'

SELECT
    dataset,
    bronze_rows,
    silver_rows,
    silver_rows - bronze_rows AS difference,
    CASE WHEN bronze_rows = silver_rows THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
    SELECT
        'accuracy' AS dataset,
        (SELECT COUNT(*) FROM bronze.riverlane_fpga_accuracy) AS bronze_rows,
        (SELECT COUNT(*) FROM silver.riverlane_fpga_accuracy) AS silver_rows

    UNION ALL

    SELECT
        'memory',
        (SELECT COUNT(*) FROM bronze.riverlane_fpga_memory),
        (SELECT COUNT(*) FROM silver.riverlane_fpga_memory)

    UNION ALL

    SELECT
        'syndrome',
        (SELECT COUNT(*) FROM bronze.riverlane_syndrome_d21)
        +
        (SELECT COUNT(*) FROM bronze.riverlane_syndrome_d23),
        (SELECT COUNT(*) FROM silver.riverlane_syndrome_observation)
) x
ORDER BY dataset;


\echo ''
\echo '============================================================'
\echo 'TEST 4 - SNAKE_CASE COLUMN NAMES'
\echo '============================================================'

SELECT
    COUNT(*) AS invalid_column_names,
    COALESCE(string_agg(table_name || '.' || column_name, ', '), 'none')
        AS invalid_columns,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM information_schema.columns
WHERE table_schema = 'silver'
  AND table_name IN (
      'riverlane_fpga_accuracy',
      'riverlane_fpga_memory',
      'riverlane_syndrome_observation'
  )
  AND column_name !~ '^[a-z][a-z0-9_]*$';


\echo ''
\echo '============================================================'
\echo 'TEST 5 - EXPECTED DATA TYPES'
\echo '============================================================'

WITH expected(table_name, column_name, expected_type) AS (
    VALUES
        ('riverlane_fpga_accuracy', 'source_index', 'integer'),
        ('riverlane_fpga_accuracy', 'distance', 'integer'),
        ('riverlane_fpga_accuracy', 'shots', 'bigint'),
        ('riverlane_fpga_accuracy', 'fails', 'bigint'),
        ('riverlane_fpga_accuracy', 'p_physical', 'numeric'),
        ('riverlane_fpga_accuracy', 'logical_error_rate', 'numeric'),
        ('riverlane_fpga_accuracy', 'source_file_last_modified', 'timestamp with time zone'),
        ('riverlane_fpga_accuracy', 'csv_extracted_at_utc', 'timestamp with time zone'),
        ('riverlane_fpga_accuracy', 'ingested_at_utc', 'timestamp with time zone'),

        ('riverlane_fpga_memory', 'distance', 'integer'),
        ('riverlane_fpga_memory', 'cluster_stack', 'numeric'),
        ('riverlane_fpga_memory', 'parent_table', 'numeric'),
        ('riverlane_fpga_memory', 'merge_stack', 'numeric'),

        ('riverlane_syndrome_observation', 'distance', 'integer'),
        ('riverlane_syndrome_observation', 'noise_rate', 'numeric'),
        ('riverlane_syndrome_observation', 'syndrome_weight', 'integer'),
        ('riverlane_syndrome_observation', 'occurrence_number', 'bigint'),
        ('riverlane_syndrome_observation', 'csv_extracted_at_utc', 'timestamp with time zone'),
        ('riverlane_syndrome_observation', 'ingested_at_utc', 'timestamp with time zone')
),
actual AS (
    SELECT table_name, column_name, data_type
    FROM information_schema.columns
    WHERE table_schema = 'silver'
)
SELECT
    COUNT(*) FILTER (
        WHERE a.data_type IS NULL OR a.data_type <> e.expected_type
    ) AS type_mismatches,

    COALESCE(
        string_agg(
            e.table_name || '.' || e.column_name ||
            ': expected=' || e.expected_type ||
            ', actual=' || COALESCE(a.data_type, 'MISSING'),
            '; '
        ) FILTER (
            WHERE a.data_type IS NULL OR a.data_type <> e.expected_type
        ),
        'none'
    ) AS mismatch_details,

    CASE
        WHEN COUNT(*) FILTER (
            WHERE a.data_type IS NULL OR a.data_type <> e.expected_type
        ) = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status

FROM expected e
LEFT JOIN actual a
  ON a.table_name = e.table_name
 AND a.column_name = e.column_name;


\echo ''
\echo '============================================================'
\echo 'TEST 6 - TRACEABILITY / PROVENANCE'
\echo '============================================================'

SELECT
    table_name,
    rows,
    invalid_provenance_rows,
    CASE WHEN invalid_provenance_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
    SELECT
        'riverlane_fpga_accuracy' AS table_name,
        COUNT(*) AS rows,
        COUNT(*) FILTER (
            WHERE source_system IS DISTINCT FROM 'riverlane'
               OR source_record_id IS NULL
               OR source_airbyte_raw_id IS NULL
               OR bronze_airbyte_raw_id IS NULL
               OR source_file_url IS NULL
               OR source_dataset_file IS NULL
               OR csv_extracted_at_utc IS NULL
               OR ingested_at_utc IS NULL
        ) AS invalid_provenance_rows
    FROM silver.riverlane_fpga_accuracy

    UNION ALL

    SELECT
        'riverlane_fpga_memory',
        COUNT(*),
        COUNT(*) FILTER (
            WHERE source_system IS DISTINCT FROM 'riverlane'
               OR source_record_id IS NULL
               OR source_airbyte_raw_id IS NULL
               OR bronze_airbyte_raw_id IS NULL
               OR source_file_url IS NULL
               OR source_dataset_file IS NULL
               OR csv_extracted_at_utc IS NULL
               OR ingested_at_utc IS NULL
        )
    FROM silver.riverlane_fpga_memory

    UNION ALL

    SELECT
        'riverlane_syndrome_observation',
        COUNT(*),
        COUNT(*) FILTER (
            WHERE source_system IS DISTINCT FROM 'riverlane'
               OR source_record_id IS NULL
               OR source_airbyte_raw_id IS NULL
               OR bronze_airbyte_raw_id IS NULL
               OR source_file_url IS NULL
               OR source_dataset_file IS NULL
               OR source_stream IS NULL
               OR csv_extracted_at_utc IS NULL
               OR ingested_at_utc IS NULL
        )
    FROM silver.riverlane_syndrome_observation
) x
ORDER BY table_name;


\echo ''
\echo '============================================================'
\echo 'TEST 7 - SYNDROME MULTIPLICITY PRESERVED'
\echo 'Repeated scientific values are valid observations'
\echo '============================================================'

WITH bronze_values AS (
    SELECT
        payload ->> 'code' AS code,
        (payload ->> 'distance')::integer AS distance,
        payload ->> 'noise_type' AS noise_type,
        (payload ->> 'noise_rate')::numeric AS noise_rate,
        (payload ->> 'syndrome_weight')::integer AS syndrome_weight,
        COUNT(*) AS n
    FROM (
        SELECT data -> '_airbyte_data' AS payload
        FROM bronze.riverlane_syndrome_d21

        UNION ALL

        SELECT data -> '_airbyte_data'
        FROM bronze.riverlane_syndrome_d23
    ) b
    GROUP BY 1,2,3,4,5
),
silver_values AS (
    SELECT
        code,
        distance,
        noise_type,
        noise_rate,
        syndrome_weight,
        COUNT(*) AS n
    FROM silver.riverlane_syndrome_observation
    GROUP BY 1,2,3,4,5
),
comparison AS (
    SELECT
        COALESCE(b.code, s.code) AS code,
        COALESCE(b.distance, s.distance) AS distance,
        COALESCE(b.noise_type, s.noise_type) AS noise_type,
        COALESCE(b.noise_rate, s.noise_rate) AS noise_rate,
        COALESCE(b.syndrome_weight, s.syndrome_weight) AS syndrome_weight,
        COALESCE(b.n, 0) AS bronze_n,
        COALESCE(s.n, 0) AS silver_n
    FROM bronze_values b
    FULL OUTER JOIN silver_values s
      USING (code, distance, noise_type, noise_rate, syndrome_weight)
)
SELECT
    (SELECT COUNT(*) FROM bronze.riverlane_syndrome_d21)
    +
    (SELECT COUNT(*) FROM bronze.riverlane_syndrome_d23)
        AS bronze_observations,

    (SELECT COUNT(*) FROM silver.riverlane_syndrome_observation)
        AS silver_observations,

    COUNT(*) AS value_combinations,

    COUNT(*) FILTER (WHERE bronze_n <> silver_n)
        AS multiplicity_mismatches,

    CASE
        WHEN COUNT(*) FILTER (WHERE bronze_n <> silver_n) = 0
         AND (SELECT COUNT(*) FROM silver.riverlane_syndrome_observation) = 2000000
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM comparison;


\echo ''
\echo '============================================================'
\echo 'TEST 8 - SOURCE-SPECIFIC SCIENTIFIC RULES'
\echo '============================================================'

WITH syndrome_groups AS (
    SELECT
        distance,
        noise_type,
        noise_rate,
        COUNT(*) AS observations
    FROM silver.riverlane_syndrome_observation
    GROUP BY 1,2,3
),
metrics AS (
    SELECT
        (SELECT COUNT(*) FROM syndrome_groups) AS syndrome_group_count,

        (SELECT COUNT(*)
         FROM syndrome_groups
         WHERE observations <> 100000) AS bad_group_sizes,

        (SELECT COUNT(*)
         FROM silver.riverlane_syndrome_observation
         WHERE code IS NULL
            OR noise_type IS NULL
            OR syndrome_weight IS NULL
            OR syndrome_weight < 0
            OR noise_rate IS NULL
            OR noise_rate <= 0
            OR distance IS NULL
            OR distance NOT IN (21,23)
            OR source_stream IS NULL
            OR source_stream NOT IN (
                'riverlane_syndrome_d21',
                'riverlane_syndrome_d23'
            )
            OR (
                source_stream = 'riverlane_syndrome_d21'
                AND distance IS DISTINCT FROM 21
            )
            OR (
                source_stream = 'riverlane_syndrome_d23'
                AND distance IS DISTINCT FROM 23
            )
        ) AS syndrome_rule_violations,

        (SELECT COUNT(*)
         FROM silver.riverlane_fpga_accuracy
         WHERE d_h IS NULL
            OR d_v IS NULL
            OR distance IS NULL
            OR d_h IS DISTINCT FROM distance
            OR d_v IS DISTINCT FROM distance

            OR rounds IS NULL
            OR rounds <= 0

            OR shots IS NULL
            OR shots <= 0
            OR fails IS NULL
            OR fails < 0
            OR fails > shots

            OR p_physical IS NULL
            OR p_physical < 0
            OR p_physical > 1

            OR ler_percent IS NULL
            OR logical_error_rate IS NULL
            OR logical_error_rate < 0
            OR logical_error_rate > 1

            OR ABS(
                logical_error_rate
                -
                fails::numeric / NULLIF(shots, 0)
            ) > 0.000000000001

            OR ABS(
                logical_error_rate
                -
                ler_percent / 100
            ) > 0.000000000001

            OR total_cycles IS NULL
            OR total_cycles <= 0

            OR time_per_round IS NULL
            OR time_per_round <= 0
        ) AS accuracy_rule_violations,

        (SELECT COUNT(*)
         FROM silver.riverlane_fpga_memory
         WHERE distance IS NULL
            OR distance <= 0
            OR cluster_stack IS NULL
            OR cluster_stack <= 0
            OR parent_table IS NULL
            OR parent_table <= 0
            OR merge_stack IS NULL
            OR merge_stack <= 0
        ) AS memory_rule_violations
)
SELECT
    syndrome_group_count,
    bad_group_sizes,
    syndrome_rule_violations,
    accuracy_rule_violations,
    memory_rule_violations,

    CASE
        WHEN syndrome_group_count = 20
         AND bad_group_sizes = 0
         AND syndrome_rule_violations = 0
         AND accuracy_rule_violations = 0
         AND memory_rule_violations = 0
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM metrics;



\echo ''
\echo '============================================================'
\echo 'TEST 9 - BRONZE REPEATED OBSERVATIONS QUANTIFIED'
\echo 'Repeated rows are measured, not automatically treated as errors'
\echo '============================================================'

WITH duplicate_profile AS (
    SELECT
        'd21' AS source,
        COUNT(*) AS total_rows,
        COUNT(DISTINCT data -> '_airbyte_data')
            AS distinct_value_combinations,
        COUNT(*) - COUNT(DISTINCT data -> '_airbyte_data')
            AS repeated_observations
    FROM bronze.riverlane_syndrome_d21

    UNION ALL

    SELECT
        'd23',
        COUNT(*),
        COUNT(DISTINCT data -> '_airbyte_data'),
        COUNT(*) - COUNT(DISTINCT data -> '_airbyte_data')
    FROM bronze.riverlane_syndrome_d23
)
SELECT
    source,
    total_rows,
    distinct_value_combinations,
    repeated_observations,
    CASE
        WHEN total_rows = 1000000
         AND repeated_observations > 0
         AND distinct_value_combinations + repeated_observations = total_rows
        THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM duplicate_profile
ORDER BY source;

\echo ''
\echo '============================================================'
\echo 'SUMMARY'
\echo 'Expected: accuracy=77 / memory=9 / syndrome=2,000,000'
\echo 'Expected syndrome experimental groups: 20 x 100,000'
\echo '============================================================'
