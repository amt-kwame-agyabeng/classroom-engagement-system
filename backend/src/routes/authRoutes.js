
const express = require('express');

const resendRateLimiter = require('../middleware/resendRateLimiter');
const passwordResetRateLimiter = require('../middleware/passwordResetRateLimiter');

const {
    register,
    login,
    verifyEmailAddress,
    verifyEmailFromLink,
    resendVerification,
    forgotPassword,
    resetPassword,
    refresh,
    logout
} = require('../controllers/authController');

const validateRequest = require('../middleware/validateRequest');
const loginRateLimiter = require('../middleware/loginRateLimiter');

const {
    registerSchema,
    loginSchema,
    verifyEmailSchema,
    resendVerificationSchema,
    forgotPasswordSchema,
    resetPasswordSchema

} = require('../validators/authValidators');

const router = express.Router();

// Register a new user
router.post(
    '/register',
    validateRequest(registerSchema),
    register
);

// User login
router.post('/login', loginRateLimiter, validateRequest(loginSchema), login);

// Refresh the authenticated session
router.post('/refresh', refresh);

// Log out and revoke the refresh session
router.post('/logout', logout);

// Display the email verification confirmation page
router.get(
    '/verify-email',
    verifyEmailFromLink
);

// Verify a user's email address
router.post(
    '/verify-email',
    validateRequest(verifyEmailSchema),
    verifyEmailAddress
);

// Request a new email verification link
router.post(
    '/resend-verification',
    resendRateLimiter,
    validateRequest(resendVerificationSchema),
    resendVerification
);

// Request a password reset email
router.post(
    '/forgot-password',
    passwordResetRateLimiter,
    validateRequest(forgotPasswordSchema),
    forgotPassword
);

// Complete password reset
router.post(
    '/reset-password',
    validateRequest(resetPasswordSchema),
    resetPassword
);

module.exports = router;
