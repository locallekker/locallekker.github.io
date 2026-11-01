-- ============================================================================
-- Apply: Admin two-way support chat
-- Run this once against the production Supabase database (SQL editor).
-- Safe to re-run: it drops and recreates the affected policies.
--
-- Fixes:
--   1. Admins can INSERT replies into member support conversations
--      (members were the only ones in participant_ids, so admins were blocked)
--   2. Admins can UPDATE the read_by array (read receipts) on any message
--      in a support conversation
-- ============================================================================

-- 1) INSERT policy: allow participants OR admins on admin support conversations
drop policy if exists chat_messages_insert on public.chat_messages;

create policy chat_messages_insert on public.chat_messages
  for insert with check (
    exists (
      select 1
      from public.chat_conversations c
      where c.id = conversation_id
        and (
          auth.uid() = any (c.participant_ids)
          or (
            c.is_admin = true
            and exists (
              select 1 from public.profiles p
              where p.id = auth.uid() and p.role = 'admin'
            )
          )
        )
    )
  );

-- 2) UPDATE policy: allow participants (for read receipts) OR admins
drop policy if exists chat_messages_update on public.chat_messages;

create policy chat_messages_update on public.chat_messages
  for update using (
    exists (
      select 1
      from public.chat_conversations c
      where c.id = conversation_id
        and (
          auth.uid() = any (c.participant_ids)
          or exists (
            select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'admin'
          )
        )
    )
  );

-- Verify
select policyname, cmd
from pg_policies
where schemaname = 'public'
  and tablename = 'chat_messages'
order by policyname;
