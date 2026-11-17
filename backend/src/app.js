const express = require('express');
const cookieParser = require('cookie-parser');
const pool = require('./config/database');
const errorHandler = require('./middleware/errorHandler');
const authRoutes = require('./routes/authRoutes');
const universityRoutes = require('./routes/universityRoutes');
const platformAdminRoutes = require('./routes/platformAdminRoutes');
const requireAuth = require('./middleware/requireAuth');
const withIdentityContext = require('./utils/withIdentityContext');



const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: false }));
app.use(cookieParser());
app.use('/api/auth', authRoutes);
app.use('/api/universities', universityRoutes);
app.use('/api/platform-admins', platformAdminRoutes);

// Welcome endpoint
app.get('/', (req, res) => {
    res.status(200).json({
        success: true,
        message: 'Classroom Engagement and Feedback System API',
        version: '1.0.0'
    });
});

// API health check
app.get('/api/health', (req, res) => {
    res.status(200).json({
        success: true,
        status: 'healthy',
        message: 'Backend is running successfully'
    });
});



app.get('/api/auth/me', requireAuth, async (req, res, next) => {
    try {
        const user = await withIdentityContext(
            { userId: req.auth.userId },
            async (client) => {
                const result = await client.query(`
                    SELECT
                        app_private.current_user_id() AS user_id,
                        app_private.current_university_id() AS university_id
                `);

                return result.rows[0];
            }
        );

        return res.status(200).json({
            success: true,
            message: 'Authenticated identity retrieved successfully.',
            user
        });
    } catch (error) {
        return next(error);
    }
});

// Database health check
app.get('/api/health/database', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT
                current_database() AS database,
                current_user AS user,
                NOW() AS checked_at
        `);

        res.status(200).json({
            success: true,
            status: 'connected',
            message: 'Database connection is working',
            database: result.rows[0].database,
            user: result.rows[0].user,
            checkedAt: result.rows[0].checked_at
        });
    } catch (error) {
        console.error('Database health check failed:', error.message);

        res.status(503).json({
            success: false,
            status: 'disconnected',
            message: 'Database connection failed'
        });
    }
});




// Centralized error handling middleware
app.use(errorHandler);

module.exports = app;
