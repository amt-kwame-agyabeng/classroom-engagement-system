
const path = require('path');

require('dotenv').config({
    path: path.resolve(__dirname, '../../../.env')
});

const config = {
    port: process.env.PORT || 5000,

    database: {
        host: process.env.DB_HOST || 'localhost',
        port: Number(process.env.DB_PORT) || 5432,
        name: process.env.POSTGRES_DB,
        user: process.env.POSTGRES_USER,
        password: process.env.POSTGRES_PASSWORD
    },

    auth: {
        accessTokenSecret: process.env.JWT_ACCESS_SECRET,
        accessTokenExpiresIn: process.env.JWT_ACCESS_EXPIRES_IN || '15m',
        refreshTokenExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '7d'
    },

    identity: {
        signingKeyId: process.env.DB_IDENTITY_SIGNING_KEY_ID,
        signingSecret: process.env.DB_IDENTITY_SIGNING_SECRET
    }
};

if (!config.auth.accessTokenSecret) {
    throw new Error('JWT_ACCESS_SECRET is not configured');
}

if (config.auth.accessTokenSecret.length < 64) {
    throw new Error('JWT_ACCESS_SECRET must be at least 64 characters');
}

if (!config.identity.signingKeyId) {
    throw new Error('DB_IDENTITY_SIGNING_KEY_ID is not configured');
}

if (!/^[A-Za-z0-9_-]{1,32}$/.test(config.identity.signingKeyId)) {
    throw new Error('DB_IDENTITY_SIGNING_KEY_ID has an invalid format');
}

if (
    !config.identity.signingSecret ||
    !/^[0-9a-fA-F]{64}$/.test(config.identity.signingSecret)
) {
    throw new Error('DB_IDENTITY_SIGNING_SECRET must be exactly 64 hexadecimal characters');
}

module.exports = config;
