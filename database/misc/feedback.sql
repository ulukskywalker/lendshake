-- ==========================================
-- 5. APP FEEDBACK
-- ==========================================
-- Simple table to collect user feedback and bug reports.
-- Linked to the user for follow-up.
create table if not exists public.app_feedback (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  user_id uuid not null references auth.users(id) on delete cascade,
  feedback_type text not null check (feedback_type in ('general', 'bug', 'feature')),
  rating integer check (rating is null or (rating >= 1 and rating <= 5)),
  message text not null check (char_length(trim(message)) > 0),
  app_version text,
  os_version text
);

create index if not exists app_feedback_created_at_idx
  on public.app_feedback (created_at desc);
create index if not exists app_feedback_user_id_idx
  on public.app_feedback (user_id, created_at desc);
create index if not exists app_feedback_type_idx
  on public.app_feedback (feedback_type, created_at desc);

alter table public.app_feedback enable row level security;

-- Policies
-- Participants can view the full history of their loan.
drop policy if exists "Insert Own Feedback" on public.app_feedback;
create policy "Insert Own Feedback" on public.app_feedback
for insert
to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Select Own Feedback" on public.app_feedback;
create policy "Select Own Feedback" on public.app_feedback
for select
to authenticated
using ((select auth.uid()) = user_id);
