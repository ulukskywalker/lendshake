
-- Migration: 01_add_pandadoc_fields.sql
-- Add transient fields to track PandaDoc integration status

alter table public.loans 
add column if not exists t_pandadoc_id text;

alter table public.loans 
add column if not exists t_pandadoc_status text;

-- Add index for webhook lookups if needed
create index if not exists loans_pandadoc_id_idx on public.loans (t_pandadoc_id);
