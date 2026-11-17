const appointPlatformAdmin = async (client, userId) => {
    const result = await client.query(
        `SELECT app_private.appoint_platform_admin($1::uuid) AS assignment_id`,
        [userId]
    );

    return {
        assignmentId: result.rows[0].assignment_id
    };
};

const revokePlatformAdmin = async (client, assignmentId) => {
    const result = await client.query(
        `SELECT app_private.revoke_platform_admin($1::uuid) AS assignment_id`,
        [assignmentId]
    );

    return {
        assignmentId: result.rows[0].assignment_id
    };
};

module.exports = {
    appointPlatformAdmin,
    revokePlatformAdmin
};
