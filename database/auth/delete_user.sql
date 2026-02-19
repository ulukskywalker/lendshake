-- ==========================================
-- Secure User Deletion RPC
-- ==========================================
-- Allows a user to delete their own account, strictly conditional on having no legal records.

create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then 
    raise exception 'Not authenticated'; 
  end if;

  -- 1. Cleanup: Delete safe-to-remove loans (Drafts and Cancelled) where user is the creator (Lender)
  --    Access control: User is lender.
  delete from public.loans 
  where lender_id = v_uid 
    and status in ('draft', 'cancelled');

  -- 2. Validation: Check for ANY remaining legal records
  --    If the user is a Lender OR Borrower on any loan that is NOT draft/cancelled,
  --    we cannot delete them because it would break the foreign key integrity of the legal contract.
  if exists (
    select 1 from public.loans
    where lender_id = v_uid or borrower_id = v_uid
  ) then
    raise exception 'Cannot delete account: You have active or past loan records. Please contact support to resolve these legal documents.';
  end if;

  -- 3. Execution: Delete the user from auth.users
  --    This will cascade delete public.profiles via foreign key (if configured) 
  --    or leave it orphaned (if not). Since we verified no loans exist, this is safe.
  --    Note: This requires the function to run with appropriate privileges (security definer).
  delete from auth.users where id = v_uid;
end;
$$;

-- Grant access to authenticated users
grant execute on function public.delete_own_account() to authenticated;
