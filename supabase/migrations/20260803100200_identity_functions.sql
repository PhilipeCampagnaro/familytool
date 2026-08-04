-- Aporah backend — identity helpers, lifecycle triggers and escalation guards.
--
-- Every function here is SECURITY DEFINER with `search_path = ''`. The
-- definer part is not incidental: the policy helpers below read
-- family_members, and family_members' own policies call them. Without
-- SECURITY DEFINER that is infinite recursion, which Postgres reports as a
-- confusing "infinite recursion detected in policy" error at query time.
--
-- The empty search_path means every reference must be schema-qualified. That
-- is the point — it closes the search_path-hijacking hole that SECURITY
-- DEFINER would otherwise open.

-- ---------------------------------------------------------------------------
-- Small shared utilities
-- ---------------------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- Policy helpers
-- ---------------------------------------------------------------------------

-- The caller's household. Single-valued because of
-- family_members_one_household, and STABLE so Postgres evaluates it once per
-- statement rather than once per row.
create or replace function public.my_family_id()
returns uuid
language sql
security definer
stable
set search_path = ''
as $$
  select m.family_id
    from public.family_members m
   where m.user_id = (select auth.uid());
$$;

create or replace function public.my_role()
returns public.member_role
language sql
security definer
stable
set search_path = ''
as $$
  select m.role
    from public.family_members m
   where m.user_id = (select auth.uid());
$$;

create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select coalesce(public.my_role() = 'admin', false);
$$;

-- Whose profile may I read? Household-mates and myself, for now.
--
-- Phase 3 replaces this function to add the guest clause ("co-appears with me
-- on a resource I can read"), which is what stops names rendering blank on an
-- externally shared list. It is defined here so the profiles policy can be
-- written once and never touched again.
create or replace function public.can_see_profile(p_user_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select p_user_id = (select auth.uid())
      or exists (
           select 1
             from public.family_members m
            where m.user_id = p_user_id
              and m.family_id = public.my_family_id()
         );
$$;

-- Lowest avatar tone not yet taken in a household, so a new member does not
-- collide with an existing one. Falls back to 0 once all five are in use.
create or replace function public.next_free_tone(p_family_id uuid)
returns smallint
language sql
security definer
stable
set search_path = ''
as $$
  select coalesce(
    (select g.t
       from generate_series(0, 4) as g(t)
      where g.t not in (
              select p.tone
                from public.profiles p
                join public.family_members m on m.user_id = p.id
               where m.family_id = p_family_id
            )
      order by g.t
      limit 1),
    0)::smallint;
$$;

-- ---------------------------------------------------------------------------
-- Signup: profile + household + admin membership, atomically
-- ---------------------------------------------------------------------------

-- Runs for every new auth user, including someone who only signed up to open a
-- shared shopping list. They get a real household of their own — that is what
-- removes the "user without a family" state from the app entirely.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name     text;
  v_words    text[];
  v_initials text;
  v_family   uuid;
begin
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Neues Mitglied'
  );

  -- "Ana Rocha" -> AR, "Ana" -> AN. Mirrors what the avatars already show.
  v_words := regexp_split_to_array(v_name, '\s+');
  if array_length(v_words, 1) > 1 then
    v_initials := left(v_words[1], 1) || left(v_words[array_length(v_words, 1)], 1);
  else
    v_initials := left(v_name, 2);
  end if;
  v_initials := upper(v_initials);

  insert into public.profiles (id, display_name, initials)
  values (new.id, v_name, v_initials);

  insert into public.families (name, created_by)
  values ('Familie ' || v_name, new.id)
  returning id into v_family;

  insert into public.family_members (family_id, user_id, role)
  values (v_family, new.id, 'admin');

  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Escalation guards
-- ---------------------------------------------------------------------------

-- A household must never be left without an admin — otherwise nobody can ever
-- invite, promote or remove anyone again, and the household is permanently
-- stuck.
create or replace function public.enforce_last_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The household itself is being deleted and this DELETE is the FK cascade
  -- clearing its members (accept-invite dissolving a solo household). There is
  -- no household left to protect, so the guard must stand aside — otherwise
  -- legitimate dissolution fails.
  if not exists (select 1 from public.families f where f.id = old.family_id) then
    return old;
  end if;

  if old.role <> 'admin' or (tg_op = 'UPDATE' and new.role = 'admin') then
    if tg_op = 'DELETE' then
      return old;
    end if;
    return new;
  end if;

  if not exists (
    select 1
      from public.family_members m
     where m.family_id = old.family_id
       and m.role = 'admin'
       and m.user_id <> old.user_id
  ) then
    raise exception 'Der letzte Admin eines Haushalts kann nicht entfernt oder herabgestuft werden.'
      using errcode = 'check_violation';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger family_members_enforce_last_admin
  before update or delete on public.family_members
  for each row execute function public.enforce_last_admin();

-- Changing role is the only legitimate update to a membership. Moving a
-- membership to another household or another user would be a straightforward
-- escalation path.
create or replace function public.enforce_membership_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.family_id <> old.family_id or new.user_id <> old.user_id then
    raise exception 'Haushalt und Nutzer einer Mitgliedschaft sind unveränderlich.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create trigger family_members_enforce_immutable
  before update on public.family_members
  for each row execute function public.enforce_membership_immutable();

-- Being removed from a household must not leave someone with no household at
-- all — that state does not exist anywhere else in the system, and the app is
-- built on its absence. So a removed member immediately gets a fresh solo
-- household of their own, exactly as if they had just signed up.
--
-- Skipped during dissolution (accept-invite deleting a solo household), where
-- the member is about to be inserted into the *inviting* household instead.
-- Without that check the new solo household would claim the user's single
-- allowed membership and the join would fail on family_members_one_household.
create or replace function public.rehome_removed_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name   text;
  v_family uuid;
begin
  if not exists (select 1 from public.families f where f.id = old.family_id) then
    return old;
  end if;

  select p.display_name into v_name from public.profiles p where p.id = old.user_id;
  if v_name is null then
    return old;
  end if;

  insert into public.families (name, created_by)
  values ('Familie ' || v_name, old.user_id)
  returning id into v_family;

  insert into public.family_members (family_id, user_id, role)
  values (v_family, old.user_id, 'admin');

  return old;
end;
$$;

create trigger family_members_rehome_removed
  after delete on public.family_members
  for each row execute function public.rehome_removed_member();

create trigger families_touch_updated_at
  before update on public.families
  for each row execute function public.touch_updated_at();

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();
