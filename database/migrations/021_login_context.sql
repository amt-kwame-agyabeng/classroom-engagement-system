
-- ============================================================
-- Migration: 021_login_context.sql
-- Purpose: Secure login-context lookup for the backend.
-- Owner: classroom_security_owner
-- Runtime role: classroom_app
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- 1. Grant minimum column-level SELECT permissions.
-- ------------------------------------------------------------

-- User authentication details.
GRANT SELECT (
    id,
    full_name,
    email,
    password_hash,
    account_status,
    email_verified_at
)
ON public.users
TO classroom_security_owner;

-- Membership information.
GRANT SELECT (
    id,
    user_id,
    university_id,
    student_id,
    membership_status
)
ON public.university_memberships
TO classroom_security_owner;

-- University information needed to verify eligibility.
GRANT SELECT (
    id,
    name,
    status
)
ON public.universities
TO classroom_security_owner;

-- role_assignments already has the required SELECT privileges.
-- refresh_token_sessions is not accessed by this function.

-- ------------------------------------------------------------
-- 2. Temporarily allow the security owner to create the function.
-- ------------------------------------------------------------

GRANT CREATE ON SCHEMA app_private
TO classroom_security_owner;

SET ROLE classroom_security_owner;

-- ------------------------------------------------------------
-- 3. Create the login-context lookup function.
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION app_private.get_login_context(
    p_email TEXT
)
RETURNS TABLE (
    id UUID,
    full_name VARCHAR,
    email VARCHAR,
    password_hash TEXT,
    account_status VARCHAR,
    email_verified_at TIMESTAMPTZ,
    roles JSONB,
    memberships JSONB
)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$

    SELECT
        u.id,
        u.full_name,
        u.email,
        u.password_hash,
        u.account_status,
        u.email_verified_at,

        -- Active roles belonging to this user.
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'role', ra.role,
                        'universityId', ra.university_id,
                        'departmentId', ra.department_id
                    )
                    ORDER BY
                        ra.role,
                        ra.university_id NULLS FIRST,
                        ra.department_id NULLS FIRST
                )
                FROM public.role_assignments ra
                WHERE ra.user_id = u.id
                  AND ra.is_active = TRUE
                  AND (
                      -- Platform administrators have no university scope.
                      (
                          ra.role = 'platform_admin'
                          AND ra.university_id IS NULL
                          AND ra.department_id IS NULL
                      )

                      OR

                      -- University-scoped roles require an active
                      -- membership in an active university.
                      (
                          ra.role <> 'platform_admin'
                          AND ra.university_id IS NOT NULL
                          AND EXISTS (
                              SELECT 1
                              FROM public.university_memberships um
                              JOIN public.universities un
                                ON un.id = um.university_id
                              WHERE um.user_id = u.id
                                AND um.university_id = ra.university_id
                                AND um.membership_status = 'active'
                                AND un.status = 'active'
                          )
                      )
                  )
            ),
            '[]'::jsonb
        ) AS roles,

        -- Active memberships in active universities.
        COALESCE(
            (
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'membershipId', um.id,
                        'universityId', un.id,
                        'universityName', un.name,
                        'studentId', um.student_id
                    )
                    ORDER BY un.name
                )
                FROM public.university_memberships um
                JOIN public.universities un
                  ON un.id = um.university_id
                WHERE um.user_id = u.id
                  AND um.membership_status = 'active'
                  AND un.status = 'active'
            ),
            '[]'::jsonb
        ) AS memberships

    FROM public.users u
    WHERE lower(u.email) = lower(btrim(p_email))
    LIMIT 1;

$function$;

-- ------------------------------------------------------------
-- 4. Restore the normal migration role.
-- ------------------------------------------------------------

RESET ROLE;

-- Remove the temporary schema creation permission.
REVOKE CREATE ON SCHEMA app_private
FROM classroom_security_owner;

-- ------------------------------------------------------------
-- 5. Restrict function execution.
-- ------------------------------------------------------------

REVOKE ALL
ON FUNCTION app_private.get_login_context(TEXT)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION app_private.get_login_context(TEXT)
TO classroom_app;

COMMIT;

-- ============================================================
-- End of migration 021
-- ============================================================
