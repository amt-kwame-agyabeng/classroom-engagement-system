
const withIdentityContext = require('../utils/withIdentityContext');
const {
    isPlatformAdmin,
    hasUniversityRole
} = require('../services/authorizationService');

const ALLOWED_ROLES = new Set([
    'platform_admin',
    'university_admin',
    'department_admin',
    'lecturer',
    'student'
]);

const UUID_REGEX =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const requireRole = (
    role,
    operation,
    {
        universityIdParam = 'universityId',
        departmentIdParam = 'departmentId'
    } = {}
) => {
    if (!ALLOWED_ROLES.has(role)) {
        throw new Error(`Unsupported authorization role: ${role}`);
    }

    if (typeof operation !== 'function') {
        throw new Error('An authorized database operation is required');
    }

    return async (req, res, next) => {
        try {
            const isGlobalRole = role === 'platform_admin';

            const universityId = isGlobalRole
                ? null
                : req.params[universityIdParam];

            const departmentId = role === 'department_admin'
                ? req.params[departmentIdParam]
                : null;

            if (
                !isGlobalRole &&
                !UUID_REGEX.test(universityId || '')
            ) {
                return res.status(400).json({
                    success: false,
                    message: 'A valid university ID is required.'
                });
            }

            if (
                role === 'department_admin' &&
                !UUID_REGEX.test(departmentId || '')
            ) {
                return res.status(400).json({
                    success: false,
                    message: 'A valid department ID is required.'
                });
            }

            const result = await withIdentityContext(
                {
                    userId: req.auth.userId,
                    universityId
                },
                async (client) => {
                    const allowed = isGlobalRole
                        ? await isPlatformAdmin(client)
                        : await hasUniversityRole(
                            client,
                            role,
                            universityId,
                            departmentId
                        );

                    if (!allowed) {
                        return { authorized: false };
                    }

                    const data = await operation({
                        req,
                        client,
                        auth: req.auth
                    });

                    return {
                        authorized: true,
                        data
                    };
                }
            );

            if (!result.authorized) {
                return res.status(403).json({
                    success: false,
                    message: 'You do not have permission to perform this action.'
                });
            }

            return res.status(200).json({
                success: true,
                data: result.data
            });

        } catch (error) {
            return next(error);
        }
    };
};

module.exports = requireRole;
