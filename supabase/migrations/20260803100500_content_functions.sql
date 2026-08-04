-- Aporah backend — content access predicates and content-side guards.

-- ---------------------------------------------------------------------------
-- Guest stubs
--
-- External sharing arrives in the next migration. These two are declared now,
-- returning false, so that can_read_* / can_write_* below can be written once
-- with the guest branch already in place. Phase 3 replaces only these two
-- bodies; not a single access predicate has to be touched or re-reviewed.
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
  select false;
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
  select false;
$$;

-- ---------------------------------------------------------------------------
-- Read predicates
--
-- The shape is identical for all four containers:
--
--   household branch  -> member of the owning household, AND the row is either
--                        'family', or mine, or 'custom' and shared with me
--   guest branch      -> an explicit external grant, household irrelevant
--
-- 'private' needs no clause of its own: it is exactly the case where only
-- `owner_id = auth.uid()` matches.
--
-- The guest branch sits deliberately OUTSIDE the household gate. That is the
-- one place in this schema where a row is readable by someone who is not in the
-- owning household, and it is the line to re-read whenever these predicates
-- change.
-- ---------------------------------------------------------------------------

create or replace function public.can_read_list(p_list_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.lists l
     where l.id = p_list_id
       and (
             (
               l.family_id = public.my_family_id()
               and (
                     l.visibility = 'family'
                  or l.owner_id = (select auth.uid())
                  or (
                       l.visibility = 'custom'
                       and exists (
                             select 1
                               from public.list_shares s
                              where s.list_id = l.id
                                and s.user_id = (select auth.uid())
                           )
                     )
                   )
             )
             or public.is_guest_of('list', l.id)
           )
  );
$$;

create or replace function public.can_read_box(p_box_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.boxes b
     where b.id = p_box_id
       and (
             (
               b.family_id = public.my_family_id()
               and (
                     b.visibility = 'family'
                  or b.owner_id = (select auth.uid())
                  or (
                       b.visibility = 'custom'
                       and exists (
                             select 1
                               from public.box_shares s
                              where s.box_id = b.id
                                and s.user_id = (select auth.uid())
                           )
                     )
                   )
             )
             or public.is_guest_of('box', b.id)
           )
  );
$$;

create or replace function public.can_read_task(p_task_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.tasks t
     where t.id = p_task_id
       and (
             (
               t.family_id = public.my_family_id()
               and (
                     t.visibility = 'family'
                  or t.owner_id = (select auth.uid())
                  or (
                       t.visibility = 'custom'
                       and exists (
                             select 1
                               from public.task_shares s
                              where s.task_id = t.id
                                and s.user_id = (select auth.uid())
                           )
                     )
                   )
             )
             or public.is_guest_of('task', t.id)
           )
  );
$$;

-- No guest branch, by design: calendars are never shareable outside the
-- household. public.shareable_kind has no value that could name one, so this is
-- enforced twice over.
create or replace function public.can_read_calendar(p_calendar_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.calendars c
     where c.id = p_calendar_id
       and c.family_id = public.my_family_id()
       and (
             c.visibility = 'family'
          or c.owner_id = (select auth.uid())
          or (
               c.visibility = 'custom'
               and exists (
                     select 1
                       from public.calendar_shares s
                      where s.calendar_id = c.id
                        and s.user_id = (select auth.uid())
                   )
             )
           )
  );
$$;

-- ---------------------------------------------------------------------------
-- Write predicates
--
-- Anyone in the household who can see a container can work inside it — add
-- items, tick things off. That includes kids, deliberately: a chore board a
-- child cannot tick is not a chore board.
--
-- A guest can only work inside it if their grant says can_edit.
-- ---------------------------------------------------------------------------

create or replace function public.can_write_list(p_list_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select public.can_read_list(p_list_id)
     and (
           exists (
             select 1 from public.lists l
              where l.id = p_list_id and l.family_id = public.my_family_id()
           )
           or public.can_edit_guest('list', p_list_id)
         );
$$;

create or replace function public.can_write_box(p_box_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select public.can_read_box(p_box_id)
     and (
           exists (
             select 1 from public.boxes b
              where b.id = p_box_id and b.family_id = public.my_family_id()
           )
           or public.can_edit_guest('box', p_box_id)
         );
$$;

create or replace function public.can_write_task(p_task_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select public.can_read_task(p_task_id)
     and (
           exists (
             select 1 from public.tasks t
              where t.id = p_task_id and t.family_id = public.my_family_id()
           )
           or public.can_edit_guest('task', p_task_id)
         );
$$;

create or replace function public.can_write_calendar(p_calendar_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select public.can_read_calendar(p_calendar_id)
     and not exists (
           select 1 from public.calendars c
            where c.id = p_calendar_id and c.is_read_only
         );
$$;

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------

-- Ownership, household and visibility are the owner's to change and nobody
-- else's. Without this, any member of a family-visible list could flip it to
-- 'private' and take the household's shopping list hostage — and a guest with
-- can_edit could move it into their own household.
create or replace function public.enforce_container_ownership()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- No JWT: a trigger, a migration or a service_role Edge Function. Those are
  -- the privileged paths (reassignment on member removal, dissolution) and are
  -- trusted by construction.
  if (select auth.uid()) is null then
    return new;
  end if;

  if (
       new.owner_id   is distinct from old.owner_id
    or new.family_id  is distinct from old.family_id
    or new.visibility is distinct from old.visibility
     )
     and old.owner_id is distinct from (select auth.uid())
  then
    raise exception 'Nur der Eigentümer kann Sichtbarkeit, Eigentum oder Haushalt ändern.'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

create trigger lists_enforce_ownership
  before update on public.lists
  for each row execute function public.enforce_container_ownership();

create trigger boxes_enforce_ownership
  before update on public.boxes
  for each row execute function public.enforce_container_ownership();

create trigger tasks_enforce_ownership
  before update on public.tasks
  for each row execute function public.enforce_container_ownership();

create trigger calendars_enforce_ownership
  before update on public.calendars
  for each row execute function public.enforce_container_ownership();

-- Leaving a household must not strand rows that nobody on earth can read.
-- Shared content is handed to an admin; private content goes with its owner,
-- because there is no one left who was ever entitled to see it.
create or replace function public.reassign_content_on_member_removal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid;
begin
  -- Dissolution: the household and everything in it is cascading away already.
  if not exists (select 1 from public.families f where f.id = old.family_id) then
    return old;
  end if;

  delete from public.lists
   where family_id = old.family_id and owner_id = old.user_id and visibility = 'private';
  delete from public.boxes
   where family_id = old.family_id and owner_id = old.user_id and visibility = 'private';
  delete from public.tasks
   where family_id = old.family_id and owner_id = old.user_id and visibility = 'private';
  delete from public.calendars
   where family_id = old.family_id and owner_id = old.user_id and visibility = 'private';

  select m.user_id
    into v_admin
    from public.family_members m
   where m.family_id = old.family_id
     and m.role = 'admin'
     and m.user_id <> old.user_id
   order by m.joined_at
   limit 1;

  if v_admin is not null then
    update public.lists     set owner_id = v_admin
     where family_id = old.family_id and owner_id = old.user_id;
    update public.boxes     set owner_id = v_admin
     where family_id = old.family_id and owner_id = old.user_id;
    update public.tasks     set owner_id = v_admin
     where family_id = old.family_id and owner_id = old.user_id;
    update public.calendars set owner_id = v_admin
     where family_id = old.family_id and owner_id = old.user_id;
  end if;

  return old;
end;
$$;

-- BEFORE triggers fire in name order, so "enforce_last_admin" runs before
-- "reassign_content": the removal is rejected outright before any content is
-- touched.
create trigger family_members_reassign_content
  before delete on public.family_members
  for each row execute function public.reassign_content_on_member_removal();

create trigger lists_touch_updated_at
  before update on public.lists
  for each row execute function public.touch_updated_at();

create trigger list_items_touch_updated_at
  before update on public.list_items
  for each row execute function public.touch_updated_at();

create trigger boxes_touch_updated_at
  before update on public.boxes
  for each row execute function public.touch_updated_at();

create trigger box_items_touch_updated_at
  before update on public.box_items
  for each row execute function public.touch_updated_at();

create trigger tasks_touch_updated_at
  before update on public.tasks
  for each row execute function public.touch_updated_at();

create trigger calendars_touch_updated_at
  before update on public.calendars
  for each row execute function public.touch_updated_at();

create trigger events_touch_updated_at
  before update on public.events
  for each row execute function public.touch_updated_at();
