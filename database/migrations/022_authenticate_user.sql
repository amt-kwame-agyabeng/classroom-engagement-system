BEGIN;

-- Minimum permissions required by the authentication function.
GRANT SELECT (
    id, full_name, email, password_hash, account_status, email_verified_at
) ON public.users TO classroom_security_owner;

GRANT SELECT (
    user_id, role, university_id, department_id, is_active, revoked_at
) ON public.role_assignments TO classroom_security_owner;

GRANT SELECT (
    id, user_id, university_id, student_id, membership_status
) ON public.university_memberships TO classroom_security_owner;

GRANT SELECT (
    id, name, status
) ON public.universities TO classroom_security_owner;

GRANT CREATE ON SCHEMA app_private TO classroom_security_owner;

SET ROLE classroom_security_owner;

CREATE FUNCTION app_private.authenticate_user(
    p_email TEXT,
    p_password TEXT
)
RETURNS TABLE (
    user_id UUID,
    full_name VARCHAR,
    email VARCHAR,
    account_status VARCHAR,
    email_verified_at TIMESTAMPTZ,
    roles JSONB,
    memberships JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
DECLARE
    v_user_id UUID;
    v_full_name VARCHAR;
    v_email VARCHAR;
    v_password_hash TEXT;
    v_hash TEXT;
    v_account_status VARCHAR;
    v_email_verified_at TIMESTAMPTZ;
    v_roles JSONB;
    v_memberships JSONB;
BEGIN
    IF p_email IS NULL OR p_password IS NULL THEN
        RETURN;
    END IF;

    -- Retrieve only the columns this function is permitted to read.
    SELECT
        u.id,
        u.full_name,
        u.email,
        u.password_hash,
        u.account_status,
        u.email_verified_at
    INTO
        v_user_id,
        v_full_name,
        v_email,
        v_password_hash,
        v_account_status,
        v_email_verified_at
    FROM public.users AS u
    WHERE lower(u.email) = lower(btrim(p_email))
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    -- Adapt Node bcrypt's $2b$ prefix for pgcrypto's $2a$ format.
    IF left(v_password_hash, 4) = '$2b$' THEN
        v_hash := '$2a$' || substring(v_password_hash FROM 5);
    ELSIF left(v_password_hash, 4) = '$2a$' THEN
        v_hash := v_password_hash;
    ELSE
        RETURN;
    END IF;

    -- Verify the password without returning the stored hash.
    IF public.crypt(p_password, v_hash) IS DISTINCT FROM v_hash THEN
        RETURN;
    END IF;

    -- Retrieve valid active roles.
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'role', ra.role,
                'universityId', ra.university_id,
                'departmentId', ra.department_id
            )
            ORDER BY
                ra.role,
                ra.university_id NULLS FIRST,
                ra.department_id NULLS FIRST
        ),
        '[]'::jsonb
    )
    INTO v_roles
    FROM public.role_assignments AS ra
    WHERE ra.user_id = v_user_id
      AND ra.is_active = TRUE
      AND ra.revoked_at IS NULL
      AND (
          (
              ra.role = 'platform_admin'
              AND ra.university_id IS NULL
              AND ra.department_id IS NULL
          )
          OR
          (
              ra.role <> 'platform_admin'
              AND ra.university_id IS NOT NULL
              AND EXISTS (
                  SELECT 1
                  FROM public.university_memberships AS um
                  JOIN public.universities AS un
                    ON un.id = um.university_id
                  WHERE um.user_id = v_user_id
                    AND um.university_id = ra.university_id
                    AND um.membership_status = 'active'
                    AND un.status = 'active'
              )
          )
      );

    -- Retrieve active university memberships.
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'membershipId', um.id,
                'universityId', un.id,
                'universityName', un.name,
                'studentId', um.student_id
            )
            ORDER BY un.name
        ),
        '[]'::jsonb
    )
    INTO v_memberships
    FROM public.university_memberships AS um
    JOIN public.universities AS un
      ON un.id = um.university_id
    WHERE um.user_id = v_user_id
      AND um.membership_status = 'active'
      AND un.status = 'active';

    RETURN QUERY
    SELECT
        v_user_id,
        v_full_name,
        v_email,
        v_account_status,
        v_email_verified_at,
        v_roles,
        v_memberships;
END;
$function$;

RESET ROLE;

REVOKE CREATE ON SCHEMA app_private FROM classroom_security_owner;

REVOKE ALL ON FUNCTION
    app_private.authenticate_user(TEXT, TEXT)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
    app_private.authenticate_user(TEXT, TEXT)
TO classroom_app;

-- Remove the old function that exposed password hashes.
DROP FUNCTION app_private.get_login_context(TEXT);

COMMIT;
