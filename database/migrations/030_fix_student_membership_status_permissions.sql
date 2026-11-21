BEGIN;

-- Allow the security owner to read the membership creation timestamp.
GRANT SELECT (created_at)
ON public.university_memberships
TO classroom_security_owner;

COMMIT;
