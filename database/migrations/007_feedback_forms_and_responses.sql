
BEGIN;

-- =========================================================
-- MIGRATION 007: FEEDBACK FORMS AND RESPONSES
-- =========================================================

-- =========================================================
-- 1. FEEDBACK TEMPLATES
-- =========================================================

CREATE TABLE feedback_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID,
    created_by UUID,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    template_scope VARCHAR(20) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT feedback_templates_title_check
        CHECK (LENGTH(TRIM(title)) > 0),

    CONSTRAINT feedback_templates_scope_check
        CHECK (template_scope IN ('platform', 'university')),

    CONSTRAINT feedback_templates_scope_fk
        CHECK (
            (template_scope = 'platform' AND university_id IS NULL)
            OR
            (template_scope = 'university' AND university_id IS NOT NULL)
        ),

    CONSTRAINT feedback_templates_university_fk
        FOREIGN KEY (university_id)
        REFERENCES universities(id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_templates_creator_fk
        FOREIGN KEY (created_by)
        REFERENCES users(id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_templates_id_university_unique
        UNIQUE (id, university_id)
);

CREATE INDEX feedback_templates_scope_idx
    ON feedback_templates(template_scope, is_active);

CREATE INDEX feedback_templates_university_idx
    ON feedback_templates(university_id, is_active)
    WHERE university_id IS NOT NULL;

-- =========================================================
-- 2. FEEDBACK TEMPLATE QUESTIONS
-- =========================================================

CREATE TABLE feedback_template_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id UUID NOT NULL,
    question_text TEXT NOT NULL,
    question_type VARCHAR(30) NOT NULL,
    display_order SMALLINT NOT NULL,
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    min_rating SMALLINT,
    max_rating SMALLINT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT feedback_template_questions_text_check
        CHECK (LENGTH(TRIM(question_text)) > 0),

    CONSTRAINT feedback_template_questions_type_check
        CHECK (
            question_type IN (
                'short_text',
                'long_text',
                'single_choice',
                'multiple_select',
                'rating'
            )
        ),

    CONSTRAINT feedback_template_questions_order_check
        CHECK (display_order > 0),

    CONSTRAINT feedback_template_questions_rating_check
        CHECK (
            (
                question_type = 'rating'
                AND min_rating IS NOT NULL
                AND max_rating IS NOT NULL
                AND min_rating < max_rating
            )
            OR
            (
                question_type <> 'rating'
                AND min_rating IS NULL
                AND max_rating IS NULL
            )
        ),

    CONSTRAINT feedback_template_questions_template_fk
        FOREIGN KEY (template_id)
        REFERENCES feedback_templates(id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_template_questions_template_order_unique
        UNIQUE (template_id, display_order),

    CONSTRAINT feedback_template_questions_id_template_unique
        UNIQUE (id, template_id)
);

CREATE INDEX feedback_template_questions_template_idx
    ON feedback_template_questions(template_id, display_order);

-- =========================================================
-- 3. FEEDBACK TEMPLATE OPTIONS
-- =========================================================

CREATE TABLE feedback_template_options (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id UUID NOT NULL,
    question_id UUID NOT NULL,
    option_text VARCHAR(500) NOT NULL,
    display_order SMALLINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT feedback_template_options_text_check
        CHECK (LENGTH(TRIM(option_text)) > 0),

    CONSTRAINT feedback_template_options_order_check
        CHECK (display_order > 0),

    CONSTRAINT feedback_template_options_question_fk
        FOREIGN KEY (question_id, template_id)
        REFERENCES feedback_template_questions(id, template_id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_template_options_question_order_unique
        UNIQUE (question_id, display_order),

    CONSTRAINT feedback_template_options_id_question_unique
        UNIQUE (id, question_id, template_id)
);

CREATE INDEX feedback_template_options_question_idx
    ON feedback_template_options(question_id, display_order);

-- =========================================================
-- 4. FEEDBACK FORMS
-- =========================================================

CREATE TABLE feedback_forms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    class_section_id UUID NOT NULL,
    session_id UUID,
    template_id UUID,
    template_university_id UUID,
    created_by UUID NOT NULL,

    title VARCHAR(200) NOT NULL,
    description TEXT,

    is_anonymous BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',

    opens_at TIMESTAMPTZ,
    closes_at TIMESTAMPTZ,
    results_released_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT feedback_forms_title_check
        CHECK (LENGTH(TRIM(title)) > 0),

    CONSTRAINT feedback_forms_status_check
        CHECK (
            status IN ('draft', 'scheduled', 'open', 'closed', 'cancelled')
        ),

    CONSTRAINT feedback_forms_dates_check
        CHECK (
            opens_at IS NULL
            OR closes_at IS NULL
            OR closes_at > opens_at
        ),

    CONSTRAINT feedback_forms_release_check
        CHECK (
            results_released_at IS NULL
            OR status = 'closed'
        ),

    CONSTRAINT feedback_forms_class_fk
        FOREIGN KEY (class_section_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_forms_session_fk
        FOREIGN KEY (session_id, class_section_id, university_id)
        REFERENCES class_sessions(id, class_section_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_forms_template_fk
        FOREIGN KEY (template_id)
        REFERENCES feedback_templates(id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_forms_template_university_fk
        FOREIGN KEY (template_id, template_university_id)
        REFERENCES feedback_templates(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_forms_template_university_check
        CHECK (
            template_university_id IS NULL
            OR template_university_id = university_id
        ),

    CONSTRAINT feedback_forms_creator_fk
        FOREIGN KEY (created_by)
        REFERENCES users(id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_forms_id_university_unique
        UNIQUE (id, university_id)
);

CREATE INDEX feedback_forms_class_status_idx
    ON feedback_forms(class_section_id, status, created_at DESC);

CREATE INDEX feedback_forms_university_idx
    ON feedback_forms(university_id, created_at DESC);

CREATE INDEX feedback_forms_session_idx
    ON feedback_forms(session_id)
    WHERE session_id IS NOT NULL;

-- =========================================================
-- 5. FEEDBACK QUESTIONS
-- Questions are copied from templates when a form is created.
-- =========================================================

CREATE TABLE feedback_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    form_id UUID NOT NULL,

    question_text TEXT NOT NULL,
    question_type VARCHAR(30) NOT NULL,
    display_order SMALLINT NOT NULL,
    is_required BOOLEAN NOT NULL DEFAULT TRUE,

    min_rating SMALLINT,
    max_rating SMALLINT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT feedback_questions_text_check
        CHECK (LENGTH(TRIM(question_text)) > 0),

    CONSTRAINT feedback_questions_type_check
        CHECK (
            question_type IN (
                'short_text',
                'long_text',
                'single_choice',
                'multiple_select',
                'rating'
            )
        ),

    CONSTRAINT feedback_questions_order_check
        CHECK (display_order > 0),

    CONSTRAINT feedback_questions_rating_check
        CHECK (
            (
                question_type = 'rating'
                AND min_rating IS NOT NULL
                AND max_rating IS NOT NULL
                AND min_rating < max_rating
            )
            OR
            (
                question_type <> 'rating'
                AND min_rating IS NULL
                AND max_rating IS NULL
            )
        ),

    CONSTRAINT feedback_questions_form_fk
        FOREIGN KEY (form_id, university_id)
        REFERENCES feedback_forms(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_questions_form_order_unique
        UNIQUE (form_id, display_order),

    CONSTRAINT feedback_questions_id_form_unique
        UNIQUE (id, form_id, university_id)
);

CREATE INDEX feedback_questions_form_idx
    ON feedback_questions(form_id, display_order);

-- =========================================================
-- 6. FEEDBACK QUESTION OPTIONS
-- =========================================================

CREATE TABLE feedback_question_options (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    form_id UUID NOT NULL,
    question_id UUID NOT NULL,

    option_text VARCHAR(500) NOT NULL,
    display_order SMALLINT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT feedback_question_options_text_check
        CHECK (LENGTH(TRIM(option_text)) > 0),

    CONSTRAINT feedback_question_options_order_check
        CHECK (display_order > 0),

    CONSTRAINT feedback_question_options_question_fk
        FOREIGN KEY (question_id, form_id, university_id)
        REFERENCES feedback_questions(id, form_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_question_options_order_unique
        UNIQUE (question_id, display_order),

    CONSTRAINT feedback_question_options_id_question_unique
        UNIQUE (id, question_id, form_id, university_id)
);

CREATE INDEX feedback_question_options_question_idx
    ON feedback_question_options(question_id, display_order);

-- =========================================================
-- 7. FEEDBACK SUBMISSIONS
-- One submission per student per form.
-- Anonymous identity uses a server-generated protected key.
-- =========================================================

CREATE TABLE feedback_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    form_id UUID NOT NULL,

    student_user_id UUID,
    anonymous_participant_key BYTEA,

    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT feedback_submissions_identity_check
        CHECK (
            (student_user_id IS NOT NULL AND anonymous_participant_key IS NULL)
            OR
            (student_user_id IS NULL AND anonymous_participant_key IS NOT NULL)
        ),

    CONSTRAINT feedback_submissions_anonymous_key_check
        CHECK (
            anonymous_participant_key IS NULL
            OR OCTET_LENGTH(anonymous_participant_key) >= 32
        ),

    CONSTRAINT feedback_submissions_form_fk
        FOREIGN KEY (form_id, university_id)
        REFERENCES feedback_forms(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_submissions_student_fk
        FOREIGN KEY (university_id, student_user_id)
        REFERENCES university_memberships(university_id, user_id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_submissions_id_form_unique
        UNIQUE (id, form_id, university_id)
);

CREATE UNIQUE INDEX feedback_submissions_named_unique
    ON feedback_submissions(form_id, student_user_id)
    WHERE student_user_id IS NOT NULL;

CREATE UNIQUE INDEX feedback_submissions_anonymous_unique
    ON feedback_submissions(form_id, anonymous_participant_key)
    WHERE anonymous_participant_key IS NOT NULL;

CREATE INDEX feedback_submissions_form_submitted_idx
    ON feedback_submissions(form_id, submitted_at DESC);

CREATE INDEX feedback_submissions_student_idx
    ON feedback_submissions(university_id, student_user_id)
    WHERE student_user_id IS NOT NULL;

-- =========================================================
-- 8. FEEDBACK ANSWERS
-- One answer per question per submission.
-- =========================================================

CREATE TABLE feedback_answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    form_id UUID NOT NULL,
    submission_id UUID NOT NULL,
    question_id UUID NOT NULL,

    text_response TEXT,
    rating_value SMALLINT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT feedback_answers_submission_fk
        FOREIGN KEY (submission_id, form_id, university_id)
        REFERENCES feedback_submissions(id, form_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_answers_question_fk
        FOREIGN KEY (question_id, form_id, university_id)
        REFERENCES feedback_questions(id, form_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_answers_id_question_unique
        UNIQUE (id, question_id, form_id, university_id),

    CONSTRAINT feedback_answers_submission_question_unique
        UNIQUE (submission_id, question_id),

    CONSTRAINT feedback_answers_rating_nonnegative
        CHECK (rating_value IS NULL OR rating_value >= 0)
);

CREATE INDEX feedback_answers_question_idx
    ON feedback_answers(question_id, form_id);

-- =========================================================
-- 9. FEEDBACK ANSWER SELECTIONS
-- Stores selected options for choice questions.
-- =========================================================

CREATE TABLE feedback_answer_selections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    form_id UUID NOT NULL,
    question_id UUID NOT NULL,
    answer_id UUID NOT NULL,
    selected_option_id UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT feedback_answer_selections_answer_fk
        FOREIGN KEY (answer_id, question_id, form_id, university_id)
        REFERENCES feedback_answers(id, question_id, form_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT feedback_answer_selections_option_fk
        FOREIGN KEY (
            selected_option_id,
            question_id,
            form_id,
            university_id
        )
        REFERENCES feedback_question_options(
            id,
            question_id,
            form_id,
            university_id
        )
        ON DELETE RESTRICT,

    CONSTRAINT feedback_answer_selections_unique
        UNIQUE (answer_id, selected_option_id)
);

CREATE INDEX feedback_answer_selections_answer_idx
    ON feedback_answer_selections(answer_id);

CREATE INDEX feedback_answer_selections_option_idx
    ON feedback_answer_selections(question_id, selected_option_id);

COMMIT;
