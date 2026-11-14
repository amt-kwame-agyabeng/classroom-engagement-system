BEGIN;

-- ============================================================
-- MIGRATION 013: CLASS SECTIONS ACCESS POLICIES
-- ============================================================

-- Allow authorised users to read class sections.
CREATE POLICY class_sections_select_policy
ON public.class_sections
FOR SELECT
TO classroom_app
USING (
    -- Platform administrators can access all universities.
    app_private.is_platform_admin()

    OR

    -- All other roles must match the active university context.
    (
        university_id = app_private.current_university_id()
        AND
        (
            -- University administrators.
            app_private.has_university_role(
                'university_admin',
                university_id
            )

            OR

            -- Department administrators.
            app_private.can_access_class_as_department_admin(
                course_offering_id,
                university_id
            )

            OR

            -- Assigned lecturers.
            app_private.can_access_class_as_lecturer(
                id,
                university_id
            )

            OR

            -- Actively enrolled students.
            app_private.can_access_class_as_student(
                id,
                university_id
            )
        )
    )
);

COMMIT;