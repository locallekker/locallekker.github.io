-- Enforce a maximum number of active saved cards per member.
-- Migration: 20260709000000_add_member_card_limit
--
-- Members may keep up to 3 active cards on file (the original signup card plus
-- two additional cards added during in-app payments). To add another card the
-- member must first delete an existing one. This is enforced in the app
-- (PaystackService.addPaymentMethod / CardLimitException) and backstopped here
-- at the database level so the invariant holds regardless of the entry point.

-- ── Limit helper ───────────────────────────────────────────────────────────
-- Single source of truth for the limit so the app constant
-- (PaystackService.maxSavedCards) and the DB stay aligned.
CREATE OR REPLACE FUNCTION public.member_card_limit()
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT 3;
$$;

-- ── Enforcement trigger ────────────────────────────────────────────────────
-- Blocks any INSERT/UPDATE that would leave a member with more than
-- member_card_limit() active cards. Only rows that END UP active are counted,
-- so soft-deletes (is_active = false) and reactivations are handled correctly.
CREATE OR REPLACE FUNCTION public.enforce_member_card_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    active_count INTEGER;
    max_cards INTEGER := public.member_card_limit();
BEGIN
    -- Only enforce when a card is newly inserted as active, or an existing
    -- inactive card is being reactivated (false -> true). Routine updates on an
    -- already-active row (e.g. changing the primary flag) must NOT be blocked —
    -- otherwise a member who somehow exceeds the limit could not manage their
    -- cards or even delete them down to the limit.
    IF NEW.is_active IS TRUE
       AND (TG_OP = 'INSERT' OR COALESCE(OLD.is_active, FALSE) = FALSE) THEN
        SELECT COUNT(*)
        INTO active_count
        FROM public.members_card_details
        WHERE user_id = NEW.user_id
          AND is_active = TRUE
          AND id <> NEW.id; -- exclude the row being written (self on UPDATE/INSERT)

        IF active_count >= max_cards THEN
            RAISE EXCEPTION
                'CARD_LIMIT_REACHED: member % already has % active cards (max %)',
                NEW.user_id, active_count, max_cards
                USING ERRCODE = 'check_violation';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_member_card_limit ON public.members_card_details;
CREATE TRIGGER trg_enforce_member_card_limit
    BEFORE INSERT OR UPDATE ON public.members_card_details
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_member_card_limit();

-- ── Dedup support ──────────────────────────────────────────────────────────
-- Ensure the same Paystack authorization is never stored twice for one member.
-- The app reactivates/refreshes an existing row instead of inserting a
-- duplicate; this partial unique index guarantees the invariant at the DB
-- level. (The active-card lookup index already exists from an earlier
-- migration: idx_members_card_details_authorization_code.)

-- First collapse any pre-existing duplicates so the unique index can be built.
-- For each (user_id, authorization_code) group keep the best row — prefer a
-- primary card, then an active card, then the most recently created — and
-- remove the redundant copies. These are exact duplicate card records, so the
-- kept row fully preserves the member's saved card.
WITH ranked AS (
    SELECT
        id,
        ROW_NUMBER() OVER (
            PARTITION BY user_id, authorization_code
            ORDER BY is_primary DESC, is_active DESC, created_at DESC
        ) AS rn
    FROM public.members_card_details
)
DELETE FROM public.members_card_details m
USING ranked r
WHERE m.id = r.id
  AND r.rn > 1;

DROP INDEX IF EXISTS members_card_details_user_auth_unique;
CREATE UNIQUE INDEX members_card_details_user_auth_unique
ON public.members_card_details (user_id, authorization_code);

COMMENT ON FUNCTION public.member_card_limit() IS
    'Maximum number of active saved cards a member may keep (mirrors PaystackService.maxSavedCards).';
COMMENT ON FUNCTION public.enforce_member_card_limit() IS
    'Trigger: prevents a member from exceeding member_card_limit() active saved cards.';
