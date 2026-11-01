-- =============================================================================
-- INSERT SUBSCRIPTION FOR USER WHO ALREADY PAID
-- This creates a subscription record for Clyde (clydemflan@gmail.com)
-- =============================================================================

-- First, check if subscription already exists
DO $$
BEGIN
    -- Only insert if no subscription exists for this user
    IF NOT EXISTS (
        SELECT 1 FROM public.subscriptions 
        WHERE user_id = '80eff2dc-6297-4d50-a22b-6213213f659f'
    ) THEN
        -- Insert subscription with 30-day active period
        INSERT INTO public.subscriptions (
            user_id,
            plan_type,
            status,
            auto_renew,
            current_period_start,
            current_period_end,
            next_payment_date,
            created_at,
            updated_at
        ) VALUES (
            '80eff2dc-6297-4d50-a22b-6213213f659f',  -- Your user ID
            'monthly',                                -- Plan type
            'active',                                 -- Status
            true,                                     -- Auto-renew enabled
            NOW(),                                    -- Period starts now
            NOW() + INTERVAL '1 month',              -- Period ends same day next month (handles 30/31/leap year)
            NOW() + INTERVAL '1 month',              -- Next payment same day next month
            NOW(),
            NOW()
        );
        RAISE NOTICE 'Subscription created successfully!';
    ELSE
        RAISE NOTICE 'Subscription already exists for this user.';
    END IF;
END $$;

-- Verify the subscription was created
SELECT 
    'Subscription created successfully!' as message,
    id,
    user_id,
    plan_type,
    status,
    current_period_start,
    current_period_end,
    next_payment_date,
    created_at
FROM public.subscriptions
WHERE user_id = '80eff2dc-6297-4d50-a22b-6213213f659f'
ORDER BY created_at DESC
LIMIT 1;
