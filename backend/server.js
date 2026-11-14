const app = require('./src/app');
const config = require('./src/config/env');

const server = app.listen(config.port, () => {
    console.log(`Classroom Engagement API running on port ${config.port}`);
});

module.exports = server;
