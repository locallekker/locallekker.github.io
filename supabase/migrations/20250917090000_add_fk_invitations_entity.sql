-- Migration: Add foreign key from invitations.entity_id to entities.id
-- Idempotent: checks for table/column/constraint existence and performs safe backfill.

begin;

-- Ensure the invitations table exists before proceeding
do $$
begin
  if exists (
    select 1 from information_schema.tables
    where table_schema = 'public' and table_name = 'invitations'
  ) then

    -- Add entity_id column if missing (nullable to avoid breaking existing rows)
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'invitations' and column_name = 'entity_id'
    ) then
      execute 'alter table public.invitations add column entity_id uuid';
    end if;

    -- If entities table exists, attempt a best-effort backfill for invitations that
    -- can be resolved via a heuristic (e.g. match invitation.target_email -> entities.contact_email)
    if exists (
      select 1 from information_schema.tables
      where table_schema = 'public' and table_name = 'entities'
    ) then
      -- Example heuristic backfill: match by contact_email if columns exist.
      if exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'invitations' and column_name = 'target_email'
      ) and exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'entities' and column_name = 'contact_email'
      ) then
        -- Update invitations set entity_id based on matching contact_email
        execute $update_sql$
          update public.invitations i
          set entity_id = e.id
          from public.entities e
          where i.entity_id is null
            and i.target_email is not null
            and lower(i.target_email) = lower(e.contact_email)
        $update_sql$;
      end if;

      -- Add constraint only if it doesn't already exist
      if not exists (
        select 1 from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu on kcu.constraint_name = tc.constraint_name
        where tc.table_schema = 'public' and tc.table_name = 'invitations'
          and tc.constraint_type = 'FOREIGN KEY' and kcu.column_name = 'entity_id'
      ) then
        -- Use ON DELETE SET NULL to avoid cascading deletions
        execute 'alter table public.invitations add constraint invitations_entity_id_fkey foreign key (entity_id) references public.entities(id) on delete set null';
      end if;
    end if;
  end if;
end$$;

commit;
