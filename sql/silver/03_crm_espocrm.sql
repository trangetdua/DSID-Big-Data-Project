-- ============================================================
-- CRM SILVER - ESPOCRM
-- Deterministic deduplication
-- Source: MariaDB via Airbyte
-- Target: PostgreSQL Silver
-- ============================================================

-- Airbyte raw ID is technical lineage and a final tie-breaker
-- within the current Bronze snapshot.
-- It is NOT the immutable CRM/business identifier.

BEGIN;

CREATE SCHEMA IF NOT EXISTS silver;


-- ============================================================
-- 1. ACCOUNT
-- Grain: one current record per EspoCRM Account ID
-- ============================================================

DROP TABLE IF EXISTS silver.crm_account;

CREATE TABLE silver.crm_account AS
WITH ranked AS (
    SELECT
        b.*,

        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY
                modified_at DESC NULLS LAST,
                _airbyte_extracted_at DESC NULLS LAST,
                _airbyte_raw_id DESC NULLS LAST
        ) AS _silver_rn

    FROM bronze.account AS b
)
SELECT
    id::text AS source_record_id,
    id::text AS account_id,

    name,
    type AS account_type,
    website,
    industry,
    sic_code,

    deleted,
    is_locked,

    created_at,
    modified_at,
    stream_updated_at,

    version_number,

    created_by_id,
    modified_by_id,
    assigned_user_id,
    campaign_id,

    description,

    billing_address_street,
    billing_address_city,
    billing_address_state,
    billing_address_postal_code,
    billing_address_country,

    shipping_address_street,
    shipping_address_city,
    shipping_address_state,
    shipping_address_postal_code,
    shipping_address_country,

    'espocrm'::text AS source_system,

    _airbyte_raw_id AS bronze_airbyte_raw_id,
    _airbyte_extracted_at AS ingested_at_utc

FROM ranked
WHERE _silver_rn = 1;

ALTER TABLE silver.crm_account
    ADD CONSTRAINT crm_account_pkey
    PRIMARY KEY (source_record_id);


-- ============================================================
-- 2. CONTACT
-- Grain: one current record per EspoCRM Contact ID
-- ============================================================

DROP TABLE IF EXISTS silver.crm_contact;

CREATE TABLE silver.crm_contact AS
WITH ranked AS (
    SELECT
        b.*,

        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY
                modified_at DESC NULLS LAST,
                _airbyte_extracted_at DESC NULLS LAST,
                _airbyte_raw_id DESC NULLS LAST
        ) AS _silver_rn

    FROM bronze.contact AS b
)
SELECT
    id::text AS source_record_id,
    id::text AS contact_id,
    account_id::text AS account_id,

    first_name,
    middle_name,
    last_name,
    salutation_name,

    deleted,
    do_not_call,

    created_at,
    modified_at,
    stream_updated_at,

    created_by_id,
    modified_by_id,
    assigned_user_id,
    campaign_id,

    description,

    address_street,
    address_city,
    address_state,
    address_postal_code,
    address_country,

    'espocrm'::text AS source_system,

    _airbyte_raw_id AS bronze_airbyte_raw_id,
    _airbyte_extracted_at AS ingested_at_utc

FROM ranked
WHERE _silver_rn = 1;

ALTER TABLE silver.crm_contact
    ADD CONSTRAINT crm_contact_pkey
    PRIMARY KEY (source_record_id);


-- ============================================================
-- 3. OPPORTUNITY
-- Grain: one current record per EspoCRM Opportunity ID
-- ============================================================

DROP TABLE IF EXISTS silver.crm_opportunity;

CREATE TABLE silver.crm_opportunity AS
WITH ranked AS (
    SELECT
        b.*,

        ROW_NUMBER() OVER (
            PARTITION BY id
            ORDER BY
                modified_at DESC NULLS LAST,
                _airbyte_extracted_at DESC NULLS LAST,
                _airbyte_raw_id DESC NULLS LAST
        ) AS _silver_rn

    FROM bronze.opportunity AS b
)
SELECT
    id::text AS source_record_id,
    id::text AS opportunity_id,

    account_id::text AS account_id,
    contact_id::text AS contact_id,

    name,
    stage,
    last_stage,

    amount::numeric AS amount,
    amount_currency,
    probability,
    close_date::date AS close_date,

    deleted,

    lead_source,
    description,

    created_at,
    modified_at,
    stream_updated_at,

    version_number,

    created_by_id,
    modified_by_id,
    assigned_user_id,
    campaign_id,

    'espocrm'::text AS source_system,

    _airbyte_raw_id AS bronze_airbyte_raw_id,
    _airbyte_extracted_at AS ingested_at_utc

FROM ranked
WHERE _silver_rn = 1;

ALTER TABLE silver.crm_opportunity
    ADD CONSTRAINT crm_opportunity_pkey
    PRIMARY KEY (source_record_id);


COMMIT;
