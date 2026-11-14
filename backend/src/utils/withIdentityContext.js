
const pool = require('../config/database');
const { createIdentityToken } = require('./identityToken');

const withIdentityContext = async (
    { userId, universityId = null },
    callback
) => {
    if (typeof callback !== 'function') {
        throw new Error('A database callback is required');
    }

    const identityToken = createIdentityToken({
        userId,
        universityId
    });

    const client = await pool.connect();
    let transactionStarted = false;
    let releaseError;

    try {
        await client.query('BEGIN');
        transactionStarted = true;

        await client.query(
            `SELECT pg_catalog.set_config(
                'app.identity_token',
                $1,
                true
            )`,
            [identityToken]
        );

        const result = await callback(client);

        await client.query('COMMIT');
        transactionStarted = false;

        return result;
    } catch (error) {
        if (transactionStarted) {
            try {
                await client.query('ROLLBACK');
            } catch (rollbackError) {
                releaseError = rollbackError;
            }
        }

        throw error;
    } finally {
        client.release(releaseError);
    }
};

module.exports = withIdentityContext;
