-- Update existing trusted partner bank accounts to set correct subaccount_active status
-- Run this after adding the subaccount columns

-- Set subaccount_active to false for all records without a subaccount_code
-- Partners will need to re-save their banking details to create subaccounts
UPDATE trusted_partner_bank_accounts 
SET subaccount_active = false
WHERE subaccount_code IS NULL;

-- Verify the update
SELECT 
    user_id,
    account_holder_name,
    bank_name,
    paystack_recipient_code IS NOT NULL as has_recipient_code,
    subaccount_code IS NOT NULL as has_subaccount,
    percentage_charge,
    subaccount_active,
    CASE 
        WHEN subaccount_code IS NOT NULL THEN '✅ Subaccount ready'
        WHEN paystack_recipient_code IS NOT NULL THEN '⚠️ Need to re-save to create subaccount'
        ELSE '❌ No banking details'
    END as status
FROM trusted_partner_bank_accounts
ORDER BY created_at DESC;
