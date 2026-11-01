-- Add new deal types support: buy-get and percent-off with manual price
-- Adds new metadata columns on trusted_partner_discounts and audit fields on deal_authorizations

-- Trusted partner discounts: deal_type, custom_data, requires_manual_price
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'trusted_partner_discounts'
          AND column_name = 'deal_type'
    ) THEN
        ALTER TABLE public.trusted_partner_discounts
        ADD COLUMN deal_type TEXT DEFAULT 'standard';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'trusted_partner_discounts'
          AND column_name = 'custom_data'
    ) THEN
        ALTER TABLE public.trusted_partner_discounts
        ADD COLUMN custom_data JSONB;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'trusted_partner_discounts'
          AND column_name = 'requires_manual_price'
    ) THEN
        ALTER TABLE public.trusted_partner_discounts
        ADD COLUMN requires_manual_price BOOLEAN DEFAULT FALSE;
    END IF;
END $$;

-- Deal authorizations: capture member-entered price and discount snapshot
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'deal_authorizations'
          AND column_name = 'member_entered_price'
    ) THEN
        ALTER TABLE public.deal_authorizations
        ADD COLUMN member_entered_price DECIMAL(10,2);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'deal_authorizations'
          AND column_name = 'applied_discount_amount'
    ) THEN
        ALTER TABLE public.deal_authorizations
        ADD COLUMN applied_discount_amount DECIMAL(10,2);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'deal_authorizations'
          AND column_name = 'deal_type'
    ) THEN
        ALTER TABLE public.deal_authorizations
        ADD COLUMN deal_type TEXT;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'deal_authorizations'
          AND column_name = 'deal_snapshot'
    ) THEN
        ALTER TABLE public.deal_authorizations
        ADD COLUMN deal_snapshot JSONB;
    END IF;
END $$;
