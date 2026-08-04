-- Aporah backend — sharing a list, box or task outward, to someone who is not
-- in the household.
--
-- The motivating case: a shopping list for a party at work, sent into a group
-- chat. Recipients sign up, get a household of their own like any other user,
-- and see exactly that one list inside it — nothing else, ever.
--
-- A token never grants access to a row. It is exchanged, once, for a durable
-- row in guest_access. That keeps every policy in this schema `to
-- authenticated` and means nothing here is ever readable anonymously.

create table public.share_links (
  id            uuid primary key default gen_random_uuid(),
  resource_kind public.shareable_kind not null,
  resource_id   uuid not null,
  -- Denormalised from the resource so an admin can audit and revoke every
  -- outbound link their household ever created, in one query.
  family_id     uuid not null references public.families (id) on delete cascade,
  -- Only ever the hash. The raw token is returned once, by create-share-link.
  token_hash    text not null unique,
  created_by    uuid not null references auth.users (id) on delete cascade,
  can_edit      boolean not null default true,
  expires_at    timestamptz,
  max_uses      integer check (max_uses is null or max_uses > 0),
  use_count     integer not null default 0,
  revoked_at    timestamptz,
  created_at    timestamptz not null default now()
);

create table public.guest_access (
  resource_kind public.shareable_kind not null,
  resource_id   uuid not null,
  user_id       uuid not null references auth.users (id) on delete cascade,
  can_edit      boolean not null default true,
  granted_via   uuid references public.share_links (id) on delete set null,
  invited_by    uuid not null references auth.users (id) on delete cascade,
  created_at    timestamptz not null default now(),

  primary key (resource_kind, resource_id, user_id)
);

-- The hot path of every read a guest performs.
create index guest_access_user_kind_idx on public.guest_access (user_id, resource_kind);
create index guest_access_resource_idx  on public.guest_access (resource_kind, resource_id);
create index share_links_resource_idx   on public.share_links (resource_kind, resource_id);
create index share_links_family_idx     on public.share_links (family_id);
create index share_links_created_by_idx on public.share_links (created_by);

-- ---------------------------------------------------------------------------
-- The guest predicates, for real this time
--
-- These two replace the stubs from the content migration. Nothing else changes:
-- every can_read_* / can_write_* predicate already calls them, so external
-- sharing switches on without a single access rule being rewritten.
-- ---------------------------------------------------------------------------

create or replace function public.is_guest_of(
  p_kind public.shareable_kind,
  p_resource_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.guest_access g
     where g.resource_kind = p_kind
       and g.resource_id = p_resource_id
       and g.user_id = (select auth.uid())
  );
$$;

create or replace function public.can_edit_guest(
  p_kind public.shareable_kind,
  p_resource_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.guest_access g
     where g.resource_kind = p_kind
       and g.resource_id = p_resource_id
       and g.user_id = (select auth.uid())
       and g.can_edit
  );
$$;

-- ---------------------------------------------------------------------------
-- Polymorphic helpers
--
-- guest_access is polymorphic where the internal *_shares tables are not, and
-- the asymmetry is deliberate: the value of the per-table design was a
-- composite foreign key proving "shared only with a household member", and a
-- guest is by definition not one. With three shareable kinds, one table plus a
-- cleanup trigger beats six tables and six sets of policies.
-- ---------------------------------------------------------------------------

create or replace function public.can_read_shareable(
  p_kind public.shareable_kind,
  p_resource_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select case p_kind
           when 'list' then public.can_read_list(p_resource_id)
           when 'box'  then public.can_read_box(p_resource_id)
           when 'task' then public.can_read_task(p_resource_id)
         end;
$$;

create or replace function public.owns_shareable(
  p_kind public.shareable_kind,
  p_resource_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select case p_kind
           when 'list' then exists (select 1 from public.lists l
                                     where l.id = p_resource_id and l.owner_id = (select auth.uid()))
           when 'box'  then exists (select 1 from public.boxes b
                                     where b.id = p_resource_id and b.owner_id = (select auth.uid()))
           when 'task' then exists (select 1 from public.tasks t
                                     where t.id = p_resource_id and t.owner_id = (select auth.uid()))
         end;
$$;

create or replace function public.shareable_family_id(
  p_kind public.shareable_kind,
  p_resource_id uuid
)
returns uuid
language sql
security definer
stable
set search_path = ''
as $$
  select case p_kind
           when 'list' then (select l.family_id from public.lists l where l.id = p_resource_id)
           when 'box'  then (select b.family_id from public.boxes b where b.id = p_resource_id)
           when 'task' then (select t.family_id from public.tasks t where t.id = p_resource_id)
         end;
$$;

-- ---------------------------------------------------------------------------
-- Profile visibility, extended for guests
--
-- Without this, every name on an externally shared list renders blank. With it
-- written carelessly, a guest could enumerate the entire household.
--
-- The rule is deliberately narrow: I may see exactly the people whose names
-- actually appear on a resource I can read — its owner, and whoever created,
-- was assigned, or ticked off something in it. Not the rest of the household.
-- ---------------------------------------------------------------------------

create or replace function public.can_see_profile(p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select
    -- Myself.
    p_user_id = (select auth.uid())

    -- My household.
    or exists (
         select 1 from public.family_members m
          where m.user_id = p_user_id
            and m.family_id = public.my_family_id()
       )

    -- A guest on something I can read (so the household sees the guest's name).
    or exists (
         select 1 from public.guest_access g
          where g.user_id = p_user_id
            and public.can_read_shareable(g.resource_kind, g.resource_id)
       )

    -- Someone whose name appears on something shared with me (so the guest sees
    -- the household names actually rendered on that one resource).
    or exists (
         select 1
           from public.guest_access g
          where g.user_id = (select auth.uid())
            and (
              (g.resource_kind = 'list' and exists (
                 select 1 from public.lists l
                  where l.id = g.resource_id
                    and (
                      l.owner_id = p_user_id
                      or exists (
                           select 1 from public.list_items i
                            where i.list_id = l.id
                              and p_user_id in (i.created_by, i.assignee_id, i.done_by)
                         )
                    )
              ))
              or (g.resource_kind = 'box' and exists (
                 select 1 from public.boxes b
                  where b.id = g.resource_id
                    and (
                      b.owner_id = p_user_id
                      or exists (
                           select 1 from public.box_items bi
                            where bi.box_id = b.id and bi.created_by = p_user_id
                         )
                    )
              ))
              or (g.resource_kind = 'task' and exists (
                 select 1 from public.tasks t
                  where t.id = g.resource_id
                    and p_user_id in (t.owner_id, t.assignee_id, t.done_by)
              ))
            )
       );
$$;

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------

-- Kids do not share family content with strangers. Checked against
-- created_by rather than auth.uid() so it holds even though the only writer is
-- a service_role Edge Function, where auth.uid() is null.
create or replace function public.enforce_share_link_author()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select m.role from public.family_members m where m.user_id = new.created_by) = 'kid' then
    raise exception 'Kinder können keine externen Freigabe-Links erstellen.'
      using errcode = 'check_violation';
  end if;

  if public.shareable_family_id(new.resource_kind, new.resource_id) is distinct from new.family_id then
    raise exception 'Der Freigabe-Link gehört nicht zum Haushalt der Ressource.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger share_links_enforce_author
  before insert on public.share_links
  for each row execute function public.enforce_share_link_author();

-- Revoking a link has to mean something for the people who already used it,
-- otherwise "revoke" only stops future redemptions and leaves every existing
-- guest in place.
create or replace function public.revoke_link_guests()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.revoked_at is not null and old.revoked_at is null then
    delete from public.guest_access where granted_via = new.id;
  end if;
  return new;
end;
$$;

create trigger share_links_revoke_guests
  after update on public.share_links
  for each row execute function public.revoke_link_guests();

-- The price of the polymorphic design: no foreign key can clean these up, so a
-- trigger does.
create or replace function public.cleanup_guest_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_kind public.shareable_kind;
begin
  v_kind := case tg_table_name
              when 'lists' then 'list'::public.shareable_kind
              when 'boxes' then 'box'::public.shareable_kind
              when 'tasks' then 'task'::public.shareable_kind
            end;

  delete from public.guest_access where resource_kind = v_kind and resource_id = old.id;
  delete from public.share_links  where resource_kind = v_kind and resource_id = old.id;
  return old;
end;
$$;

create trigger lists_cleanup_guest_access
  after delete on public.lists
  for each row execute function public.cleanup_guest_access();

create trigger boxes_cleanup_guest_access
  after delete on public.boxes
  for each row execute function public.cleanup_guest_access();

create trigger tasks_cleanup_guest_access
  after delete on public.tasks
  for each row execute function public.cleanup_guest_access();

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.share_links  enable row level security;
alter table public.guest_access enable row level security;

-- Your own outbound links; an admin sees every link the household issued.
create policy "share_links_select" on public.share_links for select to authenticated
  using (
    family_id = public.my_family_id()
    and (created_by = (select auth.uid()) or public.is_admin())
  );

create policy "share_links_update" on public.share_links for update to authenticated
  using (
    family_id = public.my_family_id()
    and (created_by = (select auth.uid()) or public.is_admin())
  )
  with check (
    family_id = public.my_family_id()
    and (created_by = (select auth.uid()) or public.is_admin())
  );

create policy "share_links_delete" on public.share_links for delete to authenticated
  using (
    family_id = public.my_family_id()
    and (created_by = (select auth.uid()) or public.is_admin())
  );

-- No insert policy: links are minted by the create-share-link Edge Function,
-- which is the only place a token exists in plaintext.

-- token_hash is never selectable, and the only updatable column is revoked_at —
-- so "revoke this link" is expressible while re-pointing a live link at another
-- resource is not.
revoke all on public.share_links from authenticated;

grant select (
  id, resource_kind, resource_id, family_id, created_by,
  can_edit, expires_at, max_uses, use_count, revoked_at, created_at
) on public.share_links to authenticated;

grant update (revoked_at) on public.share_links to authenticated;
grant delete on public.share_links to authenticated;

-- A guest sees their own grants (that is how the app knows a list is shared
-- *into* the account, and whether it is editable). The household sees the
-- guests on resources it can already read, to render the Teilen sheet.
create policy "guest_access_select" on public.guest_access for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.can_read_shareable(resource_kind, resource_id)
  );

-- Removing a guest: the resource owner, an admin of the owning household, or
-- the guest themselves walking away.
create policy "guest_access_delete" on public.guest_access for delete to authenticated
  using (
    user_id = (select auth.uid())
    or public.owns_shareable(resource_kind, resource_id)
    or (
      public.is_admin()
      and public.shareable_family_id(resource_kind, resource_id) = public.my_family_id()
    )
  );

-- No insert or update policy: grants are created only by redeem-share-link,
-- which verifies a token the client cannot forge. A client-side insert here
-- would let anyone grant themselves access to any list in the system.
--
-- RLS alone already denies both, since a missing policy is a denial. The
-- revoke is belt and braces: it means a future migration that adds a policy by
-- mistake still cannot open the hole on its own.
revoke insert, update on public.guest_access from authenticated;
