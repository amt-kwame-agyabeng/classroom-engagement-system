
const crypto = require('crypto');
const config = require('../config/env');

const createIdentityToken = ({ userId, universityId = null }) => {
    if (!userId || typeof userId !== 'string') {
        throw new Error('A verified user ID is required');
    }

    const keyId = config.identity.signingKeyId;
    const secret = Buffer.from(config.identity.signingSecret, 'hex');

    const issuedAt = Math.floor(Date.now() / 1000);
    const expiresAt = issuedAt + 60;
    const nonce = crypto.randomUUID();

    const payload = [
        'v1',
        keyId,
        userId.toLowerCase(),
        universityId ? universityId.toLowerCase() : '-',
        issuedAt,
        expiresAt,
        nonce
    ].join('|');

    const signature = crypto
        .createHmac('sha256', secret)
        .update(payload, 'utf8')
        .digest('hex');

    return `${payload}.${signature}`;
};

module.exports = { createIdentityToken };
