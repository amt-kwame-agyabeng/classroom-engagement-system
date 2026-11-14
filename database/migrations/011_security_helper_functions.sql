
BEGIN;

-- Private schema for security helper functions.
CREATE SCHEMA IF NOT EXISTS app_private
    AUTHORIZATION classroom_admin;

-- Prevent ordinary users from creating or replacing objects
-- in the security helper schema.
REVOKE ALL ON SCHEMA app_private FROM PUBLIC;

GRANT USAGE ON SCHEMA app_private TO classroom_app;


-- Return the authenticated user ID established by the backend.
CREATE OR REPLACE FUNCTION app_private.current_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
PARALLEL SAFE
SET search_path = pg_catalog
AS $$
    SELECT NULLIF(
        pg_catalog.current_setting('app.current_user_id', true),
        ''
    )::uuid;
$$;


-- Return the university scope established by the backend.
CREATE OR REPLACE FUNCTION app_private.current_university_id()
RETURNS uuid
LANGUAGE sql
STABLE
PARALLEL SAFE
SET search_path = pg_catalog
AS $$
    SELECT NULLIF(
        pg_catalog.current_setting('app.current_university_id', true),
        ''
    )::uuid;
$$;


-- Remove default PUBLIC execution permissions.
REVOKE ALL ON FUNCTION app_private.current_user_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION app_private.current_university_id() FROM PUBLIC;

-- Allow the application role to execute these helpers.
GRANT EXECUTE ON FUNCTION app_private.current_user_id()
    TO classroom_app;

GRANT EXECUTE ON FUNCTION app_private.current_university_id()
    TO classroom_app;

COMMENT ON FUNCTION app_private.current_user_id() IS
    'Returns the transaction-local authenticated user UUID established by the backend.';

COMMENT ON FUNCTION app_private.current_university_id() IS
    'Returns the transaction-local university UUID established by the backend.';



-- Check whether the current user has an active role
-- within the requested university and optional department.
CREATE OR REPLACE FUNCTION app_private.has_university_role(
    p_role text,
    p_university_id uuid,
    p_department_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.role_assignments ra
        WHERE ra.user_id = app_private.current_user_id()
          AND ra.role = p_role
          AND ra.university_id = p_university_id
          AND ra.is_active = true
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
$$;

REVOKE ALL ON FUNCTION app_private.has_university_role(
    text, uuid, uuid
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION app_private.has_university_role(
    text, uuid, uuid
) TO classroom_app;

COMMENT ON FUNCTION app_private.has_university_role(
    text, uuid, uuid
) IS
    'Checks for an active university role, optionally scoped to a department.';


-- Check whether the current user has an active platform admin role.
CREATE OR REPLACE FUNCTION app_private.is_platform_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = pg_catalog
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.role_assignments ra
        WHERE ra.user_id = app_private.current_user_id()
          AND ra.role = 'platform_admin'
          AND ra.university_id IS NULL
          AND ra.department_id IS NULL
          AND ra.is_active = true
    );
$$;

REVOKE ALL ON FUNCTION app_private.is_platform_admin() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION app_private.is_platform_admin()
    TO classroom_app;

COMMENT ON FUNCTION app_private.is_platform_admin() IS
    'Checks whether the current user has an active platform administrator role.';

COMMIT;
