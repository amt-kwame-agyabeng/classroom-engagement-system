
let brevoClient;

const getBrevoClient = async () => {
    if (!process.env.BREVO_API_KEY) {
        throw new Error('BREVO_API_KEY is not configured');
    }

    if (!brevoClient) {
        const { BrevoClient } = await import('@getbrevo/brevo');

        brevoClient = new BrevoClient({
            apiKey: process.env.BREVO_API_KEY,
            timeoutInSeconds: 30,
            maxRetries: 2
        });
    }

    return brevoClient;
};

const sendEmail = async ({ to, subject, htmlContent, textContent }) => {
    const client = await getBrevoClient();

    return client.transactionalEmails.sendTransacEmail({
        sender: {
            name: process.env.BREVO_SENDER_NAME,
            email: process.env.BREVO_SENDER_EMAIL
        },
        to: [{ email: to }],
        subject,
        htmlContent,
        textContent
    });
};

module.exports = { sendEmail };
