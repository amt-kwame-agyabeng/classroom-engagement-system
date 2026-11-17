const express = require('express');

const {
    submitApplication
} = require('../controllers/universityController');

const validateRequest = require('../middleware/validateRequest');

const {
    universityApplicationSchema
} = require('../validators/universityValidators');

const router = express.Router();

// Public university application submission
router.post(
    '/applications',
    validateRequest(universityApplicationSchema),
    submitApplication
);

module.exports = router;
