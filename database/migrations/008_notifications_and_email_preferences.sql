
BEGIN;

-- =========================================================
-- MIGRATION 008: NOTIFICATIONS AND EMAIL PREFERENCES
-- =========================================================

-- =========================================================
-- 1. NOTIFICATIONS
-- Stores in-app notifications for individual users.
-- =========================================================

CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    university_id UUID,
    user_id UUID NOT NULL,

    category VARCHAR(30) NOT NULL,
    notification_type VARCHAR(60) NOT NULL,

    title VARCHAR(200) NOT NULL,
    message TEXT NOT NULL,

    resource_type VARCHAR(50),
    resource_id UUID,

    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    read_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ,

    CONSTRAINT notifications_id_user_category_unique
    UNIQUE (id, user_id, category),

    CONSTRAINT notifications_category_check
        CHECK (
            category IN (
                'questions',
                'polls',
                'quizzes',
                'feedback',
                'class_updates',
                'account_security'
            )
        ),

    CONSTRAINT notifications_type_check
        CHECK (LENGTH(TRIM(notification_type)) > 0),

    CONSTRAINT notifications_title_check
        CHECK (LENGTH(TRIM(title)) > 0),

    CONSTRAINT notifications_message_check
        CHECK (LENGTH(TRIM(message)) > 0),

    CONSTRAINT notifications_read_state_check
        CHECK (
            (is_read = FALSE AND read_at IS NULL)
            OR
            (is_read = TRUE AND read_at IS NOT NULL)
        ),

    CONSTRAINT notifications_expiry_check
        CHECK (
            expires_at IS NULL
            OR expires_at > created_at
        ),

    CONSTRAINT notifications_user_fk
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT,

    CONSTRAINT notifications_university_user_fk
        FOREIGN KEY (university_id, user_id)
        REFERENCES university_memberships(university_id, user_id)
        ON DELETE RESTRICT
);

CREATE INDEX notifications_user_created_idx
    ON notifications(user_id, created_at DESC);

CREATE INDEX notifications_user_unread_idx
    ON notifications(user_id, created_at DESC)
    WHERE is_read = FALSE;

CREATE INDEX notifications_university_idx
    ON notifications(university_id, created_at DESC)
    WHERE university_id IS NOT NULL;

-- =========================================================
-- 2. NOTIFICATION PREFERENCES
-- Stores category-based email preferences.
-- =========================================================

CREATE TABLE notification_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,

    category VARCHAR(30) NOT NULL,
    email_enabled BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT notification_preferences_category_check
        CHECK (
            category IN (
                'questions',
                'polls',
                'quizzes',
                'feedback',
                'class_updates'
            )
        ),

    CONSTRAINT notification_preferences_user_category_unique
        UNIQUE (user_id, category),

    CONSTRAINT notification_preferences_user_fk
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
);

CREATE INDEX notification_preferences_user_idx
    ON notification_preferences(user_id);

-- =========================================================
-- 3. EMAIL DELIVERY LOGS
-- Tracks asynchronous email delivery and retry attempts.
-- =========================================================

CREATE TABLE email_delivery_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID,
    user_id UUID NOT NULL,

    category VARCHAR(30) NOT NULL,
    recipient_email VARCHAR(320) NOT NULL,

    delivery_status VARCHAR(20) NOT NULL DEFAULT 'pending',
    attempt_count SMALLINT NOT NULL DEFAULT 0,

    provider_message_id VARCHAR(255),
    last_error TEXT,

    scheduled_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_attempted_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT email_delivery_logs_category_check
        CHECK (
            category IN (
                'questions',
                'polls',
                'quizzes',
                'feedback',
                'class_updates',
                'account_security'
            )
        ),

    CONSTRAINT email_delivery_logs_status_check
        CHECK (
            delivery_status IN (
                'pending',
                'processing',
                'sent',
                'failed',
                'cancelled'
            )
        ),

    CONSTRAINT email_delivery_logs_attempt_check
        CHECK (attempt_count >= 0),

    CONSTRAINT email_delivery_logs_email_check
        CHECK (
            recipient_email = LOWER(TRIM(recipient_email))
            AND LENGTH(TRIM(recipient_email)) > 0
        ),

    CONSTRAINT email_delivery_logs_delivery_check
        CHECK (
            (delivery_status = 'sent' AND delivered_at IS NOT NULL)
            OR
            (delivery_status <> 'sent' AND delivered_at IS NULL)
        ),

    CONSTRAINT email_delivery_logs_notification_fk
        FOREIGN KEY (notification_id, user_id, category)
        REFERENCES notifications(id, user_id, category)
        ON DELETE RESTRICT,

    CONSTRAINT email_delivery_logs_user_fk
        FOREIGN KEY (user_id)
        REFERENCES users(id)
        ON DELETE RESTRICT
);

CREATE INDEX email_delivery_logs_status_scheduled_idx
    ON email_delivery_logs(delivery_status, scheduled_at);

CREATE INDEX email_delivery_logs_user_created_idx
    ON email_delivery_logs(user_id, created_at DESC);

CREATE INDEX email_delivery_logs_notification_idx
    ON email_delivery_logs(notification_id)
    WHERE notification_id IS NOT NULL;

CREATE INDEX email_delivery_logs_retry_idx
    ON email_delivery_logs(scheduled_at)
    WHERE delivery_status IN ('pending', 'failed');

COMMIT;
