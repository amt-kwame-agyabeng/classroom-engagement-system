BEGIN;

-- =========================================================
-- MIGRATION 009: ANALYTICS AND HISTORICAL SNAPSHOTS
-- =========================================================

-- =========================================================
-- 1. ANALYTICS REFRESH JOBS
-- Tracks background analytics calculation jobs.
-- =========================================================

CREATE TABLE analytics_refresh_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,

    class_id UUID,
    course_offering_id UUID,
    department_id UUID,
    university_scope_id UUID,

    job_status VARCHAR(20) NOT NULL DEFAULT 'pending',

    scheduled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,

    attempt_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT analytics_refresh_jobs_class_fk
        FOREIGN KEY (class_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT analytics_refresh_jobs_course_fk
        FOREIGN KEY (course_offering_id, university_id)
        REFERENCES course_offerings(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT analytics_refresh_jobs_department_fk
        FOREIGN KEY (department_id, university_id)
        REFERENCES departments(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT analytics_refresh_jobs_university_scope_fk
        FOREIGN KEY (university_scope_id)
        REFERENCES universities(id)
        ON DELETE RESTRICT,

    CONSTRAINT analytics_refresh_jobs_one_scope_check
        CHECK (
            num_nonnulls(
                class_id,
                course_offering_id,
                department_id,
                university_scope_id
            ) = 1
        ),


    CONSTRAINT analytics_refresh_jobs_university_scope_check
        CHECK (
            university_scope_id IS NULL
            OR university_scope_id = university_id
        ),


    CONSTRAINT analytics_refresh_jobs_status_check
        CHECK (
            job_status IN (
                'pending',
                'processing',
                'completed',
                'failed'
            )
        ),

    CONSTRAINT analytics_refresh_jobs_attempt_check
        CHECK (attempt_count >= 0),


    CONSTRAINT analytics_refresh_jobs_status_dates_check
        CHECK (
            (job_status = 'pending'
                AND started_at IS NULL
                AND completed_at IS NULL)
            OR
            (job_status = 'processing'
                AND started_at IS NOT NULL
                AND completed_at IS NULL)
            OR
            (job_status IN ('completed', 'failed')
                AND started_at IS NOT NULL
                AND completed_at IS NOT NULL)
        ),

    CONSTRAINT analytics_refresh_jobs_timestamp_order_check
        CHECK (
            completed_at IS NULL
            OR completed_at >= started_at
        ),

    CONSTRAINT analytics_refresh_jobs_university_fk
        FOREIGN KEY (university_id)
        REFERENCES universities(id)
        ON DELETE RESTRICT
);

CREATE INDEX analytics_refresh_jobs_status_scheduled_idx
    ON analytics_refresh_jobs(job_status, scheduled_at);

CREATE INDEX analytics_refresh_jobs_university_idx
    ON analytics_refresh_jobs(university_id, created_at DESC);



-- =========================================================
-- 2. CLASS ANALYTICS
-- Stores the latest calculated engagement statistics per class.
-- =========================================================

CREATE TABLE class_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,
    class_section_id UUID NOT NULL,

    total_students INTEGER NOT NULL DEFAULT 0,
    participating_students INTEGER NOT NULL DEFAULT 0,
    total_questions INTEGER NOT NULL DEFAULT 0,
    total_poll_responses INTEGER NOT NULL DEFAULT 0,
    total_quiz_submissions INTEGER NOT NULL DEFAULT 0,
    total_feedback_responses INTEGER NOT NULL DEFAULT 0,

    participation_rate NUMERIC(5,2) NOT NULL DEFAULT 0,

    calculated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT class_analytics_counts_check
        CHECK (
            total_students >= 0
            AND participating_students >= 0
            AND participating_students <= total_students
            AND total_questions >= 0
            AND total_poll_responses >= 0
            AND total_quiz_submissions >= 0
            AND total_feedback_responses >= 0
        ),

    CONSTRAINT class_analytics_rate_check
        CHECK (participation_rate BETWEEN 0 AND 100),

    CONSTRAINT class_analytics_class_unique
        UNIQUE (class_section_id),

    CONSTRAINT class_analytics_class_fk
        FOREIGN KEY (class_section_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT
);

CREATE INDEX class_analytics_university_idx
    ON class_analytics(university_id, calculated_at DESC);


-- =========================================================
-- 3. COURSE ANALYTICS
-- Stores the latest calculated statistics per course offering.
-- =========================================================

CREATE TABLE course_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,
    course_offering_id UUID NOT NULL,

    total_classes INTEGER NOT NULL DEFAULT 0,
    total_students INTEGER NOT NULL DEFAULT 0,
    participating_students INTEGER NOT NULL DEFAULT 0,
    total_questions INTEGER NOT NULL DEFAULT 0,
    total_poll_responses INTEGER NOT NULL DEFAULT 0,
    total_quiz_submissions INTEGER NOT NULL DEFAULT 0,
    total_feedback_responses INTEGER NOT NULL DEFAULT 0,

    participation_rate NUMERIC(5,2) NOT NULL DEFAULT 0,

    calculated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT course_analytics_counts_check
        CHECK (
            total_classes >= 0
            AND total_students >= 0
            AND participating_students >= 0
            AND participating_students <= total_students
            AND total_questions >= 0
            AND total_poll_responses >= 0
            AND total_quiz_submissions >= 0
            AND total_feedback_responses >= 0
        ),

    CONSTRAINT course_analytics_rate_check
        CHECK (participation_rate BETWEEN 0 AND 100),

    CONSTRAINT course_analytics_offering_unique
        UNIQUE (course_offering_id),

    CONSTRAINT course_analytics_offering_fk
        FOREIGN KEY (course_offering_id, university_id)
        REFERENCES course_offerings(id, university_id)
        ON DELETE RESTRICT
);

CREATE INDEX course_analytics_university_idx
    ON course_analytics(university_id, calculated_at DESC);


-- =========================================================
-- 4. DEPARTMENT ANALYTICS
-- Stores the latest calculated statistics per department.
-- =========================================================

CREATE TABLE department_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,
    department_id UUID NOT NULL,

    total_courses INTEGER NOT NULL DEFAULT 0,
    total_classes INTEGER NOT NULL DEFAULT 0,
    total_students INTEGER NOT NULL DEFAULT 0,
    participating_students INTEGER NOT NULL DEFAULT 0,
    total_questions INTEGER NOT NULL DEFAULT 0,
    total_poll_responses INTEGER NOT NULL DEFAULT 0,
    total_quiz_submissions INTEGER NOT NULL DEFAULT 0,
    total_feedback_responses INTEGER NOT NULL DEFAULT 0,

    participation_rate NUMERIC(5,2) NOT NULL DEFAULT 0,

    calculated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT department_analytics_counts_check
        CHECK (
            total_courses >= 0
            AND total_classes >= 0
            AND total_students >= 0
            AND participating_students >= 0
            AND participating_students <= total_students
            AND total_questions >= 0
            AND total_poll_responses >= 0
            AND total_quiz_submissions >= 0
            AND total_feedback_responses >= 0
        ),

    CONSTRAINT department_analytics_rate_check
        CHECK (participation_rate BETWEEN 0 AND 100),

    CONSTRAINT department_analytics_department_unique
        UNIQUE (department_id),

    CONSTRAINT department_analytics_department_fk
        FOREIGN KEY (department_id, university_id)
        REFERENCES departments(id, university_id)
        ON DELETE RESTRICT
);

CREATE INDEX department_analytics_university_idx
    ON department_analytics(university_id, calculated_at DESC);


-- =========================================================
-- 5. UNIVERSITY ANALYTICS
-- Stores the latest calculated statistics per university.
-- =========================================================

CREATE TABLE university_analytics (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL UNIQUE,

    total_departments INTEGER NOT NULL DEFAULT 0,
    total_courses INTEGER NOT NULL DEFAULT 0,
    total_classes INTEGER NOT NULL DEFAULT 0,
    total_students INTEGER NOT NULL DEFAULT 0,
    participating_students INTEGER NOT NULL DEFAULT 0,
    total_questions INTEGER NOT NULL DEFAULT 0,
    total_poll_responses INTEGER NOT NULL DEFAULT 0,
    total_quiz_submissions INTEGER NOT NULL DEFAULT 0,
    total_feedback_responses INTEGER NOT NULL DEFAULT 0,

    participation_rate NUMERIC(5,2) NOT NULL DEFAULT 0,

    calculated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT university_analytics_counts_check
        CHECK (
            total_departments >= 0
            AND total_courses >= 0
            AND total_classes >= 0
            AND total_students >= 0
            AND participating_students >= 0
            AND participating_students <= total_students
            AND total_questions >= 0
            AND total_poll_responses >= 0
            AND total_quiz_submissions >= 0
            AND total_feedback_responses >= 0
        ),

    CONSTRAINT university_analytics_rate_check
        CHECK (participation_rate BETWEEN 0 AND 100),

    CONSTRAINT university_analytics_university_fk
        FOREIGN KEY (university_id)
        REFERENCES universities(id)
        ON DELETE RESTRICT
);

CREATE INDEX university_analytics_calculated_idx
    ON university_analytics(calculated_at DESC);


-- =========================================================
-- 6. ANALYTICS SNAPSHOTS
-- Preserves historical analytics for trend analysis.
-- Exactly one scope reference must be populated.
-- =========================================================

CREATE TABLE analytics_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,

    class_id UUID,
    course_offering_id UUID,
    department_id UUID,
    university_scope_id UUID,

    metrics JSONB NOT NULL,

    calculated_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT analytics_snapshots_one_scope_check
        CHECK (
            num_nonnulls(
                class_id,
                course_offering_id,
                department_id,
                university_scope_id
            ) = 1
        ),

    CONSTRAINT analytics_snapshots_university_scope_check
        CHECK (
            university_scope_id IS NULL
            OR university_scope_id = university_id
        ),

    CONSTRAINT analytics_snapshots_metrics_check
        CHECK (
            jsonb_typeof(metrics) = 'object'
        ),

    CONSTRAINT analytics_snapshots_class_fk
        FOREIGN KEY (class_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT analytics_snapshots_course_fk
        FOREIGN KEY (course_offering_id, university_id)
        REFERENCES course_offerings(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT analytics_snapshots_department_fk
        FOREIGN KEY (department_id, university_id)
        REFERENCES departments(id, university_id)
        ON DELETE RESTRICT,


    CONSTRAINT analytics_snapshots_university_fk
        FOREIGN KEY (university_scope_id)
        REFERENCES universities(id)
        ON DELETE RESTRICT
);

CREATE INDEX analytics_snapshots_class_history_idx
    ON analytics_snapshots(class_id, calculated_at DESC)
    WHERE class_id IS NOT NULL;

CREATE INDEX analytics_snapshots_course_history_idx
    ON analytics_snapshots(course_offering_id, calculated_at DESC)
    WHERE course_offering_id IS NOT NULL;

CREATE INDEX analytics_snapshots_department_history_idx
    ON analytics_snapshots(department_id, calculated_at DESC)
    WHERE department_id IS NOT NULL;

CREATE INDEX analytics_snapshots_university_history_idx
    ON analytics_snapshots(university_scope_id, calculated_at DESC)
    WHERE university_scope_id IS NOT NULL;

CREATE INDEX analytics_snapshots_university_calculated_idx
    ON analytics_snapshots(university_id, calculated_at DESC);


COMMIT;