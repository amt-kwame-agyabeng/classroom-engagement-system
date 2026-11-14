

BEGIN;
GRANT CREATE ON SCHEMA app_private TO classroom_security_owner;

-- Grant only the column privileges required by the session functions.
GRANT SELECT (user_id, token_hash, expires_at, revoked_at)
ON public.refresh_token_sessions
TO classroom_security_owner;

GRANT INSERT (user_id, token_hash, ip_address, user_agent, expires_at)
ON public.refresh_token_sessions
TO classroom_security_owner;

GRANT UPDATE (revoked_at, last_used_at)
ON public.refresh_token_sessions
TO classroom_security_owner;


-- 1. Authenticate credentials and create a refresh-token session.
CREATE OR REPLACE FUNCTION app_private.create_authenticated_session(
    p_email TEXT,
    p_password TEXT,
    p_refresh_token TEXT,
    p_ip_address INET,
    p_user_agent TEXT,
    p_expires_at TIMESTAMPTZ
)
RETURNS TABLE (
    session_id UUID,
    user_id UUID,
    full_name VARCHAR,
    email VARCHAR,
    account_status VARCHAR,
    email_verified_at TIMESTAMPTZ,
    roles JSONB,
    memberships JSONB
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_auth RECORD;
    v_session_id UUID;
    v_token_hash TEXT;
BEGIN
    IF p_refresh_token IS NULL
       OR p_refresh_token !~ '^[0-9a-f]{64}$'
       OR p_expires_at IS NULL
       OR p_expires_at <= statement_timestamp()
       OR p_expires_at > statement_timestamp() + INTERVAL '30 days'
    THEN
        RAISE EXCEPTION 'Invalid session parameters'
            USING ERRCODE = '22023';
    END IF;

    SELECT a.*
    INTO v_auth
    FROM app_private.authenticate_user(p_email, p_password) AS a
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- Create a session only for an active, verified account.
    IF v_auth.account_status = 'active'
       AND v_auth.email_verified_at IS NOT NULL
    THEN
        v_token_hash := encode(
            public.digest(p_refresh_token, 'sha256'),
            'hex'
        );

        INSERT INTO public.refresh_token_sessions (
            user_id,
            token_hash,
            ip_address,
            user_agent,
            expires_at
        )
        VALUES (
            v_auth.user_id,
            v_token_hash,
            p_ip_address,
            p_user_agent,
            p_expires_at
        )
        RETURNING id INTO v_session_id;
    END IF;

    RETURN QUERY
    SELECT
        v_session_id,
        v_auth.user_id,
        v_auth.full_name,
        v_auth.email,
        v_auth.account_status,
        v_auth.email_verified_at,
        v_auth.roles,
        v_auth.memberships;
END;
$function$;


-- 2. Rotate a refresh token atomically.
CREATE OR REPLACE FUNCTION app_private.rotate_refresh_token(
    p_refresh_token TEXT,
    p_new_refresh_token TEXT,
    p_ip_address INET,
    p_user_agent TEXT,
    p_expires_at TIMESTAMPTZ
)
RETURNS TABLE (
    user_id UUID,
    full_name VARCHAR,
    email VARCHAR
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_old_hash TEXT;
    v_new_hash TEXT;
    v_session RECORD;
    v_user RECORD;
BEGIN
    IF p_refresh_token IS NULL
       OR p_refresh_token !~ '^[0-9a-f]{64}$'
       OR p_new_refresh_token IS NULL
       OR p_new_refresh_token !~ '^[0-9a-f]{64}$'
       OR p_refresh_token = p_new_refresh_token
       OR p_expires_at IS NULL
       OR p_expires_at <= statement_timestamp()
       OR p_expires_at > statement_timestamp() + INTERVAL '30 days'
    THEN
        RAISE EXCEPTION 'Invalid refresh-token parameters'
            USING ERRCODE = '22023';
    END IF;

    v_old_hash := encode(
        public.digest(p_refresh_token, 'sha256'),
        'hex'
    );

    v_new_hash := encode(
        public.digest(p_new_refresh_token, 'sha256'),
        'hex'
    );

    -- Lock the existing session to prevent concurrent rotation.
    SELECT
        s.user_id,
        s.expires_at,
        s.revoked_at
    INTO v_session
    FROM public.refresh_token_sessions AS s
    WHERE s.token_hash = v_old_hash
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    IF v_session.revoked_at IS NOT NULL
       OR v_session.expires_at <= statement_timestamp()
    THEN
        RETURN;
    END IF;

    SELECT
        u.id,
        u.full_name,
        u.email,
        u.account_status,
        u.email_verified_at
    INTO v_user
    FROM public.users AS u
    WHERE u.id = v_session.user_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- Do not renew sessions belonging to unavailable accounts.
    IF v_user.account_status <> 'active'
       OR v_user.email_verified_at IS NULL
    THEN
        UPDATE public.refresh_token_sessions
        SET
            revoked_at = statement_timestamp(),
            last_used_at = statement_timestamp()
        WHERE token_hash = v_old_hash;

        RETURN;
    END IF;

    -- Revoke the previous token.
    UPDATE public.refresh_token_sessions
    SET
        revoked_at = statement_timestamp(),
        last_used_at = statement_timestamp()
    WHERE token_hash = v_old_hash;

    -- Insert its replacement in the same transaction.
    INSERT INTO public.refresh_token_sessions (
        user_id,
        token_hash,
        ip_address,
        user_agent,
        expires_at
    )
    VALUES (
        v_user.id,
        v_new_hash,
        p_ip_address,
        p_user_agent,
        p_expires_at
    );

    RETURN QUERY
    SELECT v_user.id, v_user.full_name, v_user.email;
END;
$function$;


-- 3. Revoke a refresh-token session during logout.
CREATE OR REPLACE FUNCTION app_private.revoke_refresh_token(
    p_refresh_token TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_token_hash TEXT;
BEGIN
    IF p_refresh_token IS NULL
       OR p_refresh_token !~ '^[0-9a-f]{64}$'
    THEN
        RETURN FALSE;
    END IF;

    v_token_hash := encode(
        public.digest(p_refresh_token, 'sha256'),
        'hex'
    );

    UPDATE public.refresh_token_sessions
    SET revoked_at = statement_timestamp()
    WHERE token_hash = v_token_hash
      AND revoked_at IS NULL;

    RETURN FOUND;
END;
$function$;


-- Assign ownership to the restricted security role.
ALTER FUNCTION app_private.create_authenticated_session(
    TEXT, TEXT, TEXT, INET, TEXT, TIMESTAMPTZ
) OWNER TO classroom_security_owner;

ALTER FUNCTION app_private.rotate_refresh_token(
    TEXT, TEXT, INET, TEXT, TIMESTAMPTZ
) OWNER TO classroom_security_owner;

ALTER FUNCTION app_private.revoke_refresh_token(TEXT)
OWNER TO classroom_security_owner;


-- Remove default PUBLIC execution and grant only to the application role.
REVOKE ALL ON FUNCTION app_private.create_authenticated_session(
    TEXT, TEXT, TEXT, INET, TEXT, TIMESTAMPTZ
) FROM PUBLIC;

REVOKE ALL ON FUNCTION app_private.rotate_refresh_token(
    TEXT, TEXT, INET, TEXT, TIMESTAMPTZ
) FROM PUBLIC;

REVOKE ALL ON FUNCTION app_private.revoke_refresh_token(TEXT)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION app_private.create_authenticated_session(
    TEXT, TEXT, TEXT, INET, TEXT, TIMESTAMPTZ
) TO classroom_app;

GRANT EXECUTE ON FUNCTION app_private.rotate_refresh_token(
    TEXT, TEXT, INET, TEXT, TIMESTAMPTZ
) TO classroom_app;

GRANT EXECUTE ON FUNCTION app_private.revoke_refresh_token(TEXT)
TO classroom_app;

REVOKE CREATE ON SCHEMA app_private FROM classroom_security_owner;

COMMIT;
