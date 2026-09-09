-- Whose day a calendar belongs to, and a face for the household.
--
-- Kalender and Board are both getting a filter row of *people* rather than of
-- accounts. A household with four children at school has a dozen calendars and
-- a chip each is unreadable; the same twelve as six faces is the row a parent
-- actually uses. This is the column that row is built from.
--
-- **This is not visibility, and must never become it.** Calendars in Aporah are
-- never private and never shared outward — `shareable_kind` names no calendar,
-- the read policy has no guest branch, and every calendar is written
-- `visibility: 'family'`. Whose calendar this is and who may see it are separate
-- questions, exactly as `tasks.assignee_id` (who does it) is separate from
-- `tasks.visibility` (who may see it). The old single `who` string conflated
-- those two and had to be taken back out; don't rebuild it here. Everyone in the
-- household still sees every calendar.
--
-- No policy changes, therefore: these columns are readable and writable by
-- exactly whoever could already read and write the row.

-- ---------------------------------------------------------------------------
-- Ownership
-- ---------------------------------------------------------------------------

-- Two columns rather than one, because a schoolchild is often not a member.
--
-- Members join by e-mail invitation, so a family member *is* an account — and a
-- ten-year-old with a WebUntis login usually has no e-mail address of their own.
-- Insisting on `owner_member_id` would leave exactly the children this feature
-- exists for unrepresentable. So: the member id when there is one, a plain name
-- when there is not, and the household when there is neither.
--
--   owner_member_id set -> that member. Their face, their chores, their lessons.
--   owner_label set     -> a person in the household without an account.
--   both null           -> the whole family. The shared calendar, Ferien, Abfall.
--
-- `on delete set null` rather than cascade: a member leaving the household must
-- not delete the calendar, it makes it the family's.
alter table public.calendars
  add column owner_member_id uuid references auth.users (id) on delete set null,
  add column owner_label     text check (owner_label is null or length(trim(owner_label)) between 1 and 60);

comment on column public.calendars.owner_member_id is
  'Whose day this calendar belongs to — NOT who may see it. Null with owner_label null means the whole household.';
comment on column public.calendars.owner_label is
  'The person this calendar belongs to when they have no account (a child with a WebUntis login and no e-mail address).';

-- The same pair on the connection, as the default for the calendars it produces.
--
-- `calendar-events` recreates `calendars` rows on every read, so the per-calendar
-- value is the one a household edits and the connection's is what a *new*
-- calendar starts as. For WebUntis that default is worth a lot: the connect flow
-- already asks whose timetable this is, so every one of Alice's calendars is hers
-- without anybody visiting a settings screen.
alter table public.calendar_connections
  add column owner_member_id uuid references auth.users (id) on delete set null,
  add column owner_label     text check (owner_label is null or length(trim(owner_label)) between 1 and 60);

comment on column public.calendar_connections.owner_member_id is
  'Default owner for the calendars this account produces. See calendars.owner_member_id.';
comment on column public.calendar_connections.owner_label is
  'Default owner name for an account belonging to somebody with no login — the child a WebUntis connection was scanned for.';

-- Existing connections belong to whoever set them up. A household that has been
-- using the app already gets a sensible chip row on the first refresh rather
-- than everything piled under "Familie", and can move the shared calendar to the
-- family from the connections page afterwards — which is one edit instead of a
-- dozen.
update public.calendar_connections set owner_member_id = created_by where created_by is not null;

-- And the calendars those connections have already produced, for the same
-- reason: `calendar-events` only writes owner columns on a calendar it *creates*,
-- so without this every existing row would read as the family's until somebody
-- disconnected and reconnected the account.
update public.calendars c
   set owner_member_id = conn.created_by
  from public.calendar_connections conn
 where c.connection_id = conn.id
   and conn.created_by is not null;

-- A school connection belongs to the **pupil**, not to the parent who scanned
-- the QR code — and the parent is exactly who `created_by` names, so the two
-- backfills above would have filed a child's timetable under their mother.
--
-- WebUntis already told us whose key it is: `config.student_name` holds
-- "Boff Campagnaro Alice", surname first, the way Untis writes it. The last
-- token is the given name, which is the same rule the connect flow uses when it
-- suggests a name to type — see `_pupilShortName`. Applied after the two
-- updates above so it overrides them.
--
-- Only for the app-secret route: a pasted-link WebUntis connection has no
-- student_name to read, and stays with whoever added it.
update public.calendar_connections
   set owner_member_id = null,
       owner_label = nullif(regexp_replace(trim(config ->> 'student_name'), '^.*\s', ''), '')
 where provider = 'webuntis'
   and auth_type = 'secret'
   and coalesce(trim(config ->> 'student_name'), '') <> '';

update public.calendars c
   set owner_member_id = conn.owner_member_id,
       owner_label     = conn.owner_label
  from public.calendar_connections conn
 where c.connection_id = conn.id
   and conn.provider = 'webuntis'
   and conn.auth_type = 'secret'
   and conn.owner_label is not null;

-- ---------------------------------------------------------------------------
-- The household's own face
-- ---------------------------------------------------------------------------

-- So the "Familie" chip is an avatar like every other chip in the row rather
-- than a word among faces. Same private `avatars` bucket as a profile picture,
-- same signed-URL treatment; the path is keyed by family id rather than user id,
-- because the picture belongs to the household and has to outlive the admin who
-- uploaded it.
--
-- Null is a complete answer: the household falls back to its initials on a tone
-- circle, exactly as a member without a picture already does.
alter table public.families add column avatar_url text;

comment on column public.families.avatar_url is
  'Object path in the private avatars bucket, under <family_id>/. Null means initials on a tone circle.';

-- Read: anybody in the household. Write: admins only, and only under their own
-- family's prefix — `is_admin` is the same predicate the rest of the schema uses,
-- and it lives in `private` rather than `public` so it is not reachable as an
-- RPC.
create policy "avatars_read_family_picture"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = private.my_family_id()::text
  );

create policy "avatars_write_family_picture"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = private.my_family_id()::text
    and private.is_admin()
  );

create policy "avatars_delete_family_picture"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = private.my_family_id()::text
    and private.is_admin()
  );
