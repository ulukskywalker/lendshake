 -- Helper function to get a full name string from a user profile
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

-- Trigger Function: Automatically snapshot lender/borrower names when a loan is first created.
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

  return new;
end;
$$;

-- Attach Trigger to Loans table
drop trigger if exists trg_set_loan_name_snapshots_on_insert on public.loans;
create trigger trg_set_loan_name_snapshots_on_insert
before insert on public.loans
for each row execute function public.set_loan_name_snapshots_on_insert();

-- Migration Logic: Backfill any missing snapshots for existing loans
update public.loans l
set
  lender_name_snapshot = coalesce(
    nullif(trim(coalesce(l.lender_name_snapshot, '')), ''),
    public.resolve_profile_full_name(l.lender_id),
    'Lender'
  ),
  borrower_name_snapshot = case
    when l.borrower_signed_at is null then nullif(trim(coalesce(l.borrower_name_snapshot, '')), '')
    else coalesce(
      nullif(trim(coalesce(l.borrower_name_snapshot, '')), ''),
      public.resolve_profile_full_name(l.borrower_id),
      nullif(trim(coalesce(l.borrower_name, '')), ''),
      'Borrower'
    )
  end
where nullif(trim(coalesce(l.lender_name_snapshot, '')), '') is null
   or (
     l.borrower_signed_at is not null
     and nullif(trim(coalesce(l.borrower_name_snapshot, '')), '') is null
   );

-- Trigger Function: Ensure that critical signature fields CANNOT be changed once set.
-- This protects the legal integrity of the loan agreement.
create or replace function public.enforce_loan_signed_field_immutability()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op <> 'update' then
    return new;
  end if;

  if old.lender_signed_at is not null and new.lender_signed_at is distinct from old.lender_signed_at then
    raise exception 'lender_signed_at is immutable once set';
  end if;

  if old.borrower_signed_at is not null and new.borrower_signed_at is distinct from old.borrower_signed_at then
    raise exception 'borrower_signed_at is immutable once set';
  end if;

  if nullif(trim(coalesce(old.lender_name_snapshot, '')), '') is not null
     and new.lender_name_snapshot is distinct from old.lender_name_snapshot then
    raise exception 'lender_name_snapshot is immutable once set';
  end if;

  if old.borrower_signed_at is not null
     and new.borrower_name_snapshot is distinct from old.borrower_name_snapshot then
    raise exception 'borrower_name_snapshot is immutable once set';
  end if;

  if nullif(trim(coalesce(old.agreement_text, '')), '') is not null
     and new.agreement_text is distinct from old.agreement_text then
    raise exception 'agreement_text is immutable once set';
  end if;

  return new;
end;
$$;

-- Attach Immutability Trigger
drop trigger if exists trg_enforce_loan_signed_field_immutability on public.loans;
create trigger trg_enforce_loan_signed_field_immutability
before update on public.loans
for each row execute function public.enforce_loan_signed_field_immutability();

-- Performance Indexes
create index if not exists loans_status_idx on public.loans (status);
create index if not exists loans_lender_status_idx on public.loans (lender_id, status);
create index if not exists loans_borrower_status_idx on public.loans (borrower_id, status);

-- ==========================================
-- RPCs (Remote Procedure Calls)
-- These functions encapsulate complex business logic and state transitions
-- ==========================================

-- RPC: Lender signs the draft loan
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
  update public.loans
    set lender_signed_at = now(),
        agreement_text = p_agreement_text,
        lender_name_snapshot = v_lender_snapshot,
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

-- RPC: Borrower signs the loan
create or replace function public.borrower_sign_loan(
  p_loan_id uuid,
  p_borrower_ip text default null
)
returns public.loans
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.borrower_sign_loan_with_identity(
    p_loan_id,
    p_borrower_ip,
    null,
    null,
    null,
    null,
    null,
    null,
    null
  );
end;
$$;

-- RPC: Borrower signs loan with identity details updates
create or replace function public.borrower_sign_loan_with_identity(
  p_loan_id uuid,
  p_borrower_ip text default null,
  p_borrower_first_name text default null,
  p_borrower_last_name text default null,
  p_borrower_address_line_1 text default null,
  p_borrower_address_line_2 text default null,
  p_borrower_state text default null,
  p_borrower_country text default null,
  p_borrower_postal_code text default null,
  p_borrower_phone text default null
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
  v_borrower_profile_name text;
  v_borrower_snapshot text;
  v_borrower_address_line_1 text;
  v_borrower_address_line_2 text;
  v_borrower_state text;
  v_borrower_country text;
  v_borrower_postal_code text;
  v_borrower_phone text;
  v_input_first_name text;
  v_input_last_name text;
  v_input_address_line_1 text;
  v_input_address_line_2 text;
  v_input_state text;
  v_input_country text;
  v_input_postal_code text;
  v_input_phone text;
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

  -- Validate Identity Inputs
  v_input_first_name := nullif(trim(coalesce(p_borrower_first_name, '')), '');
  v_input_last_name := nullif(trim(coalesce(p_borrower_last_name, '')), '');
  v_input_address_line_1 := nullif(trim(coalesce(p_borrower_address_line_1, '')), '');
  v_input_address_line_2 := nullif(trim(coalesce(p_borrower_address_line_2, '')), '');
  v_input_state := nullif(trim(coalesce(p_borrower_state, '')), '');
  v_input_country := nullif(trim(coalesce(p_borrower_country, '')), '');
  v_input_postal_code := nullif(trim(coalesce(p_borrower_postal_code, '')), '');
  v_input_phone := nullif(trim(coalesce(p_borrower_phone, '')), '');

  select
    nullif(
      trim(
        concat_ws(
          ' ',
          nullif(trim(coalesce(first_name, '')), ''),
          nullif(trim(coalesce(last_name, '')), '')
        )
      ),
      ''
    ),
    nullif(trim(coalesce(address_line_1, '')), ''),
    nullif(trim(coalesce(address_line_2, '')), ''),
    nullif(trim(coalesce(residence_state, '')), ''),
    nullif(trim(coalesce(country, '')), ''),
    nullif(trim(coalesce(postal_code, '')), ''),
    nullif(trim(coalesce(phone_number, '')), '')
  into
    v_borrower_profile_name,
    v_borrower_address_line_1,
    v_borrower_address_line_2,
    v_borrower_state,
    v_borrower_country,
    v_borrower_postal_code,
    v_borrower_phone
  from public.profiles
  where id = auth.uid();

  if v_input_first_name is not null and v_input_last_name is not null then
    v_borrower_profile_name := concat_ws(' ', v_input_first_name, v_input_last_name);
  end if;
  if v_input_address_line_1 is not null then
    v_borrower_address_line_1 := v_input_address_line_1;
  end if;
  if v_input_address_line_2 is not null then
    v_borrower_address_line_2 := v_input_address_line_2;
  end if;
  if v_input_state is not null then
    v_borrower_state := upper(v_input_state);
  end if;
  if v_input_country is not null then
    v_borrower_country := v_input_country;
  end if;
  if v_input_postal_code is not null then
    v_borrower_postal_code := v_input_postal_code;
  end if;
  if v_input_phone is not null then
    v_borrower_phone := v_input_phone;
  end if;

  if v_borrower_profile_name is null
     or v_borrower_address_line_1 is null
     or v_borrower_state is null
     or v_borrower_country is null
     or v_borrower_postal_code is null
     or v_borrower_phone is null then
    raise exception 'Borrower identity details are required before signing';
  end if;

  v_lender_snapshot := coalesce(
    nullif(trim(coalesce(v_loan.lender_name_snapshot, '')), ''),
    public.resolve_profile_full_name(v_loan.lender_id),
    'Lender'
  );
  v_borrower_snapshot := v_borrower_profile_name;

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

-- RPC: Generic Status Transition (e.g., funding sent, active, forgiven, cancelled)
create or replace function public.transition_loan_status(
  p_loan_id uuid,
  p_new_status text,
  p_reason text default null
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
    if nullif(trim(coalesce(p_reason, '')), '') is null then
      raise exception 'Rejection reason is required';
    end if;
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
  elsif p_new_status = 'cancelled' then
    update public.loans
      set status = p_new_status,
          agreement_rejection_reason = nullif(trim(coalesce(p_reason, '')), '')
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
      'to_status', p_new_status,
      'reason', nullif(trim(coalesce(p_reason, '')), '')
    )
  );

  return v_loan;
end;
$$;

grant execute on function public.lender_sign_loan(uuid, text, text) to authenticated;
grant execute on function public.borrower_sign_loan(uuid, text) to authenticated;
grant execute on function public.borrower_sign_loan_with_identity(uuid, text, text, text, text, text, text, text, text) to authenticated;
grant execute on function public.transition_loan_status(uuid, text, text) to authenticated;
