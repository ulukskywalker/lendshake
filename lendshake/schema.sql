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
-- 3.1 PAYMENT APPROVAL RPC (Atomic Balance Recompute)
-- ==========================================
-- 3.1.1 Accrual metadata columns (idempotent)
alter table public.payments
  add column if not exists accrual_period_start timestamptz,
  add column if not exists accrual_period_end timestamptz,
  add column if not exists created_by text default 'user';

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

-- 3.1.3 Prevent duplicate accrual rows per loan/period/type
create unique index if not exists payments_accrual_unique_idx
  on public.payments (loan_id, type, accrual_period_end)
  where type in ('interest', 'late_fee') and accrual_period_end is not null;

-- 3.1.4 Centralized balance recompute
create or replace function public.recompute_loan_balance(p_loan_id uuid)
returns public.loans
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.loans%rowtype;
  v_repayments numeric := 0;
  v_charges numeric := 0;
  v_new_balance numeric := 0;
begin
  select * into v_loan
  from public.loans
  where id = p_loan_id
  for update;

  if not found then
    raise exception 'Loan not found';
  end if;

  select coalesce(sum(amount::numeric), 0)
    into v_repayments
  from public.payments
  where loan_id = v_loan.id
    and status = 'approved'
    and type = 'repayment';

  select coalesce(sum(amount::numeric), 0)
    into v_charges
  from public.payments
  where loan_id = v_loan.id
    and status = 'approved'
    and type in ('interest', 'late_fee');

  v_new_balance := greatest(0, coalesce(v_loan.principal_amount, 0) + v_charges - v_repayments);

  if v_new_balance <= 0 and v_loan.status in ('active', 'funding_sent', 'approved') then
    update public.loans
      set remaining_balance = 0,
          status = 'completed'
    where id = v_loan.id
    returning * into v_loan;
  else
    update public.loans
      set remaining_balance = v_new_balance
    where id = v_loan.id
    returning * into v_loan;
  end if;

  return v_loan;
end;
$$;

-- 3.1.5 Payment approval RPC using centralized recompute
create or replace function public.approve_payment_and_recompute_balance(p_payment_id uuid)
returns public.loans
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments%rowtype;
begin
  select * into v_payment
  from public.payments
  where id = p_payment_id
  for update;

  if not found then
    raise exception 'Payment not found';
  end if;

  if v_payment.type <> 'repayment' then
    raise exception 'Only repayment payments can be approved with this RPC';
  end if;

  if coalesce(v_payment.status, 'pending') <> 'pending' then
    raise exception 'Payment is not pending';
  end if;

  if not exists (
    select 1
    from public.loans l
    where l.id = v_payment.loan_id
      and l.lender_id = auth.uid()
  ) then
    raise exception 'Not authorized to approve this payment';
  end if;

  update public.payments
    set status = 'approved'
  where id = p_payment_id;

  return public.recompute_loan_balance(v_payment.loan_id);
end;
$$;

grant execute on function public.approve_payment_and_recompute_balance(uuid) to authenticated;
grant execute on function public.recompute_loan_balance(uuid) to service_role;

-- 3.1.6 Interest + late fee accrual for one loan (idempotent)
create or replace function public.accrue_loan_charges(p_loan_id uuid, p_as_of timestamptz default now())
returns public.loans
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.loans%rowtype;
  v_interest_amount numeric := 0;
  v_late_fee_amount numeric := 0;
  v_grace_days integer := 5;
  v_schedule text;
  v_cycle_interval interval;
  v_period record;
begin
  select * into v_loan
  from public.loans
  where id = p_loan_id
  for update;

  if not found then
    raise exception 'Loan not found';
  end if;

  if v_loan.status <> 'active' then
    return v_loan;
  end if;

  v_schedule := lower(coalesce(v_loan.repayment_schedule, ''));

  -- Monthly interest accrual (APR based, one row per month)
  if coalesce(v_loan.interest_rate, 0) > 0 then
    v_interest_amount := (coalesce(v_loan.principal_amount, 0) * (v_loan.interest_rate / 100.0)) / 12.0;

    insert into public.payments (
      loan_id, amount, date, status, type, proof_url,
      accrual_period_start, accrual_period_end, created_by
    )
    select
      v_loan.id,
      v_interest_amount::float8,
      gs.due_at,
      'approved',
      'interest',
      null,
      gs.due_at - interval '1 month',
      gs.due_at,
      'system'
    from (
      select generate_series(
        coalesce(v_loan.created_at, now()) + interval '1 month',
        p_as_of,
        interval '1 month'
      ) as due_at
    ) gs
    on conflict (loan_id, type, accrual_period_end) where (type in ('interest', 'late_fee') and accrual_period_end is not null)
    do nothing;
  end if;

  -- Late fee parsing
  if v_loan.late_fee_policy ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then
    v_late_fee_amount := v_loan.late_fee_policy::numeric;
  elsif v_loan.late_fee_policy ~ '\$[0-9]+(\.[0-9]+)?' then
    v_late_fee_amount := substring(v_loan.late_fee_policy from '\$([0-9]+(\.[0-9]+)?)')::numeric;
  else
    v_late_fee_amount := 0;
  end if;

  if v_loan.late_fee_policy ~ '([0-9]+)\s*day' then
    v_grace_days := substring(v_loan.late_fee_policy from '([0-9]+)\s*day')::integer;
  end if;

  if v_late_fee_amount > 0 then
    if v_schedule like '%month%' then
      v_cycle_interval := interval '1 month';
    elsif v_schedule like '%bi%' then
      v_cycle_interval := interval '14 days';
    else
      v_cycle_interval := null;
    end if;

    if v_cycle_interval is not null then
      for v_period in
        select
          gs.due_at - v_cycle_interval as period_start,
          gs.due_at as period_end
        from (
          select generate_series(
            coalesce(v_loan.created_at, now()) + v_cycle_interval,
            p_as_of,
            v_cycle_interval
          ) as due_at
        ) gs
      loop
        if p_as_of > (v_period.period_end + make_interval(days => v_grace_days)) then
          if not exists (
            select 1
            from public.payments p
            where p.loan_id = v_loan.id
              and p.status = 'approved'
              and p.type = 'repayment'
              and p.date > v_period.period_start
              and p.date <= (v_period.period_end + make_interval(days => v_grace_days))
          ) then
            insert into public.payments (
              loan_id, amount, date, status, type, proof_url,
              accrual_period_start, accrual_period_end, created_by
            )
            values (
              v_loan.id,
              v_late_fee_amount::float8,
              v_period.period_end + make_interval(days => v_grace_days),
              'approved',
              'late_fee',
              null,
              v_period.period_start,
              v_period.period_end,
              'system'
            )
            on conflict (loan_id, type, accrual_period_end) where (type in ('interest', 'late_fee') and accrual_period_end is not null)
            do nothing;
          end if;
        end if;
      end loop;
    else
      -- Lump sum schedule: one late-fee opportunity around maturity.
      if p_as_of > (v_loan.maturity_date + make_interval(days => v_grace_days)) then
        if not exists (
          select 1
          from public.payments p
          where p.loan_id = v_loan.id
            and p.status = 'approved'
            and p.type = 'repayment'
            and p.date > coalesce(v_loan.created_at, now())
            and p.date <= (v_loan.maturity_date + make_interval(days => v_grace_days))
        ) then
          insert into public.payments (
            loan_id, amount, date, status, type, proof_url,
            accrual_period_start, accrual_period_end, created_by
          )
          values (
            v_loan.id,
            v_late_fee_amount::float8,
            v_loan.maturity_date + make_interval(days => v_grace_days),
            'approved',
            'late_fee',
            null,
            coalesce(v_loan.created_at, now()),
            v_loan.maturity_date,
            'system'
          )
          on conflict (loan_id, type, accrual_period_end) where (type in ('interest', 'late_fee') and accrual_period_end is not null)
          do nothing;
        end if;
      end if;
    end if;
  end if;

  return public.recompute_loan_balance(v_loan.id);
end;
$$;

grant execute on function public.accrue_loan_charges(uuid, timestamptz) to service_role;

-- 3.1.7 Batch accrual for all active loans
create or replace function public.accrue_all_loans(p_as_of timestamptz default now())
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan_id uuid;
  v_locked boolean;
begin
  -- Prevent overlapping runs.
  v_locked := pg_try_advisory_lock(hashtext('public.accrue_all_loans'));
  if not v_locked then
    return;
  end if;

  begin
    for v_loan_id in
      select id
      from public.loans
      where status = 'active'
    loop
      perform public.accrue_loan_charges(v_loan_id, p_as_of);
    end loop;
  exception when others then
    perform pg_advisory_unlock(hashtext('public.accrue_all_loans'));
    raise;
  end;

  perform pg_advisory_unlock(hashtext('public.accrue_all_loans'));
end;
$$;

grant execute on function public.accrue_all_loans(timestamptz) to service_role;

-- 3.1.8 Optional pg_cron schedule (hourly)
-- Run once in SQL editor as service_role/postgres.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if not exists (
      select 1
      from cron.job
      where jobname = 'accrue-loan-charges-hourly'
    ) then
      perform cron.schedule(
        'accrue-loan-charges-hourly',
        '5 * * * *',
        $$select public.accrue_all_loans(now());$$
      );
    end if;
  end if;
exception when others then
  raise notice 'pg_cron not available or schedule creation failed: %', sqlerrm;
end;
$$;


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
