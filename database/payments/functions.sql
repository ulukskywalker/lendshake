-- 3.1.4 Centralized Loan Balance Recompute
-- Calculates the outstanding balance by summing principal, interest, late fees, and subtracting repayments.
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

  -- Sum all approved repayments
  select coalesce(sum(amount::numeric), 0)
    into v_repayments
  from public.payments
  where loan_id = v_loan.id
    and status = 'approved'
    and type = 'repayment';

  -- Sum all charges (principal is handled separately in calc) + interest + late fees
  select coalesce(sum(amount::numeric), 0)
    into v_charges
  from public.payments
  where loan_id = v_loan.id
    and status = 'approved'
    and type in ('interest', 'late_fee');

  v_new_balance := greatest(0, coalesce(v_loan.principal_amount, 0) + v_charges - v_repayments);

  -- Auto-close loan if balance hits 0
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

-- 3.1.5 Payment approval RPC
-- Atomically marks a payment as approved, re-computes balance, and logs the event.
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

-- RPC: Reject a payment
create or replace function public.reject_payment_with_reason(
  p_payment_id uuid,
  p_reason text
)
returns public.payments
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments%rowtype;
begin
  if nullif(trim(coalesce(p_reason, '')), '') is null then
    raise exception 'Rejection reason is required';
  end if;

  select * into v_payment
  from public.payments
  where id = p_payment_id
  for update;

  if not found then
    raise exception 'Payment not found';
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
    raise exception 'Not authorized to reject this payment';
  end if;

  update public.payments
    set status = 'rejected',
        rejection_reason = nullif(trim(coalesce(p_reason, '')), '')
  where id = p_payment_id
  returning * into v_payment;

  perform public.append_loan_event(
    v_payment.loan_id,
    'payment_rejected',
    auth.uid(),
    v_payment.id,
    jsonb_build_object(
      'payment_type', v_payment.type,
      'payment_amount', v_payment.amount,
      'reason', v_payment.rejection_reason
    )
  );

  return v_payment;
end;
$$;

-- 3.1.6 Interest + late fee accrual for one loan (idempotent)
-- Checks if interest or late fees are due "as of" a given date and inserts system payments.
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
        coalesce(v_loan.first_payment_date, v_loan.created_at + interval '1 month'),
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
            coalesce(v_loan.first_payment_date, v_loan.created_at + v_cycle_interval),
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
-- Designed to be run by pg_cron on a schedule.
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

create index if not exists accrual_runs_ran_at_idx on public.accrual_runs (ran_at desc);
create index if not exists accrual_runs_success_ran_at_idx on public.accrual_runs (success, ran_at desc);

-- 3.1.9 Scheduler management helpers (pg_cron)
create or replace function public.ensure_accrual_schedule(p_cron text default '5 * * * *')
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing_job_id bigint;
  v_new_job_id bigint;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise exception 'pg_cron extension is not enabled';
  end if;

  select jobid
  into v_existing_job_id
  from cron.job
  where jobname = 'accrue-loan-charges-hourly'
  limit 1;

  if v_existing_job_id is not null then
    perform cron.unschedule(v_existing_job_id);
  end if;

  select cron.schedule(
    'accrue-loan-charges-hourly',
    p_cron,
    $cron$select public.accrue_all_loans(now());$cron$
  )
  into v_new_job_id;

  return v_new_job_id;
end;
$$;

create or replace function public.disable_accrual_schedule()
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job_id bigint;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    return false;
  end if;

  select jobid
  into v_job_id
  from cron.job
  where jobname = 'accrue-loan-charges-hourly'
  limit 1;

  if v_job_id is null then
    return false;
  end if;

  perform cron.unschedule(v_job_id);
  return true;
end;
$$;

create or replace function public.get_accrual_health()
returns table (
  last_run_at timestamptz,
  last_run_success boolean,
  failed_runs_last_24h integer,
  failed_runs_total integer
)
language sql
security definer
set search_path = public
as $$
  with latest as (
    select ran_at, success
    from public.accrual_runs
    order by ran_at desc
    limit 1
  ),
  stats as (
    select
      count(*) filter (where success = false and ran_at >= now() - interval '24 hours')::integer as failed_24h,
      count(*) filter (where success = false)::integer as failed_total
    from public.accrual_runs
  )
  select
    latest.ran_at,
    latest.success,
    stats.failed_24h,
    stats.failed_total
  from stats
  left join latest on true;
$$;

grant execute on function public.approve_payment_and_recompute_balance(uuid) to authenticated;
grant execute on function public.recompute_loan_balance(uuid) to service_role;
grant execute on function public.reject_payment_with_reason(uuid, text) to authenticated;
grant execute on function public.accrue_loan_charges(uuid, timestamptz) to service_role;
grant execute on function public.accrue_all_loans(timestamptz) to service_role;
grant execute on function public.ensure_accrual_schedule(text) to service_role;
grant execute on function public.disable_accrual_schedule() to service_role;
grant execute on function public.get_accrual_health() to service_role;
