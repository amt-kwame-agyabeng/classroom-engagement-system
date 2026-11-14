
const express = require('express');

const resendRateLimiter = require('../middleware/resendRateLimiter');
const {
    register,
    login,
    verifyEmailAddress,
    verifyEmailFromLink,
    resendVerification,
    refresh,
    logout
} = require('../controllers/authController');

const validateRequest = require('../middleware/validateRequest');
const loginRateLimiter = require('../middleware/loginRateLimiter');

const {
    registerSchema,
    loginSchema,
    verifyEmailSchema,
    resendVerificationSchema

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

module.exports = router;
