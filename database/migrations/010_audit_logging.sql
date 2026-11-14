
BEGIN;

-- =========================================================
-- 1. AUDIT LOGS
-- Records important administrative, security and academic
-- configuration events across the platform.
-- =========================================================

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    university_id UUID,
    actor_user_id UUID,

    event_category VARCHAR(50) NOT NULL,
    event_type VARCHAR(100) NOT NULL,

    resource_type VARCHAR(100),
    resource_id UUID,

    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    ip_address INET,
    user_agent TEXT,
    request_id VARCHAR(150),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT audit_logs_university_fk
        FOREIGN KEY (university_id)
        REFERENCES universities(id)
        ON DELETE RESTRICT,

    CONSTRAINT audit_logs_actor_fk
        FOREIGN KEY (actor_user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT,

    CONSTRAINT audit_logs_category_check
        CHECK (
            event_category IN (
                'authentication',
                'account_security',
                'administration',
                'academic_configuration',
                'data_privacy',
                'system'
            )
        ),

    CONSTRAINT audit_logs_event_type_check
        CHECK (LENGTH(TRIM(event_type)) > 0),

    CONSTRAINT audit_logs_resource_type_check
        CHECK (
            resource_type IS NULL
            OR LENGTH(TRIM(resource_type)) > 0
        ),

    CONSTRAINT audit_logs_metadata_check
        CHECK (jsonb_typeof(metadata) = 'object')
);

-- =========================================================
-- 2. AUDIT LOG INDEXES
-- Supports filtering and investigating audit events.
-- =========================================================

CREATE INDEX audit_logs_university_created_idx
    ON audit_logs(university_id, created_at DESC);

CREATE INDEX audit_logs_actor_created_idx
    ON audit_logs(actor_user_id, created_at DESC);

CREATE INDEX audit_logs_category_created_idx
    ON audit_logs(event_category, created_at DESC);

CREATE INDEX audit_logs_resource_idx
    ON audit_logs(resource_type, resource_id)
    WHERE resource_type IS NOT NULL
      AND resource_id IS NOT NULL;

CREATE INDEX audit_logs_request_id_idx
    ON audit_logs(request_id)
    WHERE request_id IS NOT NULL;

COMMIT;
