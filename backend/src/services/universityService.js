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

// List university applications with optional filtering and pagination.
const listUniversityApplications = async (
    client,
    { status = null, limit = 50, offset = 0 } = {}
) => {
    const result = await client.query(
        `SELECT *
         FROM app_private.list_university_applications(
             $1::text,
             $2::integer,
             $3::integer
         )`,
        [status, limit, offset]
    );

    return result.rows;
};

// Mark a university application as under review.
const markUniversityApplicationUnderReview = async (
    client,
    requestId,
    reviewNotes = null
) => {
    const result = await client.query(
        `SELECT app_private.mark_university_application_under_review(
            $1::uuid,
            $2::text
        ) AS request_id`,
        [requestId, reviewNotes]
    );

    return {
        requestId: result.rows[0].request_id
    };
};

// Approve a university application.
const approveUniversityApplication = async (
    client,
    requestId,
    reviewNotes = null
) => {
    const result = await client.query(
        `SELECT app_private.approve_university_application(
            $1::uuid,
            $2::text
        ) AS university_id`,
        [requestId, reviewNotes]
    );

    return {
        universityId: result.rows[0].university_id
    };
};

// Reject a university application.
const rejectUniversityApplication = async (
    client,
    requestId,
    reviewNotes
) => {
    const result = await client.query(
        `SELECT app_private.reject_university_application(
            $1::uuid,
            $2::text
        ) AS request_id`,
        [requestId, reviewNotes]
    );

    return {
        requestId: result.rows[0].request_id
    };
};

module.exports = {
    submitUniversityApplication,
    listUniversityApplications,
    markUniversityApplicationUnderReview,
    approveUniversityApplication,
    rejectUniversityApplication
};