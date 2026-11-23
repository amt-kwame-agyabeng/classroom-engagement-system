BEGIN;

-- =========================================================
-- 1. PASSWORD RESET PERMISSIONS
-- =========================================================

-- Allow the security owner to find and validate reset tokens.
GRANT SELECT (
    id,
    user_id,
    token_hash,
    expires_at,
    used_at
)
ON public.password_reset_tokens
TO classroom_security_owner;

-- Allow the security owner to create reset tokens.
GRANT INSERT (
    user_id,
    token_hash,
    expires_at
)
ON public.password_reset_tokens
TO classroom_security_owner;

-- Allow the security owner to consume reset tokens.
GRANT UPDATE (
    used_at
)
ON public.password_reset_tokens
TO classroom_security_owner;

-- Allow removal of previous unused reset tokens.
GRANT DELETE
ON public.password_reset_tokens
TO classroom_security_owner;

-- Allow controlled password updates.
GRANT UPDATE (
    password_hash,
    updated_at
)
ON public.users
TO classroom_security_owner;

-- Allow revocation of existing refresh-token sessions.
-- This permission already exists in migration 023,
-- so we do not need to grant it again.

-- Allow password-reset audit events.
GRANT INSERT (
    actor_user_id,
    event_category,
    event_type,
    resource_type,
    resource_id,
    metadata
)
ON public.audit_logs
TO classroom_security_owner;

-- Allow privileged functions to be created.
GRANT CREATE ON SCHEMA app_private
TO classroom_security_owner;

SET ROLE classroom_security_owner;

-- =========================================================
-- 2. CREATE PASSWORD RESET TOKEN
-- =========================================================

CREATE OR REPLACE FUNCTION app_private.create_password_reset_token(
    p_user_id UUID,
    p_token_hash TEXT,
    p_expires_at TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_token_id UUID;
BEGIN
    IF p_user_id IS NULL
       OR p_token_hash IS NULL
       OR p_token_hash !~ '^[0-9a-f]{64}$'
       OR p_expires_at IS NULL
       OR p_expires_at <= statement_timestamp()

    THEN
        RAISE EXCEPTION 'Invalid password reset token request';
    END IF;

    -- Lock the user row to prevent concurrent reset requests
    -- from creating multiple valid tokens.
    PERFORM 1
    FROM public.users AS u
    WHERE u.id = p_user_id
      AND u.account_status IN ('active', 'pending')
      AND u.email_verified_at IS NOT NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NULL;
    END IF;

    -- Remove previously unused reset tokens for this user.
    DELETE FROM public.password_reset_tokens
    WHERE user_id = p_user_id
      AND used_at IS NULL;

    -- Store only the hashed token.
    INSERT INTO public.password_reset_tokens (
        user_id,
        token_hash,
        expires_at
    )
    VALUES (
        p_user_id,
        p_token_hash,
        p_expires_at
    )
    RETURNING id INTO v_token_id;

    RETURN v_token_id;
END;
$function$;

-- =========================================================
-- 3. COMPLETE PASSWORD RESET
-- =========================================================

CREATE OR REPLACE FUNCTION app_private.complete_password_reset(
    p_token_hash TEXT,
    p_new_password_hash TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_user_id UUID;
    v_token_id UUID;
    v_revoked_sessions INTEGER;
BEGIN
    -- Validate input.
    IF p_token_hash IS NULL
       OR p_token_hash !~ '^[0-9a-f]{64}$'
       OR p_new_password_hash IS NULL
       OR p_new_password_hash !~ '^\$2[aby]\$12\$[./A-Za-z0-9]{53}$'
    THEN
        RETURN FALSE;
    END IF;

    -- Identify the user associated with the reset token.
    SELECT t.user_id
    INTO v_user_id
    FROM public.password_reset_tokens AS t
    WHERE t.token_hash = p_token_hash
      AND t.used_at IS NULL
      AND t.expires_at > statement_timestamp();

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Lock the user first to maintain a consistent lock order.
    PERFORM 1
    FROM public.users AS u
    WHERE u.id = v_user_id
      AND u.account_status IN ('active', 'pending')
      AND u.email_verified_at IS NOT NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Lock and revalidate the reset token.
    SELECT t.id
    INTO v_token_id
    FROM public.password_reset_tokens AS t
    WHERE t.token_hash = p_token_hash
      AND t.user_id = v_user_id
      AND t.used_at IS NULL
      AND t.expires_at > statement_timestamp()
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;



    -- Update the password.
    UPDATE public.users
    SET
        password_hash = p_new_password_hash,
        updated_at = statement_timestamp()
    WHERE id = v_user_id;

    -- Mark the reset token as consumed.
    UPDATE public.password_reset_tokens
    SET used_at = statement_timestamp()
    WHERE id = v_token_id;

    -- Revoke all active refresh-token sessions.
    UPDATE public.refresh_token_sessions
    SET revoked_at = statement_timestamp()
    WHERE user_id = v_user_id
      AND revoked_at IS NULL;

    GET DIAGNOSTICS v_revoked_sessions = ROW_COUNT;

    -- Record the security event.
    INSERT INTO public.audit_logs (
        actor_user_id,
        event_category,
        event_type,
        resource_type,
        resource_id,
        metadata
    )
    VALUES (
        v_user_id,
        'account_security',
        'password_reset_completed',
        'user',
        v_user_id,
        jsonb_build_object(
            'revoked_sessions', v_revoked_sessions
        )
    );

    RETURN TRUE;
END;
$function$;

-- =========================================================
-- 4. FUNCTION OWNERSHIP AND EXECUTION PERMISSIONS
-- =========================================================

ALTER FUNCTION app_private.create_password_reset_token(
    UUID,
    TEXT,
    TIMESTAMPTZ
)
OWNER TO classroom_security_owner;

ALTER FUNCTION app_private.complete_password_reset(
    TEXT,
    TEXT
)
OWNER TO classroom_security_owner;

-- Prevent public execution.
REVOKE ALL ON FUNCTION app_private.create_password_reset_token(
    UUID,
    TEXT,
    TIMESTAMPTZ
)
FROM PUBLIC;

REVOKE ALL ON FUNCTION app_private.complete_password_reset(
    TEXT,
    TEXT
)
FROM PUBLIC;

-- Allow the backend application to execute these functions.
GRANT EXECUTE ON FUNCTION app_private.create_password_reset_token(
    UUID,
    TEXT,
    TIMESTAMPTZ
)
TO classroom_app;

GRANT EXECUTE ON FUNCTION app_private.complete_password_reset(
    TEXT,
    TEXT
)
TO classroom_app;

-- =========================================================
-- 5. MIGRATION CLEANUP
-- =========================================================

RESET ROLE;

REVOKE CREATE ON SCHEMA app_private
FROM classroom_security_owner;

COMMIT;