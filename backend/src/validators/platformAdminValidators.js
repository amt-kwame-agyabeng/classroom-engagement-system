const Joi = require('joi');

const appointPlatformAdminSchema = Joi.object({
    userId: Joi.string()
        .guid({ version: ['uuidv4'] })
        .required()
        .messages({
            'string.guid': 'A valid user ID is required.',
            'any.required': 'User ID is required.'
        })
}).unknown(false);

const revokePlatformAdminParamsSchema = Joi.object({
    assignmentId: Joi.string()
        .guid({ version: ['uuidv4'] })
        .required()
        .messages({
            'string.guid': 'A valid assignment ID is required.',
            'any.required': 'Assignment ID is required.'
        })
}).unknown(false);

module.exports = {
    appointPlatformAdminSchema,
    revokePlatformAdminParamsSchema
};
