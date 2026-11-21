const PG_ERROR_STATUS_CODES = {
    '42501': 403, // Insufficient privilege / authorization failure
    '22023': 400, // Invalid parameter value
    'P0002': 404, // Requested resource not found
    '23514': 409, // Business rule / state violation
    '23505': 409  // Unique constraint violation
};

const errorHandler = (err, req, res, next) => {
    console.error('API Error:', {
        message: err.message,
        code: err.code,
        stack: err.stack,
        method: req.method,
        path: req.originalUrl
    });

    if (res.headersSent) {
        return next(err);
    }

    const statusCode =
        err.statusCode ||
        PG_ERROR_STATUS_CODES[err.code] ||
        500;

    return res.status(statusCode).json({
        success: false,
        message: statusCode >= 500
            ? 'Internal server error'
            : err.message
    });
};

module.exports = errorHandler;