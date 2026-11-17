const Joi = require('joi');

const universityApplicationSchema = Joi.object({
    institutionName: Joi.string()
        .trim()
        .min(2)
        .max(255)
        .required()
        .messages({
            'string.empty': 'Institution name is required',
            'string.min': 'Institution name must be at least 2 characters',
            'string.max': 'Institution name cannot exceed 255 characters',
            'any.required': 'Institution name is required'
        }),

    website: Joi.string()
        .trim()
        .max(255)
        .uri({ scheme: ['http', 'https'] })
        .allow('', null)
        .optional()
        .messages({
            'string.uri': 'Please provide a valid website URL',
            'string.max': 'Website URL cannot exceed 255 characters'
        }),

    country: Joi.string()
        .trim()
        .min(2)
        .max(100)
        .default('Ghana')
        .messages({
            'string.empty': 'Country is required',
            'string.min': 'Country must be at least 2 characters',
            'string.max': 'Country cannot exceed 100 characters'
        }),

    representativeName: Joi.string()
        .trim()
        .min(2)
        .max(150)
        .required()
        .messages({
            'string.empty': 'Representative name is required',
            'string.min': 'Representative name must be at least 2 characters',
            'string.max': 'Representative name cannot exceed 150 characters',
            'any.required': 'Representative name is required'
        }),

    representativeEmail: Joi.string()
        .trim()
        .lowercase()
        .email()
        .max(255)
        .required()
        .messages({
            'string.empty': 'Representative email is required',
            'string.email': 'Please provide a valid representative email',
            'string.max': 'Representative email cannot exceed 255 characters',
            'any.required': 'Representative email is required'
        }),

    proposedAdminName: Joi.string()
        .trim()
        .min(2)
        .max(150)
        .required()
        .messages({
            'string.empty': 'Proposed administrator name is required',
            'string.min': 'Proposed administrator name must be at least 2 characters',
            'string.max': 'Proposed administrator name cannot exceed 150 characters',
            'any.required': 'Proposed administrator name is required'
        }),

    proposedAdminEmail: Joi.string()
        .trim()
        .lowercase()
        .email()
        .max(255)
        .required()
        .messages({
            'string.empty': 'Proposed administrator email is required',
            'string.email': 'Please provide a valid proposed administrator email',
            'string.max': 'Proposed administrator email cannot exceed 255 characters',
            'any.required': 'Proposed administrator email is required'
        })
});

module.exports = {
    universityApplicationSchema
};
