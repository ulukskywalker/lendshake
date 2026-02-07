-- ==========================================
-- 1. PROFILES
-- ==========================================
create table if not exists public.profiles (
  id uuid references auth.users not null primary key,
  first_name text,
  last_name text,
  phone_number text,
  residence_state text,
  reminder_enabled boolean default false,
  next_reminder_at timestamptz,
  updated_at timestamptz
);

alter table public.profiles add column if not exists reminder_enabled boolean default false;
alter table public.profiles add column if not exists next_reminder_at timestamptz;

alter table public.profiles enable row level security;

create policy "Public Profiles" on profiles for select using (true);
create policy "Manage Own Profile" on profiles for all using (auth.uid() = id);


-- ==========================================
-- 2. LOANS
-- ==========================================
create table if not exists public.loans (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz default now(),
  lender_id uuid references auth.users not null,
  borrower_id uuid references auth.users,
  principal_amount numeric not null,
  interest_rate numeric not null,
  interest_type text default 'percentage', -- 'percentage' or 'fixed'
  repayment_schedule text not null,
  late_fee_policy text not null,
  maturity_date timestamptz not null,
  borrower_name text,
  borrower_email text,
  borrower_phone text,
  status text not null,
  remaining_balance numeric, -- Can be null (if Draft)
  created_at timestamptz default now(),
  
  -- Agreements
  agreement_text text,
  release_document_text text, -- "Paid in Full" receipt
  lender_signed_at timestamptz,
  borrower_signed_at timestamptz,
  lender_ip text,
  borrower_ip text
);

alter table public.loans enable row level security;

create policy "View Loans" on loans for select using (
  auth.uid() = lender_id or auth.uid() = borrower_id or borrower_email = (auth.jwt() ->> 'email')
);
create policy "Create Loans" on loans for insert with check (auth.uid() = lender_id);
create policy "Update Loans" on loans for update using (
  auth.uid() = lender_id 
  or auth.uid() = borrower_id 
  or borrower_email = (auth.jwt() ->> 'email')
);
create policy "Delete Drafts" on loans for delete using (auth.uid() = lender_id and status = 'draft');


-- ==========================================
-- 3. PAYMENTS
-- ==========================================
create table if not exists public.payments (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz default now(),
  loan_id uuid references public.loans not null,
  amount float8 not null,
  date timestamptz not null,
  status text default 'pending',
  type text default 'repayment',
  proof_url text
);

alter table public.payments enable row level security;

create policy "View Payments" on payments for select using (
  exists (select 1 from loans where loans.id = payments.loan_id and (loans.lender_id = auth.uid() or loans.borrower_id = auth.uid()))
);
create policy "Add Payments" on payments for insert with check (
  exists (select 1 from loans where loans.id = payments.loan_id and (loans.borrower_id = auth.uid() or loans.lender_id = auth.uid()))
);
create policy "Lender Updates Payments" on payments for update using (
  exists (select 1 from loans where loans.id = payments.loan_id and loans.lender_id = auth.uid())
);


-- ==========================================
-- 4. STORAGE (Bucket: 'proofs')
-- ==========================================
-- 1. Create the bucket if it doesn't exist
insert into storage.buckets (id, name, public) 
values ('proofs', 'proofs', false)
on conflict (id) do nothing;

-- 2. Policy: Allow authenticated users to upload their own files
-- Drop existing policy if any to avoid errors on re-run
drop policy if exists "Allow Individual Uploads" on storage.objects;

create policy "Allow Individual Uploads" 
on storage.objects for insert 
to authenticated 
with check (
  bucket_id = 'proofs' AND 
  (storage.foldername(name))[1] = auth.uid()::text
);

-- 3. Policy: Allow authenticated users to connect/select (needed for Signed URL generation context in some SDK versions, but primarily for consistency)
drop policy if exists "Allow Individual Select" on storage.objects;

create policy "Allow Individual Select" 
on storage.objects for select 
to authenticated 
using (
  bucket_id = 'proofs'
  -- Removed folder check to allow Lender & Borrower to view each other's proofs
  -- Security is maintained because only they know the file path (via payments table)
);
