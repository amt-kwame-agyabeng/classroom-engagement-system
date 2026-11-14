
BEGIN;

-- =========================================================
-- 1. UNIVERSITY TIMEZONE
-- Existing universities default to Ghana time.
-- =========================================================

ALTER TABLE universities
ADD COLUMN timezone_name VARCHAR(100) NOT NULL
DEFAULT 'Africa/Accra';


-- =========================================================
-- 2. CLASS INVITATIONS
-- Email-based invitations to join a class section.
-- Store only hashed invitation tokens.
-- =========================================================

CREATE TABLE class_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,
    class_section_id UUID NOT NULL,

    invited_email VARCHAR(255) NOT NULL,
    token_hash CHAR(64) NOT NULL UNIQUE,

    invited_by UUID NOT NULL,
    accepted_by_user_id UUID,

    status VARCHAR(20) NOT NULL DEFAULT 'pending',

    expires_at TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT class_invitations_status_check
        CHECK (status IN ('pending', 'accepted', 'expired', 'revoked')),

    CONSTRAINT class_invitations_email_check
        CHECK (LENGTH(TRIM(invited_email)) > 0),

    CONSTRAINT class_invitations_state_check
        CHECK (
            (status = 'pending'
                AND accepted_by_user_id IS NULL
                AND accepted_at IS NULL
                AND revoked_at IS NULL)
            OR
            (status = 'accepted'
                AND accepted_by_user_id IS NOT NULL
                AND accepted_at IS NOT NULL
                AND revoked_at IS NULL)
            OR
            (status = 'expired'
                AND accepted_by_user_id IS NULL
                AND accepted_at IS NULL
                AND revoked_at IS NULL)
            OR
            (status = 'revoked'
                AND accepted_by_user_id IS NULL
                AND accepted_at IS NULL
                AND revoked_at IS NOT NULL)
        ),

    CONSTRAINT class_invitations_section_fk
        FOREIGN KEY (class_section_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT class_invitations_invited_by_fk
        FOREIGN KEY (invited_by)
        REFERENCES users(id)
        ON DELETE RESTRICT,

    CONSTRAINT class_invitations_accepted_membership_fk
        FOREIGN KEY (university_id, accepted_by_user_id)
        REFERENCES university_memberships(university_id, user_id)
        ON DELETE RESTRICT
);

CREATE INDEX class_invitations_section_status_idx
    ON class_invitations(class_section_id, status);

CREATE INDEX class_invitations_email_idx
    ON class_invitations(LOWER(invited_email));

CREATE UNIQUE INDEX class_invitations_pending_email_unique
    ON class_invitations(class_section_id, LOWER(invited_email))
    WHERE status = 'pending';


-- =========================================================
-- 3. CLASS ACCESS CODES
-- Store hashed codes, never the usable plaintext code.
-- Only one active code per class section.
-- =========================================================

CREATE TABLE class_access_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,
    class_section_id UUID NOT NULL,

    code_hash CHAR(64) NOT NULL UNIQUE,

    created_by UUID NOT NULL,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT class_access_codes_state_check
        CHECK (
            (is_active = TRUE AND revoked_at IS NULL)
            OR
            (is_active = FALSE AND revoked_at IS NOT NULL)
        ),

    CONSTRAINT class_access_codes_section_fk
        FOREIGN KEY (class_section_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT class_access_codes_created_by_fk
        FOREIGN KEY (created_by)
        REFERENCES users(id)
        ON DELETE RESTRICT
);

CREATE UNIQUE INDEX class_access_codes_one_active_idx
    ON class_access_codes(class_section_id)
    WHERE is_active = TRUE;

CREATE INDEX class_access_codes_section_idx
    ON class_access_codes(university_id, class_section_id);


-- =========================================================
-- 4. CLASS SCHEDULE RULES
-- Defines recurring weekly timetable entries.
--
-- weekday:
-- 0 = Sunday
-- 1 = Monday
-- 2 = Tuesday
-- 3 = Wednesday
-- 4 = Thursday
-- 5 = Friday
-- 6 = Saturday
--
-- Times are stored as local university times.
-- =========================================================

CREATE TABLE class_schedule_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,
    class_section_id UUID NOT NULL,

    weekday SMALLINT NOT NULL,

    start_time TIME NOT NULL,
    end_time TIME NOT NULL,

    effective_start_date DATE NOT NULL,
    effective_end_date DATE NOT NULL,

    timezone_name VARCHAR(100) NOT NULL,

    status VARCHAR(20) NOT NULL DEFAULT 'active',

    created_by UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT class_schedule_rules_weekday_check
        CHECK (weekday BETWEEN 0 AND 6),

    CONSTRAINT class_schedule_rules_time_check
        CHECK (end_time > start_time),

    CONSTRAINT class_schedule_rules_dates_check
        CHECK (effective_end_date >= effective_start_date),

    CONSTRAINT class_schedule_rules_status_check
        CHECK (status IN ('active', 'paused', 'ended')),

    CONSTRAINT class_schedule_rules_id_section_unique
        UNIQUE (id, class_section_id, university_id),

    CONSTRAINT class_schedule_rules_section_fk
        FOREIGN KEY (class_section_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT class_schedule_rules_created_by_fk
        FOREIGN KEY (created_by)
        REFERENCES users(id)
        ON DELETE RESTRICT
);

CREATE INDEX class_schedule_rules_section_status_idx
    ON class_schedule_rules(class_section_id, status);

CREATE INDEX class_schedule_rules_date_idx
    ON class_schedule_rules(effective_start_date, effective_end_date);


-- =========================================================
-- 5. CLASS SESSIONS
-- Individual scheduled teaching sessions.
--
-- schedule_rule_id is NULL for manually created sessions.
-- starts_at and ends_at are timezone-aware timestamps.
-- session_date preserves the local calendar date.
-- =========================================================

CREATE TABLE class_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL,
    class_section_id UUID NOT NULL,
    schedule_rule_id UUID,

    session_title VARCHAR(150),

    session_date DATE NOT NULL,

    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,

    timezone_name VARCHAR(100) NOT NULL,

    status VARCHAR(20) NOT NULL DEFAULT 'scheduled',

    created_by UUID NOT NULL,

    completed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT class_sessions_time_check
        CHECK (ends_at > starts_at),

    CONSTRAINT class_sessions_status_check
        CHECK (status IN ('scheduled', 'completed', 'cancelled')),

    CONSTRAINT class_sessions_state_check
        CHECK (
            (status = 'scheduled'
                AND completed_at IS NULL
                AND cancelled_at IS NULL)
            OR
            (status = 'completed'
                AND completed_at IS NOT NULL
                AND cancelled_at IS NULL)
            OR
            (status = 'cancelled'
                AND completed_at IS NULL
                AND cancelled_at IS NOT NULL)
        ),

    CONSTRAINT class_sessions_section_fk
        FOREIGN KEY (class_section_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT class_sessions_schedule_rule_fk
        FOREIGN KEY (schedule_rule_id, class_section_id, university_id)
        REFERENCES class_schedule_rules(id, class_section_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT class_sessions_created_by_fk
        FOREIGN KEY (created_by)
        REFERENCES users(id)
        ON DELETE RESTRICT
);

-- Prevent duplicate sessions generated from the same rule.
CREATE UNIQUE INDEX class_sessions_rule_date_unique
    ON class_sessions(schedule_rule_id, session_date)
    WHERE schedule_rule_id IS NOT NULL;

-- Prevent two sessions in the same section from having
-- exactly the same start timestamp.
CREATE UNIQUE INDEX class_sessions_section_start_unique
    ON class_sessions(class_section_id, starts_at);

CREATE INDEX class_sessions_section_date_idx
    ON class_sessions(class_section_id, session_date);

CREATE INDEX class_sessions_university_date_idx
    ON class_sessions(university_id, session_date);

CREATE INDEX class_sessions_rule_idx
    ON class_sessions(schedule_rule_id)
    WHERE schedule_rule_id IS NOT NULL;

COMMIT;
