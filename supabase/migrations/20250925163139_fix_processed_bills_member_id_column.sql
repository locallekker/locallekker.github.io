-- Fix processed_bills table column name from user_id to member_id for consistency
-- with the updated terminology (user -> member)

BEGIN;

-- Rename the column from user_id to member_id (already done)
-- ALTER TABLE public.processed_bills RENAME COLUMN user_id TO member_id;

-- Update the index name to reflect the new column name
DROP INDEX IF EXISTS idx_processed_bills_user_id;
CREATE INDEX IF NOT EXISTS idx_processed_bills_member_id ON processed_bills(member_id);

-- Update RLS policies to use member_id instead of user_id
DROP POLICY IF EXISTS "Users can view their own processed bills" ON public.processed_bills;
DROP POLICY IF EXISTS "Users can insert their own processed bills" ON public.processed_bills;
DROP POLICY IF EXISTS "Users can update their own processed bills" ON public.processed_bills;

CREATE POLICY "Members can view their own processed bills" ON public.processed_bills
    FOR SELECT USING (auth.uid() = member_id);

CREATE POLICY "Members can insert their own processed bills" ON public.processed_bills
    FOR INSERT WITH CHECK (auth.uid() = member_id);

CREATE POLICY "Members can update their own processed bills" ON public.processed_bills
    FOR UPDATE USING (auth.uid() = member_id);

-- Update the function to use member_id
CREATE OR REPLACE FUNCTION get_user_bill_statistics(user_uuid UUID)
RETURNS TABLE (
    total_bills BIGINT,
    total_saved DECIMAL(10,2),
    total_spent DECIMAL(10,2),
    most_used_partner TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*) as total_bills,
        COALESCE(SUM(discount_amount), 0) as total_saved,
        COALESCE(SUM(original_total), 0) as total_spent,
        (
            SELECT partner_id
            FROM processed_bills pb2
            WHERE pb2.member_id = user_uuid
            GROUP BY partner_id
            ORDER BY COUNT(*) DESC
            LIMIT 1
        ) as most_used_partner
    FROM processed_bills pb
    WHERE pb.member_id = user_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

COMMIT;