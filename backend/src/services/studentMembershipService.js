const withIdentityContext = require('../utils/withIdentityContext');

// Submit a student membership request to a university.
const submitMembershipRequest = async (
    userId,
    universityId,
    studentId = null
) => {
    return withIdentityContext(
        { userId, universityId },
        async (client) => {
            const result = await client.query(
                `SELECT app_private.submit_student_membership_request(
                    $1::uuid,
                    $2::varchar
                ) AS membership_id`,
                [universityId, studentId]
            );

            return {
                membershipId: result.rows[0].membership_id
            };
        }
    );
};

// Retrieve the authenticated student's membership status.
const getMyMembershipStatus = async (
    userId,
    universityId
) => {
    return withIdentityContext(
        { userId, universityId },
        async (client) => {
            const result = await client.query(
                `SELECT *
                 FROM app_private.get_my_student_membership_status(
                    $1::uuid
                 )`,
                [universityId]
            );

            return result.rows[0] || null;
        }
    );
};

// List pending membership requests for university administrators.
const listMembershipRequests = async (
    userId,
    universityId,
    { limit = 50, offset = 0 } = {}
) => {
    return withIdentityContext(
        { userId, universityId },
        async (client) => {
            const result = await client.query(
                `SELECT *
                 FROM app_private.list_student_membership_requests(
                    $1::uuid,
                    $2::integer,
                    $3::integer
                 )`,
                [universityId, limit, offset]
            );

            return result.rows;
        }
    );
};

// Approve a student membership request.
const approveMembershipRequest = async (
    userId,
    universityId,
    membershipId
) => {
    return withIdentityContext(
        { userId, universityId },
        async (client) => {
            const result = await client.query(
                `SELECT app_private.approve_student_membership_request(
                    $1::uuid,
                    $2::uuid
                ) AS membership_id`,
                [universityId, membershipId]
            );

            return {
                membershipId: result.rows[0].membership_id
            };
        }
    );
};

// Reject a student membership request.
const rejectMembershipRequest = async (
    userId,
    universityId,
    membershipId,
    rejectionReason
) => {
    return withIdentityContext(
        { userId, universityId },
        async (client) => {
            const result = await client.query(
                `SELECT app_private.reject_student_membership_request(
                    $1::uuid,
                    $2::uuid,
                    $3::text
                ) AS membership_id`,
                [
                    universityId,
                    membershipId,
                    rejectionReason
                ]
            );

            return {
                membershipId: result.rows[0].membership_id
            };
        }
    );
};

module.exports = {
    submitMembershipRequest,
    getMyMembershipStatus,
    listMembershipRequests,
    approveMembershipRequest,
    rejectMembershipRequest
};
