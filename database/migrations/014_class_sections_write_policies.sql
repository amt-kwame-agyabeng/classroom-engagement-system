BEGIN;

-- ============================================================
-- MIGRATION 014: CLASS SECTIONS WRITE POLICIES
-- ============================================================

-- INSERT: Only authorised administrators can create sections.
CREATE POLICY class_sections_insert_policy
ON public.class_sections
FOR INSERT
TO classroom_app
WITH CHECK (
    -- Every creator must match the authenticated user.
    created_by = app_private.current_user_id()

    AND

    (
        -- Platform administrators.
        app_private.is_platform_admin()

        OR

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
            )
        )
    )
);

-- UPDATE: Administrators can update sections within their scope.
CREATE POLICY class_sections_update_policy
ON public.class_sections
FOR UPDATE
TO classroom_app
USING (
    app_private.is_platform_admin()

    OR

    (
        university_id = app_private.current_university_id()
        AND
        (
            app_private.has_university_role(
                'university_admin',
                university_id
            )

            OR

            app_private.can_access_class_as_department_admin(
                course_offering_id,
                university_id
            )
        )
    )
)
WITH CHECK (
    app_private.is_platform_admin()

    OR

    (
        university_id = app_private.current_university_id()
        AND
        (
            app_private.has_university_role(
                'university_admin',
                university_id
            )

            OR

            app_private.can_access_class_as_department_admin(
                course_offering_id,
                university_id
            )
        )
    )
);

COMMIT;