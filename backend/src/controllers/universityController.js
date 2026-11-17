const { submitUniversityApplication } = require('../services/universityService');

const submitApplication = async (req, res, next) => {
    try {
        const application = await submitUniversityApplication(req.body);

        return res.status(201).json({
            success: true,
            message: 'University application submitted successfully. It is pending review.',
            data: {
                requestId: application.request_id,
                status: application.request_status
            }
        });
    } catch (error) {
        next(error);
    }
};

module.exports = {
    submitApplication
};
