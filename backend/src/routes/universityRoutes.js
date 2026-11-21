const express = require('express');

const {
    submitApplication
} = require('../controllers/universityController');

const {
    submitRequest,
    getMyStatus,
    listRequests,
    approveRequest,
    rejectRequest
} = require('../controllers/studentMembershipController');

const requireAuth = require('../middleware/requireAuth');
const validateRequest = require('../middleware/validateRequest');

const {
    universityApplicationSchema
} = require('../validators/universityValidators');

const {
    universityIdParamsSchema,
    submitMembershipRequestSchema,
    membershipRequestParamsSchema,
    listMembershipRequestsSchema,
    rejectMembershipRequestSchema
} = require('../validators/studentMembershipValidators');

const router = express.Router();

// Public university application submission
router.post(
    '/applications',
    validateRequest(universityApplicationSchema),
    submitApplication
);

// Submit a student membership request
router.post(
    '/:universityId/membership-requests',
    requireAuth,
    validateRequest(universityIdParamsSchema, 'params'),
    validateRequest(submitMembershipRequestSchema),
    submitRequest
);

// Get the authenticated user's membership status
router.get(
    '/:universityId/membership-requests/me',
    requireAuth,
    validateRequest(universityIdParamsSchema, 'params'),
    getMyStatus
);

// List pending membership requests for University Admin review
router.get(
    '/:universityId/membership-requests',
    requireAuth,
    validateRequest(universityIdParamsSchema, 'params'),
    validateRequest(listMembershipRequestsSchema, 'query'),
    listRequests
);

// Approve a student membership request
router.post(
    '/:universityId/membership-requests/:requestId/approve',
    requireAuth,
    validateRequest(membershipRequestParamsSchema, 'params'),
    approveRequest
);

// Reject a student membership request
router.post(
    '/:universityId/membership-requests/:requestId/reject',
    requireAuth,
    validateRequest(membershipRequestParamsSchema, 'params'),
    validateRequest(rejectMembershipRequestSchema),
    rejectRequest
);

module.exports = router;