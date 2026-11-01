-- Chat conversations support member <-> trusted partner and member/partner <-> admin flows.

CREATE TABLE IF NOT EXISTS public.chat_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  is_admin boolean NOT NULL DEFAULT false,
  participant_ids uuid[] NOT NULL
);

CREATE TABLE IF NOT EXISTS public.chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid NOT NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  read_by uuid[] NOT NULL DEFAULT '{}'
);

ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS read_by uuid[] NOT NULL DEFAULT '{}';

ALTER TABLE public.chat_conversations
  ADD COLUMN IF NOT EXISTS last_read_at timestamptz;

ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS chat_conversations_select ON public.chat_conversations;
DROP POLICY IF EXISTS chat_conversations_insert ON public.chat_conversations;
DROP POLICY IF EXISTS chat_conversations_delete ON public.chat_conversations;
DROP POLICY IF EXISTS chat_messages_select ON public.chat_messages;
DROP POLICY IF EXISTS chat_messages_insert ON public.chat_messages;
DROP POLICY IF EXISTS chat_messages_update ON public.chat_messages;
DROP POLICY IF EXISTS chat_messages_delete ON public.chat_messages;

CREATE POLICY chat_conversations_select ON public.chat_conversations
  FOR SELECT USING (
    auth.uid() = ANY (participant_ids) OR public.is_admin()
  );

CREATE POLICY chat_conversations_insert ON public.chat_conversations
  FOR INSERT WITH CHECK (auth.uid() = ANY (participant_ids));

CREATE POLICY chat_conversations_delete ON public.chat_conversations
  FOR DELETE USING (
    auth.uid() = ANY (participant_ids)
    OR (is_admin AND public.is_admin())
  );

CREATE POLICY chat_messages_select ON public.chat_messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.chat_conversations c
      WHERE c.id = conversation_id
        AND (auth.uid() = ANY (c.participant_ids) OR (c.is_admin AND public.is_admin()))
    )
  );

CREATE POLICY chat_messages_insert ON public.chat_messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.chat_conversations c
      WHERE c.id = conversation_id
        AND (
          auth.uid() = ANY (c.participant_ids)
          OR (c.is_admin AND public.is_admin())
        )
    )
  );

CREATE POLICY chat_messages_update ON public.chat_messages
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.chat_conversations c
      WHERE c.id = conversation_id
        AND (auth.uid() = ANY (c.participant_ids) OR (c.is_admin AND public.is_admin()))
    )
  ) WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.chat_conversations c
      WHERE c.id = conversation_id
        AND (auth.uid() = ANY (c.participant_ids) OR (c.is_admin AND public.is_admin()))
    )
  );

CREATE POLICY chat_messages_delete ON public.chat_messages
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM public.chat_conversations c
      WHERE c.id = conversation_id
        AND (auth.uid() = ANY (c.participant_ids) OR (c.is_admin AND public.is_admin()))
    )
  );

-- Let chat participants load only the counterpart's display name and profile photo.
DROP POLICY IF EXISTS chat_participants_can_read_profiles ON public.profiles;
CREATE POLICY chat_participants_can_read_profiles ON public.profiles
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.chat_conversations c
      WHERE auth.uid() = ANY (c.participant_ids)
        AND public.profiles.id = ANY (c.participant_ids)
    )
  );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'chat_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
  END IF;
END $$;