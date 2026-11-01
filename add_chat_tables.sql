-- Chat tables for Local Lekker

-- Conversations store participants inline for simplicity
create table if not exists public.chat_conversations (
  id uuid primary key default gen_random_uuid(),
  created_at timestamp with time zone default now(),
  is_admin boolean default false,
  participant_ids uuid[] not null
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid references public.chat_conversations(id) on delete cascade,
  sender_id uuid not null,
  content text not null,
  created_at timestamp with time zone default now()
);

-- RLS
alter table public.chat_conversations enable row level security;
alter table public.chat_messages enable row level security;

-- Policies: participants can select/insert; admin can select all
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'chat_conversations'
      and policyname = 'chat_conversations_select'
  ) then
    create policy chat_conversations_select on public.chat_conversations
      for select using (
        (auth.uid() = any (participant_ids))
        or exists (
          select 1 from public.profiles p
          where p.id = auth.uid() and p.role = 'admin'
        )
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'chat_conversations'
      and policyname = 'chat_conversations_insert'
  ) then
    create policy chat_conversations_insert on public.chat_conversations
      for insert with check (
        auth.uid() = any (participant_ids)
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'chat_messages'
      and policyname = 'chat_messages_select'
  ) then
    create policy chat_messages_select on public.chat_messages
      for select using (
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
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'chat_messages'
      and policyname = 'chat_messages_insert'
  ) then
    create policy chat_messages_insert on public.chat_messages
      for insert with check (
        exists (
          select 1
          from public.chat_conversations c
          where c.id = conversation_id
            and auth.uid() = any (c.participant_ids)
        )
      );
  end if;
end $$;
