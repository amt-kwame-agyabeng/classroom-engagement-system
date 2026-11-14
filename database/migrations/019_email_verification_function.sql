BEGIN;

-- ============================================================
-- MIGRATION 019: EMAIL VERIFICATION FUNCTION
-- Purpose: Securely verify email addresses and activate accounts.
-- ============================================================

-- 1. Grant minimum required column privileges.

GRANT SELECT (
    token_hash,
    user_id,
    expires_at,
    used_at
)
ON TABLE public.email_verification_tokens
TO classroom_security_owner;

GRANT UPDATE (used_at)
ON TABLE public.email_verification_tokens
TO classroom_security_owner;

GRANT SELECT (
    id,
    account_status
)
ON TABLE public.users
TO classroom_security_owner;

GRANT UPDATE (
    account_status,
    email_verified_at
)
ON TABLE public.users
TO classroom_security_owner;


-- 2. Temporarily allow the security owner to create
--    its function inside app_private.

GRANT CREATE ON SCHEMA app_private
TO classroom_security_owner;

SET ROLE classroom_security_owner;


-- 3. Create the verification function.

CREATE FUNCTION app_private.verify_email_token(
    p_token_hash TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $function$
DECLARE
    v_user_id UUID;
BEGIN

    -- Validate the SHA-256 hash format.
    IF p_token_hash IS NULL
       OR p_token_hash !~ '^[0-9a-f]{64}$'
    THEN
        RETURN FALSE;
    END IF;

    -- Find and lock a valid, unused token.
    SELECT t.user_id
    INTO v_user_id
    FROM public.email_verification_tokens AS t
    WHERE t.token_hash = p_token_hash
      AND t.used_at IS NULL
      AND t.expires_at > pg_catalog.now()
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Activate only a pending account.
    UPDATE public.users
    SET
        account_status = 'active',
        email_verified_at = pg_catalog.now()
    WHERE id = v_user_id
      AND account_status = 'pending';

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    -- Consume the verification token.
    UPDATE public.email_verification_tokens
    SET used_at = pg_catalog.now()
    WHERE token_hash = p_token_hash
      AND used_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Token consumption failed';
    END IF;

    RETURN TRUE;

END;
$function$;

RESET ROLE;


-- 4. Remove temporary schema creation permission.

REVOKE CREATE ON SCHEMA app_private
FROM classroom_security_owner;


-- 5. Restrict function execution.

REVOKE ALL ON FUNCTION app_private.verify_email_token(TEXT)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION app_private.verify_email_token(TEXT)
TO classroom_app;

COMMIT;
