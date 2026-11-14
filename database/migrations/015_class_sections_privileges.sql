BEGIN;

-- Allow reading class section records.
GRANT SELECT
ON public.class_sections
TO classroom_app;

-- Allow inserting approved class section fields.
GRANT INSERT (
    university_id,
    course_offering_id,
    section_code,
    section_name,
    status,
    capacity,
    created_by
)
ON public.class_sections
TO classroom_app;

-- Allow updating approved editable fields only.
GRANT UPDATE (
    course_offering_id,
    section_code,
    section_name,
    status,
    capacity,
    updated_at,
    closed_at,
    archived_at
)
ON public.class_sections
TO classroom_app;

COMMIT;