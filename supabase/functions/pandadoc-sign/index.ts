import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { sendDiscordAlert, DiscordColors, withErrorLogging } from "../_shared/discord.ts";

const PANDADOC_API_KEY = Deno.env.get("PANDADOC_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Use a simple fetch wrapper for PandaDoc API
async function pandaDocRequest(method: string, endpoint: string, body?: any) {
    const url = `https://api.pandadoc.com/public/v1${endpoint}`;
    const headers = {
        "Authorization": `API-Key ${PANDADOC_API_KEY}`,
        "Content-Type": "application/json",
    };

    const options: RequestInit = {
        method,
        headers,
    };

    if (body) {
        options.body = JSON.stringify(body);
    }

    const response = await fetch(url, options);
    if (!response.ok) {
        const text = await response.text();
        throw new Error(`PandaDoc API Error: ${response.status} ${text}`);
    }
    return response.json();
}

serve(async (req: Request) => {
    return await withErrorLogging(req, async (req) => {
        // CORS implementation
        if (req.method === "OPTIONS") {
            return new Response("ok", {
                headers: {
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
                },
            });
        }

        try {
            const url = new URL(req.url);
            const path = url.pathname.split("/").pop(); // Get last segment

            // 1. Send Document Flow
            if (path === "send" && req.method === "POST") {
                const {
                    loan_id,
                    borrower_email,
                    borrower_name,
                    lender_name,
                    loan_amount,
                    interest_rate,
                    repayment_schedule,
                    lender_state,
                    borrower_state
                } = await req.json();

                if (!loan_id || !borrower_email) {
                    throw new Error("Missing required fields: loan_id, borrower_email");
                }

                // 1. Resolve Template ID based on State
                // Priority: Lender State -> Borrower State -> Default
                let template_id;
                const preferredState = lender_state || borrower_state;

                if (preferredState) {
                    const stateKey = `PANDADOC_TEMPLATE_ID_${preferredState.toUpperCase()}`;
                    template_id = Deno.env.get(stateKey);
                }
                // Fallback
                if (!template_id) {
                    template_id = Deno.env.get("PANDADOC_TEMPLATE_ID");
                }

                if (!template_id) throw new Error(`PandaDoc Template not found for state: ${preferredState || 'default'}`);

                const createResponse = await pandaDocRequest("POST", "/documents", {
                    name: `Loan Agreement - ${loan_id}`,
                    template_uuid: template_id,
                    recipients: [
                        {
                            email: borrower_email,
                            first_name: borrower_name || "Borrower",
                            role: "Borrower", // Ensure your template has a role named "Borrower"
                            signing_order: 1
                        },
                        // Optionally add Lender if they need to sign too, usually role "Lender"
                    ],
                    tokens: [
                        { name: "Loan.Principal", value: loan_amount },
                        { name: "Loan.Interest", value: interest_rate },
                        { name: "Loan.Schedule", value: repayment_schedule },
                        { name: "Lender.Name", value: lender_name },
                        { name: "Borrower.Name", value: borrower_name }
                    ],
                    metadata: {
                        loan_id: loan_id // Crucial for webhook matching
                    }
                });

                const docId = createResponse.id;

                // 2. Wait for document to be 'document.draft' to 'document.uploaded' (API is async)
                // For simplicity, we just trigger send. PandaDoc usually queues it. 
                // Sometimes you need to delay slightly or check status, but let's try direct send.

                // 3. Send Document Silently (Enforce App Login)
                await pandaDocRequest("POST", `/documents/${docId}/send`, {
                    message: "Please sign this loan agreement via Loandry.",
                    silent: true
                });

                // 4. Update Supabase with Document ID
                // We use the Supabase SDK to update the record secureley
                const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2");
                const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

                await supabase
                    .from("loans")
                    .update({
                        t_pandadoc_id: docId,
                        t_pandadoc_status: "sent",
                        status: "sent" // Update app status to sent
                    })
                    .eq("id", loan_id);

                return new Response(JSON.stringify({ success: true, doc_id: docId }), {
                    headers: { "Content-Type": "application/json" },
                });
            }

            // 3. Session Generation (For Embedded Sign)
            if (path === "session" && req.method === "POST") {
                const { doc_id, recipient_email } = await req.json();
                if (!doc_id || !recipient_email) throw new Error("doc_id and recipient_email required");

                const session = await pandaDocRequest("POST", `/documents/${doc_id}/sessions`, {
                    recipient: recipient_email
                });

                return new Response(JSON.stringify({
                    success: true,
                    session_id: session.id,
                    signing_url: `https://app.pandadoc.com/s/${session.id}`
                }), {
                    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
                });
            }

            // 4. Webhook Handler
            if (path === "webhook" && req.method === "POST") {
                const event = await req.json();
                // event usually contains [{ event: 'document_state_changed', data: { ... } }]

                const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2");
                const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

                for (const item of event) {
                    if (item.event === "document_state_changed") {
                        const doc = item.data;
                        const loanId = doc.metadata?.loan_id;
                        const status = doc.status; // 'document.completed' is what we care about

                        if (loanId && status === "document.completed") {
                            try {
                                // 1. Download Signed PDF
                                const pdfUrl = `https://api.pandadoc.com/public/v1/documents/${doc.id}/download`;
                                const pdfRes = await fetch(pdfUrl, {
                                    headers: { "Authorization": `API-Key ${PANDADOC_API_KEY}` }
                                });

                                if (pdfRes.ok) {
                                    const pdfData = await pdfRes.arrayBuffer();

                                    // 2. Upload to Supabase Storage
                                    const filePath = `${loanId}/agreement.pdf`;
                                    const { error: uploadError } = await supabase.storage
                                        .from('loan-documents')
                                        .upload(filePath, pdfData, {
                                            contentType: 'application/pdf',
                                            upsert: true
                                        });

                                    if (uploadError) {
                                        console.error("Storage Upload Error:", uploadError);
                                    } else {
                                        console.log("PDF uploaded to:", filePath);
                                    }

                                    // 3. Update Loan Record with Agreement URL
                                    await supabase
                                        .from("loans")
                                        .update({
                                            t_pandadoc_status: "completed",
                                            agreement_url: filePath
                                        })
                                        .eq("id", loanId);
                                }
                            } catch (downloadError) {
                                console.error("Failed to process document download:", downloadError);
                            }

                            // Mark loan as approved/active
                            await supabase.rpc('transition_loan_status', {
                                p_loan_id: loanId,
                                p_new_status: 'approved', // Or 'active' if funding is not tracked separately
                                p_reason: 'Signed via PandaDoc'
                            });
                        }
                    }
                }

                return new Response(JSON.stringify({ received: true }), {
                    headers: { "Content-Type": "application/json" },
                });
            }

            throw new Error("Not Found");

        } catch (error: any) {
            return new Response(JSON.stringify({ error: error.message }), {
                status: 400,
                headers: { "Content-Type": "application/json" },
            });
        }
    });
});
