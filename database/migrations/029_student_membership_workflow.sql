BEGIN;

-- ============================================================
-- Migration 029: Student Membership Request Workflow
--
-- Supports:
--   1. Student membership requests.
--   2. Membership status lookup.
--   3. University Administrator request review.
--   4. Student membership approval.
--   5. Student membership rejection.
--
-- All privileged operations use SECURITY DEFINER functions
-- owned by classroom_security_owner.
-- ============================================================

-- ------------------------------------------------------------
-- 1. Prevent duplicate active student role assignments
-- ------------------------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS
    role_assignments_one_active_student_per_university_idx
ON public.role_assignments (user_id, university_id)
WHERE role = 'student'
  AND university_id IS NOT NULL
  AND is_active = TRUE
  AND revoked_at IS NULL;

-- ------------------------------------------------------------
-- 2. Membership permissions
-- ------------------------------------------------------------

GRANT SELECT (
    id,
    university_id,
    user_id,
    student_id,
    membership_status,
    joined_at,
    deactivated_at,
    updated_at
)
ON public.university_memberships
TO classroom_security_owner;

GRANT INSERT (
    university_id,
    user_id,
    student_id,
    membership_status,
    joined_at,
    deactivated_at,
    updated_at
)
ON public.university_memberships
TO classroom_security_owner;

GRANT UPDATE (
    student_id,
    membership_status,
    joined_at,
    deactivated_at,
    updated_at
)
ON public.university_memberships
TO classroom_security_owner;

-- ------------------------------------------------------------
-- 3. Role assignment permissions
-- ------------------------------------------------------------

GRANT SELECT (
    id,
    user_id,
    university_id,
    department_id,
    role,
    is_active,
    revoked_at
)
ON public.role_assignments
TO classroom_security_owner;

GRANT INSERT (
    user_id,
    university_id,
    department_id,
    role,
    assigned_by,
    is_active,
    revoked_at
)
ON public.role_assignments
TO classroom_security_owner;

-- ------------------------------------------------------------
-- 4. University permissions
-- ------------------------------------------------------------

GRANT SELECT (
    id,
    name,
    status
)
ON public.universities
TO classroom_security_owner;

-- ------------------------------------------------------------
-- 5. User permissions
-- ------------------------------------------------------------

GRANT SELECT (
    id,
    full_name,
    email,
    account_status,
    email_verified_at
)
ON public.users
TO classroom_security_owner;

-- ------------------------------------------------------------
-- 6. Audit log permissions
-- ------------------------------------------------------------

GRANT INSERT (
    university_id,
    actor_user_id,
    event_category,
    event_type,
    resource_type,
    resource_id,
    metadata
)
ON public.audit_logs
TO classroom_security_owner;

-- ------------------------------------------------------------
-- 7. Allow controlled function creation
-- ------------------------------------------------------------

GRANT CREATE ON SCHEMA app_private
TO classroom_security_owner;

SET ROLE classroom_security_owner;

-- ============================================================
-- 8. Submit or reapply for student membership
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.submit_student_membership_request(
    p_university_id UUID,
    p_student_id VARCHAR(100) DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_verified_user_id UUID;
    v_verified_university_id UUID;
    v_university_status TEXT;
    v_membership RECORD;
    v_membership_id UUID;
    v_student_id VARCHAR(100);
    v_previous_status TEXT;
BEGIN
    -- --------------------------------------------------------
    -- 1. Verify the authenticated user.
    -- --------------------------------------------------------

    v_actor_id := app_private.current_user_id();

    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'An active, verified account is required.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 2. Verify the signed university context.
    -- --------------------------------------------------------

    SELECT
        verified.verified_user_id,
        verified.verified_university_id
    INTO
        v_verified_user_id,
        v_verified_university_id
    FROM app_private.verify_identity_token(
        pg_catalog.current_setting('app.identity_token', true)
    ) AS verified;

    IF v_verified_user_id IS NULL
       OR v_verified_user_id <> v_actor_id
       OR v_verified_university_id IS NULL
       OR v_verified_university_id <> p_university_id
    THEN
        RAISE EXCEPTION 'The authenticated university context is invalid.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 3. Validate the university.
    -- --------------------------------------------------------

    IF p_university_id IS NULL THEN
        RAISE EXCEPTION 'A university ID is required.'
            USING ERRCODE = '22023';
    END IF;

    SELECT u.status::TEXT
    INTO v_university_status
    FROM public.universities AS u
    WHERE u.id = p_university_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'University not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_university_status <> 'active' THEN
        RAISE EXCEPTION 'Membership requests are only available for active universities.'
            USING ERRCODE = '23514';
    END IF;

    -- --------------------------------------------------------
    -- 4. Validate the optional student ID.
    -- --------------------------------------------------------

    v_student_id := NULLIF(trim(p_student_id), '');

    IF v_student_id IS NOT NULL
       AND length(v_student_id) > 100
    THEN
        RAISE EXCEPTION 'Student ID cannot exceed 100 characters.'
            USING ERRCODE = '22023';
    END IF;

    -- --------------------------------------------------------
    -- 5. Lock any existing membership.
    -- --------------------------------------------------------

    SELECT
        m.id,
        m.membership_status,
        m.student_id
    INTO v_membership
    FROM public.university_memberships AS m
    WHERE m.university_id = p_university_id
      AND m.user_id = v_actor_id
    FOR UPDATE;

    -- --------------------------------------------------------
    -- 6. Create a new membership request.
    -- --------------------------------------------------------

    IF NOT FOUND THEN

        INSERT INTO public.university_memberships (
            university_id,
            user_id,
            student_id,
            membership_status,
            joined_at,
            deactivated_at,
            updated_at
        )
        VALUES (
            p_university_id,
            v_actor_id,
            v_student_id,
            'pending',
            NULL,
            NULL,
            clock_timestamp()
        )
        RETURNING id INTO v_membership_id;

        v_previous_status := NULL;

    ELSE

        v_membership_id := v_membership.id;
        v_previous_status := v_membership.membership_status;

        -- Existing pending applications cannot be duplicated.
        IF v_previous_status = 'pending' THEN
            RAISE EXCEPTION 'A membership request is already pending.'
                USING ERRCODE = '23514';
        END IF;

        -- Active students cannot submit another request.
        IF v_previous_status = 'active' THEN
            RAISE EXCEPTION 'You already have active membership at this university.'
                USING ERRCODE = '23514';
        END IF;

        -- Suspended memberships require administrative action.
        IF v_previous_status = 'suspended' THEN
            RAISE EXCEPTION 'Your membership is suspended. Contact your university administrator.'
                USING ERRCODE = '23514';
        END IF;

        -- Only deactivated memberships may be reapplied for.
        IF v_previous_status <> 'deactivated' THEN
            RAISE EXCEPTION 'This membership cannot be reapplied for.'
                USING ERRCODE = '23514';
        END IF;

        -- Reuse the existing membership record.
        UPDATE public.university_memberships
        SET
            student_id = COALESCE(v_student_id, student_id),
            membership_status = 'pending',
            joined_at = NULL,
            deactivated_at = NULL,
            updated_at = clock_timestamp()
        WHERE id = v_membership_id;

    END IF;

    -- --------------------------------------------------------
    -- 7. Record the submission in the audit log.
    -- --------------------------------------------------------

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
        p_university_id,
        v_actor_id,
        'administration',
        'student_membership_request_submitted',
        'university_membership',
        v_membership_id,
        jsonb_build_object(
            'previous_status', v_previous_status,
            'new_status', 'pending',
            'student_id_provided', v_student_id IS NOT NULL
        )
    );

    RETURN v_membership_id;
END;
$$;

REVOKE ALL ON FUNCTION
    app_private.submit_student_membership_request(UUID, VARCHAR)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
    app_private.submit_student_membership_request(UUID, VARCHAR)
TO classroom_app;

-- ============================================================
-- 9. Get the authenticated user's membership status
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.get_my_student_membership_status(
    p_university_id UUID
)
RETURNS TABLE (
    university_id UUID,
    university_name VARCHAR(255),
    membership_id UUID,
    membership_status VARCHAR(20),
    student_id VARCHAR(100),
    joined_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_verified_user_id UUID;
    v_verified_university_id UUID;
    v_university_status TEXT;
BEGIN
    -- --------------------------------------------------------
    -- 1. Verify the authenticated user.
    -- --------------------------------------------------------

    v_actor_id := app_private.current_user_id();

    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'An active, verified account is required.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 2. Verify the signed university context.
    -- --------------------------------------------------------

    SELECT
        verified.verified_user_id,
        verified.verified_university_id
    INTO
        v_verified_user_id,
        v_verified_university_id
    FROM app_private.verify_identity_token(
        pg_catalog.current_setting('app.identity_token', true)
    ) AS verified;

    IF v_verified_user_id IS NULL
       OR v_verified_user_id <> v_actor_id
       OR v_verified_university_id IS NULL
       OR v_verified_university_id <> p_university_id
    THEN
        RAISE EXCEPTION 'The authenticated university context is invalid.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 3. Validate the university.
    -- --------------------------------------------------------

    IF p_university_id IS NULL THEN
        RAISE EXCEPTION 'A university ID is required.'
            USING ERRCODE = '22023';
    END IF;

    SELECT u.status::TEXT
    INTO v_university_status
    FROM public.universities AS u
    WHERE u.id = p_university_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'University not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_university_status <> 'active' THEN
        RAISE EXCEPTION 'University is not active.'
            USING ERRCODE = '23514';
    END IF;

    -- --------------------------------------------------------
    -- 4. Return only the authenticated user's membership.
    -- --------------------------------------------------------

    RETURN QUERY
    SELECT
        u.id,
        u.name,
        m.id,
        COALESCE(m.membership_status, 'not_submitted')::VARCHAR(20),
        m.student_id,
        m.joined_at,
        m.created_at,
        m.updated_at
    FROM public.universities AS u
    LEFT JOIN public.university_memberships AS m
        ON m.university_id = u.id
       AND m.user_id = v_actor_id
    WHERE u.id = p_university_id;

END;
$$;

REVOKE ALL ON FUNCTION
    app_private.get_my_student_membership_status(UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
    app_private.get_my_student_membership_status(UUID)
TO classroom_app;

-- ============================================================
-- 10. List pending student membership requests
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.list_student_membership_requests(
    p_university_id UUID,
    p_limit INTEGER DEFAULT 50,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    membership_id UUID,
    student_user_id UUID,
    student_name VARCHAR(255),
    student_email VARCHAR(255),
    student_id VARCHAR(100),
    membership_status VARCHAR(20),
    submitted_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_verified_user_id UUID;
    v_verified_university_id UUID;
    v_university_status TEXT;
BEGIN
    -- --------------------------------------------------------
    -- 1. Verify the authenticated user.
    -- --------------------------------------------------------

    v_actor_id := app_private.current_user_id();

    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'An active, verified account is required.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 2. Verify the signed university context.
    -- --------------------------------------------------------

    SELECT
        verified.verified_user_id,
        verified.verified_university_id
    INTO
        v_verified_user_id,
        v_verified_university_id
    FROM app_private.verify_identity_token(
        pg_catalog.current_setting('app.identity_token', true)
    ) AS verified;

    IF v_verified_user_id IS NULL
       OR v_verified_user_id <> v_actor_id
       OR v_verified_university_id IS NULL
       OR v_verified_university_id <> p_university_id
    THEN
        RAISE EXCEPTION 'The authenticated university context is invalid.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 3. Validate pagination.
    -- --------------------------------------------------------

    IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
        RAISE EXCEPTION 'Limit must be between 1 and 100.'
            USING ERRCODE = '22023';
    END IF;

    IF p_offset IS NULL OR p_offset < 0 THEN
        RAISE EXCEPTION 'Offset must be zero or greater.'
            USING ERRCODE = '22023';
    END IF;

    -- --------------------------------------------------------
    -- 4. Validate the university.
    -- --------------------------------------------------------

    SELECT u.status::TEXT
    INTO v_university_status
    FROM public.universities AS u
    WHERE u.id = p_university_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'University not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_university_status <> 'active' THEN
        RAISE EXCEPTION 'University is not active.'
            USING ERRCODE = '23514';
    END IF;

    -- --------------------------------------------------------
    -- 5. Verify University Admin authorization.
    -- --------------------------------------------------------

    IF NOT app_private.has_university_role(
        'university_admin',
        p_university_id,
        NULL
    ) THEN
        RAISE EXCEPTION 'University Admin authorization is required.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 6. Return pending requests for this university only.
    -- --------------------------------------------------------

    RETURN QUERY
    SELECT
        m.id,
        m.user_id,
        u.full_name,
        u.email,
        m.student_id,
        m.membership_status,
        m.created_at,
        m.updated_at
    FROM public.university_memberships AS m
    JOIN public.users AS u
        ON u.id = m.user_id
    WHERE m.university_id = p_university_id
      AND m.membership_status = 'pending'
      AND m.deactivated_at IS NULL
    ORDER BY m.created_at ASC, m.id ASC
    LIMIT p_limit
    OFFSET p_offset;

END;
$$;

REVOKE ALL ON FUNCTION
    app_private.list_student_membership_requests(UUID, INTEGER, INTEGER)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
    app_private.list_student_membership_requests(UUID, INTEGER, INTEGER)
TO classroom_app;


-- ============================================================
-- 11. Approve a student membership request
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.approve_student_membership_request(
    p_university_id UUID,
    p_membership_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_verified_user_id UUID;
    v_verified_university_id UUID;
    v_university_status TEXT;
    v_membership_user_id UUID;
    v_membership_status TEXT;
    v_membership_deactivated_at TIMESTAMPTZ;
    v_student_account_status TEXT;
    v_student_email_verified_at TIMESTAMPTZ;
    v_existing_student_role BOOLEAN;
    v_approved_at TIMESTAMPTZ;
BEGIN
    -- --------------------------------------------------------
    -- 1. Verify the authenticated administrator.
    -- --------------------------------------------------------

    v_actor_id := app_private.current_user_id();

    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'An active, verified account is required.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 2. Verify the signed university context.
    -- --------------------------------------------------------

    SELECT
        verified.verified_user_id,
        verified.verified_university_id
    INTO
        v_verified_user_id,
        v_verified_university_id
    FROM app_private.verify_identity_token(
        pg_catalog.current_setting('app.identity_token', true)
    ) AS verified;

    IF v_verified_user_id IS NULL
       OR v_verified_user_id <> v_actor_id
       OR v_verified_university_id IS NULL
       OR v_verified_university_id <> p_university_id
    THEN
        RAISE EXCEPTION 'The authenticated university context is invalid.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 3. Validate the supplied IDs.
    -- --------------------------------------------------------

    IF p_university_id IS NULL OR p_membership_id IS NULL THEN
        RAISE EXCEPTION 'University ID and membership ID are required.'
            USING ERRCODE = '22023';
    END IF;

    -- --------------------------------------------------------
    -- 4. Verify the university is active.
    -- --------------------------------------------------------

    SELECT u.status::TEXT
    INTO v_university_status
    FROM public.universities AS u
    WHERE u.id = p_university_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'University not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_university_status <> 'active' THEN
        RAISE EXCEPTION 'University is not active.'
            USING ERRCODE = '23514';
    END IF;

    -- --------------------------------------------------------
    -- 5. Verify University Admin authorization.
    -- --------------------------------------------------------

    IF NOT app_private.has_university_role(
        'university_admin',
        p_university_id,
        NULL
    ) THEN
        RAISE EXCEPTION 'University Admin authorization is required.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 6. Lock the membership request.
    -- --------------------------------------------------------

    SELECT
        m.user_id,
        m.membership_status,
        m.deactivated_at
    INTO
        v_membership_user_id,
        v_membership_status,
        v_membership_deactivated_at
    FROM public.university_memberships AS m
    WHERE m.id = p_membership_id
      AND m.university_id = p_university_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Membership request not found.'
            USING ERRCODE = 'P0002';
    END IF;

    -- --------------------------------------------------------
    -- 7. Ensure the request is still pending.
    -- --------------------------------------------------------

    IF v_membership_status <> 'pending'
       OR v_membership_deactivated_at IS NOT NULL
    THEN
        RAISE EXCEPTION 'Only pending membership requests can be approved.'
            USING ERRCODE = '23514';
    END IF;

    -- --------------------------------------------------------
    -- 8. Verify the student's account.
    -- --------------------------------------------------------

    SELECT
        u.account_status,
        u.email_verified_at
    INTO
        v_student_account_status,
        v_student_email_verified_at
    FROM public.users AS u
    WHERE u.id = v_membership_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Student account not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_student_account_status <> 'active' THEN
        RAISE EXCEPTION 'The student account is not active.'
            USING ERRCODE = '23514';
    END IF;

    IF v_student_email_verified_at IS NULL THEN
        RAISE EXCEPTION 'The student email address has not been verified.'
            USING ERRCODE = '23514';
    END IF;

    -- --------------------------------------------------------
    -- 9. Prevent duplicate active student role assignments.
    -- --------------------------------------------------------

    SELECT EXISTS (
        SELECT 1
        FROM public.role_assignments AS ra
        WHERE ra.user_id = v_membership_user_id
          AND ra.university_id = p_university_id
          AND ra.role = 'student'
          AND ra.is_active = TRUE
          AND ra.revoked_at IS NULL
    )
    INTO v_existing_student_role;

    IF v_existing_student_role THEN
        RAISE EXCEPTION 'The student already has an active student role.'
            USING ERRCODE = '23505';
    END IF;

    -- --------------------------------------------------------
    -- 10. Activate the membership.
    -- --------------------------------------------------------

    v_approved_at := pg_catalog.clock_timestamp();

    UPDATE public.university_memberships
    SET
        membership_status = 'active',
        joined_at = v_approved_at,
        deactivated_at = NULL,
        updated_at = v_approved_at
    WHERE id = p_membership_id
      AND university_id = p_university_id;

    -- --------------------------------------------------------
    -- 11. Assign the student role.
    -- --------------------------------------------------------

    INSERT INTO public.role_assignments (
        user_id,
        university_id,
        department_id,
        role,
        assigned_by,
        is_active,
        revoked_at
    )
    VALUES (
        v_membership_user_id,
        p_university_id,
        NULL,
        'student',
        v_actor_id,
        TRUE,
        NULL
    );

    -- --------------------------------------------------------
    -- 12. Record the audit event.
    -- --------------------------------------------------------

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
        p_university_id,
        v_actor_id,
        'administration',
        'student_membership_request_approved',
        'university_membership',
        p_membership_id,
        pg_catalog.jsonb_build_object(
            'student_user_id', v_membership_user_id,
            'membership_status', 'active',
            'approved_at', v_approved_at
        )
    );

    -- --------------------------------------------------------
    -- 13. Return the approved membership ID.
    -- --------------------------------------------------------

    RETURN p_membership_id;

END;
$$;

REVOKE ALL ON FUNCTION
    app_private.approve_student_membership_request(UUID, UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
    app_private.approve_student_membership_request(UUID, UUID)
TO classroom_app;


-- ============================================================
-- 12. Reject a student membership request
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.reject_student_membership_request(
    p_university_id UUID,
    p_membership_id UUID,
    p_rejection_reason TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_verified_user_id UUID;
    v_verified_university_id UUID;
    v_university_status TEXT;
    v_membership_user_id UUID;
    v_membership_status TEXT;
    v_membership_deactivated_at TIMESTAMPTZ;
    v_rejection_reason TEXT;
    v_rejected_at TIMESTAMPTZ;
BEGIN
    -- --------------------------------------------------------
    -- 1. Verify the authenticated administrator.
    -- --------------------------------------------------------

    v_actor_id := app_private.current_user_id();

    IF v_actor_id IS NULL THEN
        RAISE EXCEPTION 'An active, verified account is required.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 2. Verify the signed university context.
    -- --------------------------------------------------------

    SELECT
        verified.verified_user_id,
        verified.verified_university_id
    INTO
        v_verified_user_id,
        v_verified_university_id
    FROM app_private.verify_identity_token(
        pg_catalog.current_setting('app.identity_token', true)
    ) AS verified;

    IF v_verified_user_id IS NULL
       OR v_verified_user_id <> v_actor_id
       OR v_verified_university_id IS NULL
       OR v_verified_university_id <> p_university_id
    THEN
        RAISE EXCEPTION 'The authenticated university context is invalid.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 3. Validate supplied IDs.
    -- --------------------------------------------------------

    IF p_university_id IS NULL OR p_membership_id IS NULL THEN
        RAISE EXCEPTION 'University ID and membership ID are required.'
            USING ERRCODE = '22023';
    END IF;

    -- --------------------------------------------------------
    -- 4. Validate the rejection reason.
    -- --------------------------------------------------------

    v_rejection_reason := pg_catalog.btrim(p_rejection_reason);

    IF p_rejection_reason IS NULL
       OR v_rejection_reason IS NULL
       OR pg_catalog.length(v_rejection_reason) < 5
       OR pg_catalog.length(v_rejection_reason) > 5000
    THEN
        RAISE EXCEPTION
            'Rejection reason must contain between 5 and 5000 characters.'
            USING ERRCODE = '22023';
    END IF;

    -- --------------------------------------------------------
    -- 5. Verify the university is active.
    -- --------------------------------------------------------

    SELECT u.status::TEXT
    INTO v_university_status
    FROM public.universities AS u
    WHERE u.id = p_university_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'University not found.'
            USING ERRCODE = 'P0002';
    END IF;

    IF v_university_status <> 'active' THEN
        RAISE EXCEPTION 'University is not active.'
            USING ERRCODE = '23514';
    END IF;

    -- --------------------------------------------------------
    -- 6. Verify University Admin authorization.
    -- --------------------------------------------------------

    IF NOT app_private.has_university_role(
        'university_admin',
        p_university_id,
        NULL
    ) THEN
        RAISE EXCEPTION 'University Admin authorization is required.'
            USING ERRCODE = '42501';
    END IF;

    -- --------------------------------------------------------
    -- 7. Lock the membership request.
    -- --------------------------------------------------------

    SELECT
        m.user_id,
        m.membership_status,
        m.deactivated_at
    INTO
        v_membership_user_id,
        v_membership_status,
        v_membership_deactivated_at
    FROM public.university_memberships AS m
    WHERE m.id = p_membership_id
      AND m.university_id = p_university_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Membership request not found.'
            USING ERRCODE = 'P0002';
    END IF;

    -- --------------------------------------------------------
    -- 8. Ensure the request is still pending.
    -- --------------------------------------------------------

    IF v_membership_status <> 'pending'
       OR v_membership_deactivated_at IS NOT NULL
    THEN
        RAISE EXCEPTION 'Only pending membership requests can be rejected.'
            USING ERRCODE = '23514';
    END IF;

    -- --------------------------------------------------------
    -- 9. Deactivate the membership request.
    -- --------------------------------------------------------

    v_rejected_at := pg_catalog.clock_timestamp();

    UPDATE public.university_memberships
    SET
        membership_status = 'deactivated',
        joined_at = NULL,
        deactivated_at = v_rejected_at,
        updated_at = v_rejected_at
    WHERE id = p_membership_id
      AND university_id = p_university_id;

    -- --------------------------------------------------------
    -- 10. Record the audit event.
    -- --------------------------------------------------------

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
        p_university_id,
        v_actor_id,
        'administration',
        'student_membership_request_rejected',
        'university_membership',
        p_membership_id,
        pg_catalog.jsonb_build_object(
            'student_user_id', v_membership_user_id,
            'previous_status', 'pending',
            'new_status', 'deactivated',
            'rejection_reason', v_rejection_reason,
            'rejected_at', v_rejected_at
        )
    );

    -- --------------------------------------------------------
    -- 11. Return the rejected membership ID.
    -- --------------------------------------------------------

    RETURN p_membership_id;

END;
$$;

REVOKE ALL ON FUNCTION
    app_private.reject_student_membership_request(UUID, UUID, TEXT)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
    app_private.reject_student_membership_request(UUID, UUID, TEXT)
TO classroom_app;


-- ============================================================
-- 13. Final security cleanup
-- ============================================================

RESET ROLE;

REVOKE CREATE ON SCHEMA app_private
FROM classroom_security_owner;

COMMIT;
