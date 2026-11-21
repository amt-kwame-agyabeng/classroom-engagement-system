const {
    submitMembershipRequest,
    getMyMembershipStatus,
    listMembershipRequests,
    approveMembershipRequest,
    rejectMembershipRequest
} = require('../services/studentMembershipService');

// Submit a student membership request.
const submitRequest = async (req, res, next) => {
    try {
        const result = await submitMembershipRequest(
            req.auth.userId,
            req.params.universityId,
            req.body.studentId || null
        );

        return res.status(201).json({
            success: true,
            message: 'Student membership request submitted successfully.',
            data: result
        });
    } catch (error) {
        next(error);
    }
};

// Get the authenticated user's membership status.
const getMyStatus = async (req, res, next) => {
    try {
        const status = await getMyMembershipStatus(
            req.auth.userId,
            req.params.universityId
        );

        return res.status(200).json({
            success: true,
            data: status
        });
    } catch (error) {
        next(error);
    }
};

// List membership requests for university administrators.
const listRequests = async (req, res, next) => {
    try {
        const requests = await listMembershipRequests(
            req.auth.userId,
            req.params.universityId,
            req.query
        );

        return res.status(200).json({
            success: true,
            data: requests,
            pagination: {
                limit: Number(req.query.limit) || 50,
                offset: Number(req.query.offset) || 0
            }
        });
    } catch (error) {
        next(error);
    }
};

// Approve a student membership request.
const approveRequest = async (req, res, next) => {
    try {
        const result = await approveMembershipRequest(
            req.auth.userId,
            req.params.universityId,
            req.params.requestId
        );

        return res.status(200).json({
            success: true,
            message: 'Student membership request approved successfully.',
            data: result
        });
    } catch (error) {
        next(error);
    }
};

// Reject a student membership request.
const rejectRequest = async (req, res, next) => {
    try {
        const result = await rejectMembershipRequest(
            req.auth.userId,
            req.params.universityId,
            req.params.requestId,
            req.body.rejectionReason
        );

        return res.status(200).json({
            success: true,
            message: 'Student membership request rejected.',
            data: result
        });
    } catch (error) {
        next(error);
    }
};

module.exports = {
    submitRequest,
    getMyStatus,
    listRequests,
    approveRequest,
    rejectRequest
};
