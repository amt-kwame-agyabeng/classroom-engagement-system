
const {
    appointPlatformAdmin: appointPlatformAdminService,
    revokePlatformAdmin: revokePlatformAdminService
} = require('../services/platformAdminService');

const appointPlatformAdmin = async ({ client, req }) => {
    try {
        return await appointPlatformAdminService(
            client,
            req.body.userId
        );
    } catch (error) {
        if (
            error.code === '22023' &&
            error.message ===
                'The target user must have an active, verified account.'
        ) {
            error.statusCode = 404;
            error.message = 'The target user does not exist or is not eligible for appointment.';
        }

        if (error.code === '23505') {
            error.statusCode = 409;
        }

        throw error;
    }
};

const revokePlatformAdmin = async ({ client, req }) => {
    try {
        return await revokePlatformAdminService(
            client,
            req.params.assignmentId
        );
    } catch (error) {
        if (
            error.message ===
            'The last active Platform Administrator cannot be revoked.'
        ) {
            error.statusCode = 409;
        }

        throw error;
    }
};

module.exports = {
    appointPlatformAdmin,
    revokePlatformAdmin
};
