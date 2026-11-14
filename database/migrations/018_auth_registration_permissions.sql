
BEGIN;

-- ============================================================
-- MIGRATION 018: AUTH REGISTRATION PERMISSIONS
-- Purpose: Allow classroom_app to register users safely.
-- ============================================================

-- USERS: remove existing application privileges first.
REVOKE ALL PRIVILEGES ON TABLE public.users
FROM classroom_app;

REVOKE ALL PRIVILEGES ON TABLE public.users
FROM PUBLIC;

-- Allow registration to insert only the required columns.
GRANT INSERT (
    full_name,
    email,
    password_hash
)
ON TABLE public.users
TO classroom_app;

-- Allow registration to return only safe profile fields.
GRANT SELECT (
    id,
    full_name,
    email,
    account_status,
    created_at
)
ON TABLE public.users
TO classroom_app;


-- EMAIL VERIFICATION TOKENS:
-- The application may create hashed verification tokens.
-- It cannot read, update or delete token records directly.

REVOKE ALL PRIVILEGES
ON TABLE public.email_verification_tokens
FROM classroom_app;

REVOKE ALL PRIVILEGES
ON TABLE public.email_verification_tokens
FROM PUBLIC;

GRANT INSERT (
    user_id,
    token_hash,
    expires_at
)
ON TABLE public.email_verification_tokens
TO classroom_app;

COMMIT;
