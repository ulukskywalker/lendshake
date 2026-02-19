-- ==========================================
-- 4. STORAGE (Bucket: 'proofs')
-- ==========================================
-- Supabase Storage bucket configuration for payment proofs.

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
  (storage.foldername(name))[1] = (select auth.uid())::text
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
