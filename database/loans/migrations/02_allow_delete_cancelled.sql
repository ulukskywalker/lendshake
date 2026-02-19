-- Migration to allow deletion of cancelled loans
DO $$
BEGIN
    -- Drop the restrictive 'Delete Drafts' policy
    DROP POLICY IF EXISTS "Delete Drafts" ON public.loans;

    -- Create a new policy that allows deleting both 'draft' and 'cancelled' loans
    CREATE POLICY "Delete Drafts and Cancelled" ON public.loans
    FOR DELETE
    USING (
        (auth.uid() = lender_id) AND (status IN ('draft', 'cancelled'))
    );
END $$;
