
const Joi = require('joi');

const registerSchema = Joi.object({
    fullName: Joi.string()
        .trim()
        .min(2)
        .max(150)
        .required()
        .messages({
            'string.empty': 'Full name is required',
            'string.min': 'Full name must be at least 2 characters',
            'string.max': 'Full name cannot exceed 150 characters',
            'any.required': 'Full name is required'
        }),

    email: Joi.string()
        .trim()
        .lowercase()
        .email()
        .max(255)
        .required()
        .messages({
            'string.empty': 'Email is required',
            'string.email': 'Please provide a valid email address',
            'any.required': 'Email is required'
        }),

    password: Joi.string()
        .min(8)
        .max(72)
        .pattern(/^(?=.*[a-z])(?=.*[A-Z])(?=.*[^A-Za-z0-9\s])(?=.*\S).+$/)
        .required()
        .messages({
            'string.min': 'Password must be at least 8 characters',
            'string.max': 'Password cannot exceed 72 characters',
            'string.pattern.base': 'Password must contain at least one uppercase letter, one lowercase letter, and one special character',
            'any.required': 'Password is required'
        })
});

const verifyEmailSchema = Joi.object({
    token: Joi.string()
        .length(64)
        .pattern(/^[0-9a-f]{64}$/)
        .required()
        .messages({
            'string.length': 'Verification token must be 64 characters',
            'string.pattern.base': 'Invalid verification token format',
            'any.required': 'Verification token is required'
        })
});

const resendVerificationSchema = Joi.object({
    email: Joi.string()
        .trim()
        .lowercase()
        .email()
        .max(255)
        .required()
        .messages({
            'string.empty': 'Email is required',
            'string.email': 'Please provide a valid email address',
            'any.required': 'Email is required'
        })
});

const loginSchema = Joi.object({
    email: Joi.string()
        .trim()
        .lowercase()
        .email()
        .max(255)
        .required()
        .messages({
            'string.empty': 'Email is required',
            'string.email': 'Please provide a valid email address',
            'any.required': 'Email is required'
        }),

    password: Joi.string()
        .min(1)
        .max(72)
        .required()
        .messages({
            'string.empty': 'Password is required',
            'string.max': 'Password cannot exceed 72 characters',
            'any.required': 'Password is required'
        })
});

module.exports = {
    registerSchema,
    verifyEmailSchema,
    resendVerificationSchema,
    loginSchema
};
