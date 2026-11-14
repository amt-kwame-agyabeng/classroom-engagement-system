const isPlatformAdmin = async (client) => {
    const result = await client.query(`
        SELECT app_private.is_platform_admin() AS allowed
    `);

    return result.rows[0].allowed;
};

const hasUniversityRole = async (
    client,
    role,
    universityId,
    departmentId = null
) => {
    if (!role || !universityId) {
        return false;
    }

    const result = await client.query(
        `
            SELECT app_private.has_university_role(
                $1::text,
                $2::uuid,
                $3::uuid
            ) AS allowed
        `,
        [role, universityId, departmentId]
    );

    return result.rows[0].allowed;
};

module.exports = {
    isPlatformAdmin,
    hasUniversityRole
};