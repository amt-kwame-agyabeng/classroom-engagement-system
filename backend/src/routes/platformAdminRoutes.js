const express = require('express');

const requireAuth = require('../middleware/requireAuth');
const requireRole = require('../middleware/requireRole');
const validateRequest = require('../middleware/validateRequest');

const {
    appointPlatformAdmin,
    revokePlatformAdmin
} = require('../controllers/platformAdminController');

const {
    appointPlatformAdminSchema,
    revokePlatformAdminParamsSchema
} = require('../validators/platformAdminValidators');

const {
    listApplications,
    markApplicationUnderReview,
    approveApplication,
    rejectApplication
} = require('../controllers/universityController');

const {
    listUniversityApplicationsSchema,
    universityApplicationParamsSchema,
    universityApplicationReviewSchema,
    universityApplicationRejectionSchema
} = require('../validators/universityValidators');

const router = express.Router();

// Appoint an additional Platform Administrator.
router.post(
    '/',
    requireAuth,
    validateRequest(appointPlatformAdminSchema),
    requireRole('platform_admin', appointPlatformAdmin)
);

// Revoke a specific Platform Administrator assignment.
router.delete(
    '/:assignmentId',
    requireAuth,
    validateRequest(revokePlatformAdminParamsSchema, 'params'),
    requireRole('platform_admin', revokePlatformAdmin)
);

// List university applications for review.
router.get(
    '/university-applications',
    requireAuth,
    validateRequest(listUniversityApplicationsSchema, 'query'),
    requireRole('platform_admin', listApplications)
);

// Mark a university application as under review.
router.patch(
    '/university-applications/:requestId/review',
    requireAuth,
    validateRequest(universityApplicationParamsSchema, 'params'),
    validateRequest(universityApplicationReviewSchema),
    requireRole('platform_admin', markApplicationUnderReview)
);

// Approve a university application.
router.post(
    '/university-applications/:requestId/approve',
    requireAuth,
    validateRequest(universityApplicationParamsSchema, 'params'),
    validateRequest(universityApplicationReviewSchema),
    requireRole('platform_admin', approveApplication)
);

// Reject a university application.
router.post(
    '/university-applications/:requestId/reject',
    requireAuth,
    validateRequest(universityApplicationParamsSchema, 'params'),
    validateRequest(universityApplicationRejectionSchema),
    requireRole('platform_admin', rejectApplication)
);

module.exports = router;