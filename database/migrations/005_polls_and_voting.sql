
BEGIN;

-- =========================================================
-- MIGRATION 005: POLLS AND VOTING
-- =========================================================

-- =========================================================
-- 1. POLLS
-- Stores poll configuration and publication settings.
-- =========================================================

CREATE TABLE polls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    CONSTRAINT polls_id_university_unique
    UNIQUE (id, university_id),
    class_section_id UUID NOT NULL,
    session_id UUID,
    created_by UUID NOT NULL,

    title VARCHAR(200) NOT NULL,
    description TEXT,

    poll_type VARCHAR(20) NOT NULL,
    is_anonymous BOOLEAN NOT NULL DEFAULT FALSE,
    allow_vote_changes BOOLEAN NOT NULL DEFAULT FALSE,
    show_results_before_close BOOLEAN NOT NULL DEFAULT FALSE,

    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    opens_at TIMESTAMPTZ,
    closes_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT polls_title_not_empty
        CHECK (LENGTH(TRIM(title)) > 0),

    CONSTRAINT polls_description_not_empty
        CHECK (
            description IS NULL
            OR LENGTH(TRIM(description)) > 0
        ),

    CONSTRAINT polls_type_check
        CHECK (poll_type IN ('single_choice', 'multiple_choice')),

    CONSTRAINT polls_status_check
        CHECK (status IN ('draft', 'scheduled', 'open', 'closed', 'cancelled')),

    CONSTRAINT polls_dates_check
        CHECK (
            opens_at IS NULL
            OR closes_at IS NULL
            OR closes_at > opens_at
        ),

    CONSTRAINT polls_class_fk
        FOREIGN KEY (class_section_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT polls_session_fk
        FOREIGN KEY (session_id, class_section_id, university_id)
        REFERENCES class_sessions(id, class_section_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT polls_creator_fk
        FOREIGN KEY (created_by)
        REFERENCES users(id)
        ON DELETE RESTRICT
);

CREATE INDEX polls_class_status_idx
    ON polls(class_section_id, status, created_at DESC);

CREATE INDEX polls_university_created_idx
    ON polls(university_id, created_at DESC);

CREATE INDEX polls_session_idx
    ON polls(session_id)
    WHERE session_id IS NOT NULL;

-- =========================================================
-- 2. POLL OPTIONS
-- Stores the available choices for each poll.
-- =========================================================

CREATE TABLE poll_options (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    poll_id UUID NOT NULL,
    option_text VARCHAR(500) NOT NULL,
    display_order SMALLINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT poll_options_text_not_empty
        CHECK (LENGTH(TRIM(option_text)) > 0),

    CONSTRAINT poll_options_display_order_check
        CHECK (display_order > 0),

    CONSTRAINT poll_options_poll_fk
        FOREIGN KEY (poll_id, university_id)
        REFERENCES polls(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT poll_options_id_poll_unique
        UNIQUE (id, poll_id, university_id),

    CONSTRAINT poll_options_poll_order_unique
        UNIQUE (poll_id, display_order)
);

CREATE INDEX poll_options_poll_idx
    ON poll_options(poll_id, display_order);

-- =========================================================
-- 3. POLL SUBMISSIONS
-- One submission per student or anonymous participant.
-- =========================================================

CREATE TABLE poll_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    poll_id UUID NOT NULL,

    student_user_id UUID,
    anonymous_participant_key BYTEA,

    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT poll_submissions_identity_check
        CHECK (
            (
                student_user_id IS NOT NULL
                AND anonymous_participant_key IS NULL
            )
            OR
            (
                student_user_id IS NULL
                AND anonymous_participant_key IS NOT NULL
            )
        ),

    CONSTRAINT poll_submissions_poll_fk
        FOREIGN KEY (poll_id, university_id)
        REFERENCES polls(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT poll_submissions_student_membership_fk
        FOREIGN KEY (university_id, student_user_id)
        REFERENCES university_memberships(university_id, user_id)
        ON DELETE RESTRICT,

    CONSTRAINT poll_submissions_id_poll_unique
        UNIQUE (id, poll_id, university_id)
);

CREATE UNIQUE INDEX poll_submissions_named_unique
    ON poll_submissions(poll_id, student_user_id)
    WHERE student_user_id IS NOT NULL;

CREATE UNIQUE INDEX poll_submissions_anonymous_unique
    ON poll_submissions(poll_id, anonymous_participant_key)
    WHERE anonymous_participant_key IS NOT NULL;

CREATE INDEX poll_submissions_poll_submitted_idx
    ON poll_submissions(poll_id, submitted_at DESC);

-- =========================================================
-- 4. POLL VOTE SELECTIONS
-- Stores one or more options selected by a submission.
-- =========================================================


CREATE TABLE poll_vote_selections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    poll_id UUID NOT NULL,
    submission_id UUID NOT NULL,
    poll_option_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT poll_vote_selections_poll_fk
        FOREIGN KEY (poll_id, university_id)
        REFERENCES polls(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT poll_vote_selections_submission_fk
        FOREIGN KEY (submission_id, poll_id, university_id)
        REFERENCES poll_submissions(id, poll_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT poll_vote_selections_option_fk
        FOREIGN KEY (poll_option_id, poll_id, university_id)
        REFERENCES poll_options(id, poll_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT poll_vote_selections_submission_option_unique
        UNIQUE (submission_id, poll_option_id)
);

CREATE INDEX poll_vote_selections_poll_option_idx
    ON poll_vote_selections(poll_id, poll_option_id);

CREATE INDEX poll_vote_selections_university_idx
    ON poll_vote_selections(university_id, poll_id);


COMMIT;
