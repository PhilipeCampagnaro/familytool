-- Aporah backend — RLS specification, executable.
--
-- Run with `supabase test db`. Every assertion below corresponds to a cell in
-- the permission matrix in docs/backend.md; if you change a policy, change this
-- file in the same commit.
--
-- A note on shape: RLS usually *filters* rather than raises. An UPDATE a user
-- is not entitled to make succeeds syntactically and changes nothing, so the
-- honest test is "the statement ran, and the row is unchanged" — not
-- throws_ok. Exceptions only appear where a trigger or a grant is what stops
-- the operation.
--
-- Fixtures:
--   Ana    admin  of the Rocha household
--   Marco  member of the Rocha household
--   Lea    kid    of the Rocha household
--   Chris  a stranger, admin of his own household (the work colleague)

begin;
select plan(77);

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.test_as(p_user uuid) returns void
language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
end;
$$;

-- session_user is unaffected by SET ROLE, so this always lands back on the
-- privileged role the test suite was started with.
create or replace function public.test_as_service() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', session_user, true);
end;
$$;

create or replace function public.new_user(p_id uuid, p_email text, p_name text) returns void
language plpgsql as $$
begin
  -- handle_new_user fires here: profile + solo household + admin membership.
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data
  ) values (
    p_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    p_email, '', now(), now(), now(),
    '{}'::jsonb, json_build_object('display_name', p_name)::jsonb
  );
end;
$$;

-- How many rows a statement actually touched.
--
-- "RLS filtered this away" and "the statement was a no-op for some other reason"
-- look identical from the outside: both raise nothing and change nothing. This
-- makes the filtering itself the thing under test — zero rows affected, asserted
-- directly — instead of inferring it from an absence of errors afterwards.
create or replace function public.test_rows_affected(p_sql text) returns integer
language plpgsql as $$
declare
  v_rows integer;
begin
  execute p_sql;
  get diagnostics v_rows = row_count;
  return v_rows;
end;
$$;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

select public.new_user('a0000000-0000-0000-0000-000000000001', 'ana@example.com',   'Ana Rocha');
select public.new_user('a0000000-0000-0000-0000-000000000002', 'marco@example.com', 'Marco Rocha');
select public.new_user('a0000000-0000-0000-0000-000000000003', 'lea@example.com',   'Lea Rocha');
select public.new_user('c0000000-0000-0000-0000-000000000001', 'chris@work.example','Chris Weber');

-- Signup gives everyone a household of their own. That is the invariant the
-- whole app leans on, so it is the first thing asserted.
select is(
  (select count(*)::int from public.family_members),
  4,
  'signup creates exactly one membership per user'
);

select is(
  (select count(distinct family_id)::int from public.family_members),
  4,
  'each new user gets their own household'
);

select is(
  (select role::text from public.family_members
    where user_id = 'a0000000-0000-0000-0000-000000000001'),
  'admin',
  'the creator of a household is its admin'
);

-- Assemble the Rocha household: Marco and Lea join Ana's, exactly as
-- accept_family_invite would (dissolve the solo household, then insert).
do $$
declare
  v_ana_family uuid;
begin
  select family_id into v_ana_family from public.family_members
   where user_id = 'a0000000-0000-0000-0000-000000000001';

  delete from public.families where id in (
    select family_id from public.family_members
     where user_id in ('a0000000-0000-0000-0000-000000000002',
                       'a0000000-0000-0000-0000-000000000003')
  );

  insert into public.family_members (family_id, user_id, role) values
    (v_ana_family, 'a0000000-0000-0000-0000-000000000002', 'member'),
    (v_ana_family, 'a0000000-0000-0000-0000-000000000003', 'kid');

  -- Stashed so assertions made *as a guest* can still name this household.
  -- Reading it through a subquery on family_members would return NULL for a
  -- guest and make several tests pass for the wrong reason.
  perform set_config('test.rocha_family', v_ana_family::text, true);

  insert into public.family_invites (family_id, email, role, token_hash, invited_by)
  values (v_ana_family, 'oma@example.com', 'member', 'hash-oma',
          'a0000000-0000-0000-0000-000000000001');
end;
$$;

-- Seed content: one family list, two private lists, one custom-shared list.
do $$
declare
  v_family uuid := current_setting('test.rocha_family')::uuid;
begin
  insert into public.lists (id, family_id, name, owner_id, visibility) values
    ('11111111-0000-0000-0000-000000000001', v_family, 'Wocheneinkauf',
     'a0000000-0000-0000-0000-000000000001', 'family'),
    ('11111111-0000-0000-0000-000000000002', v_family, 'Therapie',
     'a0000000-0000-0000-0000-000000000001', 'private'),
    ('11111111-0000-0000-0000-000000000003', v_family, 'Geburtstagsliste',
     'a0000000-0000-0000-0000-000000000001', 'custom'),
    ('11111111-0000-0000-0000-000000000004', v_family, 'Marcos Notizen',
     'a0000000-0000-0000-0000-000000000002', 'private');

  -- The birthday list: Lea may see it, Marco may not.
  insert into public.list_shares (list_id, family_id, user_id)
  values ('11111111-0000-0000-0000-000000000003', v_family,
          'a0000000-0000-0000-0000-000000000003');

  insert into public.list_items (id, list_id, text, created_by) values
    ('22222222-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001',
     'Milch', 'a0000000-0000-0000-0000-000000000001');
end;
$$;

-- ---------------------------------------------------------------------------
-- Internal visibility
-- ---------------------------------------------------------------------------

select public.test_as('a0000000-0000-0000-0000-000000000002');  -- Marco, member

select is(
  (select count(*)::int from public.lists),
  2,
  'member sees the family list and their own private list, nothing else'
);

select is(
  (select count(*)::int from public.lists
    where id = '11111111-0000-0000-0000-000000000002'),
  0,
  'member cannot see an admin''s private list'
);

select is(
  (select count(*)::int from public.lists
    where id = '11111111-0000-0000-0000-000000000003'),
  0,
  'custom-shared list is invisible to a household member not on the share'
);

select public.test_as('a0000000-0000-0000-0000-000000000003');  -- Lea, kid

select is(
  (select count(*)::int from public.lists
    where id = '11111111-0000-0000-0000-000000000003'),
  1,
  'custom-shared list is visible to the member it was shared with'
);

select public.test_as('a0000000-0000-0000-0000-000000000001');  -- Ana, admin

select is(
  (select count(*)::int from public.lists
    where id = '11111111-0000-0000-0000-000000000004'),
  0,
  'admin cannot see a member''s private list — privat means privat, no backdoor'
);

-- ---------------------------------------------------------------------------
-- Kid: sees and participates, but never administers
-- ---------------------------------------------------------------------------

select public.test_as('a0000000-0000-0000-0000-000000000003');  -- Lea, kid

select lives_ok(
  $$update public.list_items set done = true
     where id = '22222222-0000-0000-0000-000000000001'$$,
  'kid can tick off a task on a family list'
);

select lives_ok(
  $$insert into public.list_items (list_id, text, created_by)
    values ('11111111-0000-0000-0000-000000000001', 'Kekse',
            'a0000000-0000-0000-0000-000000000003')$$,
  'kid can add an item to a family list'
);

select is(
  (select count(*)::int from public.family_invites),
  0,
  'kid cannot see the household''s pending invites'
);

select lives_ok(
  $$update public.family_members set role = 'admin'
     where user_id = 'a0000000-0000-0000-0000-000000000003'$$,
  'kid''s self-promotion attempt is accepted syntactically'
);

select public.test_as_service();

select is(
  (select role::text from public.family_members
    where user_id = 'a0000000-0000-0000-0000-000000000003'),
  'kid',
  '...and changed nothing — the policy filtered the row out'
);

-- ---------------------------------------------------------------------------
-- Kalender-Verbindungen
--
-- The connection layer adds something the rest of the schema does not have: a
-- live credential for somebody's real Google or iCloud account. So these
-- assertions are less about who sees what and more about what nobody may reach
-- — the secrets table, the sync columns, and the household boundary.
--
-- (Migration …101000_calendar_connections.sql.)
-- ---------------------------------------------------------------------------

select public.test_as_service();

do $$
declare
  v_rocha uuid := current_setting('test.rocha_family')::uuid;
begin
  perform set_config('test.chris_family',
    (select family_id from public.family_members
      where user_id = 'c0000000-0000-0000-0000-000000000001')::text, true);

  insert into public.calendar_connections
    (id, family_id, provider, auth_type, external_account, display_name, created_by)
  values
    ('44444444-0000-0000-0000-000000000001', v_rocha, 'google', 'oauth',
     'ana@gmail.com',        'Google (Ana)',    'a0000000-0000-0000-0000-000000000001'),
    ('44444444-0000-0000-0000-000000000002', v_rocha, 'icloud', 'caldav',
     'marco@icloud.com',     'iCloud (Marco)',  'a0000000-0000-0000-0000-000000000002'),
    ('44444444-0000-0000-0000-000000000003', v_rocha, 'outlook', 'oauth',
     'marco@arbeit.example', 'Outlook (Marco)', 'a0000000-0000-0000-0000-000000000002'),
    ('44444444-0000-0000-0000-000000000004', v_rocha, 'google', 'oauth',
     'ana.zweit@gmail.com',  'Google (Ana 2)',  'a0000000-0000-0000-0000-000000000001'),
    ('44444444-0000-0000-0000-000000000009',
     current_setting('test.chris_family')::uuid, 'google', 'oauth',
     'chris@gmail.com',      'Google (Chris)',  'c0000000-0000-0000-0000-000000000001');

  insert into public.calendar_connection_secrets (connection_id, refresh_token)
  values ('44444444-0000-0000-0000-000000000001', 'v1.aaaa.bbbb');

  -- One hand-made calendar holding one hand-typed event. Both the sync-column
  -- guard and the guest's "sees no calendar events" assertion further down need
  -- something real to be about.
  insert into public.calendars (id, family_id, name, owner_id)
  values ('55555555-0000-0000-0000-000000000001', v_rocha, 'Familie',
          'a0000000-0000-0000-0000-000000000001');

  insert into public.events (id, calendar_id, title, starts_at, ends_at)
  values ('66666666-0000-0000-0000-000000000001',
          '55555555-0000-0000-0000-000000000001', 'Zahnarzt',
          '2026-09-03T09:00:00Z', '2026-09-03T10:00:00Z');
end;
$$;

select public.test_as('a0000000-0000-0000-0000-000000000001');  -- Ana, admin

-- The one table in this schema that no signed-in user may touch at all. Unlike
-- share_links.token_hash, which is a useless hash if it leaks, these are live
-- capabilities on somebody's real account.
select throws_ok(
  $$select * from public.calendar_connection_secrets$$,
  '42501',
  null,
  'nobody signed in can read a stored OAuth token or CalDAV password'
);

select throws_ok(
  $$insert into public.calendar_connection_secrets (connection_id)
    values ('44444444-0000-0000-0000-000000000002')$$,
  '42501',
  null,
  '...nor write one'
);

-- Connections are minted by the Edge Functions, which are the only place a
-- credential exists in the clear. A client-created row would look connected and
-- sync nothing.
select throws_ok(
  $$insert into public.calendar_connections
      (family_id, provider, auth_type, external_account, display_name)
    values (current_setting('test.rocha_family')::uuid, 'ferien', 'public',
            'NI', 'Ferien')$$,
  '42501',
  null,
  'a client cannot create a calendar connection at all'
);

select lives_ok(
  $$update public.calendar_connections set display_name = 'Anas Google'
     where id = '44444444-0000-0000-0000-000000000001'$$,
  'whoever connected an account can rename it'
);

select is(
  (select display_name from public.calendar_connections
    where id = '44444444-0000-0000-0000-000000000001'),
  'Anas Google',
  '...and the rename lands'
);

-- Everything except the display name, the sub-calendar choice and the ordering
-- is the server's. These four are column grants, not policies, which is why
-- they raise instead of filtering.
select throws_ok(
  $$update public.calendar_connections set status = 'active'
     where id = '44444444-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'but not clear a reconnect prompt by writing status directly'
);

select throws_ok(
  $$update public.calendar_connections
       set family_id = current_setting('test.chris_family')::uuid
     where id = '44444444-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'nor hand a live token to another household'
);

select throws_ok(
  $$update public.calendar_connections set external_account = 'jemand@gmail.com'
     where id = '44444444-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'nor relabel which account a credential belongs to'
);

select throws_ok(
  $$update public.calendar_connections set is_read_only = true
     where id = '44444444-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'nor change whether a feed is writable'
);

select public.test_as('a0000000-0000-0000-0000-000000000002');  -- Marco, member

select is(
  public.test_rows_affected(
    $$update public.calendar_connections set display_name = 'Marcos Umbenennung'
       where id = '44444444-0000-0000-0000-000000000001'$$),
  0,
  'a member who did not attach the account updates zero rows — RLS filters it'
);

select is(
  (select display_name from public.calendar_connections
    where id = '44444444-0000-0000-0000-000000000001'),
  'Anas Google',
  '...and the name is untouched'
);

select is(
  public.test_rows_affected(
    $$delete from public.calendar_connections
       where id = '44444444-0000-0000-0000-000000000001'$$),
  0,
  'and deletes zero rows'
);

select is(
  (select count(*)::int from public.calendar_connections
    where id = '44444444-0000-0000-0000-000000000001'),
  1,
  '...the connection is still there'
);

select public.test_as('a0000000-0000-0000-0000-000000000003');  -- Lea, kid

select is(
  public.test_rows_affected(
    $$update public.calendar_connections set display_name = 'Leas Umbenennung'
       where id = '44444444-0000-0000-0000-000000000001'$$),
  0,
  'a kid cannot rename a connection either'
);

select public.test_as('a0000000-0000-0000-0000-000000000001');  -- Ana, admin

select is(
  public.test_rows_affected(
    $$update public.calendar_connections set display_name = 'Marcos iCloud'
       where id = '44444444-0000-0000-0000-000000000002'$$),
  1,
  'an admin can rename a connection somebody else attached'
);

select is(
  (select display_name from public.calendar_connections
    where id = '44444444-0000-0000-0000-000000000002'),
  'Marcos iCloud',
  '...and that one lands'
);

select is(
  public.test_rows_affected(
    $$delete from public.calendar_connections
       where id = '44444444-0000-0000-0000-000000000003'$$),
  1,
  'and can disconnect one'
);

select is(
  (select count(*)::int from public.calendar_connections
    where id = '44444444-0000-0000-0000-000000000003'),
  0,
  '...which really removes it'
);

select is(
  (select count(*)::int from public.calendar_connections),
  3,
  'the household sees its own connections and only those'
);

select public.test_as('c0000000-0000-0000-0000-000000000001');  -- Chris, outsider

select is(
  (select count(*)::int from public.calendar_connections),
  1,
  'and another household sees only its own'
);

-- The sync columns belong to the sync function. A client that could write them
-- could detach a calendar from its connection, or pass an invented one off as
-- synced. This is a trigger, so it raises rather than filtering.
select public.test_as('a0000000-0000-0000-0000-000000000001');

select throws_ok(
  $$insert into public.calendars (family_id, name, owner_id, connection_id)
    values (current_setting('test.rocha_family')::uuid, 'Erfunden',
            'a0000000-0000-0000-0000-000000000001',
            '44444444-0000-0000-0000-000000000001')$$,
  '23514',
  null,
  'a client cannot pass a calendar off as a synced one'
);

select throws_ok(
  $$insert into public.calendars (family_id, name, owner_id, sync_token)
    values (current_setting('test.rocha_family')::uuid, 'Erfunden',
            'a0000000-0000-0000-0000-000000000001', 'tok')$$,
  '23514',
  null,
  'nor invent a sync cursor'
);

select throws_ok(
  $$update public.calendars
       set connection_id = '44444444-0000-0000-0000-000000000001'
     where id = '55555555-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'nor attach an existing calendar to a connection'
);

select throws_ok(
  $$update public.calendars set sync_token = 'tok'
     where id = '55555555-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'nor clear a cursor to force a refetch on every open'
);

select lives_ok(
  $$update public.calendars set name = 'Familie neu'
     where id = '55555555-0000-0000-0000-000000000001'$$,
  'while renaming an ordinary calendar still works'
);

select public.test_as_service();

-- family_check_id mirrors family_id so a composite FK can prove the connection
-- belongs to the same household. Cross-household is not validated against — it
-- cannot be represented.
select throws_ok(
  $$insert into public.calendars
      (family_id, name, owner_id, connection_id, external_id)
    values (current_setting('test.rocha_family')::uuid, 'Geklaut',
            'a0000000-0000-0000-0000-000000000001',
            '44444444-0000-0000-0000-000000000009', 'primary')$$,
  '23503',
  null,
  'a calendar cannot point at another household''s connection'
);

select lives_ok(
  $$insert into public.calendars
      (id, family_id, name, owner_id, connection_id, external_id)
    values ('55555555-0000-0000-0000-000000000002',
            current_setting('test.rocha_family')::uuid, 'Google Privat',
            'a0000000-0000-0000-0000-000000000001',
            '44444444-0000-0000-0000-000000000001', 'primary')$$,
  'the sync can attach a calendar to a connection in the same household'
);

select is(
  (select family_check_id from public.calendars
    where id = '55555555-0000-0000-0000-000000000002'),
  current_setting('test.rocha_family')::uuid,
  '...with the FK''s mirror column derived by trigger, not supplied by the caller'
);

select throws_ok(
  $$insert into public.calendar_connections
      (family_id, provider, auth_type, external_account, display_name, is_read_only)
    values (current_setting('test.rocha_family')::uuid, 'ferien', 'public',
            'NI', 'Ferien', false)$$,
  '23514',
  null,
  'a public feed cannot be marked writable'
);

select throws_ok(
  $$insert into public.calendars
      (family_id, name, owner_id, connection_id, external_id)
    values (current_setting('test.rocha_family')::uuid, 'Doppelt',
            'a0000000-0000-0000-0000-000000000001',
            '44444444-0000-0000-0000-000000000001', 'primary')$$,
  '23505',
  null,
  'one Aporah calendar per provider sub-calendar'
);

insert into public.events (id, calendar_id, title, starts_at, ends_at, external_uid)
values ('66666666-0000-0000-0000-000000000002',
        '55555555-0000-0000-0000-000000000002', 'Sportkurs',
        '2026-09-01T10:00:00Z', '2026-09-01T11:00:00Z', 'uid-sport');

select throws_ok(
  $$insert into public.events (calendar_id, title, starts_at, ends_at, external_uid)
    values ('55555555-0000-0000-0000-000000000002', 'Sportkurs',
            '2026-09-01T10:00:00Z', '2026-09-01T11:00:00Z', 'uid-sport')$$,
  '23505',
  null,
  'the same provider event cannot be imported twice'
);

-- ...but a recurring series shares one UID across every occurrence, which is
-- why starts_at is part of the identity and not merely part of the row.
select lives_ok(
  $$insert into public.events (calendar_id, title, starts_at, ends_at, external_uid)
    values ('55555555-0000-0000-0000-000000000002', 'Sportkurs',
            '2026-09-08T10:00:00Z', '2026-09-08T11:00:00Z', 'uid-sport')$$,
  'a recurring series keeps one row per occurrence'
);

delete from public.calendar_connections
 where id = '44444444-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.calendar_connection_secrets),
  0,
  'disconnecting takes the stored credential with it'
);

select is(
  (select count(*)::int from public.calendars where connection_id is not null)
  + (select count(*)::int from public.events where external_uid is not null),
  0,
  '...and every calendar and event it produced'
);

-- ---------------------------------------------------------------------------
-- Escalation guards
-- ---------------------------------------------------------------------------

select public.test_as('a0000000-0000-0000-0000-000000000002');  -- Marco, member

select lives_ok(
  $$update public.family_members set role = 'admin'
     where user_id = 'a0000000-0000-0000-0000-000000000002'$$,
  'member''s self-promotion attempt is accepted syntactically'
);

select public.test_as_service();

select is(
  (select role::text from public.family_members
    where user_id = 'a0000000-0000-0000-0000-000000000002'),
  'member',
  '...and changed nothing either'
);

-- A family-visible list must not be hijackable into someone's private stash.
-- Here RLS *does* let the UPDATE through — Marco can write to that list — and
-- the ownership trigger is what stops it.
select public.test_as('a0000000-0000-0000-0000-000000000002');

select throws_ok(
  $$update public.lists set visibility = 'private'
     where id = '11111111-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'non-owner cannot change a list''s visibility'
);

select public.test_as_service();

select throws_ok(
  $$delete from public.family_members
     where user_id = 'a0000000-0000-0000-0000-000000000001'$$,
  '23514',
  null,
  'the last admin of a household cannot be removed'
);

-- drop_connections_on_member_removal sorts BEFORE enforce_last_admin and has
-- therefore already deleted Ana's connections by the time the guard raises. What
-- puts them back is statement atomicity, not trigger ordering — so it is worth
-- an assertion rather than an assumption.
select is(
  (select count(*)::int from public.calendar_connections
    where created_by = 'a0000000-0000-0000-0000-000000000001'),
  1,
  'a refused removal leaves the admin''s calendar connections intact'
);

select throws_ok(
  $$insert into public.family_members (family_id, user_id, role)
    values (current_setting('test.rocha_family')::uuid,
            'c0000000-0000-0000-0000-000000000001', 'member')$$,
  '23505',
  null,
  'a user cannot hold a second household membership'
);

-- Removal must leave the person somewhere, never nowhere.
delete from public.family_members
 where family_id = current_setting('test.rocha_family')::uuid
   and user_id = 'a0000000-0000-0000-0000-000000000002';

select is(
  (select count(*)::int from public.family_members
    where user_id = 'a0000000-0000-0000-0000-000000000002'),
  1,
  'a removed member is rehomed into a fresh household of their own'
);

select is(
  (select role::text from public.family_members
    where user_id = 'a0000000-0000-0000-0000-000000000002'),
  'admin',
  'and is the admin of it'
);

select is(
  (select count(*)::int from public.lists
    where id = '11111111-0000-0000-0000-000000000004'),
  0,
  'their private content left with them rather than being orphaned'
);

-- Content is handed to an admin; a credential is not. A Google refresh token
-- must not keep working for a household the person has left.
select is(
  (select count(*)::int from public.calendar_connections
    where created_by = 'a0000000-0000-0000-0000-000000000002'),
  0,
  'and their calendar connections went with them, credentials included'
);

select is(
  (select count(*)::int from public.calendar_connections
    where created_by = 'a0000000-0000-0000-0000-000000000001'),
  1,
  'while everybody else''s stayed put'
);

-- ---------------------------------------------------------------------------
-- External sharing: the guest boundary
-- ---------------------------------------------------------------------------

insert into public.lists (id, family_id, name, owner_id, visibility)
values ('11111111-0000-0000-0000-000000000005',
        current_setting('test.rocha_family')::uuid, 'Party Einkauf',
        'a0000000-0000-0000-0000-000000000001', 'family');

insert into public.share_links (id, resource_kind, resource_id, family_id,
                                token_hash, created_by, can_edit)
values ('33333333-0000-0000-0000-000000000001', 'list',
        '11111111-0000-0000-0000-000000000005',
        current_setting('test.rocha_family')::uuid,
        'hash-party', 'a0000000-0000-0000-0000-000000000001', true);

insert into public.guest_access (resource_kind, resource_id, user_id,
                                 can_edit, granted_via, invited_by)
values ('list', '11111111-0000-0000-0000-000000000005',
        'c0000000-0000-0000-0000-000000000001', true,
        '33333333-0000-0000-0000-000000000001',
        'a0000000-0000-0000-0000-000000000001');

select public.test_as('c0000000-0000-0000-0000-000000000001');  -- Chris, the guest

select is(
  (select count(*)::int from public.lists
    where id = '11111111-0000-0000-0000-000000000005'),
  1,
  'guest sees the list shared with them'
);

select is(
  (select count(*)::int from public.lists
    where family_id = current_setting('test.rocha_family')::uuid
      and id <> '11111111-0000-0000-0000-000000000005'),
  0,
  'guest sees no other list belonging to that household'
);

select is((select count(*)::int from public.boxes),  0, 'guest sees no boxes');
select is((select count(*)::int from public.tasks),  0, 'guest sees no Board tasks');
select is((select count(*)::int from public.events), 0, 'guest sees no calendar events');

select is(
  (select count(*)::int from public.families
    where id = current_setting('test.rocha_family')::uuid),
  0,
  'guest cannot see the household that shared with them'
);

select is(
  (select count(*)::int from public.family_members
    where family_id = current_setting('test.rocha_family')::uuid),
  0,
  'guest cannot enumerate the household roster'
);

select is(
  (select count(*)::int from public.profiles
    where id = 'a0000000-0000-0000-0000-000000000003'),
  0,
  'guest cannot read the profile of a household member absent from the shared list'
);

select is(
  (select count(*)::int from public.profiles
    where id = 'a0000000-0000-0000-0000-000000000001'),
  1,
  'guest can read the profile of the person who shared, so the name renders'
);

select lives_ok(
  $$insert into public.list_items (list_id, text, created_by)
    values ('11111111-0000-0000-0000-000000000005', 'Chips',
            'c0000000-0000-0000-0000-000000000001')$$,
  'guest with can_edit can add an item'
);

select throws_ok(
  $$update public.lists set visibility = 'private'
     where id = '11111111-0000-0000-0000-000000000005'$$,
  '23514',
  null,
  'guest cannot change the shared list''s visibility'
);

select throws_ok(
  $$update public.lists
       set family_id = (select family_id from public.family_members
                         where user_id = 'c0000000-0000-0000-0000-000000000001')
     where id = '11111111-0000-0000-0000-000000000005'$$,
  '23514',
  null,
  'guest cannot move the shared list into their own household'
);

select is(
  (select count(*)::int from public.share_links),
  0,
  'guest cannot see the share links of the household that invited them'
);

-- Sharing never spreads without a household adult doing it deliberately.
select throws_ok(
  $$insert into public.guest_access (resource_kind, resource_id, user_id, invited_by)
    values ('list', '11111111-0000-0000-0000-000000000005',
            'a0000000-0000-0000-0000-000000000003',
            'c0000000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'guest cannot grant access to anyone else'
);

-- ---------------------------------------------------------------------------
-- Revocation actually revokes
-- ---------------------------------------------------------------------------

select public.test_as_service();

update public.share_links set revoked_at = now()
 where id = '33333333-0000-0000-0000-000000000001';

select is(
  (select count(*)::int from public.guest_access
    where granted_via = '33333333-0000-0000-0000-000000000001'),
  0,
  'revoking a link removes the guests who joined through it'
);

select public.test_as('c0000000-0000-0000-0000-000000000001');

select is(
  (select count(*)::int from public.lists
    where id = '11111111-0000-0000-0000-000000000005'),
  0,
  'and the guest immediately loses sight of the list'
);

-- ---------------------------------------------------------------------------
-- Kalender is never externally shareable
-- ---------------------------------------------------------------------------

select public.test_as_service();

select throws_ok(
  $$select 'calendar'::public.shareable_kind$$,
  '22P02',
  null,
  'there is no shareable_kind value that could name a calendar'
);

-- ---------------------------------------------------------------------------
-- Dissolving a household
--
-- The last leg of the connection lifecycle, and the one place
-- drop_connections_on_member_removal must stand aside: the household is already
-- cascading away, so there is nothing left to protect.
-- ---------------------------------------------------------------------------

select lives_ok(
  $$delete from public.families
     where id = current_setting('test.chris_family')::uuid$$,
  'a household with a calendar connection can still be dissolved'
);

select is(
  (select count(*)::int from public.calendar_connections),
  1,
  '...and its connection went with it, leaving only the other household''s'
);

select * from finish();
rollback;
