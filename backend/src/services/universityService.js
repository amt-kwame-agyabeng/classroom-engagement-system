const pool = require('../config/database');

const submitUniversityApplication = async (application) => {
    const {
        institutionName,
        website,
        country,
        representativeName,
        representativeEmail,
        proposedAdminName,
        proposedAdminEmail
    } = application;

    try {
        const result = await pool.query(
            `SELECT *
             FROM app_private.submit_university_application(
                 $1, $2, $3, $4, $5, $6, $7
             )`,
            [
                institutionName,
                website || null,
                country,
                representativeName,
                representativeEmail,
                proposedAdminName,
                proposedAdminEmail
            ]
        );

        return result.rows[0];
    } catch (error) {
        if (error.code === '23505') {
            const conflict = new Error(
                'An application for this institution already exists.'
            );
            conflict.statusCode = 409;
            throw conflict;
        }

        throw error;
    }
};

module.exports = {
    submitUniversityApplication
};
