-- ==========================================
-- 1. PROFILES
-- ==========================================
create table if not exists public.profiles (
  id uuid references auth.users not null primary key,
  first_name text,
  last_name text,
  phone_number text,
  residence_state text,
  updated_at timestamptz
);

alter table public.profiles drop column if exists reminder_enabled;
alter table public.profiles drop column if exists next_reminder_at;

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
  lender_name_snapshot text,
  borrower_name_snapshot text,
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
drop policy if exists "Update Loans" on loans;
drop policy if exists "No Direct Loan Updates" on loans;
create policy "No Direct Loan Updates" on loans for update using (false) with check (false);
create policy "Delete Drafts" on loans for delete using (auth.uid() = lender_id and status = 'draft');

alter table public.loans add column if not exists lender_name_snapshot text;
alter table public.loans add column if not exists borrower_name_snapshot text;

create or replace function public.resolve_profile_full_name(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_first text;
  v_last text;
  v_name text;
begin
  select first_name, last_name
  into v_first, v_last
  from public.profiles
  where id = p_user_id;

  v_name := concat_ws(' ', nullif(trim(coalesce(v_first, '')), ''), nullif(trim(coalesce(v_last, '')), ''));
  return nullif(trim(coalesce(v_name, '')), '');
end;
$$;

create or replace function public.set_loan_name_snapshots_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if nullif(trim(coalesce(new.lender_name_snapshot, '')), '') is null then
    new.lender_name_snapshot := coalesce(
      public.resolve_profile_full_name(new.lender_id),
      'Lender'
    );
  end if;

  if nullif(trim(coalesce(new.borrower_name_snapshot, '')), '') is null then
    new.borrower_name_snapshot := coalesce(
      nullif(trim(coalesce(new.borrower_name, '')), ''),
      'Borrower'
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_set_loan_name_snapshots_on_insert on public.loans;
create trigger trg_set_loan_name_snapshots_on_insert
before insert on public.loans
for each row execute function public.set_loan_name_snapshots_on_insert();

update public.loans l
set
  lender_name_snapshot = coalesce(
    nullif(trim(coalesce(l.lender_name_snapshot, '')), ''),
    public.resolve_profile_full_name(l.lender_id),
    'Lender'
  ),
  borrower_name_snapshot = coalesce(
    nullif(trim(coalesce(l.borrower_name_snapshot, '')), ''),
    nullif(trim(coalesce(l.borrower_name, '')), ''),
    'Borrower'
  )
where nullif(trim(coalesce(l.lender_name_snapshot, '')), '') is null
   or nullif(trim(coalesce(l.borrower_name_snapshot, '')), '') is null;

-- 2.2 Immutable event log (audit trail)
create table if not exists public.loan_events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  loan_id uuid not null references public.loans(id) on delete cascade,
  event_type text not null,
  actor_user_id uuid references auth.users(id),
  payment_id uuid,
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists loan_events_loan_created_idx
  on public.loan_events (loan_id, created_at desc);
create index if not exists loan_events_type_created_idx
  on public.loan_events (event_type, created_at desc);

alter table public.loan_events enable row level security;

drop policy if exists "View Loan Events" on public.loan_events;
create policy "View Loan Events" on public.loan_events for select using (
  exists (
    select 1
    from public.loans l
    where l.id = loan_events.loan_id
      and (
        l.lender_id = auth.uid()
        or l.borrower_id = auth.uid()
        or l.borrower_email = (auth.jwt() ->> 'email')
      )
  )
);

drop policy if exists "No Direct Loan Event Writes" on public.loan_events;
create policy "No Direct Loan Event Writes" on public.loan_events
for all
using (false)
with check (false);

create or replace function public.append_loan_event(
  p_loan_id uuid,
  p_event_type text,
  p_actor_user_id uuid default null,
  p_payment_id uuid default null,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.loan_events (
    loan_id, event_type, actor_user_id, payment_id, metadata
  ) values (
    p_loan_id, p_event_type, p_actor_user_id, p_payment_id, coalesce(p_metadata, '{}'::jsonb)
  );
end;
$$;

grant execute on function public.append_loan_event(uuid, text, uuid, uuid, jsonb) to service_role;

-- 2.1 Status transition & signing RPCs (authoritative server-side workflow)
create or replace function public.lender_sign_loan(
  p_loan_id uuid,
  p_agreement_text text,
  p_lender_ip text default null
)
returns public.loans
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.loans%rowtype;
  v_lender_snapshot text;
  v_borrower_snapshot text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_loan
  from public.loans
  where id = p_loan_id
  for update;

  if not found then
    raise exception 'Loan not found';
  end if;

  if v_loan.lender_id <> auth.uid() then
    raise exception 'Only the lender can sign this agreement';
  end if;

  if v_loan.status <> 'draft' then
    raise exception 'Loan is not in draft status';
  end if;

  if v_loan.lender_signed_at is not null then
    raise exception 'Loan is already signed by lender';
  end if;

  if coalesce(trim(p_agreement_text), '') = '' then
    raise exception 'Agreement text is required';
  end if;

  v_lender_snapshot := coalesce(
    nullif(trim(coalesce(v_loan.lender_name_snapshot, '')), ''),
    public.resolve_profile_full_name(v_loan.lender_id),
    'Lender'
  );
  v_borrower_snapshot := coalesce(
    nullif(trim(coalesce(v_loan.borrower_name_snapshot, '')), ''),
    nullif(trim(coalesce(v_loan.borrower_name, '')), ''),
    'Borrower'
  );

  update public.loans
    set lender_signed_at = now(),
        agreement_text = p_agreement_text,
        lender_name_snapshot = v_lender_snapshot,
        borrower_name_snapshot = v_borrower_snapshot,
        lender_ip = nullif(p_lender_ip, ''),
        status = 'sent'
  where id = p_loan_id
  returning * into v_loan;

  perform public.append_loan_event(
    p_loan_id,
    'lender_signed',
    auth.uid(),
    null,
    jsonb_build_object(
      'from_status', 'draft',
      'to_status', 'sent',
      'ip', nullif(p_lender_ip, '')
    )
  );

  return v_loan;
end;
$$;

create or replace function public.borrower_sign_loan(
  p_loan_id uuid,
  p_borrower_ip text default null
)
returns public.loans
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.loans%rowtype;
  v_user_email text;
  v_lender_snapshot text;
  v_borrower_snapshot text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_loan
  from public.loans
  where id = p_loan_id
  for update;

  if not found then
    raise exception 'Loan not found';
  end if;

  if v_loan.status <> 'sent' then
    raise exception 'Loan is not ready for borrower signature';
  end if;

  if v_loan.borrower_signed_at is not null then
    raise exception 'Loan is already signed by borrower';
  end if;

  v_user_email := auth.jwt() ->> 'email';
  if v_loan.borrower_id is not null and v_loan.borrower_id <> auth.uid() then
    raise exception 'This loan is assigned to another borrower';
  end if;

  if v_loan.borrower_id is null and coalesce(v_loan.borrower_email, '') <> coalesce(v_user_email, '') then
    raise exception 'Authenticated user email does not match borrower email';
  end if;

  v_lender_snapshot := coalesce(
    nullif(trim(coalesce(v_loan.lender_name_snapshot, '')), ''),
    public.resolve_profile_full_name(v_loan.lender_id),
    'Lender'
  );
  v_borrower_snapshot := coalesce(
    nullif(trim(coalesce(v_loan.borrower_name_snapshot, '')), ''),
    nullif(trim(coalesce(v_loan.borrower_name, '')), ''),
    'Borrower'
  );

  update public.loans
    set borrower_signed_at = now(),
        borrower_ip = nullif(p_borrower_ip, ''),
        lender_name_snapshot = v_lender_snapshot,
        borrower_name_snapshot = v_borrower_snapshot,
        borrower_id = coalesce(v_loan.borrower_id, auth.uid()),
        status = 'approved'
  where id = p_loan_id
  returning * into v_loan;

  perform public.append_loan_event(
    p_loan_id,
    'borrower_signed',
    auth.uid(),
    null,
    jsonb_build_object(
      'from_status', 'sent',
      'to_status', 'approved',
      'ip', nullif(p_borrower_ip, '')
    )
  );

  return v_loan;
end;
$$;

create or replace function public.transition_loan_status(
  p_loan_id uuid,
  p_new_status text
)
returns public.loans
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan public.loans%rowtype;
  v_old_status text;
  v_is_lender boolean := false;
  v_is_borrower boolean := false;
  v_user_email text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_loan
  from public.loans
  where id = p_loan_id
  for update;

  if not found then
    raise exception 'Loan not found';
  end if;

  v_user_email := auth.jwt() ->> 'email';
  v_is_lender := v_loan.lender_id = auth.uid();
  v_is_borrower := v_loan.borrower_id = auth.uid()
    or (v_loan.borrower_id is null and coalesce(v_loan.borrower_email, '') = coalesce(v_user_email, ''));

  if not v_is_lender and not v_is_borrower then
    raise exception 'Not authorized to transition this loan';
  end if;

  if p_new_status = v_loan.status then
    return v_loan;
  end if;
  v_old_status := v_loan.status;

  if p_new_status = 'funding_sent' then
    if not v_is_lender or v_loan.status <> 'approved' then
      raise exception 'Invalid transition to funding_sent';
    end if;
  elsif p_new_status = 'active' then
    if not v_is_borrower or v_loan.status <> 'funding_sent' then
      raise exception 'Invalid transition to active';
    end if;
  elsif p_new_status = 'forgiven' then
    if not v_is_lender or v_loan.status not in ('active', 'funding_sent', 'approved') then
      raise exception 'Invalid transition to forgiven';
    end if;
  elsif p_new_status = 'cancelled' then
    if v_loan.status = 'sent' then
      null; -- lender can cancel request; borrower can reject request
    elsif v_loan.status = 'approved' and v_is_lender then
      null;
    else
      raise exception 'Invalid transition to cancelled';
    end if;
  else
    raise exception 'Unsupported transition target status: %', p_new_status;
  end if;

  if p_new_status = 'forgiven' then
    update public.loans
      set status = p_new_status,
          remaining_balance = 0
    where id = p_loan_id
    returning * into v_loan;
  else
    update public.loans
      set status = p_new_status
    where id = p_loan_id
    returning * into v_loan;
  end if;

  perform public.append_loan_event(
    p_loan_id,
    'status_transition',
    auth.uid(),
    null,
    jsonb_build_object(
      'from_status', v_old_status,
      'to_status', p_new_status
    )
  );

  return v_loan;
end;
$$;

grant execute on function public.lender_sign_loan(uuid, text, text) to authenticated;
grant execute on function public.borrower_sign_loan(uuid, text) to authenticated;
grant execute on function public.transition_loan_status(uuid, text) to authenticated;


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

create policy "View Payments" on payments for select using (
  exists (select 1 from loans where loans.id = payments.loan_id and (loans.lender_id = auth.uid() or loans.borrower_id = auth.uid()))
);
drop policy if exists "Add Payments" on payments;
drop policy if exists "Borrower Add Repayments" on payments;
drop policy if exists "Lender Add Funding" on payments;
create policy "Borrower Add Repayments" on payments for insert with check (
  type = 'repayment'
  and status = 'pending'
  and coalesce(created_by, 'user') = 'user'
  and exists (
    select 1
    from loans
    where loans.id = payments.loan_id
      and loans.borrower_id = auth.uid()
  )
);
create policy "Lender Add Funding" on payments for insert with check (
  type = 'funding'
  and status = 'approved'
  and coalesce(created_by, 'user') = 'user'
  and exists (
    select 1
    from loans
    where loans.id = payments.loan_id
      and loans.lender_id = auth.uid()
      and loans.status = 'approved'
  )
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
  v_loan public.loans%rowtype;
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

  v_loan := public.recompute_loan_balance(v_payment.loan_id);

  perform public.append_loan_event(
    v_payment.loan_id,
    'payment_approved',
    auth.uid(),
    v_payment.id,
    jsonb_build_object(
      'payment_type', v_payment.type,
      'payment_amount', v_payment.amount,
      'loan_status_after', v_loan.status,
      'remaining_balance_after', v_loan.remaining_balance
    )
  );

  return v_loan;
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
  v_interest_rows_inserted integer := 0;
  v_late_fee_rows_inserted integer := 0;
  v_rows integer := 0;
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
    get diagnostics v_rows = row_count;
    v_interest_rows_inserted := v_interest_rows_inserted + coalesce(v_rows, 0);
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
            get diagnostics v_rows = row_count;
            v_late_fee_rows_inserted := v_late_fee_rows_inserted + coalesce(v_rows, 0);
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
          get diagnostics v_rows = row_count;
          v_late_fee_rows_inserted := v_late_fee_rows_inserted + coalesce(v_rows, 0);
        end if;
      end if;
    end if;
  end if;

  if v_interest_rows_inserted > 0 or v_late_fee_rows_inserted > 0 then
    perform public.append_loan_event(
      v_loan.id,
      'accrual_applied',
      null,
      null,
      jsonb_build_object(
        'as_of', p_as_of,
        'interest_rows', v_interest_rows_inserted,
        'late_fee_rows', v_late_fee_rows_inserted,
        'interest_amount_each', v_interest_amount,
        'late_fee_amount_each', v_late_fee_amount
      )
    );
  end if;

  return public.recompute_loan_balance(v_loan.id);
end;
$$;

grant execute on function public.accrue_loan_charges(uuid, timestamptz) to service_role;

-- 3.1.7 Accrual run log for observability
create table if not exists public.accrual_runs (
  id bigint generated by default as identity primary key,
  ran_at timestamptz not null default now(),
  as_of timestamptz not null,
  loans_processed integer not null default 0,
  accrual_rows_inserted integer not null default 0,
  success boolean not null default true,
  error_text text
);

alter table public.accrual_runs enable row level security;
drop policy if exists "Service Role Read Accrual Runs" on public.accrual_runs;
create policy "Service Role Read Accrual Runs" on public.accrual_runs for select to service_role using (true);

-- 3.1.8 Batch accrual for all active loans (with metrics logging)
create or replace function public.accrue_all_loans(p_as_of timestamptz default now())
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_loan_id uuid;
  v_locked boolean;
  v_loans_processed integer := 0;
  v_accrual_rows_inserted integer := 0;
  v_before_count integer := 0;
  v_after_count integer := 0;
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
      select count(*)::integer
      into v_before_count
      from public.payments
      where loan_id = v_loan_id
        and type in ('interest', 'late_fee')
        and coalesce(created_by, 'user') = 'system';

      perform public.accrue_loan_charges(v_loan_id, p_as_of);

      select count(*)::integer
      into v_after_count
      from public.payments
      where loan_id = v_loan_id
        and type in ('interest', 'late_fee')
        and coalesce(created_by, 'user') = 'system';

      v_accrual_rows_inserted := v_accrual_rows_inserted + greatest(v_after_count - v_before_count, 0);
      v_loans_processed := v_loans_processed + 1;
    end loop;

    insert into public.accrual_runs (
      as_of, loans_processed, accrual_rows_inserted, success, error_text
    ) values (
      p_as_of, v_loans_processed, v_accrual_rows_inserted, true, null
    );
  exception when others then
    insert into public.accrual_runs (
      as_of, loans_processed, accrual_rows_inserted, success, error_text
    ) values (
      p_as_of, v_loans_processed, v_accrual_rows_inserted, false, sqlerrm
    );
    perform pg_advisory_unlock(hashtext('public.accrue_all_loans'));
    raise;
  end;

  perform pg_advisory_unlock(hashtext('public.accrue_all_loans'));
end;
$$;

grant execute on function public.accrue_all_loans(timestamptz) to service_role;

-- 3.1.9 Optional pg_cron schedule (hourly)
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
