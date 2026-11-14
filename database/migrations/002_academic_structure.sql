
-- =========================================================
-- Migration 002: Academic Structure
-- Project: Classroom Engagement and Feedback System
-- Database: PostgreSQL 16+
-- Depends on: 001_identity_university.sql
-- =========================================================

BEGIN;

-- ---------------------------------------------------------
-- 1. FACULTIES
-- A university can have multiple faculties or schools.
-- ---------------------------------------------------------

CREATE TABLE faculties (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL
        REFERENCES universities(id) ON DELETE RESTRICT,

    name VARCHAR(200) NOT NULL,
    code VARCHAR(50),
    description TEXT,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (id, university_id)
);

CREATE UNIQUE INDEX faculties_name_unique
    ON faculties (university_id, LOWER(name));

CREATE UNIQUE INDEX faculties_code_unique
    ON faculties (university_id, LOWER(code))
    WHERE code IS NOT NULL;


-- ---------------------------------------------------------
-- 2. DEPARTMENTS
-- Each department belongs to a faculty and university.
-- ---------------------------------------------------------

CREATE TABLE departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,
    faculty_id UUID NOT NULL,

    name VARCHAR(200) NOT NULL,
    code VARCHAR(50),
    description TEXT,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT departments_faculty_fk
        FOREIGN KEY (faculty_id, university_id)
        REFERENCES faculties(id, university_id)
        ON DELETE RESTRICT,

    UNIQUE (id, university_id)
);

CREATE UNIQUE INDEX departments_name_unique
    ON departments (university_id, LOWER(name));

CREATE UNIQUE INDEX departments_code_unique
    ON departments (university_id, LOWER(code))
    WHERE code IS NOT NULL;

CREATE INDEX departments_faculty_idx
    ON departments(faculty_id);


-- ---------------------------------------------------------
-- 3. ACADEMIC PROGRAMMES
-- Degree and diploma programmes offered by departments.
-- ---------------------------------------------------------

CREATE TABLE academic_programmes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,
    department_id UUID NOT NULL,

    name VARCHAR(255) NOT NULL,
    code VARCHAR(50) NOT NULL,

    award_type VARCHAR(100),
    duration_years NUMERIC(3,1),

    description TEXT,

    status VARCHAR(20) NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'inactive', 'archived')),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT academic_programmes_department_fk
        FOREIGN KEY (department_id, university_id)
        REFERENCES departments(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT academic_programmes_duration_check
        CHECK (duration_years IS NULL OR duration_years > 0),

    UNIQUE (id, university_id)
);

CREATE UNIQUE INDEX academic_programmes_code_unique
    ON academic_programmes(university_id, LOWER(code));

CREATE INDEX academic_programmes_department_idx
    ON academic_programmes(department_id);


-- ---------------------------------------------------------
-- 4. ACADEMIC COURSES
-- University's central course catalogue.
-- A course can be used by multiple programmes.
-- ---------------------------------------------------------

CREATE TABLE academic_courses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,
    department_id UUID,

    course_code VARCHAR(50) NOT NULL,
    title VARCHAR(255) NOT NULL,

    description TEXT,
    credit_hours NUMERIC(4,1),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT academic_courses_department_fk
        FOREIGN KEY (department_id, university_id)
        REFERENCES departments(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT academic_courses_credit_check
        CHECK (credit_hours IS NULL OR credit_hours > 0),

    UNIQUE (id, university_id)
);

CREATE UNIQUE INDEX academic_courses_code_unique
    ON academic_courses(university_id, LOWER(course_code));

CREATE INDEX academic_courses_department_idx
    ON academic_courses(department_id);


-- ---------------------------------------------------------
-- 5. CURRICULUM VERSIONS
-- Preserves historical versions of programme curricula.
-- ---------------------------------------------------------

CREATE TABLE curriculum_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,
    programme_id UUID NOT NULL,

    version_label VARCHAR(50) NOT NULL,
    description TEXT,

    effective_from DATE NOT NULL,
    effective_to DATE,

    is_current BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT curriculum_versions_programme_fk
        FOREIGN KEY (programme_id, university_id)
        REFERENCES academic_programmes(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT curriculum_versions_dates_check
        CHECK (effective_to IS NULL OR effective_to >= effective_from),

    UNIQUE (id, university_id),

    UNIQUE (programme_id, version_label)
);

CREATE INDEX curriculum_versions_programme_idx
    ON curriculum_versions(programme_id);

CREATE UNIQUE INDEX curriculum_versions_one_current
    ON curriculum_versions(programme_id)
    WHERE is_current = TRUE;


-- ---------------------------------------------------------
-- 6. ACADEMIC YEARS
-- Academic years are defined separately for each university.
-- Example: 2026/2027.
-- ---------------------------------------------------------

CREATE TABLE academic_years (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,

    name VARCHAR(50) NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,

    is_current BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT academic_years_dates_check
        CHECK (end_date > start_date),

    UNIQUE (id, university_id),
    UNIQUE (university_id, name)
);

CREATE INDEX academic_years_university_idx
    ON academic_years(university_id);

CREATE UNIQUE INDEX academic_years_one_current
    ON academic_years(university_id)
    WHERE is_current = TRUE;


-- ---------------------------------------------------------
-- 7. ACADEMIC SEMESTERS
-- Defines semester names and ordering for each university.
-- Example: Semester 1, Semester 2.
-- ---------------------------------------------------------

CREATE TABLE academic_semesters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,

    name VARCHAR(100) NOT NULL,
    semester_number SMALLINT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT academic_semesters_number_check
        CHECK (semester_number > 0),

  UNIQUE (id, university_id),
    UNIQUE (university_id, semester_number)
);

CREATE UNIQUE INDEX academic_semesters_name_unique
    ON academic_semesters(university_id, LOWER(name));

-- ---------------------------------------------------------
-- 8. ACADEMIC PERIODS
-- Represents an actual semester within an academic year.
-- Connects an academic year to a semester definition.
-- ---------------------------------------------------------

CREATE TABLE academic_periods (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,
    academic_year_id UUID NOT NULL,
    academic_semester_id UUID NOT NULL,

    start_date DATE NOT NULL,
    end_date DATE NOT NULL,

    status VARCHAR(20) NOT NULL DEFAULT 'upcoming'
        CHECK (status IN (
            'upcoming',
            'active',
            'completed',
            'cancelled'
        )),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT academic_periods_dates_check
        CHECK (end_date > start_date),

    CONSTRAINT academic_periods_year_fk
        FOREIGN KEY (academic_year_id, university_id)
        REFERENCES academic_years(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT academic_periods_semester_fk
        FOREIGN KEY (academic_semester_id, university_id)
        REFERENCES academic_semesters(id, university_id)
        ON DELETE RESTRICT,

    UNIQUE (id, university_id),

    UNIQUE (academic_year_id, academic_semester_id)
);

CREATE INDEX academic_periods_university_status_idx
    ON academic_periods(university_id, status);


-- ---------------------------------------------------------
-- 9. PROGRAMME COURSES
-- Maps courses to a specific curriculum version.
-- References semester definitions, not actual periods.
-- ---------------------------------------------------------

CREATE TABLE programme_courses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,

    curriculum_version_id UUID NOT NULL,
    academic_course_id UUID NOT NULL,
    academic_semester_id UUID NOT NULL,

    study_level SMALLINT NOT NULL,
    is_compulsory BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT programme_courses_curriculum_fk
        FOREIGN KEY (curriculum_version_id, university_id)
        REFERENCES curriculum_versions(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT programme_courses_course_fk
        FOREIGN KEY (academic_course_id, university_id)
        REFERENCES academic_courses(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT programme_courses_semester_fk
        FOREIGN KEY (academic_semester_id, university_id)
        REFERENCES academic_semesters(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT programme_courses_level_check
        CHECK (study_level > 0),

    UNIQUE (
        curriculum_version_id,
        academic_course_id
    ),

    UNIQUE (
        curriculum_version_id,
        academic_course_id,
        university_id
    )
);

CREATE INDEX programme_courses_course_idx
    ON programme_courses(academic_course_id);

CREATE INDEX programme_courses_curriculum_idx
    ON programme_courses(curriculum_version_id);


-- ---------------------------------------------------------
-- 10. COURSE OFFERINGS
-- A course delivered during a particular academic period.
-- One offering can serve multiple programme curricula.
-- ---------------------------------------------------------

CREATE TABLE course_offerings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,

    academic_course_id UUID NOT NULL,
    academic_period_id UUID NOT NULL,

    offering_code VARCHAR(80),

    status VARCHAR(20) NOT NULL DEFAULT 'planned'
        CHECK (status IN (
            'planned',
            'active',
            'completed',
            'cancelled'
        )),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT course_offerings_course_fk
        FOREIGN KEY (academic_course_id, university_id)
        REFERENCES academic_courses(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT course_offerings_period_fk
        FOREIGN KEY (academic_period_id, university_id)
        REFERENCES academic_periods(id, university_id)
        ON DELETE RESTRICT,

    UNIQUE (id, university_id, academic_course_id),

    UNIQUE (
        university_id,
        academic_course_id,
        academic_period_id
    )
);

CREATE INDEX course_offerings_period_idx
    ON course_offerings(academic_period_id);

CREATE INDEX course_offerings_university_status_idx
    ON course_offerings(university_id, status);


-- ---------------------------------------------------------
-- 11. OFFERING PROGRAMMES
-- Connects a course offering to the curriculum versions
-- that include the course.
-- ---------------------------------------------------------

CREATE TABLE offering_programmes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,

    course_offering_id UUID NOT NULL,
    academic_course_id UUID NOT NULL,
    curriculum_version_id UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT offering_programmes_offering_fk
        FOREIGN KEY (
            course_offering_id,
            university_id,
            academic_course_id
        )
        REFERENCES course_offerings(
            id,
            university_id,
            academic_course_id
        )
        ON DELETE RESTRICT,

    CONSTRAINT offering_programmes_curriculum_course_fk
        FOREIGN KEY (
            curriculum_version_id,
            academic_course_id,
            university_id
        )
        REFERENCES programme_courses(
            curriculum_version_id,
            academic_course_id,
            university_id
        )
        ON DELETE RESTRICT,

    UNIQUE (course_offering_id, curriculum_version_id)
);

CREATE INDEX offering_programmes_curriculum_idx
    ON offering_programmes(curriculum_version_id);


-- ---------------------------------------------------------
-- 12. ROLE ASSIGNMENT DEPARTMENT FOREIGN KEY
-- Now that departments exist, enforce department scope.
-- A department administrator must belong to a department
-- within the same university specified in role_assignments.
-- ---------------------------------------------------------

ALTER TABLE role_assignments
    ADD CONSTRAINT role_assignments_department_fk
    FOREIGN KEY (department_id, university_id)
    REFERENCES departments(id, university_id)
    ON DELETE RESTRICT;


-- ---------------------------------------------------------
-- END MIGRATION
-- ---------------------------------------------------------

COMMIT;
