-- ==========================================
-- 2.2 LOAN EVENT LOG
-- ==========================================
-- Immutable audit trail for all significant actions on a loan.
-- This serves as the legal ledger of what happened when.
create table if not exists public.loan_events (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  loan_id uuid not null references public.loans(id) on delete cascade,
  event_type text not null, -- e.g., 'created', 'sent', 'signed', 'payment_made'
  actor_user_id uuid references auth.users(id), -- Who performed the action (nullable for system events)
  payment_id uuid, -- Optional reference if the event relates to a payment
  metadata jsonb not null default '{}'::jsonb -- Additional context (e.g., ip address, reasons)
);

create index if not exists loan_events_loan_created_idx
  on public.loan_events (loan_id, created_at desc);
create index if not exists loan_events_type_created_idx
  on public.loan_events (event_type, created_at desc);

alter table public.loan_events enable row level security;

-- Policies
-- Participants can view the full history of their loan.
drop policy if exists "View Loan Events" on public.loan_events;
create policy "View Loan Events" on public.loan_events for select using (
  exists (
    select 1
    from public.loans l
    where l.id = loan_events.loan_id
      and (
        l.lender_id = (select auth.uid())
        or l.borrower_id = (select auth.uid())
        or l.borrower_email = ((select auth.jwt()) ->> 'email')
      )
  )
);

-- Integrity Policies
-- Events are append-only. No one (not even the creator) can edit or delete an event once logged.
drop policy if exists "No Direct Loan Event Writes" on public.loan_events;
drop policy if exists "No Direct Loan Event Inserts" on public.loan_events;
drop policy if exists "No Direct Loan Event Updates" on public.loan_events;
drop policy if exists "No Direct Loan Event Deletes" on public.loan_events;
create policy "No Direct Loan Event Inserts" on public.loan_events
for insert
with check (false);

create policy "No Direct Loan Event Updates" on public.loan_events
for update
using (false)
with check (false);

create policy "No Direct Loan Event Deletes" on public.loan_events
for delete
using (false);

-- Helper Function to safely append events (used by other functions)
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
