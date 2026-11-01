-- =============================================================================
-- REINSTATEMENT SCRIPT FOR EXISTING USER houselillian5@gmail.com
-- =============================================================================
-- User already exists in auth.users with ID: 78e67dc8-583b-4fe0-84e6-aa4d0c55a92e
-- This script recreates all profile and business records for the trusted partner
-- =============================================================================

DO $$
DECLARE
    user_uuid UUID := '78e67dc8-583b-4fe0-84e6-aa4d0c55a92e';
    business_name TEXT := 'Momsies'; -- Based on existing data
    contact_email TEXT := 'houselillian5@gmail.com';
    contact_phone TEXT := '+27-74-589-7516'; -- Replace with actual phone
    street_address TEXT := '5 Lillian lane Gonubie'; -- Replace with actual address
    city_name TEXT := 'East London'; -- Replace with actual city
    province_name TEXT := 'Eastern Cape'; -- Replace with actual province
    business_category TEXT := 'Retail';
BEGIN

    RAISE NOTICE 'Starting reinstatement for user: %', user_uuid;

    -- =============================================================================
    -- STEP 1: CREATE/UPDATE PROFILE RECORD
    -- =============================================================================
    INSERT INTO public.profiles (
        id,
        email,
        name,
        surname,
        role,
        contact,
        street,
        city,
        province,
        subscription,
        created_at,
        updated_at
    ) VALUES (
        user_uuid,
        contact_email,
        'Lillian',
        'House',
        'trusted_partner',
        contact_phone,
        street_address,
        city_name,
        province_name,
        'active',
        NOW(),
        NOW()
    ) ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        name = EXCLUDED.name,
        surname = EXCLUDED.surname,
        role = EXCLUDED.role,
        contact = EXCLUDED.contact,
        street = EXCLUDED.street,
        city = EXCLUDED.city,
        province = EXCLUDED.province,
        subscription = EXCLUDED.subscription,
        updated_at = NOW();

    RAISE NOTICE 'Profile record created/updated for user: %', user_uuid;

    -- =============================================================================
    -- STEP 2: CREATE MEMBERSHIP RECORD
    -- =============================================================================
    INSERT INTO public.memberships (
        user_id,
        role,
        gateway,
        created_at,
        updated_at
    ) VALUES (
        user_uuid,
        'trusted_partner',
        'admin_reinstatement',
        NOW(),
        NOW()
    ) ON CONFLICT (user_id) DO UPDATE SET
        role = EXCLUDED.role,
        gateway = EXCLUDED.gateway,
        updated_at = NOW();

    RAISE NOTICE 'Membership record created/updated for user: %', user_uuid;

    -- =============================================================================
    -- STEP 3: CREATE TRUSTED PARTNER RECORD
    -- =============================================================================
    INSERT INTO public.trusted_partners (
        user_id,
        business_name,
        created_at,
        updated_at
    ) VALUES (
        user_uuid,
        business_name,
        NOW(),
        NOW()
    ) ON CONFLICT (user_id) DO UPDATE SET
        business_name = EXCLUDED.business_name,
        updated_at = NOW();

    RAISE NOTICE 'Trusted partner record created/updated for user: %', user_uuid;

    -- =============================================================================
    -- STEP 4: CREATE BUSINESS RECORD
    -- =============================================================================
    INSERT INTO public.businesses (
        owner_member_id,
        name,
        category,
        address,
        contact_email,
        contact_number,
        verified,
        created_at,
        updated_at
    ) VALUES (
        user_uuid,
        business_name,
        business_category,
        CONCAT(street_address, ', ', city_name, ', ', province_name),
        contact_email,
        contact_phone,
        true, -- Pre-verify the business
        NOW(),
        NOW()
    ) ON CONFLICT (owner_member_id) DO UPDATE SET
        name = EXCLUDED.name,
        category = EXCLUDED.category,
        address = EXCLUDED.address,
        contact_email = EXCLUDED.contact_email,
        contact_number = EXCLUDED.contact_number,
        verified = EXCLUDED.verified,
        updated_at = NOW();

    RAISE NOTICE 'Business record created/updated for user: %', user_uuid;

    -- =============================================================================
    -- STEP 5: CREATE SAMPLE DISCOUNT (OPTIONAL)
    -- =============================================================================
    -- Only create if no discounts exist for this user
    IF NOT EXISTS (
        SELECT 1 FROM public.trusted_partner_discounts
        WHERE trusted_partner_id = user_uuid
    ) THEN
        INSERT INTO public.trusted_partner_discounts (
            trusted_partner_id,
            business_id,
            name,
            description,
            item_name,
            item_price,
            percentage,
            is_active,
            created_at,
            updated_at
        )
        SELECT
            user_uuid,
            b.id,
            'Welcome Discount',
            'Special discount for Local Lekker members',
            'Any Item',
            100.00,
            10.00,
            true,
            NOW(),
            NOW()
        FROM public.businesses b
        WHERE b.owner_member_id = user_uuid
        LIMIT 1;

        RAISE NOTICE 'Sample discount created for user: %', user_uuid;
    END IF;

    -- =============================================================================
    -- VERIFICATION
    -- =============================================================================
    RAISE NOTICE '=== REINSTATEMENT COMPLETE ===';
    RAISE NOTICE 'User ID: %', user_uuid;
    RAISE NOTICE 'Email: %', contact_email;
    RAISE NOTICE 'Role: trusted_partner';
    RAISE NOTICE 'Business: %', business_name;

END $$;

-- =============================================================================
-- VERIFICATION QUERIES (Run these after executing the script)
-- =============================================================================

-- Check profile
SELECT id, email, name, surname, role, subscription
FROM public.profiles
WHERE id = '78e67dc8-583b-4fe0-84e6-aa4d0c55a92e';

-- Check membership
SELECT user_id, role, gateway
FROM public.memberships
WHERE user_id = '78e67dc8-583b-4fe0-84e6-aa4d0c55a92e';

-- Check trusted partner
SELECT user_id, business_name
FROM public.trusted_partners
WHERE user_id = '78e67dc8-583b-4fe0-84e6-aa4d0c55a92e';

-- Check business
SELECT id, owner_member_id, name, category, verified
FROM public.businesses
WHERE owner_member_id = '78e67dc8-583b-4fe0-84e6-aa4d0c55a92e';

-- Check discounts
SELECT trusted_partner_id, name, percentage, is_active
FROM public.trusted_partner_discounts
WHERE trusted_partner_id = '78e67dc8-583b-4fe0-84e6-aa4d0c55a92e';