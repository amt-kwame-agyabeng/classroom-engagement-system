const {
    submitUniversityApplication,
    listUniversityApplications: listApplicationsService,
    markUniversityApplicationUnderReview: markUnderReviewService,
    approveUniversityApplication: approveApplicationService,
    rejectUniversityApplication: rejectApplicationService
} = require('../services/universityService');

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

// List applications for Platform Admin review.
const listApplications = async ({ client, req }) => {
    const applications = await listApplicationsService(client, req.query);

    return {
        applications,
        pagination: {
            limit: req.query.limit,
            offset: req.query.offset
        }
    };
};

// Mark an application as under review.
const markApplicationUnderReview = async ({ client, req }) => {
    try {
        return await markUnderReviewService(
            client,
            req.params.requestId,
            req.body.reviewNotes
        );
    } catch (error) {
        if (error.code === 'P0002') {
            error.statusCode = 404;
            error.message = 'University application not found.';
        } else if (error.code === '23514') {
            error.statusCode = 409;
            error.message = 'Only pending applications can be marked under review.';
        } else if (error.code === '22023') {
            error.statusCode = 400;
        }

        throw error;
    }
};

// Approve an application.
const approveApplication = async ({ client, req }) => {
    try {
        return await approveApplicationService(
            client,
            req.params.requestId,
            req.body.reviewNotes
        );
    } catch (error) {
        if (error.code === 'P0002') {
            error.statusCode = 404;
            error.message = 'University application not found.';
        } else if (error.code === '23514') {
            error.statusCode = 409;

            if (
                error.message.includes(
                    'proposed administrator must have an active account'
                )
            ) {
                error.message =
                    'The proposed administrator must have an active account and a verified matching email address.';
            } else {
                error.message =
                    'This application cannot be approved in its current state.';
            }
        } else if (error.code === '22023') {
            error.statusCode = 400;
        }

        throw error;
    }
};

// Reject an application.
const rejectApplication = async ({ client, req }) => {
    try {
        return await rejectApplicationService(
            client,
            req.params.requestId,
            req.body.reviewNotes
        );
    } catch (error) {
        if (error.code === 'P0002') {
            error.statusCode = 404;
            error.message = 'University application not found.';
        } else if (error.code === '23514') {
            error.statusCode = 409;
            error.message =
                'This application cannot be rejected in its current state.';
        } else if (error.code === '22023') {
            error.statusCode = 400;
        }

        throw error;
    }
};

module.exports = {
    submitApplication,
    listApplications,
    markApplicationUnderReview,
    approveApplication,
    rejectApplication
};