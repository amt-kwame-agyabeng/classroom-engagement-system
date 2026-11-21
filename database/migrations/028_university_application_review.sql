BEGIN;

-- ============================================================
-- Migration 028: University Application Review Workflow
--
-- Supports:
--   1. Listing university applications.
--   2. Marking applications as under review.
--   3. Approving applications and onboarding administrators.
--   4. Rejecting applications.
--
-- All privileged operations will be implemented through
-- SECURITY DEFINER functions owned by classroom_security_owner.
-- ============================================================

-- ------------------------------------------------------------
-- 1. University application permissions
-- ------------------------------------------------------------

GRANT SELECT (
    id,
    university_id,
    institution_name,
    website,
    country,
    representative_name,
    representative_email,
    proposed_admin_name,
    proposed_admin_email,
    status,
    review_notes,
    reviewed_by,
    reviewed_at,
    created_at
)
ON public.university_requests
TO classroom_security_owner;

GRANT UPDATE (
    university_id,
    status,
    reviewed_by,
    reviewed_at,
    review_notes,
    updated_at
)
ON public.university_requests
TO classroom_security_owner;

-- ------------------------------------------------------------
-- 2. University creation permissions
-- ------------------------------------------------------------

GRANT INSERT (
    name,
    website,
    country,
    status,
    approved_at
)
ON public.universities
TO classroom_security_owner;

-- ------------------------------------------------------------
-- 3. University membership permissions
-- ------------------------------------------------------------

GRANT INSERT (
    university_id,
    user_id,
    membership_status,
    joined_at
)
ON public.university_memberships
TO classroom_security_owner;

-- ------------------------------------------------------------
-- 4. Audit logging permissions
-- ------------------------------------------------------------

GRANT INSERT (
    university_id
)
ON public.audit_logs
TO classroom_security_owner;

-- ------------------------------------------------------------
-- 5. Allow controlled function creation
-- ------------------------------------------------------------

GRANT CREATE ON SCHEMA app_private
TO classroom_security_owner;

SET ROLE classroom_security_owner;

-- ============================================================
-- 6. List university applications for Platform Administrators
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.list_university_applications(
    p_status TEXT DEFAULT NULL,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    request_id UUID,
    institution_name VARCHAR(255),
    website VARCHAR(255),
    country VARCHAR(100),
    representative_name VARCHAR(150),
    representative_email VARCHAR(255),
    proposed_admin_name VARCHAR(150),
    proposed_admin_email VARCHAR(255),
    application_status VARCHAR(20),
    review_notes TEXT,
    submitted_at TIMESTAMPTZ,
    reviewed_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
BEGIN
    v_actor_id := app_private.current_user_id();

    IF v_actor_id IS NULL
       OR NOT app_private.is_platform_admin()
    THEN
        RAISE EXCEPTION 'Platform Administrator privileges are required.'
            USING ERRCODE = '42501';
    END IF;

    IF p_status IS NOT NULL
       AND p_status NOT IN (
           'pending',
           'under_review',
           'approved',
           'rejected'
       )
    THEN
        RAISE EXCEPTION 'Invalid university application status.'
            USING ERRCODE = '22023';
    END IF;

    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
        RAISE EXCEPTION 'Limit must be between 1 and 100.'
            USING ERRCODE = '22023';
    END IF;

    IF p_offset IS NULL OR p_offset < 0 THEN
        RAISE EXCEPTION 'Offset cannot be negative.'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT
        ur.id,
        ur.institution_name,
        ur.website,
        ur.country,
        ur.representative_name,
        ur.representative_email,
        ur.proposed_admin_name,
        ur.proposed_admin_email,
        ur.status,
        ur.review_notes,
        ur.created_at,
        ur.reviewed_at
    FROM public.university_requests AS ur
    WHERE p_status IS NULL
       OR ur.status::TEXT = p_status
    ORDER BY ur.created_at DESC, ur.id DESC
    LIMIT p_limit
    OFFSET p_offset;
END;
$$;
-- ============================================================
-- 7. Mark a university application as under review
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.mark_university_application_under_review(
    p_request_id UUID,
    p_review_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_request RECORD;
BEGIN
    v_actor_id := app_private.current_user_id();

    IF v_actor_id IS NULL
       OR NOT app_private.is_platform_admin()
    THEN
        RAISE EXCEPTION 'Platform Administrator privileges are required.'
            USING ERRCODE = '42501';
    END IF;

    IF p_request_id IS NULL THEN
        RAISE EXCEPTION 'An application ID is required.'
            USING ERRCODE = '22023';
    END IF;

    IF p_review_notes IS NOT NULL
       AND length(trim(p_review_notes)) > 5000
    THEN
        RAISE EXCEPTION 'Review notes cannot exceed 5000 characters.'
            USING ERRCODE = '22023';
    END IF;

    SELECT
        ur.id,
        ur.institution_name,
        ur.status
    INTO v_request
    FROM public.university_requests AS ur
    WHERE ur.id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'University application not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_request.status <> 'pending' THEN
        RAISE EXCEPTION 'Only pending applications can be marked under review.'
            USING ERRCODE = '23514';
    END IF;

    UPDATE public.university_requests
    SET
        status = 'under_review',
        reviewed_by = v_actor_id,
        reviewed_at = clock_timestamp(),
        review_notes = NULLIF(trim(p_review_notes), ''),
        updated_at = clock_timestamp()
    WHERE id = p_request_id;

    INSERT INTO public.audit_logs (
        actor_user_id,
        event_category,
        event_type,
        resource_type,
        resource_id,
        metadata
    )
    VALUES (
        v_actor_id,
        'administration',
        'university_application_marked_under_review',
        'university_request',
        p_request_id,
        jsonb_build_object(
            'institution_name', v_request.institution_name,
            'previous_status', 'pending',
            'new_status', 'under_review'
        )
    );

    RETURN p_request_id;
END;
$$;

-- ============================================================
-- 8. Approve a university application
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.approve_university_application(
    p_request_id UUID,
    p_review_notes TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_request RECORD;
    v_admin_user_id UUID;
    v_university_id UUID;
BEGIN
    -- Identify and authorize the reviewing Platform Administrator.
    v_actor_id := app_private.current_user_id();

    IF v_actor_id IS NULL
       OR NOT app_private.is_platform_admin()
    THEN
        RAISE EXCEPTION 'Platform Administrator privileges are required.'
            USING ERRCODE = '42501';
    END IF;

    IF p_request_id IS NULL THEN
        RAISE EXCEPTION 'An application ID is required.'
            USING ERRCODE = '22023';
    END IF;

    IF p_review_notes IS NOT NULL
       AND length(trim(p_review_notes)) > 5000
    THEN
        RAISE EXCEPTION 'Review notes cannot exceed 5000 characters.'
            USING ERRCODE = '22023';
    END IF;

    -- Lock the application to prevent concurrent approval.
    SELECT
        ur.id,
        ur.university_id,
        ur.institution_name,
        ur.website,
        ur.country,
        ur.proposed_admin_email,
        ur.status,
        ur.review_notes
    INTO v_request
    FROM public.university_requests AS ur
    WHERE ur.id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'University application not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_request.status NOT IN ('pending', 'under_review') THEN
        RAISE EXCEPTION 'Only pending or under-review applications can be approved.'
            USING ERRCODE = '23514';
    END IF;

    IF v_request.university_id IS NOT NULL THEN
        RAISE EXCEPTION 'This application is already linked to a university.'
            USING ERRCODE = '23514';
    END IF;

    -- Find and lock the proposed administrator's account.
    -- The verified account email must match the submitted email.
    SELECT u.id
    INTO v_admin_user_id
    FROM public.users AS u
    WHERE lower(trim(u.email)) = lower(trim(v_request.proposed_admin_email))
      AND u.account_status = 'active'
      AND u.email_verified_at IS NOT NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'The proposed administrator must have an active account with a verified matching email address.'
            USING ERRCODE = '23514';
    END IF;

    -- Create the active university.
    INSERT INTO public.universities (
        name,
        website,
        country,
        status,
        approved_at
    )
    VALUES (
        v_request.institution_name,
        v_request.website,
        v_request.country,
        'active',
        clock_timestamp()
    )
    RETURNING id INTO v_university_id;

    -- Create the proposed administrator's active membership.
    INSERT INTO public.university_memberships (
        university_id,
        user_id,
        membership_status,
        joined_at
    )
    VALUES (
        v_university_id,
        v_admin_user_id,
        'active',
        clock_timestamp()
    );

    -- Assign the university-wide administrator role.
    INSERT INTO public.role_assignments (
        id,
        user_id,
        university_id,
        department_id,
        role,
        assigned_by
    )
    VALUES (
        gen_random_uuid(),
        v_admin_user_id,
        v_university_id,
        NULL,
        'university_admin',
        v_actor_id
    );

    -- Mark the application as approved.
    UPDATE public.university_requests
    SET
        university_id = v_university_id,
        status = 'approved',
        reviewed_by = v_actor_id,
        reviewed_at = clock_timestamp(),
        review_notes = COALESCE(
            NULLIF(trim(p_review_notes), ''),
            v_request.review_notes
        ),
        updated_at = clock_timestamp()
    WHERE id = p_request_id;

    -- Record the completed onboarding operation.
    INSERT INTO public.audit_logs (
        university_id,
        actor_user_id,
        event_category,
        event_type,
        resource_type,
        resource_id,
        metadata
    )
    VALUES (
        v_university_id,
        v_actor_id,
        'administration',
        'university_application_approved',
        'university_request',
        p_request_id,
        jsonb_build_object(
            'institution_name', v_request.institution_name,
            'university_id', v_university_id,
            'administrator_user_id', v_admin_user_id
        )
    );

    RETURN v_university_id;
END;
$$;

-- ============================================================
-- 9. Reject a university application
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.reject_university_application(
    p_request_id UUID,
    p_review_notes TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_request RECORD;
    v_rejection_reason TEXT;
BEGIN
    -- Identify and authorize the reviewing Platform Administrator.
    v_actor_id := app_private.current_user_id();

    IF v_actor_id IS NULL
       OR NOT app_private.is_platform_admin()
    THEN
        RAISE EXCEPTION 'Platform Administrator privileges are required.'
            USING ERRCODE = '42501';
    END IF;

    IF p_request_id IS NULL THEN
        RAISE EXCEPTION 'An application ID is required.'
            USING ERRCODE = '22023';
    END IF;

    v_rejection_reason := NULLIF(trim(p_review_notes), '');

    IF v_rejection_reason IS NULL THEN
        RAISE EXCEPTION 'A rejection reason is required.'
            USING ERRCODE = '22023';
    END IF;

    IF length(v_rejection_reason) > 5000 THEN
        RAISE EXCEPTION 'Rejection reason cannot exceed 5000 characters.'
            USING ERRCODE = '22023';
    END IF;

    -- Lock the application to prevent concurrent review decisions.
    SELECT
        ur.id,
        ur.institution_name,
        ur.status,
        ur.university_id
    INTO v_request
    FROM public.university_requests AS ur
    WHERE ur.id = p_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'University application not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_request.status NOT IN ('pending', 'under_review') THEN
        RAISE EXCEPTION 'Only pending or under-review applications can be rejected.'
            USING ERRCODE = '23514';
    END IF;

    IF v_request.university_id IS NOT NULL THEN
        RAISE EXCEPTION 'An application already linked to a university cannot be rejected.'
            USING ERRCODE = '23514';
    END IF;

    -- Record the rejection decision.
    UPDATE public.university_requests
    SET
        status = 'rejected',
        reviewed_by = v_actor_id,
        reviewed_at = clock_timestamp(),
        review_notes = v_rejection_reason,
        updated_at = clock_timestamp()
    WHERE id = p_request_id;

    -- Record the rejection in the audit log.
    INSERT INTO public.audit_logs (
        actor_user_id,
        event_category,
        event_type,
        resource_type,
        resource_id,
        metadata
    )
    VALUES (
        v_actor_id,
        'administration',
        'university_application_rejected',
        'university_request',
        p_request_id,
        jsonb_build_object(
            'institution_name', v_request.institution_name,
            'previous_status', v_request.status,
            'new_status', 'rejected',
            'rejection_reason', v_rejection_reason
        )
    );

    RETURN p_request_id;
END;
$$;

-- ============================================================
-- 10. Restrict function execution permissions
-- ============================================================

REVOKE ALL ON FUNCTION app_private.list_university_applications(TEXT, INTEGER, INTEGER)
    FROM PUBLIC;

REVOKE ALL ON FUNCTION app_private.mark_university_application_under_review(UUID, TEXT)
    FROM PUBLIC;

REVOKE ALL ON FUNCTION app_private.approve_university_application(UUID, TEXT)
    FROM PUBLIC;

REVOKE ALL ON FUNCTION app_private.reject_university_application(UUID, TEXT)
    FROM PUBLIC;

GRANT EXECUTE ON FUNCTION app_private.list_university_applications(TEXT, INTEGER, INTEGER)
    TO classroom_app;

GRANT EXECUTE ON FUNCTION app_private.mark_university_application_under_review(UUID, TEXT)
    TO classroom_app;

GRANT EXECUTE ON FUNCTION app_private.approve_university_application(UUID, TEXT)
    TO classroom_app;

GRANT EXECUTE ON FUNCTION app_private.reject_university_application(UUID, TEXT)
    TO classroom_app;

-- Restore the migration role and remove temporary schema creation access.
RESET ROLE;

REVOKE CREATE ON SCHEMA app_private FROM classroom_security_owner;

COMMIT;
