BEGIN;

-- Replace the user-ID lookup with a secure email-based lookup.
-- Existing SELECT permissions were granted in migration 020.

-- Allow the security owner to verify the account's email status.
GRANT SELECT (email_verified_at)
ON public.users
TO classroom_security_owner;

GRANT CREATE ON SCHEMA app_private
TO classroom_security_owner;

SET ROLE classroom_security_owner;

DROP FUNCTION IF EXISTS app_private.create_password_reset_token(
    UUID,
    TEXT,
    TIMESTAMPTZ
);

CREATE OR REPLACE FUNCTION app_private.create_password_reset_token(
    p_email TEXT,
    p_token_hash TEXT,
    p_expires_at TIMESTAMPTZ
)
RETURNS TABLE (
    user_id UUID,
    recipient_email TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog'
AS $function$
DECLARE
    v_user_id UUID;
    v_email TEXT;
    v_status TEXT;
    v_token_id UUID;
BEGIN
    -- Validate input.
    IF p_email IS NULL
       OR length(trim(p_email)) = 0
       OR p_token_hash IS NULL
       OR p_token_hash !~ '^[0-9a-f]{64}$'
       OR p_expires_at IS NULL
       OR p_expires_at <= statement_timestamp()
    THEN
        RAISE EXCEPTION 'Invalid password reset request';
    END IF;

    -- Find and lock the eligible account.
    SELECT u.id, u.email, u.account_status
    INTO v_user_id, v_email, v_status
    FROM public.users AS u
    WHERE lower(u.email) = lower(trim(p_email))
      AND u.account_status IN ('active', 'pending')
      AND u.email_verified_at IS NOT NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- Invalidate previous unused reset tokens.
    DELETE FROM public.password_reset_tokens
    WHERE password_reset_tokens.user_id = v_user_id
      AND password_reset_tokens.used_at IS NULL;

    -- Store only the token hash.
    INSERT INTO public.password_reset_tokens (
        user_id,
        token_hash,
        expires_at
    )
    VALUES (
        v_user_id,
        p_token_hash,
        p_expires_at
    )
    RETURNING id INTO v_token_id;

    RETURN QUERY
    SELECT v_user_id, v_email;
END;
$function$;

-- Assign the privileged owner.
ALTER FUNCTION app_private.create_password_reset_token(
    TEXT,
    TEXT,
    TIMESTAMPTZ
)
OWNER TO classroom_security_owner;

-- Restrict execution to the backend application.
REVOKE ALL ON FUNCTION app_private.create_password_reset_token(
    TEXT,
    TEXT,
    TIMESTAMPTZ
)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION app_private.create_password_reset_token(
    TEXT,
    TEXT,
    TIMESTAMPTZ
)
TO classroom_app;

RESET ROLE;

-- Remove temporary function-creation permission.
REVOKE CREATE ON SCHEMA app_private
FROM classroom_security_owner;

COMMIT;