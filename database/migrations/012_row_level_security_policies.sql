BEGIN;

-- ============================================================
-- MIGRATION 012: ROW-LEVEL SECURITY POLICIES
-- ============================================================
--
-- Purpose:
-- Enforce database-level access isolation across universities,
-- users, academic structures, classes and classroom activities.
--
-- Security principles:
-- 1. Users must only access authorised university data.
-- 2. Role checks must use the security helper functions.
-- 3. Class access must respect lecturer assignments and enrolments.
-- 4. Sensitive records must receive additional restrictions.
-- 5. Anonymous identities must never be exposed through ordinary
--    application queries.
-- 6. Backend authorization remains mandatory; RLS is an
--    additional database security layer.
--
-- This migration will be applied transactionally.
-- ============================================================


-- POLICY SECTIONS WILL BE ADDED BELOW.
-- ============================================================
-- SECTION 1: SUPPORTING ACCESS FOR CLASS AUTHORIZATION HELPERS
-- ============================================================

-- Allow the non-login security owner to evaluate the transaction
-- context used by the authorization helper functions.
GRANT EXECUTE ON FUNCTION app_private.current_user_id()
TO classroom_security_owner;

GRANT EXECUTE ON FUNCTION app_private.current_university_id()
TO classroom_security_owner;


-- Grant only the columns required by the authorization helpers.

GRANT SELECT (
    university_id,
    user_id,
    membership_status
)
ON public.university_memberships
TO classroom_security_owner;


GRANT SELECT (
    university_id,
    class_section_id,
    lecturer_user_id,
    is_active,
    ended_at
)
ON public.class_section_lecturers
TO classroom_security_owner;


GRANT SELECT (
    university_id,
    class_section_id,
    student_user_id,
    enrollment_status,
    ended_at
)
ON public.class_enrollments
TO classroom_security_owner;


-- ============================================================
-- SECTION 2: RESTRICTED SECURITY-OWNER POLICIES
-- ============================================================

-- These policies apply only to classroom_security_owner.
-- Access is restricted to the current university context.

CREATE POLICY university_memberships_security_helper_read
ON public.university_memberships
FOR SELECT
TO classroom_security_owner
USING (
    university_id = app_private.current_university_id()
);


CREATE POLICY class_section_lecturers_security_helper_read
ON public.class_section_lecturers
FOR SELECT
TO classroom_security_owner
USING (
    university_id = app_private.current_university_id()
);


CREATE POLICY class_enrollments_security_helper_read
ON public.class_enrollments
FOR SELECT
TO classroom_security_owner
USING (
    university_id = app_private.current_university_id()
);

-- ============================================================
-- SECTION 3: CLASS AUTHORIZATION HELPER FUNCTIONS
-- ============================================================

-- Allow the restricted security owner to call the existing
-- university-role verification helper.
GRANT EXECUTE ON FUNCTION app_private.has_university_role(
    text, uuid, uuid
)
TO classroom_security_owner;


-- Temporarily permit function creation in the private schema.
GRANT CREATE ON SCHEMA app_private TO classroom_security_owner;


-- ------------------------------------------------------------
-- 3.1 Lecturer class access
-- ------------------------------------------------------------

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
            FROM public.university_memberships AS um
            WHERE um.university_id = p_university_id
              AND um.user_id = app_private.current_user_id()
              AND um.membership_status = 'active'
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


-- ------------------------------------------------------------
-- 3.2 Student class access
-- ------------------------------------------------------------

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
            FROM public.university_memberships AS um
            WHERE um.university_id = p_university_id
              AND um.user_id = app_private.current_user_id()
              AND um.membership_status = 'active'
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


-- Transfer function ownership to the restricted non-login role.
ALTER FUNCTION app_private.can_access_class_as_lecturer(uuid, uuid)
OWNER TO classroom_security_owner;

ALTER FUNCTION app_private.can_access_class_as_student(uuid, uuid)
OWNER TO classroom_security_owner;


-- Functions must not be publicly executable.
REVOKE ALL ON FUNCTION
    app_private.can_access_class_as_lecturer(uuid, uuid)
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    app_private.can_access_class_as_student(uuid, uuid)
FROM PUBLIC;


-- Permit the application role to use the authorization helpers.
GRANT EXECUTE ON FUNCTION
    app_private.can_access_class_as_lecturer(uuid, uuid)
TO classroom_app;

GRANT EXECUTE ON FUNCTION
    app_private.can_access_class_as_student(uuid, uuid)
TO classroom_app;


-- ============================================================
-- SECTION 4: DEPARTMENT AUTHORIZATION SUPPORT
-- ============================================================

-- Grant only the columns required to identify a course's
-- department through its course offering.

GRANT SELECT (
    id,
    university_id,
    academic_course_id
)
ON public.course_offerings
TO classroom_security_owner;


GRANT SELECT (
    id,
    university_id,
    department_id
)
ON public.academic_courses
TO classroom_security_owner;


-- Restrict security-owner reads to the active university context.

CREATE POLICY course_offerings_security_helper_read
ON public.course_offerings
FOR SELECT
TO classroom_security_owner
USING (
    university_id = app_private.current_university_id()
);


CREATE POLICY academic_courses_security_helper_read
ON public.academic_courses
FOR SELECT
TO classroom_security_owner
USING (
    university_id = app_private.current_university_id()
);

-- ============================================================
-- SECTION 5: DEPARTMENT ADMIN CLASS AUTHORIZATION
-- ============================================================

CREATE OR REPLACE FUNCTION
    app_private.can_access_class_as_department_admin(
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

        -- Require the active university context.
        AND p_university_id = app_private.current_university_id()

        -- Require an authenticated user context.
        AND app_private.current_user_id() IS NOT NULL

        -- Require an active university membership.
        AND EXISTS (
            SELECT 1
            FROM public.university_memberships AS um
            WHERE um.university_id = p_university_id
              AND um.user_id = app_private.current_user_id()
              AND um.membership_status = 'active'
        )

        -- Derive the department from the actual course offering.
        AND EXISTS (
            SELECT 1
            FROM public.course_offerings AS co
            JOIN public.academic_courses AS ac
              ON ac.id = co.academic_course_id
             AND ac.university_id = co.university_id
            WHERE co.id = p_course_offering_id
              AND co.university_id = p_university_id
              AND ac.department_id IS NOT NULL

              -- Verify the user's exact department assignment.
              AND app_private.has_university_role(
                  'department_admin',
                  p_university_id,
                  ac.department_id
              )
        );

$function$;


-- Transfer ownership to the restricted non-login security role.
ALTER FUNCTION
    app_private.can_access_class_as_department_admin(uuid, uuid)
OWNER TO classroom_security_owner;

-- Remove temporary schema creation permission.
REVOKE CREATE ON SCHEMA app_private FROM classroom_security_owner;

-- Prevent public execution.
REVOKE ALL ON FUNCTION
    app_private.can_access_class_as_department_admin(uuid, uuid)
FROM PUBLIC;


-- Allow the application role to use the helper.
GRANT EXECUTE ON FUNCTION
    app_private.can_access_class_as_department_admin(uuid, uuid)
TO classroom_app;

COMMIT;