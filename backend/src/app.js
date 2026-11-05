const express = require('express');

const app = express();

// Middleware to parse incoming JSON requests
app.use(express.json());

// Welcome endpoint
app.get('/', (req, res) => {
    res.status(200).json({
        success: true,
        message: 'Classroom Engagement and Feedback System API',
        version: '1.0.0'
    });
});

// Health check endpoint
app.get('/api/health', (req, res) => {
    res.status(200).json({
        success: true,
        status: 'healthy',
        message: 'Backend is running successfully'
    });
});

module.exports = app;
