
BEGIN;

-- =========================================================
-- 1. Add a tenant-safe reference to course_offerings
-- =========================================================

ALTER TABLE course_offerings
ADD CONSTRAINT course_offerings_id_university_unique
UNIQUE (id, university_id);


-- =========================================================
-- 2. CLASS SECTIONS
-- Each section belongs to one course offering.
-- =========================================================

CREATE TABLE class_sections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    course_offering_id UUID NOT NULL,

    section_code VARCHAR(40) NOT NULL,
    section_name VARCHAR(120) NOT NULL,

    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    capacity INTEGER,

    created_by UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ,

    CONSTRAINT class_sections_status_check
        CHECK (status IN ('draft', 'open', 'closed', 'archived')),

    CONSTRAINT class_sections_capacity_check
        CHECK (capacity IS NULL OR capacity > 0),

    CONSTRAINT class_sections_id_university_unique
        UNIQUE (id, university_id),

    CONSTRAINT class_sections_offering_fk
        FOREIGN KEY (course_offering_id, university_id)
        REFERENCES course_offerings(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT class_sections_created_by_fk
        FOREIGN KEY (created_by)
        REFERENCES users(id)
        ON DELETE RESTRICT
);

CREATE UNIQUE INDEX class_sections_offering_code_unique
    ON class_sections(course_offering_id, LOWER(section_code));

CREATE INDEX class_sections_university_status_idx
    ON class_sections(university_id, status);

CREATE INDEX class_sections_offering_idx
    ON class_sections(course_offering_id);


-- =========================================================
-- 3. CLASS SECTION LECTURERS
-- Preserves lecturer assignment history.
-- Only one active lecturer per section.
-- =========================================================

CREATE TABLE class_section_lecturers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    class_section_id UUID NOT NULL,
    lecturer_user_id UUID NOT NULL,
    assigned_by UUID NOT NULL,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,

    CONSTRAINT class_section_lecturers_status_check
        CHECK (
            (is_active = TRUE AND ended_at IS NULL)
            OR
            (is_active = FALSE AND ended_at IS NOT NULL)
        ),

    CONSTRAINT class_section_lecturers_section_fk
        FOREIGN KEY (class_section_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT class_section_lecturers_membership_fk
        FOREIGN KEY (university_id, lecturer_user_id)
        REFERENCES university_memberships(university_id, user_id)
        ON DELETE RESTRICT,

    CONSTRAINT class_section_lecturers_assigned_by_fk
        FOREIGN KEY (assigned_by)
        REFERENCES users(id)
        ON DELETE RESTRICT
);

CREATE UNIQUE INDEX class_section_lecturers_one_active_idx
    ON class_section_lecturers(class_section_id)
    WHERE is_active = TRUE;

CREATE INDEX class_section_lecturers_lecturer_idx
    ON class_section_lecturers(university_id, lecturer_user_id);

CREATE INDEX class_section_lecturers_section_history_idx
    ON class_section_lecturers(class_section_id, assigned_at);


-- =========================================================
-- 4. CLASS ENROLLMENTS
-- Tracks student membership in individual class sections.
-- =========================================================

CREATE TABLE class_enrollments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    class_section_id UUID NOT NULL,
    student_user_id UUID NOT NULL,
    enrolled_by UUID NOT NULL,

    enrollment_status VARCHAR(20) NOT NULL DEFAULT 'active',
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT class_enrollments_status_check
        CHECK (
            enrollment_status IN ('active', 'withdrawn', 'removed')
        ),

    CONSTRAINT class_enrollments_dates_check
        CHECK (
            (enrollment_status = 'active' AND ended_at IS NULL)
            OR
            (enrollment_status IN ('withdrawn', 'removed')
                AND ended_at IS NOT NULL)
        ),

    CONSTRAINT class_enrollments_unique_student
        UNIQUE (class_section_id, student_user_id),

    CONSTRAINT class_enrollments_id_university_unique
        UNIQUE (id, university_id),

    CONSTRAINT class_enrollments_section_fk
        FOREIGN KEY (class_section_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT class_enrollments_membership_fk
        FOREIGN KEY (university_id, student_user_id)
        REFERENCES university_memberships(university_id, user_id)
        ON DELETE RESTRICT,

    CONSTRAINT class_enrollments_enrolled_by_fk
        FOREIGN KEY (enrolled_by)
        REFERENCES users(id)
        ON DELETE RESTRICT
);

CREATE INDEX class_enrollments_section_status_idx
    ON class_enrollments(class_section_id, enrollment_status);

CREATE INDEX class_enrollments_student_idx
    ON class_enrollments(university_id, student_user_id);

COMMIT;
