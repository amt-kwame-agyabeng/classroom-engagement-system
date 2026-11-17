BEGIN;

-- ============================================================
-- Migration 026: Controlled Platform Administrator Management
--
-- Supports:
--   1. Appointment of additional Platform Administrators.
--   2. Revocation of an existing Platform Administrator.
--
-- Initial Platform Administrator bootstrap is intentionally
-- excluded. It must be performed through controlled database
-- administration after the target account is verified.
--
-- Both operations use the same transaction-level advisory lock
-- to protect the last-active-administrator safeguard.
-- ============================================================

-- Grant only the columns required by the controlled functions.

GRANT INSERT (
    id,
    user_id,
    university_id,
    department_id,
    role,
    assigned_by
)
ON public.role_assignments
TO classroom_security_owner;

GRANT SELECT (id)
ON public.role_assignments
TO classroom_security_owner;

GRANT UPDATE (
    is_active,
    revoked_at
)
ON public.role_assignments
TO classroom_security_owner;

GRANT INSERT (
    actor_user_id,
    event_category,
    event_type,
    resource_type,
    resource_id,
    metadata
)
ON public.audit_logs
TO classroom_security_owner;

GRANT CREATE ON SCHEMA app_private
TO classroom_security_owner;

SET ROLE classroom_security_owner;

-- ============================================================
-- Appoint a Platform Administrator
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.appoint_platform_admin(
    p_target_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_assignment_id UUID;
BEGIN
    -- Serialize all Platform Administrator management operations.
    PERFORM pg_advisory_xact_lock(20261116, 26001);

    -- Derive the actor from the verified signed identity context.
    v_actor_id := app_private.current_user_id();

    IF v_actor_id IS NULL
       OR NOT app_private.is_platform_admin()
    THEN
        RAISE EXCEPTION 'Platform Administrator privileges are required.'
            USING ERRCODE = '42501';
    END IF;

    IF p_target_user_id IS NULL THEN
        RAISE EXCEPTION 'A target user ID is required.'
            USING ERRCODE = '22023';
    END IF;

    -- Only active users with verified email addresses may be appointed.
    PERFORM 1
    FROM public.users AS u
    WHERE u.id = p_target_user_id
      AND u.account_status = 'active'
      AND u.email_verified_at IS NOT NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'The target user must have an active, verified account.'
            USING ERRCODE = '22023';
    END IF;

    -- Prevent duplicate active global Platform Administrator assignments.
    IF EXISTS (
        SELECT 1
        FROM public.role_assignments AS ra
        WHERE ra.user_id = p_target_user_id
          AND ra.role = 'platform_admin'
          AND ra.university_id IS NULL
          AND ra.department_id IS NULL
          AND ra.is_active = TRUE
          AND ra.revoked_at IS NULL
    ) THEN
        RAISE EXCEPTION 'The target user is already an active Platform Administrator.'
            USING ERRCODE = '23505';
    END IF;

    v_assignment_id := gen_random_uuid();

    INSERT INTO public.role_assignments (
        id,
        user_id,
        university_id,
        department_id,
        role,
        assigned_by
    )
    VALUES (
        v_assignment_id,
        p_target_user_id,
        NULL,
        NULL,
        'platform_admin',
        v_actor_id
    );

    -- Record the appointment in the platform audit log.
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
        'platform_admin_appointed',
        'role_assignment',
        v_assignment_id,
        jsonb_build_object(
            'target_user_id', p_target_user_id,
            'assignment_id', v_assignment_id
        )
    );

    RETURN v_assignment_id;
END;
$$;


-- ============================================================
-- Revoke a specific Platform Administrator assignment
-- ============================================================

CREATE OR REPLACE FUNCTION app_private.revoke_platform_admin(
    p_assignment_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, app_private, pg_temp
AS $$
DECLARE
    v_actor_id UUID;
    v_assignment RECORD;
    v_active_admin_count BIGINT;
BEGIN
    -- Use the same lock as appointment to prevent concurrent
    -- operations from bypassing the last-admin safeguard.
    PERFORM pg_advisory_xact_lock(20261116, 26001);

    v_actor_id := app_private.current_user_id();

    IF v_actor_id IS NULL
       OR NOT app_private.is_platform_admin()
    THEN
        RAISE EXCEPTION 'Platform Administrator privileges are required.'
            USING ERRCODE = '42501';
    END IF;

    IF p_assignment_id IS NULL THEN
        RAISE EXCEPTION 'An assignment ID is required.'
            USING ERRCODE = '22023';
    END IF;

    -- Lock the specific assignment being revoked.
    SELECT
        ra.id,
        ra.user_id,
        ra.role,
        ra.university_id,
        ra.department_id,
        ra.is_active,
        ra.revoked_at
    INTO v_assignment
    FROM public.role_assignments AS ra
    WHERE ra.id = p_assignment_id
      AND ra.role = 'platform_admin'
      AND ra.university_id IS NULL
      AND ra.department_id IS NULL
      AND ra.is_active = TRUE
      AND ra.revoked_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No active Platform Administrator assignment was found.'
            USING ERRCODE = '22023';
    END IF;

    -- Count usable administrators: active global assignments
    -- belonging to active users with verified email addresses.
    SELECT COUNT(DISTINCT ra.user_id)
    INTO v_active_admin_count
    FROM public.role_assignments AS ra
    JOIN public.users AS u
      ON u.id = ra.user_id
    WHERE ra.role = 'platform_admin'
      AND ra.university_id IS NULL
      AND ra.department_id IS NULL
      AND ra.is_active = TRUE
      AND ra.revoked_at IS NULL
      AND u.account_status = 'active'
      AND u.email_verified_at IS NOT NULL;

    -- Never allow the final active administrator to be revoked.
    IF v_active_admin_count <= 1 THEN
        RAISE EXCEPTION 'The last active Platform Administrator cannot be revoked.'
            USING ERRCODE = '23514';
    END IF;

    UPDATE public.role_assignments
    SET
        is_active = FALSE,
        revoked_at = clock_timestamp()
    WHERE id = p_assignment_id;

    -- Preserve the assignment history and record the revocation.
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
        'platform_admin_revoked',
        'role_assignment',
        p_assignment_id,
        jsonb_build_object(
            'target_user_id', v_assignment.user_id,
            'assignment_id', p_assignment_id
        )
    );

    RETURN p_assignment_id;
END;
$$;


-- ============================================================
-- Restrict function execution
-- ============================================================

REVOKE ALL ON FUNCTION
    app_private.appoint_platform_admin(UUID)
FROM PUBLIC;

REVOKE ALL ON FUNCTION
    app_private.revoke_platform_admin(UUID)
FROM PUBLIC;

GRANT EXECUTE ON FUNCTION
    app_private.appoint_platform_admin(UUID)
TO classroom_app;

GRANT EXECUTE ON FUNCTION
    app_private.revoke_platform_admin(UUID)
TO classroom_app;

RESET ROLE;

-- Remove the temporary schema creation permission.
REVOKE CREATE ON SCHEMA app_private
FROM classroom_security_owner;

COMMIT;
