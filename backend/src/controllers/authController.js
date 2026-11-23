const {
    registerUser,
    verifyEmail,
    resendVerificationEmail,
    requestPasswordReset,
    completePasswordReset,  
    loginUser,
    refreshUserSession,
    logoutUser,
} = require('../services/authService');

const register = async (req, res, next) => {
    try {
        const { fullName, email, password } = req.body;

        const { user } = await registerUser({
            fullName,
            email,
            password
        });

        return res.status(201).json({
            success: true,
            message: 'Account created. Email verification is required before activation.',
            data: { user }
        });

    } catch (error) {
        next(error);
    }
};

const login = async (req, res, next) => {
    try {
        const { email, password } = req.body;

        const result = await loginUser({
            email,
            password,
            ipAddress: req.ip,
            userAgent: req.get('user-agent')
        });

        const refreshTokenExpiry = (() => {
    const match = /^(\d+)(s|m|h|d)$/.exec(
        process.env.JWT_REFRESH_EXPIRES_IN || '7d'
    );

    if (!match) {
        throw new Error('Invalid refresh-token expiry configuration');
    }

    const units = {
        s: 1000,
        m: 60 * 1000,
        h: 60 * 60 * 1000,
        d: 24 * 60 * 60 * 1000
    };

    return Number(match[1]) * units[match[2]];
})();

        res.cookie('refreshToken', result.refreshToken, {
            httpOnly: true,
            secure: process.env.NODE_ENV === 'production',
            sameSite: 'strict',
            path: '/api/auth',
            maxAge: refreshTokenExpiry
        });

        return res.status(200).json({
            success: true,
            message: 'Login successful.',
            data: {
                accessToken: result.accessToken,
                tokenType: result.tokenType,
                expiresIn: result.expiresIn,
                user: result.user
            }
        });

    } catch (error) {
        next(error);
    }
};

const refresh = async (req, res, next) => {
    try {
        const result = await refreshUserSession({
            refreshToken: req.cookies?.refreshToken,
            ipAddress: req.ip,
            userAgent: req.get('user-agent')
        });

        const refreshTokenExpiry = (() => {
            const match = /^(\d+)(s|m|h|d)$/.exec(
                process.env.JWT_REFRESH_EXPIRES_IN || '7d'
            );

            if (!match) {
                throw new Error('Invalid refresh-token expiry configuration');
            }

            const units = {
                s: 1000,
                m: 60 * 1000,
                h: 60 * 60 * 1000,
                d: 24 * 60 * 60 * 1000
            };

            return Number(match[1]) * units[match[2]];
        })();

        res.cookie('refreshToken', result.refreshToken, {
            httpOnly: true,
            secure: process.env.NODE_ENV === 'production',
            sameSite: 'strict',
            path: '/api/auth',
            maxAge: refreshTokenExpiry
        });

        return res.status(200).json({
            success: true,
            message: 'Session refreshed successfully.',
            data: {
                accessToken: result.accessToken,
                tokenType: result.tokenType,
                expiresIn: result.expiresIn
            }
        });
    } catch (error) {
        next(error);
    }
};

const logout = async (req, res, next) => {
    try {
        await logoutUser(req.cookies?.refreshToken);

        res.clearCookie('refreshToken', {
            httpOnly: true,
            secure: process.env.NODE_ENV === 'production',
            sameSite: 'strict',
            path: '/api/auth'
        });

        return res.status(200).json({
            success: true,
            message: 'Logged out successfully.'
        });
    } catch (error) {
        next(error);
    }
};

const verifyEmailAddress = async (req, res, next) => {
    try {
        const { token } = req.body;

        const verified = await verifyEmail(token);

        if (!verified) {
            return res.status(400).json({
                success: false,
                message: 'Invalid or expired verification link.'
            });
        }

        return res.status(200).json({
            success: true,
            message: 'Email address verified successfully. Your account is now active.'
        });

    } catch (error) {
        next(error);
    }
};

const resendVerification = async (req, res, next) => {
    try {
        const { email } = req.body;

        await resendVerificationEmail(email);

        return res.status(200).json({
            success: true,
            message: 'If an account with that email requires verification, a new verification email will be sent.'
        });

    } catch (error) {
        next(error);
    }
};

const forgotPassword = async (req, res, next) => {
    try {
        const { email } = req.body;

        await requestPasswordReset(email);

        return res.status(200).json({
            success: true,
            message: 'If an eligible account exists with that email, password reset instructions will be sent.'
        });
    } catch (error) {
        next(error);
    }
};

const resetPassword = async (req, res, next) => {
    try {
        const { token, password } = req.body;

        const completed = await completePasswordReset(token, password);

        if (!completed) {
            return res.status(400).json({
                success: false,
                message: 'Invalid or expired password reset link.'
            });
        }

        return res.status(200).json({
            success: true,
            message: 'Password reset successfully. Please log in again.'
        });
    } catch (error) {
        next(error);
    }
};


const verifyEmailFromLink = (req, res) => {
    const { token } = req.query;

    if (
        typeof token !== 'string' ||
        !/^[0-9a-f]{64}$/.test(token)
    ) {
        return res.status(400).send(`
            <h2>Invalid verification link</h2>
            <p>Please request a new verification email.</p>
        `);
    }

    const safeToken = encodeURIComponent(token);

    return res.status(200).send(`
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Verify Email</title>
        </head>
        <body>
            <h2>Verify your email address</h2>
            <p>Click the button below to activate your account.</p>

            <form method="POST" action="/api/auth/verify-email">
                <input
                    type="hidden"
                    name="token"
                    value="${safeToken}"
                />
                <button type="submit">Verify Email</button>
            </form>
        </body>
        </html>
    `);
};



module.exports = {
    register,
    login,
    refresh,
    logout,
    verifyEmailAddress,
    verifyEmailFromLink,
    resendVerification,
    forgotPassword,
    resetPassword
};
