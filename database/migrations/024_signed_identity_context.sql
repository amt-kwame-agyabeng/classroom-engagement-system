-- ============================================================
-- CORRECTED DRAFT: SIGNED DATABASE IDENTITY CONTEXT
-- SECTION 1: Signing keys and identity-token verification
--
-- NOT READY FOR EXECUTION.
-- Review and complete all sections before applying.
-- ============================================================

BEGIN;

-- Temporary permission required for object ownership transfers.
GRANT CREATE ON SCHEMA app_private TO classroom_security_owner;

-- 1. Store signing keys separately from application credentials.
CREATE TABLE app_private.identity_signing_keys (
    key_id       text PRIMARY KEY,
    secret       bytea NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    expires_at   timestamptz,
    is_active    boolean NOT NULL DEFAULT true,

    CONSTRAINT identity_signing_keys_id_format
        CHECK (key_id ~ '^[A-Za-z0-9_-]{1,32}$'),

    CONSTRAINT identity_signing_keys_secret_length
        CHECK (octet_length(secret) >= 32)
);

ALTER TABLE app_private.identity_signing_keys
    OWNER TO classroom_security_owner;

REVOKE ALL ON TABLE app_private.identity_signing_keys
    FROM PUBLIC, classroom_app;

-- Only the security owner can read signing keys.
GRANT SELECT ON TABLE app_private.identity_signing_keys
    TO classroom_security_owner;


-- 2. Verify a short-lived signed identity token.
--
-- Token format:
-- payload.signature
--
-- Payload fields:
-- v1|key_id|user_uuid|university_uuid_or_dash|issued_at|expires_at|nonce_uuid
--
-- The application signs the payload using HMAC-SHA256.
-- This function verifies the signature and returns identity claims.
-- It does NOT establish that the user has a particular role.

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
    v_separator_position integer;
    v_payload text;
    v_signature text;
    v_fields text[];
    v_key_id text;
    v_user_id uuid;
    v_university_id uuid;
    v_issued_at bigint;
    v_expires_at bigint;
    v_now_epoch bigint;
    v_secret bytea;
    v_expected_signature text;
BEGIN
    -- Reject missing, oversized or malformed tokens.
    IF p_token IS NULL
       OR length(p_token) = 0
       OR length(p_token) > 1024 THEN
        RETURN;
    END IF;

    v_separator_position := position('.' IN p_token);

    IF v_separator_position < 2
       OR position('.' IN substring(p_token FROM v_separator_position + 1)) > 0 THEN
        RETURN;
    END IF;

    v_payload := substring(p_token FROM 1 FOR v_separator_position - 1);
    v_signature := substring(p_token FROM v_separator_position + 1);

    IF v_signature !~ '^[0-9a-f]{64}$' THEN
        RETURN;
    END IF;

    v_fields := string_to_array(v_payload, '|');

    IF array_length(v_fields, 1) <> 7 THEN
        RETURN;
    END IF;

    IF v_fields[1] <> 'v1'
       OR v_fields[2] !~ '^[A-Za-z0-9_-]{1,32}$'
       OR v_fields[3] !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       OR v_fields[5] !~ '^[0-9]{10,12}$'
       OR v_fields[6] !~ '^[0-9]{10,12}$'
       OR v_fields[7] !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN;
    END IF;

    IF v_fields[4] <> '-'
       AND v_fields[4] !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN;
    END IF;

    v_key_id := v_fields[2];
    v_user_id := v_fields[3]::uuid;
    v_university_id :=
        CASE
            WHEN v_fields[4] = '-' THEN NULL
            ELSE v_fields[4]::uuid
        END;

    v_issued_at := v_fields[5]::bigint;
    v_expires_at := v_fields[6]::bigint;
    v_now_epoch := floor(extract(epoch FROM now()))::bigint;

    -- Enforce a maximum token lifetime of 120 seconds.
    -- Allow 30 seconds of clock skew.
    IF v_expires_at <= v_issued_at
       OR v_expires_at - v_issued_at > 120
       OR v_issued_at > v_now_epoch + 30
       OR v_expires_at <= v_now_epoch - 30 THEN
        RETURN;
    END IF;

    -- Retrieve only an active, non-expired signing key.
    SELECT k.secret
      INTO v_secret
      FROM app_private.identity_signing_keys AS k
     WHERE k.key_id = v_key_id
       AND k.is_active = true
       AND (k.expires_at IS NULL OR k.expires_at > now());

    IF v_secret IS NULL THEN
        RETURN;
    END IF;

    -- Verify the HMAC-SHA256 signature.
    v_expected_signature :=
        encode(
            public.hmac(
                convert_to(v_payload, 'UTF8'),
                v_secret,
                'sha256'
            ),
            'hex'
        );

    -- Note: PostgreSQL text equality is not documented as a
    -- constant-time comparison. Do not treat this as a guarantee
    -- against timing side channels.

    IF v_signature <> v_expected_signature THEN
        RETURN;
    END IF;

    RETURN QUERY
        SELECT v_user_id, v_university_id;

    RETURN;
END;
$function$;

ALTER FUNCTION app_private.verify_identity_token(text)
    OWNER TO classroom_security_owner;

REVOKE ALL ON FUNCTION app_private.verify_identity_token(text)
    FROM PUBLIC, classroom_app;



-- ============================================================
-- SECTION 2: Trusted identity helper functions
-- ============================================================

-- Read the user identity only from a verified signed token.
-- Also require an active account and verified email.

CREATE OR REPLACE FUNCTION app_private.current_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT verified.verified_user_id
    FROM app_private.verify_identity_token(
        pg_catalog.current_setting('app.identity_token', true)
    ) AS verified
    JOIN public.users AS u
      ON u.id = verified.verified_user_id
    WHERE u.account_status = 'active'
      AND u.email_verified_at IS NOT NULL
    LIMIT 1;
$function$;

ALTER FUNCTION app_private.current_user_id()
    OWNER TO classroom_security_owner;


-- Read the university context only from a verified signed token.
-- A university context is valid only while that university is active.

CREATE OR REPLACE FUNCTION app_private.current_university_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT verified.verified_university_id
    FROM app_private.verify_identity_token(
        pg_catalog.current_setting('app.identity_token', true)
    ) AS verified
    JOIN public.users AS u
      ON u.id = verified.verified_user_id
    JOIN public.universities AS university
      ON university.id = verified.verified_university_id
    WHERE u.account_status = 'active'
      AND u.email_verified_at IS NOT NULL
      AND university.status = 'active'
      AND (
          EXISTS (
              SELECT 1
              FROM public.university_memberships AS membership
              WHERE membership.user_id = verified.verified_user_id
                AND membership.university_id = verified.verified_university_id
                AND membership.membership_status = 'active'
                AND membership.deactivated_at IS NULL
          )
          OR EXISTS (
              SELECT 1
              FROM public.role_assignments AS assignment
              WHERE assignment.user_id = verified.verified_user_id
                AND assignment.role = 'platform_admin'
                AND assignment.university_id IS NULL
                AND assignment.department_id IS NULL
                AND assignment.is_active = true
                AND assignment.revoked_at IS NULL
          )
      )
    LIMIT 1;
$function$;

ALTER FUNCTION app_private.current_university_id()
    OWNER TO classroom_security_owner;


-- Application code may call these helpers, but cannot directly
-- execute the underlying token verifier.

REVOKE ALL ON FUNCTION app_private.current_user_id()
    FROM PUBLIC;

REVOKE ALL ON FUNCTION app_private.current_university_id()
    FROM PUBLIC;

GRANT EXECUTE ON FUNCTION app_private.current_user_id()
    TO classroom_app;

GRANT EXECUTE ON FUNCTION app_private.current_university_id()
    TO classroom_app;

-- The application must not be able to create objects in app_private.
REVOKE CREATE ON SCHEMA app_private FROM classroom_app;



-- ============================================================
-- SECTION 3: Database-backed role authorization
-- ============================================================

-- Replace broad role_assignments access with the exact columns
-- required by authentication and authorization functions.

REVOKE SELECT ON TABLE public.role_assignments
    FROM classroom_security_owner;

REVOKE SELECT (
    assigned_by,
    created_at,
    department_id,
    id,
    is_active,
    revoked_at,
    role,
    university_id,
    user_id
) ON TABLE public.role_assignments
    FROM classroom_security_owner;

GRANT SELECT (
    user_id,
    role,
    university_id,
    department_id,
    is_active,
    revoked_at
) ON TABLE public.role_assignments
    TO classroom_security_owner;


-- Ensure the security owner can check whether a membership
-- has been deactivated, not merely whether its status is active.

GRANT SELECT (deactivated_at)
    ON TABLE public.university_memberships
    TO classroom_security_owner;


-- Check an ordinary university role against the signed identity,
-- active university membership and current role assignment.

CREATE OR REPLACE FUNCTION app_private.has_university_role(
    p_role text,
    p_university_id uuid,
    p_department_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.university_memberships AS um
        JOIN public.role_assignments AS ra
          ON ra.user_id = um.user_id
         AND ra.university_id = um.university_id
        WHERE um.user_id = app_private.current_user_id()
          AND um.university_id = p_university_id
          AND um.membership_status = 'active'
          AND um.deactivated_at IS NULL
          AND p_university_id = app_private.current_university_id()
          AND p_role IN (
              'university_admin',
              'department_admin',
              'lecturer',
              'student'
          )
          AND ra.role = p_role
          AND ra.is_active = true
          AND ra.revoked_at IS NULL
          AND (
              (
                  p_role = 'department_admin'
                  AND p_department_id IS NOT NULL
                  AND ra.department_id = p_department_id
              )
              OR
              (
                  p_role <> 'department_admin'
                  AND p_department_id IS NULL
                  AND ra.department_id IS NULL
              )
          )
    );
$function$;

ALTER FUNCTION app_private.has_university_role(text, uuid, uuid)
    OWNER TO classroom_security_owner;


-- Platform administration is global and does not require
-- a university membership.

CREATE OR REPLACE FUNCTION app_private.is_platform_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT EXISTS (
        SELECT 1
        FROM public.role_assignments AS ra
        WHERE ra.user_id = app_private.current_user_id()
          AND ra.role = 'platform_admin'
          AND ra.university_id IS NULL
          AND ra.department_id IS NULL
          AND ra.is_active = true
          AND ra.revoked_at IS NULL
    );
$function$;

ALTER FUNCTION app_private.is_platform_admin()
    OWNER TO classroom_security_owner;


REVOKE ALL ON FUNCTION app_private.has_university_role(text, uuid, uuid)
    FROM PUBLIC;

REVOKE ALL ON FUNCTION app_private.is_platform_admin()
    FROM PUBLIC;

GRANT EXECUTE ON FUNCTION app_private.has_university_role(text, uuid, uuid)
    TO classroom_app;

GRANT EXECUTE ON FUNCTION app_private.is_platform_admin()
    TO classroom_app;



-- ============================================================
-- SECTION 4: Strengthened class-access authorization
-- ============================================================

-- Department administrators must hold an active assignment
-- for the department that owns the requested course offering.

CREATE OR REPLACE FUNCTION app_private.can_access_class_as_department_admin(
    p_course_offering_id uuid,
    p_university_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT
        p_course_offering_id IS NOT NULL
        AND p_university_id IS NOT NULL
        AND p_university_id = app_private.current_university_id()
        AND app_private.current_user_id() IS NOT NULL
        AND EXISTS (
            SELECT 1
            FROM public.course_offerings AS co
            JOIN public.academic_courses AS ac
              ON ac.id = co.academic_course_id
             AND ac.university_id = co.university_id
            WHERE co.id = p_course_offering_id
              AND co.university_id = p_university_id
              AND ac.department_id IS NOT NULL
              AND app_private.has_university_role(
                  'department_admin',
                  p_university_id,
                  ac.department_id
              )
        );
$function$;

ALTER FUNCTION app_private.can_access_class_as_department_admin(uuid, uuid)
    OWNER TO classroom_security_owner;


-- Lecturers must have an active role, active membership
-- and an active assignment to the requested class.

CREATE OR REPLACE FUNCTION app_private.can_access_class_as_lecturer(
    p_class_section_id uuid,
    p_university_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT
        p_class_section_id IS NOT NULL
        AND p_university_id IS NOT NULL
        AND p_university_id = app_private.current_university_id()
        AND app_private.current_user_id() IS NOT NULL
        AND app_private.has_university_role(
            'lecturer',
            p_university_id,
            NULL::uuid
        )
        AND EXISTS (
            SELECT 1
            FROM public.class_section_lecturers AS csl
            WHERE csl.university_id = p_university_id
              AND csl.class_section_id = p_class_section_id
              AND csl.lecturer_user_id = app_private.current_user_id()
              AND csl.is_active = true
              AND csl.ended_at IS NULL
        );
$function$;

ALTER FUNCTION app_private.can_access_class_as_lecturer(uuid, uuid)
    OWNER TO classroom_security_owner;


-- Students must have an active role, active membership
-- and active enrolment in the requested class.

CREATE OR REPLACE FUNCTION app_private.can_access_class_as_student(
    p_class_section_id uuid,
    p_university_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog
AS $function$
    SELECT
        p_class_section_id IS NOT NULL
        AND p_university_id IS NOT NULL
        AND p_university_id = app_private.current_university_id()
        AND app_private.current_user_id() IS NOT NULL
        AND app_private.has_university_role(
            'student',
            p_university_id,
            NULL::uuid
        )
        AND EXISTS (
            SELECT 1
            FROM public.class_enrollments AS ce
            WHERE ce.university_id = p_university_id
              AND ce.class_section_id = p_class_section_id
              AND ce.student_user_id = app_private.current_user_id()
              AND ce.enrollment_status = 'active'
              AND ce.ended_at IS NULL
        );
$function$;

ALTER FUNCTION app_private.can_access_class_as_student(uuid, uuid)
    OWNER TO classroom_security_owner;



-- ============================================================
-- SECTION 5: Exclude deactivated memberships during login
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.authenticate_user(
    p_email text,
    p_password text
)
RETURNS TABLE (
    user_id uuid,
    full_name character varying,
    email character varying,
    account_status character varying,
    email_verified_at timestamp with time zone,
    roles jsonb,
    memberships jsonb
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

    IF left(v_password_hash, 4) = '$2b$' THEN
        v_hash := '$2a$' || substring(v_password_hash FROM 5);
    ELSIF left(v_password_hash, 4) = '$2a$' THEN
        v_hash := v_password_hash;
    ELSE
        RETURN;
    END IF;

    IF public.crypt(p_password, v_hash) IS DISTINCT FROM v_hash THEN
        RETURN;
    END IF;

    -- Return only currently valid role assignments.
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
                    AND um.deactivated_at IS NULL
                    AND un.status = 'active'
              )
          )
      );

    -- Return only currently active memberships.
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
      AND um.deactivated_at IS NULL
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

ALTER FUNCTION app_private.authenticate_user(text, text)
    OWNER TO classroom_security_owner;

-- Remove temporary schema-creation permission.
REVOKE CREATE ON SCHEMA app_private FROM classroom_security_owner;

COMMIT;
