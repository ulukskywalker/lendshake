import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendDiscordAlert, DiscordColors, withErrorLogging } from "../_shared/discord.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
// Use Service Role to ensure we can bypass RLS for cleanup
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req: Request) => {
    return await withErrorLogging(req, async (req) => {
        // 1. CORS
        if (req.method === "OPTIONS") {
            return new Response("ok", {
                headers: {
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
                },
            });
        }

        let loanIdForError = "Unknown";
        try {
            const { loan_id } = await req.json();
            if (!loan_id) throw new Error("Missing loan_id");
            loanIdForError = loan_id;

            // 2. Auth Context (User's Token)
            const authHeader = req.headers.get("Authorization");
            if (!authHeader) throw new Error("Missing Authorization header");

            // 3. User Client (RLS Enforced)
            const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
                global: { headers: { Authorization: authHeader } }
            });

            // Get user for logging
            const { data: { user }, error: userError } = await userClient.auth.getUser();
            if (userError || !user) throw new Error("Invalid user token");

            // 4. Verify Ownership / Existence via RLS
            // Try to fetch the specific loan with the user's permissions
            const { data: loan, error: fetchError } = await userClient
                .from("loans")
                .select("id, status, agreement_url, lender_id, borrower_id")
                .eq("id", loan_id)
                .single();

            if (fetchError || !loan) {
                return new Response(JSON.stringify({ error: "Loan not found or unauthorized" }), { status: 404 });
            }

            // 5. Admin Client (Service Role - Bypass RLS for Cleanup)
            const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

            // 6. Delete Payment Proofs
            // Fetch all payment proofs associated with this loan
            // (Since we are deleting the loan, payments are cascading, but we need their file paths first)
            const { data: payments } = await adminClient
                .from("payments")
                .select("proof_url")
                .eq("loan_id", loan_id)
                .not("proof_url", "is", null);

            if (payments && payments.length > 0) {
                const proofPaths = payments.map((p: any) => p.proof_url).filter((url: any) => url !== null) as string[];
                if (proofPaths.length > 0) {
                    const { error: proofError } = await adminClient.storage.from("proofs").remove(proofPaths);
                    if (proofError) console.error("Failed to delete proofs:", proofError);
                }
            }

            // 7. Delete Agreement PDF
            if (loan.agreement_url) {
                const { error: agreementError } = await adminClient.storage.from("loan-documents").remove([loan.agreement_url]);
                if (agreementError) console.error("Failed to delete agreement:", agreementError);
            }

            // 8. Delete Loan Record
            const { error: deleteError } = await adminClient
                .from("loans")
                .delete()
                .eq("id", loan_id);

            if (deleteError) throw deleteError;

            return new Response(JSON.stringify({ success: true }), {
                headers: { "Content-Type": "application/json" },
            });

        } catch (error: any) {
            return new Response(JSON.stringify({ error: error.message || "Unknown error" }), {
                status: 400,
                headers: { "Content-Type": "application/json" },
            });
        }
    });
});

