
const bcrypt = require('bcrypt');
const crypto = require('crypto');
const pool = require('../config/database');
const { sendEmail } = require('./emailService');
const config = require('../config/env');

const generateAccessToken = async (user) => {
    const { SignJWT } = await import('jose');

    const secret = new TextEncoder().encode(
        config.auth.accessTokenSecret
    );

    return new SignJWT({
        email: user.email
    })
        .setProtectedHeader({
            alg: 'HS256',
            typ: 'JWT'
        })
        .setSubject(user.user_id)
        .setIssuer('classroom-engagement-system')
        .setAudience('classroom-engagement-api')
        .setIssuedAt()
        .setExpirationTime(config.auth.accessTokenExpiresIn)
        .sign(secret);
};

const registerUser = async ({ fullName, email, password }) => {
    // Hash the password before storing it.
    const passwordHash = await bcrypt.hash(password, 12);

    // Generate a secure, random verification token.
    const verificationToken = crypto.randomBytes(32).toString('hex');

    // Store only the SHA-256 hash of the token.
    const tokenHash = crypto
        .createHash('sha256')
        .update(verificationToken)
        .digest('hex');

    // Set token expiry to 24 hours.
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);

    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        // Create the user account.
        const userResult = await client.query(
            `INSERT INTO public.users (
                full_name,
                email,
                password_hash

            )
            VALUES ($1, $2, $3)
            RETURNING id, full_name, email, account_status, created_at`,
            [fullName, email, passwordHash]
        );

        const user = userResult.rows[0];

        // Save the hashed email verification token.
        await client.query(
            `INSERT INTO public.email_verification_tokens (
                user_id,
                token_hash,
                expires_at
            )
            VALUES ($1, $2, $3)`,
            [user.id, tokenHash, expiresAt]
        );

        await client.query('COMMIT');

       const verificationLink =
    `${process.env.APP_BASE_URL}/api/auth/verify-email?token=${verificationToken}`;

await sendEmail({
    to: email,
    subject: 'Verify your Classroom Engagement System account',
    textContent: `Hello ${fullName},

Thank you for registering.

Please verify your email address by visiting this link:

${verificationLink}

This link expires in 24 hours.

If you did not create this account, please ignore this email.`,
    htmlContent: `
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: auto;">
            <h2>Welcome to Classroom Engagement System</h2>
            <p>Hello ${fullName},</p>
            <p>Thank you for registering. Please verify your email address to activate your account.</p>
            <p>
                <a href="${verificationLink}"
                   style="display: inline-block; padding: 12px 20px;
                   background-color: #2563eb; color: white;
                   text-decoration: none; border-radius: 5px;">
                    Verify Email Address
                </a>
            </p>
            <p>This link expires in 24 hours.</p>
            <p>If you did not create this account, please ignore this email.</p>
        </div>
    `
});

        return {
            user,
            verificationToken
        };

    } catch (error) {
        await client.query('ROLLBACK').catch(() => {});

        if (error.code === '23505') {
            const conflictError = new Error(
                'An account with this email already exists'
            );
            conflictError.statusCode = 409;
            throw conflictError;
        }

        throw error;

    } finally {
        client.release();
    }
};

const verifyEmail = async (token) => {
    // Hash the raw verification token using SHA-256.
    const tokenHash = crypto
        .createHash('sha256')
        .update(token)
        .digest('hex');

    // Let PostgreSQL securely validate and consume the token.
    const result = await pool.query(
        `SELECT app_private.verify_email_token($1) AS verified`,
        [tokenHash]
    );

    return result.rows[0].verified;
};

const resendVerificationEmail = async (email) => {
    // Request a new verification token from PostgreSQL.
    const result = await pool.query(
        `SELECT *
         FROM app_private.create_email_verification_token($1)`,
        [email]
    );

    // Return quietly if no pending account was found.
    if (result.rows.length === 0) {
        return;
    }

    const {
        user_id,
        recipient_email,
        verification_token
    } = result.rows[0];

    const verificationLink =
        `${process.env.APP_BASE_URL}/api/auth/verify-email?token=${verification_token}`;

    // Send the new verification email.
    await sendEmail({
        to: recipient_email,
        subject: 'Your new Classroom Engagement System verification link',
        textContent: `Hello,

You requested a new email verification link.

Please verify your email address using this link:

${verificationLink}

This link expires in 24 hours.

If you did not request this email, you can ignore it.`,
        htmlContent: `
            <div style="font-family: Arial, sans-serif; max-width: 600px; margin: auto;">
                <h2>Email Verification</h2>
                <p>You requested a new verification link.</p>
                <p>
                    <a href="${verificationLink}">
                        Verify Email Address
                    </a>
                </p>
                <p>This link expires in 24 hours.</p>
                <p>If you did not request this email, you can ignore it.</p>
            </div>
        `
    });

    // Hash the token before passing it back to PostgreSQL.
    const tokenHash = crypto
        .createHash('sha256')
        .update(verification_token)
        .digest('hex');

    // Finalize the resend only after the email has been sent.
    await pool.query(
        `SELECT app_private.finalize_email_verification_resend($1, $2)`,
        [user_id, tokenHash]
    );
};


const durationToMilliseconds = (duration) => {
    const match = /^(\d+)(s|m|h|d)$/.exec(duration);

    if (!match) {
        throw new Error('Invalid refresh-token expiry configuration');
    }

    const value = Number(match[1]);
    const units = {
        s: 1000,
        m: 60 * 1000,
        h: 60 * 60 * 1000,
        d: 24 * 60 * 60 * 1000
    };

    return value * units[match[2]];
};

const loginUser = async ({ email, password, ipAddress, userAgent }) => {
    // Generate a cryptographically secure refresh token.
    const refreshToken = crypto.randomBytes(32).toString('hex');

    // Calculate its expiry using the configured duration.
    const refreshTokenExpiry = durationToMilliseconds(
        config.auth.refreshTokenExpiresIn
    );

    const refreshTokenExpiresAt = new Date(
        Date.now() + refreshTokenExpiry
    );

    // Authenticate the user and create the refresh session atomically.
    const result = await pool.query(
        `SELECT *
         FROM app_private.create_authenticated_session(
             $1, $2, $3, $4, $5, $6
         )`,
        [
            email,
            password,
            refreshToken,
            ipAddress || null,
            userAgent || null,
            refreshTokenExpiresAt
        ]
    );

    // Do not reveal whether an email address exists.
    if (result.rows.length === 0) {
        const error = new Error('Invalid email or password');
        error.statusCode = 401;
        throw error;
    }

    const user = result.rows[0];

    // Require email verification before login.
    if (
        user.account_status === 'pending' ||
        !user.email_verified_at
    ) {
        const error = new Error(
            'Please verify your email address before logging in.'
        );
        error.statusCode = 403;
        throw error;
    }

    // Reject suspended and deactivated accounts.
    if (
        user.account_status === 'suspended' ||
        user.account_status === 'deactivated'
    ) {
        const error = new Error(
            'Your account is currently unavailable.'
        );
        error.statusCode = 403;
        throw error;
    }

    // Fail closed for any unexpected account status.
    if (user.account_status !== 'active') {
        const error = new Error(
            'Your account cannot currently log in.'
        );
        error.statusCode = 403;
        throw error;
    }

    // An active account must have a successfully created session.
    if (!user.session_id) {
        throw new Error('Unable to create an authenticated session');
    }

    // Generate the short-lived access token.
    const accessToken = await generateAccessToken(user);

    return {
        accessToken,
        refreshToken,
        tokenType: 'Bearer',
        expiresIn: config.auth.accessTokenExpiresIn,
        user: {
            id: user.user_id,
            fullName: user.full_name,
            email: user.email,
            roles: user.roles || [],
            memberships: user.memberships || []
        }
    };
};

const refreshUserSession = async ({
    refreshToken,
    ipAddress,
    userAgent
}) => {
    if (
        typeof refreshToken !== 'string' ||
        !/^[0-9a-f]{64}$/.test(refreshToken)
    ) {
        const error = new Error('Invalid or expired refresh session.');
        error.statusCode = 401;
        throw error;
    }

    const newRefreshToken = crypto.randomBytes(32).toString('hex');

    const refreshTokenExpiry = durationToMilliseconds(
        config.auth.refreshTokenExpiresIn
    );

    const expiresAt = new Date(Date.now() + refreshTokenExpiry);

    const result = await pool.query(
        `SELECT *
         FROM app_private.rotate_refresh_token($1, $2, $3, $4, $5)`,
        [
            refreshToken,
            newRefreshToken,
            ipAddress || null,
            userAgent || null,
            expiresAt
        ]
    );

    if (result.rows.length === 0) {
        const error = new Error('Invalid or expired refresh session.');
        error.statusCode = 401;
        throw error;
    }

    const user = result.rows[0];

    const accessToken = await generateAccessToken({
        user_id: user.user_id,
        email: user.email
    });

    return {
        accessToken,
        refreshToken: newRefreshToken,
        tokenType: 'Bearer',
        expiresIn: config.auth.accessTokenExpiresIn
    };
};

const logoutUser = async (refreshToken) => {
    if (
        typeof refreshToken !== 'string' ||
        !/^[0-9a-f]{64}$/.test(refreshToken)
    ) {
        return;
    }

    await pool.query(
        `SELECT app_private.revoke_refresh_token($1)`,
        [refreshToken]
    );
};

module.exports = {
    registerUser,
    verifyEmail,
    resendVerificationEmail,
    loginUser,
    refreshUserSession,
    logoutUser
};
