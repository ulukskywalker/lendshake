import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { sendDiscordAlert, DiscordColors, withErrorLogging } from "../_shared/discord.ts";

serve(async (req: Request) => {
    return await withErrorLogging(req, async (req) => {
        // CORS
        if (req.method === "OPTIONS") {
            return new Response("ok", {
                headers: {
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
                },
            });
        }

        try {
            const { title, message, severity, metadata } = await req.json();

            let color = DiscordColors.INFO;
            let prefix = "ℹ️";

            if (severity === "critical" || severity === "error") {
                color = DiscordColors.ERROR;
                prefix = "🚨";
            } else if (severity === "warning") {
                color = DiscordColors.WARNING;
                prefix = "⚠️";
            } else if (severity === "success") {
                color = DiscordColors.SUCCESS;
                prefix = "✅";
            }

            const fields = [];
            let appEnv = "production";
            let category = "system";

            if (metadata) {
                if (metadata.env) {
                    appEnv = String(metadata.env);
                }
                if (metadata.category) {
                    category = String(metadata.category);
                }
                for (const [key, value] of Object.entries(metadata)) {
                    fields.push({ name: key, value: String(value), inline: true });
                }
            }

            await sendDiscordAlert(
                `${prefix} ${title || "App Alert"}`,
                message || "No message provided",
                color,
                fields,
                appEnv,
                category
            );

            return new Response(JSON.stringify({ success: true }), {
                headers: { "Content-Type": "application/json" },
            });

        } catch (error: any) {
            return new Response(JSON.stringify({ error: error.message }), {
                status: 400,
                headers: { "Content-Type": "application/json" },
            });
        }
    });
});

