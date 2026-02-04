# LendShake - Formal Lending Ledger

LendShake is a SwiftUI application designed to formalize personal lending. It allows friends and family to create legally sound loan agreements, track repayments, and maintain a clear audit trail of debts.

## 🚀 Features

### Phase 1: Identity & Onboarding
- **Secure Authentication**: Email/Password login via Supabase.
- **Identity Verification**: Captures legal name, state of residence, and phone number (for identity confirmation).
- **Profile Management**: Users manage their contact details to ensure contracts are valid.

### Phase 2: Loan Construction (Drafting)
- **Flexible Parameters**: Define Principal ($), Interest Rate (%), Repayment Schedule, and Late Fees.
- **Draft Mode**: Create potential loans without committing immediately.
- **Swipe Actions**: Easily manage and delete drafts.

### Phase 3: Agreement & Signing
- **Digital Signatures**: "Sign" agreements with IP address and timestamp recording for audit trails.
- **Contract Generation**: Automatically generates a plain-text agreement based on loan parameters.
- **Status Workflow**:
  - `Draft` -> `Sent` (Lender signs) -> `Approved` (Borrower signs) -> `Active` (Funds confirmed).

### Phase 4: Financial Ledger
- **Transaction Tracking**: Record every repayment and funding event.
- **Balance Calculation**: Real-time remaining balance tracking.
- **Proof of Payment**:
  - Borrowers can upload screenshots (e.g., Venmo receipts).
  - Uses **Supabase Storage** (Private Buckets) with **Signed URLs** for security.
- **Lender Verification**: Lenders verify each payment ("Approve" or "Reject").

## 🛠 Tech Stack

- **Frontend**: SwiftUI (iOS 17+)
- **Backend/Database**: Supabase (PostgreSQL)
- **Auth**: Supabase Auth
- **Storage**: Supabase Storage

## 📦 Setup Instructions

### 1. Prerequisites
- Xcode 15+
- A Supabase Project

### 2. Environment Variables
Create a file named `Secrets.swift` (or similar, ensure it's gitignored if public) or set up your `Supabase` client initialization with your keys:
```swift
let supabaseUrl = URL(string: "YOUR_SUPABASE_URL")!
let supabaseKey = "YOUR_SUPABASE_ANON_KEY"
```

### 3. Database Schema
The complete SQL schema is available in the `schema.sql` file in this repository.
Copy and paste the contents of `schema.sql` into your Supabase SQL Editor to create:
- `profiles` table (RLS enabled)
- `loans` table (RLS enabled)
- `payments` table (RLS enabled)

### 4. Storage Setup
- Create a **Private** bucket named `proofs`.
- Folder structure is handled automatically by the app (`userID/filename.jpg`).

## 🛡 Security
- **Row Level Security (RLS)**: Enforced on all tables to ensure users only access their own data.
- **Private Storage**: Proof images are protected and only accessible via time-limited signed URLs.
