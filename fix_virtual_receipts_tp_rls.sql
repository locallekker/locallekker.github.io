-- Fix virtual_receipts INSERT policy: TP is identified by businesses.owner_member_id, not trusted_partner_id directly
DROP POLICY IF EXISTS "Members and trusted partners can insert virtual receipts" ON virtual_receipts;

CREATE POLICY "Members and trusted partners can insert virtual receipts"
ON virtual_receipts
FOR INSERT
WITH CHECK (
  -- Member can insert for their own deal
  (EXISTS (
    SELECT 1 FROM deal_authorizations
    WHERE deal_authorizations.id = virtual_receipts.deal_authorization_id
      AND deal_authorizations.member_id = auth.uid()
  ))
  OR
  -- TP (business owner) can insert for deals linked to their business
  (EXISTS (
    SELECT 1 FROM deal_authorizations da
    JOIN businesses b ON b.id = da.trusted_partner_id
    WHERE da.id = virtual_receipts.deal_authorization_id
      AND b.owner_member_id = auth.uid()
  ))
);

-- Also fix member_receipts INSERT to allow TP to insert on member's behalf during POS completion
DROP POLICY IF EXISTS "Members and trusted partners can insert receipts" ON member_receipts;

CREATE POLICY "Members and trusted partners can insert receipts"
ON member_receipts
FOR INSERT
WITH CHECK (
  -- Member inserts their own receipt
  (auth.uid() = member_id)
  OR
  -- TP inserts on member's behalf during POS completion
  (EXISTS (
    SELECT 1 FROM deal_authorizations da
    JOIN businesses b ON b.id = da.trusted_partner_id
    WHERE da.member_id = member_receipts.member_id
      AND b.owner_member_id = auth.uid()
  ))
);
