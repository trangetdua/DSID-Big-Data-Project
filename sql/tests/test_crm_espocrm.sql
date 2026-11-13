\pset pager off

\echo '============================================================'
\echo 'TEST 1 - SILVER PRIMARY KEYS NOT NULL'
\echo '============================================================'

WITH k AS (
    SELECT 'account' AS dataset,
           COUNT(*) AS n,
           COUNT(*) FILTER (WHERE source_record_id IS NULL) AS null_keys
    FROM silver.crm_account

    UNION ALL

    SELECT 'contact',
           COUNT(*),
           COUNT(*) FILTER (WHERE source_record_id IS NULL)
    FROM silver.crm_contact

    UNION ALL

    SELECT 'opportunity',
           COUNT(*),
           COUNT(*) FILTER (WHERE source_record_id IS NULL)
    FROM silver.crm_opportunity
)
SELECT *,
       CASE WHEN null_keys = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM k
ORDER BY dataset;


\echo ''
\echo '============================================================'
\echo 'TEST 2 - SILVER PRIMARY KEY UNIQUENESS'
\echo '============================================================'

WITH k AS (
    SELECT 'account' AS dataset,
           COUNT(*) AS n,
           COUNT(DISTINCT source_record_id) AS unique_keys
    FROM silver.crm_account

    UNION ALL

    SELECT 'contact',
           COUNT(*),
           COUNT(DISTINCT source_record_id)
    FROM silver.crm_contact

    UNION ALL

    SELECT 'opportunity',
           COUNT(*),
           COUNT(DISTINCT source_record_id)
    FROM silver.crm_opportunity
)
SELECT *,
       n - unique_keys AS duplicate_keys,
       CASE WHEN n = unique_keys THEN 'PASS' ELSE 'FAIL' END AS status
FROM k
ORDER BY dataset;


\echo ''
\echo '============================================================'
\echo 'TEST 3A - BRONZE DUPLICATES QUANTIFIED'
\echo '============================================================'

WITH d AS (
    SELECT 'account' AS dataset,
           COUNT(*) AS bronze_rows,
           COUNT(DISTINCT id) AS source_ids,
           COUNT(*) FILTER (WHERE id IS NULL) AS null_source_ids
    FROM bronze.account

    UNION ALL

    SELECT 'contact',
           COUNT(*),
           COUNT(DISTINCT id),
           COUNT(*) FILTER (WHERE id IS NULL)
    FROM bronze.contact

    UNION ALL

    SELECT 'opportunity',
           COUNT(*),
           COUNT(DISTINCT id),
           COUNT(*) FILTER (WHERE id IS NULL)
    FROM bronze.opportunity
)
SELECT *,
       bronze_rows - source_ids - null_source_ids AS duplicate_versions,
       CASE WHEN null_source_ids = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM d
ORDER BY dataset;


\echo ''
\echo '============================================================'
\echo 'TEST 3B - DETERMINISTIC DEDUP WINNER'
\echo '============================================================'

WITH ranked AS (
    SELECT
        'account' AS dataset,
        id::text AS source_id,
        _airbyte_raw_id::text AS raw_id,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY modified_at DESC NULLS LAST,
                     _airbyte_extracted_at DESC NULLS LAST,
                     _airbyte_raw_id DESC NULLS LAST
        ) AS rn
    FROM bronze.account

    UNION ALL

    SELECT
        'contact',
        id::text,
        _airbyte_raw_id::text,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY modified_at DESC NULLS LAST,
                     _airbyte_extracted_at DESC NULLS LAST,
                     _airbyte_raw_id DESC NULLS LAST
        )
    FROM bronze.contact

    UNION ALL

    SELECT
        'opportunity',
        id::text,
        _airbyte_raw_id::text,
        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY modified_at DESC NULLS LAST,
                     _airbyte_extracted_at DESC NULLS LAST,
                     _airbyte_raw_id DESC NULLS LAST
        )
    FROM bronze.opportunity
),
expected AS (
    SELECT dataset, source_id, raw_id
    FROM ranked
    WHERE rn = 1
),
actual AS (
    SELECT 'account' AS dataset,
           source_record_id AS source_id,
           bronze_airbyte_raw_id::text AS raw_id
    FROM silver.crm_account

    UNION ALL

    SELECT 'contact',
           source_record_id,
           bronze_airbyte_raw_id::text
    FROM silver.crm_contact

    UNION ALL

    SELECT 'opportunity',
           source_record_id,
           bronze_airbyte_raw_id::text
    FROM silver.crm_opportunity
),
comparison AS (
    SELECT COUNT(*) FILTER (
        WHERE e.source_id IS NULL
           OR a.source_id IS NULL
           OR e.raw_id IS DISTINCT FROM a.raw_id
    ) AS wrong_winners
    FROM expected e
    FULL OUTER JOIN actual a
      ON a.dataset = e.dataset
     AND a.source_id = e.source_id
)
SELECT wrong_winners,
       CASE WHEN wrong_winners = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM comparison;


\echo ''
\echo '============================================================'
\echo 'TEST 3C - AIRBYTE TIE-BREAK ID QUALITY'
\echo '============================================================'

WITH q AS (
    SELECT
        'account' AS dataset,
        COUNT(*) AS bronze_rows,
        COUNT(*) FILTER (
            WHERE _airbyte_raw_id IS NULL
               OR BTRIM(_airbyte_raw_id::text) = ''
        ) AS missing_raw_ids,
        COUNT(*)
          - COUNT(DISTINCT _airbyte_raw_id)
          - COUNT(*) FILTER (WHERE _airbyte_raw_id IS NULL)
          AS duplicate_nonnull_raw_ids
    FROM bronze.account

    UNION ALL

    SELECT
        'contact',
        COUNT(*),
        COUNT(*) FILTER (
            WHERE _airbyte_raw_id IS NULL
               OR BTRIM(_airbyte_raw_id::text) = ''
        ),
        COUNT(*)
          - COUNT(DISTINCT _airbyte_raw_id)
          - COUNT(*) FILTER (WHERE _airbyte_raw_id IS NULL)
    FROM bronze.contact

    UNION ALL

    SELECT
        'opportunity',
        COUNT(*),
        COUNT(*) FILTER (
            WHERE _airbyte_raw_id IS NULL
               OR BTRIM(_airbyte_raw_id::text) = ''
        ),
        COUNT(*)
          - COUNT(DISTINCT _airbyte_raw_id)
          - COUNT(*) FILTER (WHERE _airbyte_raw_id IS NULL)
    FROM bronze.opportunity
)
SELECT *,
       CASE
           WHEN missing_raw_ids = 0
            AND duplicate_nonnull_raw_ids = 0
           THEN 'PASS'
           ELSE 'FAIL'
       END AS status
FROM q
ORDER BY dataset;


\echo ''
\echo '============================================================'
\echo 'TEST 4 - SNAKE_CASE COLUMN NAMES'
\echo '============================================================'

WITH bad AS (
    SELECT table_name, column_name
    FROM information_schema.columns
    WHERE table_schema = 'silver'
      AND table_name IN (
          'crm_account',
          'crm_contact',
          'crm_opportunity'
      )
      AND column_name !~ '^[a-z][a-z0-9_]*$'
)
SELECT
    COUNT(*) AS invalid_columns,
    COALESCE(
        string_agg(table_name || '.' || column_name, ', '),
        'none'
    ) AS details,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM bad;


\echo ''
\echo '============================================================'
\echo 'TEST 5 - EXPECTED POSTGRESQL DATA TYPES'
\echo '============================================================'

WITH expected(table_name, column_name, allowed_types) AS (
    VALUES
    ('crm_account','source_record_id', ARRAY['text']),
    ('crm_account','account_id', ARRAY['text']),
    ('crm_account','created_at', ARRAY['timestamp without time zone']),
    ('crm_account','modified_at', ARRAY['timestamp without time zone']),
    ('crm_account','stream_updated_at', ARRAY['timestamp without time zone']),
    ('crm_account','deleted', ARRAY['boolean']),
    ('crm_account','ingested_at_utc', ARRAY['timestamp with time zone']),

    ('crm_contact','source_record_id', ARRAY['text']),
    ('crm_contact','contact_id', ARRAY['text']),
    ('crm_contact','account_id', ARRAY['text']),
    ('crm_contact','created_at', ARRAY['timestamp without time zone']),
    ('crm_contact','modified_at', ARRAY['timestamp without time zone']),
    ('crm_contact','stream_updated_at', ARRAY['timestamp without time zone']),
    ('crm_contact','deleted', ARRAY['boolean']),
    ('crm_contact','ingested_at_utc', ARRAY['timestamp with time zone']),

    ('crm_opportunity','source_record_id', ARRAY['text']),
    ('crm_opportunity','opportunity_id', ARRAY['text']),
    ('crm_opportunity','account_id', ARRAY['text']),
    ('crm_opportunity','contact_id', ARRAY['text']),
    ('crm_opportunity','created_at', ARRAY['timestamp without time zone']),
    ('crm_opportunity','modified_at', ARRAY['timestamp without time zone']),
    ('crm_opportunity','stream_updated_at', ARRAY['timestamp without time zone']),
    ('crm_opportunity','deleted', ARRAY['boolean']),
    ('crm_opportunity','ingested_at_utc', ARRAY['timestamp with time zone']),
    ('crm_opportunity','amount', ARRAY['numeric']),
    ('crm_opportunity','close_date', ARRAY['date']),
    ('crm_opportunity','probability', ARRAY['bigint'])
),
checks AS (
    SELECT
        e.table_name,
        e.column_name,
        e.allowed_types,
        a.data_type,
        (
            a.data_type IS NOT NULL
            AND a.data_type = ANY(e.allowed_types)
        ) AS valid
    FROM expected e
    LEFT JOIN information_schema.columns a
      ON a.table_schema = 'silver'
     AND a.table_name = e.table_name
     AND a.column_name = e.column_name
)
SELECT
    table_name,
    column_name,
    data_type,
    allowed_types,
    CASE WHEN valid THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY table_name, column_name;


\echo ''
\echo '============================================================'
\echo 'TEST 6 - BRONZE TO SILVER RECONCILIATION'
\echo '============================================================'

WITH c AS (
    SELECT
        'account' AS dataset,
        (SELECT COUNT(*) FROM bronze.account) AS bronze_rows,
        (SELECT COUNT(DISTINCT id) FROM bronze.account) AS expected_silver,
        (SELECT COUNT(*) FROM silver.crm_account) AS silver_rows

    UNION ALL

    SELECT
        'contact',
        (SELECT COUNT(*) FROM bronze.contact),
        (SELECT COUNT(DISTINCT id) FROM bronze.contact),
        (SELECT COUNT(*) FROM silver.crm_contact)

    UNION ALL

    SELECT
        'opportunity',
        (SELECT COUNT(*) FROM bronze.opportunity),
        (SELECT COUNT(DISTINCT id) FROM bronze.opportunity),
        (SELECT COUNT(*) FROM silver.crm_opportunity)
)
SELECT *,
       bronze_rows - silver_rows AS rows_deduplicated,
       CASE
           WHEN expected_silver = silver_rows THEN 'PASS'
           ELSE 'FAIL'
       END AS status
FROM c
ORDER BY dataset;


\echo ''
\echo '============================================================'
\echo 'TEST 7 - TRACEABILITY AND PROVENANCE'
\echo '============================================================'

WITH q AS (
    SELECT
        'account' AS dataset,
        COUNT(*) FILTER (
            WHERE source_system IS DISTINCT FROM 'espocrm'
               OR source_record_id IS NULL
               OR bronze_airbyte_raw_id IS NULL
               OR ingested_at_utc IS NULL
        ) AS invalid_rows
    FROM silver.crm_account

    UNION ALL

    SELECT
        'contact',
        COUNT(*) FILTER (
            WHERE source_system IS DISTINCT FROM 'espocrm'
               OR source_record_id IS NULL
               OR bronze_airbyte_raw_id IS NULL
               OR ingested_at_utc IS NULL
        )
    FROM silver.crm_contact

    UNION ALL

    SELECT
        'opportunity',
        COUNT(*) FILTER (
            WHERE source_system IS DISTINCT FROM 'espocrm'
               OR source_record_id IS NULL
               OR bronze_airbyte_raw_id IS NULL
               OR ingested_at_utc IS NULL
        )
    FROM silver.crm_opportunity
)
SELECT *,
       CASE WHEN invalid_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM q
ORDER BY dataset;


\echo ''
\echo '============================================================'
\echo 'TEST 8 - CRM RELATIONSHIP CONSISTENCY'
\echo '============================================================'

WITH q AS (
    SELECT
        (
            SELECT COUNT(*)
            FROM silver.crm_contact
            WHERE account_id IS NULL
        ) AS contacts_missing_account_id,

        (
            SELECT COUNT(*)
            FROM silver.crm_opportunity
            WHERE account_id IS NULL
        ) AS opportunities_missing_account_id,

        (
            SELECT COUNT(*)
            FROM silver.crm_contact c
            LEFT JOIN silver.crm_account a
              ON a.account_id = c.account_id
            WHERE c.account_id IS NOT NULL
              AND a.account_id IS NULL
        ) AS orphan_contacts,

        (
            SELECT COUNT(*)
            FROM silver.crm_opportunity o
            LEFT JOIN silver.crm_account a
              ON a.account_id = o.account_id
            WHERE o.account_id IS NOT NULL
              AND a.account_id IS NULL
        ) AS orphan_opportunity_accounts,

        (
            SELECT COUNT(*)
            FROM silver.crm_opportunity o
            LEFT JOIN silver.crm_contact c
              ON c.contact_id = o.contact_id
            WHERE o.contact_id IS NOT NULL
              AND c.contact_id IS NULL
        ) AS orphan_opportunity_contacts
)
SELECT *,
       CASE
           WHEN contacts_missing_account_id = 0
            AND opportunities_missing_account_id = 0
            AND orphan_contacts = 0
            AND orphan_opportunity_accounts = 0
            AND orphan_opportunity_contacts = 0
           THEN 'PASS'
           ELSE 'FAIL'
       END AS status
FROM q;


\echo ''
\echo '============================================================'
\echo 'TEST 9 - SOURCE-SPECIFIC CRM BUSINESS RULES'
\echo '============================================================'

-- Rules below target the current demo snapshot.
-- They are not universal mandatory EspoCRM constraints.

WITH q AS (
    SELECT
        (
            SELECT COUNT(*)
            FROM silver.crm_account
            WHERE NULLIF(BTRIM(name), '') IS NULL
        ) AS unnamed_accounts,

        (
            SELECT COUNT(*)
            FROM silver.crm_contact
            WHERE NULLIF(BTRIM(last_name), '') IS NULL
        ) AS contacts_missing_last_name,

        (
            SELECT COUNT(*)
            FROM silver.crm_opportunity
            WHERE NULLIF(BTRIM(name), '') IS NULL
        ) AS unnamed_opportunities,

        (
            SELECT COUNT(*)
            FROM silver.crm_opportunity
            WHERE amount IS NULL
               OR amount < 0
        ) AS invalid_amounts,

        (
            SELECT COUNT(*)
            FROM silver.crm_opportunity
            WHERE probability IS NULL
               OR probability < 0
               OR probability > 100
        ) AS invalid_probabilities,

        (
            SELECT COUNT(*)
            FROM silver.crm_opportunity
            WHERE NULLIF(BTRIM(stage), '') IS NULL
        ) AS missing_stages
)
SELECT *,
       CASE
           WHEN unnamed_accounts = 0
            AND contacts_missing_last_name = 0
            AND unnamed_opportunities = 0
            AND invalid_amounts = 0
            AND invalid_probabilities = 0
            AND missing_stages = 0
           THEN 'PASS'
           ELSE 'FAIL'
       END AS status
FROM q;


\echo ''
\echo '============================================================'
\echo 'END CRM TESTS'
\echo '============================================================'
