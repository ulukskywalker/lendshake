-- ==========================================
-- 6. SCHEMA MIGRATIONS
-- ==========================================
-- This file tracks specific schema changes that need to be applied sequentially.
-- Future migrations should be appended here.

-- 6.1 Add first_payment_date to loans (Example Migration)
alter table public.loans 
add column if not exists first_payment_date timestamptz;
