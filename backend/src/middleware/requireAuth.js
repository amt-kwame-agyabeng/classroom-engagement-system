
const { jwtVerify } = require('jose');
const config = require('../config/env');

const requireAuth = async (req, res, next) => {
    const authHeader = req.headers.authorization;

    // Require a Bearer token.
    const match = /^Bearer\s+(\S+)$/i.exec(authHeader || '');

    if (!match) {
        return res.status(401).json({
            success: false,
            message: 'Authentication required. Please provide a valid access token.'
        });
    }

    const token = match[1];

    try {
        const secret = new TextEncoder().encode(
            config.auth.accessTokenSecret
        );

        const { payload } = await jwtVerify(token, secret, {
            algorithms: ['HS256'],
            issuer: 'classroom-engagement-system',
            audience: 'classroom-engagement-api'
        });

        if (!payload.sub) {
            return res.status(401).json({
                success: false,
                message: 'Invalid access token.'
            });
        }

        // Make the verified user's identity available to controllers.
        req.auth = {
            userId: payload.sub,
            email: payload.email
        };

        return next();

    } catch (error) {
        return res.status(401).json({
            success: false,
            message: 'Invalid or expired access token.'
        });
    }
};

module.exports = requireAuth;
