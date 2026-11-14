
BEGIN;

-- =========================================================
-- MIGRATION 006: QUIZZES AND KNOWLEDGE CHECKS
-- =========================================================

-- =========================================================
-- 1. QUIZZES
-- =========================================================

CREATE TABLE quizzes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    class_section_id UUID NOT NULL,
    session_id UUID,
    created_by UUID NOT NULL,

    title VARCHAR(200) NOT NULL,
    description TEXT,

    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    opens_at TIMESTAMPTZ,
    closes_at TIMESTAMPTZ,

    results_released_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT quizzes_id_university_unique
        UNIQUE (id, university_id),

    CONSTRAINT quizzes_title_not_empty
        CHECK (LENGTH(TRIM(title)) > 0),

    CONSTRAINT quizzes_description_not_empty
        CHECK (
            description IS NULL
            OR LENGTH(TRIM(description)) > 0
        ),

    CONSTRAINT quizzes_status_check
        CHECK (
            status IN ('draft', 'scheduled', 'open', 'closed', 'cancelled')
        ),

    CONSTRAINT quizzes_dates_check
        CHECK (
            opens_at IS NULL
            OR closes_at IS NULL
            OR closes_at > opens_at
        ),

    CONSTRAINT quizzes_results_release_check
        CHECK (
            results_released_at IS NULL
            OR status = 'closed'
        ),

    CONSTRAINT quizzes_class_fk
        FOREIGN KEY (class_section_id, university_id)
        REFERENCES class_sections(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT quizzes_session_fk
        FOREIGN KEY (session_id, class_section_id, university_id)
        REFERENCES class_sessions(id, class_section_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT quizzes_creator_fk
        FOREIGN KEY (created_by)
        REFERENCES users(id)
        ON DELETE RESTRICT
);

CREATE INDEX quizzes_class_status_idx
    ON quizzes(class_section_id, status, created_at DESC);

CREATE INDEX quizzes_university_created_idx
    ON quizzes(university_id, created_at DESC);

CREATE INDEX quizzes_session_idx
    ON quizzes(session_id)
    WHERE session_id IS NOT NULL;

-- =========================================================
-- 2. QUIZ QUESTIONS
-- =========================================================

CREATE TABLE quiz_questions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    quiz_id UUID NOT NULL,

    question_text TEXT NOT NULL,
    question_type VARCHAR(30) NOT NULL,
    display_order SMALLINT NOT NULL,
    marks NUMERIC(7,2) NOT NULL DEFAULT 1.00,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT quiz_questions_text_not_empty
        CHECK (LENGTH(TRIM(question_text)) > 0),

    CONSTRAINT quiz_questions_type_check
        CHECK (
            question_type IN (
                'single_choice',
                'true_false',
                'multiple_select'
            )
        ),

    CONSTRAINT quiz_questions_order_check
        CHECK (display_order > 0),

    CONSTRAINT quiz_questions_marks_check
        CHECK (marks > 0),

    CONSTRAINT quiz_questions_quiz_fk
        FOREIGN KEY (quiz_id, university_id)
        REFERENCES quizzes(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT quiz_questions_id_quiz_unique
        UNIQUE (id, quiz_id, university_id),

    CONSTRAINT quiz_questions_quiz_order_unique
        UNIQUE (quiz_id, display_order)
);

CREATE INDEX quiz_questions_quiz_idx
    ON quiz_questions(quiz_id, display_order);

-- =========================================================
-- 3. QUIZ OPTIONS
-- =========================================================

CREATE TABLE quiz_options (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    quiz_id UUID NOT NULL,
    question_id UUID NOT NULL,

    option_text VARCHAR(500) NOT NULL,
    display_order SMALLINT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT quiz_options_text_not_empty
        CHECK (LENGTH(TRIM(option_text)) > 0),

    CONSTRAINT quiz_options_order_check
        CHECK (display_order > 0),

    CONSTRAINT quiz_options_question_fk
        FOREIGN KEY (question_id, quiz_id, university_id)
        REFERENCES quiz_questions(id, quiz_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT quiz_options_id_question_unique
        UNIQUE (id, question_id, quiz_id, university_id),

    CONSTRAINT quiz_options_question_order_unique
        UNIQUE (question_id, display_order)
);

CREATE INDEX quiz_options_question_idx
    ON quiz_options(question_id, display_order);

-- =========================================================
-- 4. QUIZ ANSWER KEYS
-- Correct answers must never be exposed to students.
-- =========================================================

CREATE TABLE quiz_answer_keys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    quiz_id UUID NOT NULL,
    question_id UUID NOT NULL,
    correct_option_id UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT quiz_answer_keys_question_fk
        FOREIGN KEY (question_id, quiz_id, university_id)
        REFERENCES quiz_questions(id, quiz_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT quiz_answer_keys_option_fk
        FOREIGN KEY (
            correct_option_id,
            question_id,
            quiz_id,
            university_id
        )
        REFERENCES quiz_options(
            id,
            question_id,
            quiz_id,
            university_id
        )
        ON DELETE RESTRICT,

    CONSTRAINT quiz_answer_keys_unique
        UNIQUE (question_id, correct_option_id)

);

CREATE INDEX quiz_answer_keys_quiz_idx
    ON quiz_answer_keys(quiz_id, question_id);

-- =========================================================
-- 5. QUIZ SUBMISSIONS
-- One submission per student per quiz.
-- =========================================================

CREATE TABLE quiz_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    quiz_id UUID NOT NULL,
    student_user_id UUID NOT NULL,

    total_score NUMERIC(9,2),
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    marked_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT quiz_submissions_score_check
        CHECK (total_score IS NULL OR total_score >= 0),

    CONSTRAINT quiz_submissions_marked_check
        CHECK (
            (total_score IS NULL AND marked_at IS NULL)
            OR
            (total_score IS NOT NULL AND marked_at IS NOT NULL)
        ),

    CONSTRAINT quiz_submissions_quiz_fk
        FOREIGN KEY (quiz_id, university_id)
        REFERENCES quizzes(id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT quiz_submissions_student_membership_fk
        FOREIGN KEY (university_id, student_user_id)
        REFERENCES university_memberships(university_id, user_id)
        ON DELETE RESTRICT,

    CONSTRAINT quiz_submissions_id_quiz_unique
        UNIQUE (id, quiz_id, university_id),

    CONSTRAINT quiz_submissions_student_unique
        UNIQUE (quiz_id, student_user_id)
);

CREATE INDEX quiz_submissions_quiz_submitted_idx
    ON quiz_submissions(quiz_id, submitted_at DESC);

CREATE INDEX quiz_submissions_student_idx
    ON quiz_submissions(university_id, student_user_id, submitted_at DESC);

-- =========================================================
-- 6. QUIZ ANSWERS
-- One answer per question in each submission.
-- =========================================================

CREATE TABLE quiz_answers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    quiz_id UUID NOT NULL,
    submission_id UUID NOT NULL,
    question_id UUID NOT NULL,

    awarded_marks NUMERIC(7,2),
    is_correct BOOLEAN,
    answered_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT quiz_answers_marks_check
        CHECK (awarded_marks IS NULL OR awarded_marks >= 0),

    CONSTRAINT quiz_answers_marking_check
        CHECK (
            (awarded_marks IS NULL AND is_correct IS NULL)
            OR
            (awarded_marks IS NOT NULL AND is_correct IS NOT NULL)
        ),

    CONSTRAINT quiz_answers_submission_fk
        FOREIGN KEY (submission_id, quiz_id, university_id)
        REFERENCES quiz_submissions(id, quiz_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT quiz_answers_question_fk
        FOREIGN KEY (question_id, quiz_id, university_id)
        REFERENCES quiz_questions(id, quiz_id, university_id)
        ON DELETE RESTRICT,

        CONSTRAINT quiz_answers_id_question_unique
        UNIQUE (id, question_id, quiz_id, university_id),

    CONSTRAINT quiz_answers_submission_question_unique
        UNIQUE (submission_id, question_id)
);


CREATE INDEX quiz_answers_question_idx
    ON quiz_answers(question_id, quiz_id);

-- =========================================================
-- 7. QUIZ ANSWER SELECTIONS
-- Stores selected options for each submitted answer.
-- =========================================================

CREATE TABLE quiz_answer_selections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID NOT NULL,
    quiz_id UUID NOT NULL,
    question_id UUID NOT NULL,
    answer_id UUID NOT NULL,
    selected_option_id UUID NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT quiz_answer_selections_answer_fk
        FOREIGN KEY (answer_id, question_id, quiz_id, university_id)
        REFERENCES quiz_answers(id, question_id, quiz_id, university_id)
        ON DELETE RESTRICT,

    CONSTRAINT quiz_answer_selections_option_fk
        FOREIGN KEY (
            selected_option_id,
            question_id,
            quiz_id,
            university_id
        )
        REFERENCES quiz_options(
            id,
            question_id,
            quiz_id,
            university_id
        )
        ON DELETE RESTRICT,

    CONSTRAINT quiz_answer_selections_unique
        UNIQUE (answer_id, selected_option_id)
);

CREATE INDEX quiz_answer_selections_answer_idx
    ON quiz_answer_selections(answer_id);

CREATE INDEX quiz_answer_selections_option_idx
    ON quiz_answer_selections(question_id, selected_option_id);

COMMIT;
