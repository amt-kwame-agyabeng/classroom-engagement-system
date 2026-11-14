BEGIN;

-- ============================================================
-- MIGRATION 017: SIGNED IDENTITY CONTEXT
-- SECTION 1: PROTECTED SIGNING-KEY STORAGE
-- ============================================================

-- Store signing keys separately from application-accessible data.
CREATE TABLE app_private.identity_signing_keys (
    key_id text PRIMARY KEY,
    secret bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
    expires_at timestamptz,
    is_active boolean NOT NULL DEFAULT true,

    CONSTRAINT identity_signing_keys_key_id_not_empty
        CHECK (pg_catalog.length(key_id) BETWEEN 1 AND 64),

    CONSTRAINT identity_signing_keys_secret_length
        CHECK (pg_catalog.length(secret) >= 32),

    CONSTRAINT identity_signing_keys_expiry_valid
        CHECK (expires_at IS NULL OR expires_at > created_at)
);

-- The restricted security owner owns the key table.
ALTER TABLE app_private.identity_signing_keys
OWNER TO classroom_security_owner;

-- Remove access from PUBLIC and the application role.
REVOKE ALL ON TABLE app_private.identity_signing_keys
FROM PUBLIC, classroom_app;

-- Permit the security owner to manage and read signing keys.
GRANT SELECT ON TABLE app_private.identity_signing_keys
TO classroom_security_owner;

-- The application role must not create objects in this schema.
REVOKE CREATE ON SCHEMA app_private FROM classroom_app;

-- ============================================================
-- SECTION 2: SIGNED IDENTITY TOKEN VERIFICATION
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.verify_identity_token(
    p_token text
)
RETURNS TABLE (
    verified_user_id uuid,
    verified_university_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_parts text[];
    v_fields text[];

    v_payload text;
    v_signature text;
    v_expected_signature text;

    v_key_id text;
    v_secret bytea;

    v_user_id uuid;
    v_university_id uuid;

    v_issued_at bigint;
    v_expires_at bigint;
    v_nonce uuid;

    v_now bigint;
BEGIN
    -- Reject missing or excessively large tokens.
    IF p_token IS NULL
       OR pg_catalog.length(p_token) > 1024
    THEN
        RETURN;
    END IF;

    -- Separate payload and signature.
    v_parts := pg_catalog.string_to_array(p_token, '.');

    IF pg_catalog.cardinality(v_parts) <> 2 THEN
        RETURN;
    END IF;

    v_payload := v_parts[1];
    v_signature := v_parts[2];

    -- Require a lowercase SHA-256 hexadecimal signature.
    IF pg_catalog.length(v_signature) <> 64
       OR v_signature !~ '^[0-9a-f]{64}$'
    THEN
        RETURN;
    END IF;

    -- Parse the seven payload fields.
    v_fields := pg_catalog.string_to_array(v_payload, '|');

    IF pg_catalog.cardinality(v_fields) <> 7 THEN
        RETURN;
    END IF;

    -- Validate token version.
    IF v_fields[1] <> 'v1' THEN
        RETURN;
    END IF;

    -- Validate key identifier.
    v_key_id := v_fields[2];

    IF v_key_id !~ '^[A-Za-z0-9_-]{1,64}$' THEN
        RETURN;
    END IF;

    -- Validate UUID formats before casting.
    IF v_fields[3] !~
       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    THEN
        RETURN;
    END IF;

    v_user_id := v_fields[3]::uuid;

    IF v_fields[4] = '-' THEN
        v_university_id := NULL;
    ELSE
        IF v_fields[4] !~
           '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
        THEN
            RETURN;
        END IF;

        v_university_id := v_fields[4]::uuid;
    END IF;

    -- Validate timestamps.
    IF v_fields[5] !~ '^[0-9]{10,12}$'
       OR v_fields[6] !~ '^[0-9]{10,12}$'
    THEN
        RETURN;
    END IF;

    v_issued_at := v_fields[5]::bigint;
    v_expires_at := v_fields[6]::bigint;

    -- Validate nonce format.
    IF v_fields[7] !~
       '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    THEN
        RETURN;
    END IF;

    v_nonce := v_fields[7]::uuid;

    -- Check token lifetime and clock skew.
    v_now := pg_catalog.floor(
        pg_catalog.date_part(
            'epoch',
            pg_catalog.statement_timestamp()
        )
    )::bigint;

    IF v_issued_at > v_now + 30
       OR v_expires_at <= v_now
       OR v_expires_at <= v_issued_at
       OR v_expires_at - v_issued_at > 120
    THEN
        RETURN;
    END IF;

    -- Retrieve the active signing key.
    SELECT k.secret
    INTO v_secret
    FROM app_private.identity_signing_keys AS k
    WHERE k.key_id = v_key_id
      AND k.is_active = true
      AND k.created_at <= pg_catalog.statement_timestamp()
      AND (
          k.expires_at IS NULL
          OR k.expires_at > pg_catalog.statement_timestamp()
      );

    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- Calculate the expected HMAC-SHA256 signature.
    v_expected_signature := pg_catalog.encode(
        public.hmac(
            pg_catalog.convert_to(v_payload, 'UTF8'),
            v_secret,
            'sha256'
        ),
        'hex'
    );

    -- Reject an invalid signature.
    IF v_signature <> v_expected_signature THEN
        RETURN;
    END IF;

    -- Return verified identity claims.
    verified_user_id := v_user_id;
    verified_university_id := v_university_id;

    RETURN NEXT;
END;
$function$;


-- Transfer ownership to the restricted security role.
ALTER FUNCTION app_private.verify_identity_token(text)
OWNER TO classroom_security_owner;

-- Prevent public execution.
REVOKE ALL ON FUNCTION
    app_private.verify_identity_token(text)
FROM PUBLIC;

-- Permit the application to submit tokens for verification.
GRANT EXECUTE ON FUNCTION
    app_private.verify_identity_token(text)
TO classroom_app;

COMMIT;