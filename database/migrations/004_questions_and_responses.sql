
BEGIN;

-- =========================================================
-- MIGRATION 004: STUDENT QUESTIONS AND LECTURER RESPONSES
-- =========================================================

-- Ensure class sessions can be referenced using both their
-- ID and the class/university they belong to.
ALTER TABLE class_sessions
    ADD CONSTRAINT class_sessions_id_class_university_unique
    UNIQUE (id, class_section_id, university_id);

-- =========================================================
-- 1. QUESTIONS
-- Stores question content without storing student identity.
-- =========================================================

CREATE TABLE questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,

    CONSTRAINT questions_id_university_unique
        UNIQUE (id, university_id),
    class_section_id UUID NOT NULL,
    session_id UUID,
    content TEXT NOT NULL,
    is_anonymous BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(20) NOT NULL DEFAULT 'published',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT questions_content_not_empty
        CHECK (LENGTH(TRIM(content)) > 0),

    CONSTRAINT questions_status_check
        CHECK (status IN ('published', 'hidden', 'deleted')),

    CONSTRAINT questions_class_fk
        FOREIGN KEY (class_section_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT questions_session_fk
        FOREIGN KEY (session_id, class_section_id, university_id)
        REFERENCES class_sessions(id, class_section_id, university_id)
        ON DELETE RESTRICT
);

CREATE INDEX questions_class_created_idx
    ON questions(class_section_id, created_at DESC);

CREATE INDEX questions_university_created_idx
    ON questions(university_id, created_at DESC);

CREATE INDEX questions_session_idx
    ON questions(session_id)
    WHERE session_id IS NOT NULL;

CREATE INDEX questions_status_idx
    ON questions(class_section_id, status, created_at DESC);

-- =========================================================
-- 2. QUESTION AUTHORSHIP
-- Links named questions to their student authors.
-- Anonymous questions must not have an entry here.
-- =========================================================

CREATE TABLE question_authorship (
    question_id UUID PRIMARY KEY,
    university_id UUID NOT NULL,
    student_user_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT question_authorship_question_fk
        FOREIGN KEY (question_id, university_id)
        REFERENCES questions(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT question_authorship_membership_fk
        FOREIGN KEY (university_id, student_user_id)
        REFERENCES university_memberships(university_id, user_id)
        ON DELETE RESTRICT
);

CREATE INDEX question_authorship_student_idx
    ON question_authorship(university_id, student_user_id);

-- =========================================================
-- 3. ANONYMOUS QUESTION IDENTITIES
-- Stores encrypted identity mappings separately.
-- Encryption/decryption is handled by the backend.
-- =========================================================

CREATE TABLE anonymous_question_identities (
    question_id UUID PRIMARY KEY,
    university_id UUID NOT NULL,
    encrypted_student_identity BYTEA NOT NULL,
    encryption_key_version VARCHAR(50) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT anonymous_identity_question_fk
        FOREIGN KEY (question_id, university_id)
        REFERENCES questions(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT anonymous_identity_key_version_check
        CHECK (LENGTH(TRIM(encryption_key_version)) > 0)
);

-- =========================================================
-- 4. QUESTION RESPONSES
-- Allows multiple lecturer responses to one question.
-- =========================================================

CREATE TABLE question_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    question_id UUID NOT NULL,
    lecturer_user_id UUID NOT NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT question_responses_content_not_empty
        CHECK (LENGTH(TRIM(content)) > 0),

    CONSTRAINT question_responses_question_fk
        FOREIGN KEY (question_id, university_id)
        REFERENCES questions(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT question_responses_lecturer_membership_fk
        FOREIGN KEY (university_id, lecturer_user_id)
        REFERENCES university_memberships(university_id, user_id)
        ON DELETE RESTRICT
);

CREATE INDEX question_responses_question_created_idx
    ON question_responses(question_id, created_at ASC);

CREATE INDEX question_responses_lecturer_idx
    ON question_responses(university_id, lecturer_user_id, created_at DESC);

COMMIT;
