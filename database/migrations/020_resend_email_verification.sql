BEGIN;

GRANT INSERT (user_id, token_hash, expires_at)
ON public.email_verification_tokens
TO classroom_security_owner;

GRANT SELECT (id, email, account_status)
ON public.users
TO classroom_security_owner;

GRANT SELECT (id, user_id, token_hash, expires_at, used_at, created_at)
ON public.email_verification_tokens
TO classroom_security_owner;

GRANT UPDATE (used_at)
ON public.email_verification_tokens
TO classroom_security_owner;

GRANT CREATE ON SCHEMA app_private
TO classroom_security_owner;

SET ROLE classroom_security_owner;

CREATE OR REPLACE FUNCTION app_private.create_email_verification_token(
    p_email TEXT
)
RETURNS TABLE (
    user_id UUID,
    recipient_email TEXT,
    verification_token TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_user_id UUID;
    v_email TEXT;
    v_status TEXT;
    v_token TEXT;
    v_token_hash TEXT;
BEGIN
    SELECT u.id, u.email, u.account_status
    INTO v_user_id, v_email, v_status
    FROM public.users u
    WHERE lower(u.email) = lower(trim(p_email))
    FOR UPDATE;

    IF NOT FOUND OR v_status <> 'pending' THEN
        RETURN;
    END IF;

    v_token := encode(public.gen_random_bytes(32), 'hex');

    v_token_hash := encode(
        public.digest(v_token, 'sha256'),
        'hex'
    );

    INSERT INTO public.email_verification_tokens (
        user_id,
        token_hash,
        expires_at
    )
    VALUES (
        v_user_id,
        v_token_hash,
        now() + interval '24 hours'
    );

    RETURN QUERY
    SELECT v_user_id, v_email, v_token;
END;
$$;

CREATE OR REPLACE FUNCTION app_private.finalize_email_verification_resend(
    p_user_id UUID,
    p_token_hash TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_latest_token_hash TEXT;
BEGIN
    -- Serialize finalization requests for this account.
    PERFORM 1
    FROM public.users u
    WHERE u.id = p_user_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Confirm that the supplied token is the newest valid token.
    SELECT t.token_hash
    INTO v_latest_token_hash
    FROM public.email_verification_tokens t
    WHERE t.user_id = p_user_id
      AND t.used_at IS NULL
      AND t.expires_at > now()
    ORDER BY t.created_at DESC, t.id DESC
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND OR v_latest_token_hash <> p_token_hash THEN
        RETURN FALSE;
    END IF;

    -- Invalidate every other unused token.
    UPDATE public.email_verification_tokens t
    SET used_at = now()
    WHERE t.user_id = p_user_id
      AND t.token_hash <> p_token_hash
      AND t.used_at IS NULL;

    RETURN TRUE;
END;
$$;
-- Restrict execution to the backend application role.
REVOKE ALL ON FUNCTION
    app_private.create_email_verification_token(TEXT)
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    app_private.finalize_email_verification_resend(UUID, TEXT)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
    app_private.create_email_verification_token(TEXT)
TO classroom_app;

GRANT EXECUTE ON FUNCTION
    app_private.finalize_email_verification_resend(UUID, TEXT)
TO classroom_app;

RESET ROLE;

-- Remove temporary function-creation permission.
REVOKE CREATE ON SCHEMA app_private
FROM classroom_security_owner;

COMMIT;
