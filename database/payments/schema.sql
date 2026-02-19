-- ==========================================
-- 3. PAYMENTS
-- ==========================================
-- Stores all financial transactions associated with a loan.
-- Can be manual repayments, funding transfers, or system-generated late fees/interest.
create table if not exists public.payments (
  id uuid default gen_random_uuid() primary key,
  created_at timestamptz default now(),
  loan_id uuid references public.loans not null,
  amount float8 not null,
  date timestamptz not null, -- Date the payment was made (user reported)
  status text default 'pending', -- 'pending' (waiting for lender approval), 'approved', 'rejected'
  type text default 'repayment', -- 'repayment', 'funding', 'late_fee', 'interest'
  proof_url text, -- Optional screenshot URL for manual verification
  rejection_reason text
);

-- Foreign key for audit trail linkage
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'loan_events_payment_id_fkey'
    and conrelid = 'public.loan_events'::regclass
  ) then
    alter table public.loan_events
      add constraint loan_events_payment_id_fkey
      foreign key (payment_id)
      references public.payments(id);
  end if;
end;
$$;

alter table public.payments enable row level security;

-- Policies
create policy "View Payments" on payments for select using (
  exists (
    select 1
    from loans
    where loans.id = payments.loan_id
    and (loans.lender_id = (select auth.uid()) or loans.borrower_id = (select auth.uid()))
  )
);
drop policy if exists "Add Payments" on payments;
drop policy if exists "Authenticated Insert Payments" on payments;
drop policy if exists "Borrower Add Repayments" on payments;
drop policy if exists "Lender Add Funding" on payments;

-- Complex Insert Policy:
-- 1. Borrowers can propose 'repayment' (status=pending).
-- 2. Lenders can record 'funding' (if loan is approved).
create policy "Authenticated Insert Payments" on payments for insert to authenticated with check (
  coalesce(created_by, 'user') = 'user'
  and (
    (
      type = 'repayment'
      and status = 'pending'
      and exists (
        select 1
        from loans
        where loans.id = payments.loan_id
        and loans.borrower_id = (select auth.uid())
      )
    )
    or
    (
      type = 'funding'
      and status = 'approved'
      and exists (
        select 1
        from loans
        where loans.id = payments.loan_id
        and loans.lender_id = (select auth.uid())
        and loans.status = 'approved'
      )
    )
  )
);

-- Lenders can update payments (to approve/reject them), but this is mostly handled via RPCs now.
create policy "Lender Updates Payments" on payments for update using (
  exists (
    select 1
    from loans
    where loans.id = payments.loan_id
    and loans.lender_id = (select auth.uid())
  )
);

-- 3.1.1 Accrual metadata columns (idempotent)
alter table public.payments
  add column if not exists accrual_period_start timestamptz,
  add column if not exists accrual_period_end timestamptz,
  add column if not exists created_by text default 'user'; -- 'system' for auto-generated fees
alter table public.payments
  add column if not exists rejection_reason text;

-- 3.1.2 Data quality checks
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'payments_type_check'
    and conrelid = 'public.payments'::regclass
  ) then
    alter table public.payments
      add constraint payments_type_check
      check (type in ('repayment', 'funding', 'late_fee', 'interest'));
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'payments_status_check'
    and conrelid = 'public.payments'::regclass
  ) then
    alter table public.payments
      add constraint payments_status_check
      check (status in ('pending', 'approved', 'rejected'));
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'payments_created_by_check'
    and conrelid = 'public.payments'::regclass
  ) then
    alter table public.payments
      add constraint payments_created_by_check
      check (created_by in ('user', 'system'));
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'payments_amount_positive_check'
    and conrelid = 'public.payments'::regclass
  ) then
    alter table public.payments
      add constraint payments_amount_positive_check
      check (amount > 0);
  end if;
end;
$$;

-- 3.1.3 Prevent duplicate accrual rows per loan/period/type
create unique index if not exists payments_accrual_unique_idx
  on public.payments (loan_id, type, accrual_period_end)
  where type in ('interest', 'late_fee') and accrual_period_end is not null;

create index if not exists payments_loan_status_type_idx
  on public.payments (loan_id, status, type, date desc);
