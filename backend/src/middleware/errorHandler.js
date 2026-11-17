
const errorHandler = (err, req, res, next) => {
    console.error('API Error:', {
        message: err.message,
        stack: err.stack,
        method: req.method,
        path: req.originalUrl
    });

    if (res.headersSent) {
        return next(err);
    }

    const statusCode = err.statusCode || 500;

    return res.status(statusCode).json({
        success: false,
        message: statusCode >= 500
            ? 'Internal server error'
            : err.message
    });
};

module.exports = errorHandler;
