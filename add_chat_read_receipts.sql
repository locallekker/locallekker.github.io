-- Add read_by column to track who has read each message
-- This allows multiple participants to have their own read status

alter table public.chat_messages 
  add column if not exists read_by uuid[] default '{}';

-- Create index for faster read status queries
create index if not exists chat_messages_read_by_idx 
  on public.chat_messages using gin(read_by);

comment on column public.chat_messages.read_by is 'Array of user IDs who have read this message';
