-- ==========================================
-- 2. LOANS
-- ==========================================
-- The core table storing all loan agreements.
create table if not exists public.loans (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz default now(),
  lender_id uuid references auth.users not null, -- The user offering the money
  borrower_id uuid references auth.users, -- The user receiving the money (nullable if invited by email)
  principal_amount numeric not null, -- The initial loan amount
  interest_rate numeric not null, -- Annual interest rate percentage
  interest_type text default 'percentage', -- 'percentage' or 'fixed'
  repayment_schedule text not null, -- e.g., "Monthly", "Bi-weekly", "Lump Sum"
  late_fee_policy text not null, -- e.g., "$15 after 5 days"
  maturity_date timestamptz not null, -- When the loan must be fully paid
  borrower_name text, -- Display name for borrower (until they sign up)
  borrower_email text, -- Email to invite borrower
  borrower_phone text,
  
  -- Snapshots: Legal names at the time of signing (immutable)
  lender_name_snapshot text,
  borrower_name_snapshot text,
  
  status text not null, -- State machine: draft -> sent -> approved -> funding_sent -> active -> completed
  remaining_balance numeric, -- Current outstanding balance. Null for Drafts.
  
  -- Agreement Documents
  agreement_text text, -- Computed legal text of the promissory note
  agreement_rejection_reason text, -- If borrower rejects the terms
  release_document_text text, -- "Paid in Full" receipt text
  lender_signed_at timestamptz, -- Timestamp of lender signature
  borrower_signed_at timestamptz, -- Timestamp of borrower signature
  lender_ip text, -- Audit: IP address of lender signing
  borrower_ip text -- Audit: IP address of borrower signing
);

alter table public.loans enable row level security;

-- Policies
-- Standard View Policy: Lenders, Borrowers, and Invitees (via email) can view the loan.
create policy "View Loans" on loans for select using (
  (select auth.uid()) = lender_id
  or (select auth.uid()) = borrower_id
  or borrower_email = ((select auth.jwt()) ->> 'email')
);

-- Creation Policy: Only authenticated users can create loans (as the lender).
create policy "Create Loans" on loans for insert with check ((select auth.uid()) = lender_id);

-- Update Policies: 
-- Direct updates are largely disabled in favor of stored procedures (RPCs) to ensure state machine integrity.
drop policy if exists "Update Loans" on loans;
drop policy if exists "No Direct Loan Updates" on loans;
create policy "No Direct Loan Updates" on loans for update using (false) with check (false);

-- Delete Policy: Draft and Cancelled loans can be deleted by the lender.
create policy "Delete Drafts and Cancelled" on loans for delete using ((select auth.uid()) = lender_id and status in ('draft', 'cancelled'));

-- Ensure columns exist (idempotency for migrations)
alter table public.loans add column if not exists lender_name_snapshot text;
alter table public.loans add column if not exists borrower_name_snapshot text;
alter table public.loans add column if not exists agreement_rejection_reason text;

-- Data Integrity Constraints
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'loans_status_check'
    and conrelid = 'public.loans'::regclass
  ) then
    alter table public.loans
      add constraint loans_status_check
      check (status in ('draft', 'sent', 'approved', 'funding_sent', 'active', 'completed', 'forgiven', 'cancelled'));
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'loans_interest_type_check'
    and conrelid = 'public.loans'::regclass
  ) then
    alter table public.loans
      add constraint loans_interest_type_check
      check (interest_type in ('percentage', 'fixed'));
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'loans_principal_amount_check'
    and conrelid = 'public.loans'::regclass
  ) then
    alter table public.loans
      add constraint loans_principal_amount_check
      check (principal_amount > 0 and principal_amount <= 10000);
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'loans_interest_rate_check'
    and conrelid = 'public.loans'::regclass
  ) then
    alter table public.loans
      add constraint loans_interest_rate_check
      check (interest_rate >= 0 and interest_rate <= 15);
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'loans_remaining_balance_check'
    and conrelid = 'public.loans'::regclass
  ) then
    alter table public.loans
      add constraint loans_remaining_balance_check
      check (remaining_balance is null or remaining_balance >= 0);
  end if;
end;
$$;
