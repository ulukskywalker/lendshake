const DISCORD_WEBHOOK_URL = Deno.env.get("DISCORD_WEBHOOK_URL") || "";
const DISCORD_FEEDBACK_WEBHOOK_URL = Deno.env.get("DISCORD_FEEDBACK_WEBHOOK_URL") || "";

export async function sendDiscordAlert(
    title: string,
    message: string,
    color: number = 0x3498db,
    fields: any[] = [],
    env: string = Deno.env.get("APP_ENVIRONMENT") || "unknown",
    category: string = "system"
) {
    // Determine which webhook to use.
    // If it's feedback, try to use the feedback-specific channel.
    let webhookUrl = DISCORD_WEBHOOK_URL;
    if (category === "feedback" && DISCORD_FEEDBACK_WEBHOOK_URL) {
        webhookUrl = DISCORD_FEEDBACK_WEBHOOK_URL;
    }

    if (!webhookUrl) {
        console.warn(`No Discord Webhook URL set for category: ${category}`);
        return;
    }

    try {
        await fetch(webhookUrl, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                embeds: [{
                    title: title,
                    description: message,
                    color: color,
                    fields: [
                        ...fields,
                        { name: "Environment", value: env, inline: true }
                    ],
                    timestamp: new Date().toISOString(),
                    footer: { text: "Loandry Monitoring" }
                }]
            })
        });
    } catch (e) {
        console.error("Failed to send Discord alert:", e);
    }
}

export const DiscordColors = {
    INFO: 0x3498db,    // Blue
    SUCCESS: 0x2ecc71, // Green
    WARNING: 0xf1c40f, // Yellow
    ERROR: 0xe74c3c,   // Red
    DELETED: 0x95a5a6  // Gray
};

/**
 * Utility to wrap an edge function handler with global error logging to Discord.
 */
export async function withErrorLogging(req: Request, handler: (req: Request) => Promise<Response>) {
    try {
        return await handler(req);
    } catch (error: any) {
        console.error("Critical Error captured by wrapper:", error);

        await sendDiscordAlert(
            "🚨 Edge Function Critical Error",
            `A runtime error occurred in an edge function.\n\n**Error:** ${error.message || "Unknown error"}\n**URL:** ${req.url}`,
            DiscordColors.ERROR,
            [
                { name: "Method", value: req.method, inline: true },
                { name: "Trace", value: error.stack?.substring(0, 1000) || "No stack trace", inline: false }
            ]
        );

        return new Response(JSON.stringify({ error: error.message || "Internal Server Error" }), {
            status: 500,
            headers: { "Content-Type": "application/json" },
        });
    }
}
