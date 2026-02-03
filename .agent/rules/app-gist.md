---
trigger: always_on
---

Technical Documentation: Formal Lending Ledger (FLL)
Phase 1: User Onboarding & Identity

Before a document can be signed, you must establish the legal identity of both parties.

Identity Collection: Users sign up (via Supabase/Firebase). You must collect Full Legal Name and State of Residence (contracts vary by state).

Payment Handles: Users link their @username for Venmo/Zelle.

Note: These are stored as strings for display only; no API connection to Venmo is required.

The Invite System: Lender creates a "Draft Loan" and sends a unique link to the Borrower. The Borrower must create an account to view and sign the terms.

Phase 2: The Loan Construction (Drafting)
The app must guide the user through creating a legally sound agreement.

Parameter Input:

Principal Amount ($)

Annual Interest Rate (%) — Include a "0%" option for family.

Repayment Schedule (Monthly, Bi-weekly, or Lump Sum).

Late Fee Policy (e.g., "$15 after 5 days").

Validation Logic:

Check interest against state-specific Usury Laws (to ensure the lender isn't charging an illegal rate).

Check against IRS AFR to flag potential gift-tax issues.

Phase 3: The Signature Pipeline (The "Docusign" Step)
This is the most critical technical integration. You will use a Template-to-Signature workflow.

Template Generation: * You create one "Master Promissory Note" template in your signature provider (e.g., Dropbox Sign).

The template has "Merge Fields" for {{Principal}}, {{Borrower_Name}}, etc.

API Request:

When the Lender hits "Send for Signature," your backend calls the API:

POST /signature_request/send_with_template

Pass the user-specific data into the merge fields.

Status Tracking (Webhooks):

Status: sent — Document is in the borrower's inbox.

Status: viewed — Borrower has opened the document.

Status: signed — The Webhook triggers your backend to move the loan to Active status.

Final Storage: Download the signed PDF + Audit Trail and store them in an encrypted bucket (Supabase Storage). Give both users a "Download Contract" button.

Phase 4: The Progress Tracker (The Manual Ledger)
Since payments are off-platform, the app acts as a Verification Gateway.

The Payment Event:

Borrower pays via Venmo.

Borrower opens your app and clicks "I've Paid".

Requirement: Borrower must input the Amount and Date.

The Proof (Optional):

Allow the borrower to upload a screenshot of the Venmo confirmation.

Lender Verification:

Loan status moves to Awaiting Confirmation.

Lender receives a notification: "Did you receive $100 from [Name]?"

Yes: Ledger updates, balance drops, next due date is set.

No: A "Dispute" flag is raised, and the borrower is notified to check their payment.

Phase 5: Loan Maturity & Closeout
Final Payment: Once Remaining_Balance hits 0, the app generates a "Release of Promissory Note" (a simple receipt stating the debt is settled).

Archiving: The loan moves to "Completed" but the signed documents remain accessible for 7 years for tax/legal purposes.