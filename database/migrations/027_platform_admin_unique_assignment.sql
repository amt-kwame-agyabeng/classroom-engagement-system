BEGIN;

-- Ensure each user has at most one active global
-- Platform Administrator assignment.

CREATE UNIQUE INDEX role_assignments_one_active_platform_admin_idx
ON public.role_assignments (user_id)
WHERE role = 'platform_admin'
  AND university_id IS NULL
  AND department_id IS NULL
  AND is_active = TRUE
  AND revoked_at IS NULL;

COMMENT ON INDEX public.role_assignments_one_active_platform_admin_idx
IS 'Prevents duplicate active global Platform Administrator assignments per user.';

COMMIT;