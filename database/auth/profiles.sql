-- ==========================================
-- 1. PROFILES
-- ==========================================
-- This table stores additional user information that is not handled by Supabase Auth (e.g., physical address, phone).
-- It is linked 1:1 with the auth.users table.
create table if not exists public.profiles (
  id uuid references auth.users not null primary key, -- References the built-in Supabase User ID
  first_name text,
  last_name text,
  address_line_1 text,
  address_line_2 text,
  phone_number text,
  residence_state text, -- Critical for determing Usury laws
  country text,
  postal_code text,
  updated_at timestamptz
);

-- Deprecated columns cleanup (if any)
alter table public.profiles drop column if exists reminder_enabled;
alter table public.profiles drop column if exists next_reminder_at;

-- Ensure necessary columns exist for identity verification
alter table public.profiles add column if not exists address_line_1 text;
alter table public.profiles add column if not exists address_line_2 text;
alter table public.profiles add column if not exists country text;
alter table public.profiles add column if not exists postal_code text;

-- Migration: Migrate data from old 'street_address' column to 'address_line_1' if it exists.
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
    and table_name = 'profiles'
    and column_name = 'street_address'
  ) then
    execute 'update public.profiles set address_line_1 = coalesce(address_line_1, street_address) where nullif(trim(coalesce(address_line_1, '''')), '''') is null and nullif(trim(coalesce(street_address, '''')), '''') is not null';
  end if;
end;
$$;

-- RLS (Row Level Security) Policies
alter table public.profiles enable row level security;

-- Clean up any old policies
drop policy if exists "Public Profiles" on profiles;
drop policy if exists "View Own Profile" on profiles;
drop policy if exists "View Participant Profiles" on profiles;
drop policy if exists "Manage Own Profile" on profiles;
drop policy if exists "Manage Own Profile Insert" on profiles;
drop policy if exists "Manage Own Profile Update" on profiles;
drop policy if exists "Manage Own Profile Delete" on profiles;
drop policy if exists "Insert Own Profile" on profiles;
drop policy if exists "Update Own Profile" on profiles;
drop policy if exists "Delete Own Profile" on profiles;

-- Users can read their OWN full profile.
create policy "View Own Profile" on profiles for select
using ((select auth.uid()) = id);

-- Users can view profiles of people they share a loan with (lender/borrower relationship).
create policy "View Participant Profiles" on profiles for select
using (
  exists (
    select 1 from public.loans l
    where (l.lender_id = (select auth.uid()) and l.borrower_id = profiles.id)
       or (l.borrower_id = (select auth.uid()) and l.lender_id = profiles.id)
  )
);

-- Users can only insert/update/delete their OWN profile.
create policy "Insert Own Profile" on profiles for insert
with check ((select auth.uid()) = id);

create policy "Update Own Profile" on profiles for update
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create policy "Delete Own Profile" on profiles for delete
using ((select auth.uid()) = id);

-- Restricted view for name-only lookups (used by resolve_profile_full_name and UI name resolution).
-- This bypasses RLS via security definer functions, so no public policy is needed.
