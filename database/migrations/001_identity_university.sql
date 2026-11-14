
-- =========================================================
-- Migration 001: Identity and University Management
-- Project: Classroom Engagement and Feedback System
-- Database: PostgreSQL 16+
-- =========================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------
-- 1. USERS
-- Stores platform user accounts.
-- ---------------------------------------------------------

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(255) NOT NULL,
    password_hash TEXT NOT NULL,

    account_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (account_status IN (
            'pending',
            'active',
            'suspended',
            'deactivated'
        )),

    email_verified_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT users_full_name_not_empty
        CHECK (LENGTH(TRIM(full_name)) > 0)
);

CREATE UNIQUE INDEX users_email_unique_lower
    ON users (LOWER(email));


-- ---------------------------------------------------------
-- 2. UNIVERSITIES
-- Stores universities registered on the platform.
-- ---------------------------------------------------------

CREATE TABLE universities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name VARCHAR(255) NOT NULL,
    website VARCHAR(255),
    country VARCHAR(100) NOT NULL DEFAULT 'Ghana',

    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN (
            'pending',
            'under_review',
            'active',
            'rejected',
            'suspended'
        )),

    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT universities_name_not_empty
        CHECK (LENGTH(TRIM(name)) > 0)
);


-- ---------------------------------------------------------
-- 3. UNIVERSITY DOMAINS
-- Stores official email domains associated with universities.
-- ---------------------------------------------------------

CREATE TABLE university_domains (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL
        REFERENCES universities(id) ON DELETE CASCADE,

    domain VARCHAR(255) NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT university_domains_domain_not_empty
        CHECK (LENGTH(TRIM(domain)) > 0)
);

CREATE UNIQUE INDEX university_domains_unique_lower
    ON university_domains (LOWER(domain));


-- ---------------------------------------------------------
-- 4. UNIVERSITY REQUESTS
-- Stores applications from institutions requesting access.
-- ---------------------------------------------------------

CREATE TABLE university_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID
        REFERENCES universities(id) ON DELETE SET NULL,

    institution_name VARCHAR(255) NOT NULL,
    website VARCHAR(255),
    country VARCHAR(100) NOT NULL DEFAULT 'Ghana',

    representative_name VARCHAR(150) NOT NULL,
    representative_email VARCHAR(255) NOT NULL,
    proposed_admin_name VARCHAR(150) NOT NULL,
    proposed_admin_email VARCHAR(255) NOT NULL,

    status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (status IN (
            'pending',
            'under_review',
            'approved',
            'rejected'
        )),

    review_notes TEXT,
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ---------------------------------------------------------
-- 5. UNIVERSITY MEMBERSHIPS
-- Connects users to universities.
-- A user can belong to multiple universities.
-- ---------------------------------------------------------

CREATE TABLE university_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID NOT NULL
        REFERENCES universities(id) ON DELETE RESTRICT,

    user_id UUID NOT NULL
        REFERENCES users(id) ON DELETE RESTRICT,

    student_id VARCHAR(100),

    membership_status VARCHAR(20) NOT NULL DEFAULT 'pending'
        CHECK (membership_status IN (
            'pending',
            'active',
            'suspended',
            'deactivated'
        )),

    joined_at TIMESTAMPTZ,
    deactivated_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT university_memberships_unique_user
        UNIQUE (university_id, user_id),

    CONSTRAINT university_memberships_unique_student_id
        UNIQUE (university_id, student_id)
);

CREATE INDEX university_memberships_user_idx
    ON university_memberships(user_id);

CREATE INDEX university_memberships_university_status_idx
    ON university_memberships(university_id, membership_status);


-- ---------------------------------------------------------
-- 6. ROLE ASSIGNMENTS
-- Supports multiple roles and university-specific scopes.
--
-- Platform administrator:
--   university_id = NULL
--   department_id = NULL
--
-- University administrator:
--   university_id = assigned university
--   department_id = NULL
--
-- Department administrator:
--   university_id = assigned university
--   department_id = assigned department
--
-- Lecturer / Student:
--   university_id = assigned university
--   department_id = NULL
-- ---------------------------------------------------------

CREATE TABLE role_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES users(id) ON DELETE RESTRICT,

    university_id UUID,
    department_id UUID,

    role VARCHAR(40) NOT NULL
        CHECK (role IN (
            'platform_admin',
            'university_admin',
            'department_admin',
            'lecturer',
            'student'
        )),

    assigned_by UUID REFERENCES users(id) ON DELETE SET NULL,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_at TIMESTAMPTZ,

    CONSTRAINT role_assignments_membership_fk
        FOREIGN KEY (university_id, user_id)
        REFERENCES university_memberships(university_id, user_id)
        ON DELETE RESTRICT,

    CONSTRAINT role_assignments_scope_check
        CHECK (
            (
                role = 'platform_admin'
                AND university_id IS NULL
                AND department_id IS NULL
            )
            OR
            (
                role = 'university_admin'
                AND university_id IS NOT NULL
                AND department_id IS NULL
            )
            OR
            (
                role IN ('lecturer', 'student')
                AND university_id IS NOT NULL
                AND department_id IS NULL
            )
            OR
            (
                role = 'department_admin'
                AND university_id IS NOT NULL
                AND department_id IS NOT NULL
            )
        )
);

CREATE INDEX role_assignments_user_idx
    ON role_assignments(user_id);

CREATE INDEX role_assignments_university_role_idx
    ON role_assignments(university_id, role);

CREATE INDEX role_assignments_department_idx
    ON role_assignments(department_id)
    WHERE department_id IS NOT NULL;


-- ---------------------------------------------------------
-- 7. EMAIL VERIFICATION TOKENS
-- Stores hashed email verification tokens.
-- ---------------------------------------------------------

CREATE TABLE email_verification_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES users(id) ON DELETE CASCADE,

    token_hash TEXT NOT NULL UNIQUE,

    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX email_verification_tokens_user_idx
    ON email_verification_tokens(user_id);


-- ---------------------------------------------------------
-- 8. PASSWORD RESET TOKENS
-- Stores hashed password reset tokens.
-- ---------------------------------------------------------

CREATE TABLE password_reset_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES users(id) ON DELETE CASCADE,

    token_hash TEXT NOT NULL UNIQUE,

    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX password_reset_tokens_user_idx
    ON password_reset_tokens(user_id);


-- ---------------------------------------------------------
-- 9. REFRESH TOKEN SESSIONS
-- Stores hashed refresh tokens and session information.
-- ---------------------------------------------------------

CREATE TABLE refresh_token_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL
        REFERENCES users(id) ON DELETE CASCADE,

    token_hash TEXT NOT NULL UNIQUE,

    ip_address INET,
    user_agent TEXT,

    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_used_at TIMESTAMPTZ
);

CREATE INDEX refresh_token_sessions_user_idx
    ON refresh_token_sessions(user_id);

CREATE INDEX refresh_token_sessions_active_idx
    ON refresh_token_sessions(user_id, expires_at)
    WHERE revoked_at IS NULL;


COMMIT;

-- =========================================================
-- END OF MIGRATION 001
-- =========================================================
