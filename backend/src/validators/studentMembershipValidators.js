const Joi = require('joi');

// Validate university ID in route parameters.
const universityIdParamsSchema = Joi.object({
    universityId: Joi.string()
        .guid({ version: ['uuidv4', 'uuidv5'] })
        .required()
});

// Submit student membership request.
const submitMembershipRequestSchema = Joi.object({
    studentId: Joi.string()
        .trim()
        .max(100)
        .allow('', null)
        .optional()
});

// Validate membership request ID in route parameters.
const membershipRequestParamsSchema = Joi.object({
    universityId: Joi.string()
        .guid({ version: ['uuidv4', 'uuidv5'] })
        .required(),

    requestId: Joi.string()
        .guid({ version: ['uuidv4', 'uuidv5'] })
        .required()
});

// Pagination for membership requests.
const listMembershipRequestsSchema = Joi.object({
    limit: Joi.number()
        .integer()
        .min(1)
        .max(100)
        .default(50),

    offset: Joi.number()
        .integer()
        .min(0)
        .default(0)
});

// Reject membership request with a required reason.
const rejectMembershipRequestSchema = Joi.object({
    rejectionReason: Joi.string()
        .trim()
        .min(5)
        .max(5000)
        .required()
        .messages({
            'string.empty': 'A rejection reason is required.',
            'string.min': 'Rejection reason must be at least 5 characters.',
            'string.max': 'Rejection reason cannot exceed 5000 characters.',
            'any.required': 'A rejection reason is required.'
        })
});

module.exports = {
    universityIdParamsSchema,
    submitMembershipRequestSchema,
    membershipRequestParamsSchema,
    listMembershipRequestsSchema,
    rejectMembershipRequestSchema
};
