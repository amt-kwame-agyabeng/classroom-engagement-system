BEGIN;

-- Enable row-level security for class sections.
ALTER TABLE public.class_sections
ENABLE ROW LEVEL SECURITY;

COMMIT;
