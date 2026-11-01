-- Add sequential receipt numbering system for trusted partners
-- Each business/trusted partner maintains their own receipt counter

-- Add receipt counter to businesses table
ALTER TABLE public.businesses 
ADD COLUMN IF NOT EXISTS receipt_counter INTEGER DEFAULT 0;

-- Create function to generate next receipt number for a business
CREATE OR REPLACE FUNCTION public.get_next_receipt_number(p_business_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_counter INTEGER;
  v_receipt_number TEXT;
  v_business_prefix TEXT;
BEGIN
  -- Lock the row to prevent concurrent updates
  SELECT receipt_counter, UPPER(SUBSTRING(name FROM 1 FOR 3))
  INTO v_counter, v_business_prefix
  FROM public.businesses
  WHERE id = p_business_id
  FOR UPDATE;
  
  -- Increment counter
  v_counter := COALESCE(v_counter, 0) + 1;
  
  -- Update counter
  UPDATE public.businesses
  SET receipt_counter = v_counter
  WHERE id = p_business_id;
  
  -- Generate receipt number: TP-{PREFIX}-{COUNTER}
  -- e.g., TP-MOM-00001 for Momsies
  v_receipt_number := 'TP-' || COALESCE(v_business_prefix, 'XXX') || '-' || LPAD(v_counter::TEXT, 5, '0');
  
  RETURN v_receipt_number;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION public.get_next_receipt_number(UUID) TO authenticated;

-- Verify the change
SELECT 
  id,
  name,
  receipt_counter
FROM public.businesses
WHERE owner_member_id IS NOT NULL
ORDER BY name;

COMMENT ON COLUMN public.businesses.receipt_counter IS 'Sequential counter for receipt numbering per business';
COMMENT ON FUNCTION public.get_next_receipt_number(UUID) IS 'Generates next sequential receipt number for a business';
