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

module.exports = router;
