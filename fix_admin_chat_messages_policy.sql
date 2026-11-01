-- Fix RLS policy to allow admins to send messages in support chats

-- Drop existing policy
drop policy if exists chat_messages_insert on public.chat_messages;

-- Recreate with admin support
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
