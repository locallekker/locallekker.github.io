-- Allow users to update read_by field on messages they haven't sent
-- This enables read receipt tracking

drop policy if exists chat_messages_update on public.chat_messages;

create policy chat_messages_update on public.chat_messages
  for update using (
    exists (
      select 1
      from public.chat_conversations c
      where c.id = conversation_id
        and (auth.uid() = any (c.participant_ids)
          or exists (
            select 1 from public.profiles p
            where p.id = auth.uid() and p.role = 'admin'
          ))
    )
  );
