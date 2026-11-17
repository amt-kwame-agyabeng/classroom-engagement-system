BEGIN;

-- Prevent duplicate applications for the same institution and country.
CREATE UNIQUE INDEX IF NOT EXISTS university_requests_active_institution_unique_idx
ON public.university_requests (
    lower(trim(institution_name)),
    lower(trim(country))
)
WHERE status IN ('pending', 'under_review', 'approved');

-- Grant only the columns required by the submission function.
GRANT INSERT (
    institution_name,
    website,
    country,
    representative_name,
    representative_email,
    proposed_admin_name,
    proposed_admin_email
)
ON public.university_requests
TO classroom_security_owner;

-- INSERT ... RETURNING requires SELECT on returned columns.
GRANT SELECT (id, status)
ON public.university_requests
TO classroom_security_owner;

GRANT CREATE ON SCHEMA app_private
TO classroom_security_owner;

SET ROLE classroom_security_owner;

CREATE OR REPLACE FUNCTION app_private.submit_university_application(
    p_institution_name TEXT,
    p_website TEXT,
    p_country TEXT,
    p_representative_name TEXT,
    p_representative_email TEXT,
    p_proposed_admin_name TEXT,
    p_proposed_admin_email TEXT
)
RETURNS TABLE (
    request_id UUID,
    request_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_institution_name TEXT;
    v_website TEXT;
    v_country TEXT;
    v_representative_name TEXT;
    v_representative_email TEXT;
    v_proposed_admin_name TEXT;
    v_proposed_admin_email TEXT;
BEGIN
    v_institution_name := trim(p_institution_name);
    v_website := NULLIF(trim(p_website), '');
    v_country := trim(p_country);
    v_representative_name := trim(p_representative_name);
    v_representative_email := lower(trim(p_representative_email));
    v_proposed_admin_name := trim(p_proposed_admin_name);
    v_proposed_admin_email := lower(trim(p_proposed_admin_email));

    -- Validate required fields.
    IF v_institution_name IS NULL OR v_institution_name = ''
       OR v_country IS NULL OR v_country = ''
       OR v_representative_name IS NULL OR v_representative_name = ''
       OR v_representative_email IS NULL OR v_representative_email = ''
       OR v_proposed_admin_name IS NULL OR v_proposed_admin_name = ''
       OR v_proposed_admin_email IS NULL OR v_proposed_admin_email = ''
    THEN
        RAISE EXCEPTION 'All required application fields must be provided.'
            USING ERRCODE = '22023';
    END IF;

    -- Validate field lengths.
    IF length(v_institution_name) > 255
       OR length(v_website) > 255
       OR length(v_country) > 100
       OR length(v_representative_name) > 150
       OR length(v_representative_email) > 255
       OR length(v_proposed_admin_name) > 150
       OR length(v_proposed_admin_email) > 255
    THEN
        RAISE EXCEPTION 'One or more application fields exceed the allowed length.'
            USING ERRCODE = '22023';
    END IF;

    -- Basic database-level email validation.
    IF v_representative_email !~
       '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
       OR v_proposed_admin_email !~
       '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    THEN
        RAISE EXCEPTION 'Valid representative and proposed administrator emails are required.'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    INSERT INTO public.university_requests AS ur (
        institution_name,
        website,
        country,
        representative_name,
        representative_email,
        proposed_admin_name,
        proposed_admin_email
    )
    VALUES (
        v_institution_name,
        v_website,
        v_country,
        v_representative_name,
        v_representative_email,
        v_proposed_admin_name,
        v_proposed_admin_email
    )
    RETURNING ur.id, ur.status::TEXT;
END;
$$;

-- Restrict execution to the backend application role.
REVOKE ALL ON FUNCTION
    app_private.submit_university_application(
        TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT
    )
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
    app_private.submit_university_application(
        TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT
    )
TO classroom_app;

RESET ROLE;

REVOKE CREATE ON SCHEMA app_private
FROM classroom_security_owner;

COMMIT;
