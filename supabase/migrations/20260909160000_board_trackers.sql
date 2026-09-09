-- ---------------------------------------------------------------------------
-- Board — Tracker
--
-- The Board header has drawn a habit grid since the screen was built, and the
-- household never had anything that repeats to fill it. It counted, for every
-- past day, how many `public.tasks` happened to be due and how many were ticked
-- — so a one-off "Reisepass verlängern" that landed on a Tuesday became a data
-- point in what reads as a habit chart. The feedback was exactly that: a to-do
-- should not be a tracker.
--
-- So a tracker becomes its own container, beside a task rather than a flavour
-- of one. The two differ in more than repetition, and the difference a family
-- feels is what happens when one is missed:
--
--   * A missed **task** is overdue. It moves to the top of the Board and stays
--     there until somebody deals with it.
--   * A missed **tracker** is a gap in the record and nothing else. It never
--     enters "Überfällig" — a household that skips the bins twice in March must
--     not open the Board in April to a wall of failures, which is the opposite
--     of what a tracker is for.
--
-- **A rule plus a log, never generated occurrences.** `trackers` holds the
-- rhythm and `tracker_checks` holds the days it was actually met; which days
-- were *due* is computed from the rule at read time. Materialising a row per
-- future day would need a job to generate them, a rewrite of the whole future
-- every time somebody edits the rhythm, and it would strand hundreds of rows on
-- delete. It is the same trade the rest of this schema already makes:
-- `german_holidays.dart` computes the Feiertage rather than storing a feed, and
-- provider recurrence is expanded on read rather than materialised (see
-- docs/backend.md).
--
-- **Not a rolling due date on `public.tasks`.** Advancing `due_date` on
-- completion is the cheap version and keeps no history at all, which is the one
-- thing a tracker exists to have — and a missed Thursday would silently
-- disappear instead of showing up as the gap it is.
--
-- Nothing migrates. Every existing task stays a task.
-- ---------------------------------------------------------------------------

-- The three rhythms, and they are two different *kinds* of thing rather than
-- three presets of one. 'daily' and 'weekdays' make the **day** the unit: a
-- Thursday tracker is met or missed on Thursday. 'weekly_count' makes the
-- **week** the unit: "vier Tage pro Woche" owes nothing on any particular day
-- and can only be missed once Sunday has closed. The app renders them
-- differently for that reason, and the enum is what keeps the two apart.
create type public.tracker_schedule as enum ('daily', 'weekdays', 'weekly_count');

create table public.trackers (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references public.families (id) on delete cascade,
  text        text not null check (length(trim(text)) between 1 and 400),
  meta        text,

  -- Same key space as lists and boxes, so a tracker can name itself from the
  -- typed text through `suggestIcon` like every other container.
  icon_key    text,

  schedule    public.tracker_schedule not null,

  -- ISO weekdays, 1 = Monday … 7 = Sunday, matching Dart's `DateTime.weekday`
  -- so neither side has to renumber. Only ever set for 'weekdays'.
  weekdays    smallint[],

  -- Days per week, only ever set for 'weekly_count'. Capped at 7 because a
  -- target above the number of days in a week can never be met.
  target      smallint,

  -- Who is meant to do it — the same axis as `tasks.assignee_id`, never a
  -- visibility hint. One member, so "is it done today?" has one answer; a habit
  -- two children each keep is two trackers, which is also how their grids
  -- should read.
  assignee_id uuid references auth.users (id) on delete set null,

  -- Nothing before this day counts as missed. Without it a tracker created in
  -- September would open with a grid of failures stretching back to whenever
  -- the household joined.
  starts_on   date not null default current_date,

  -- Retiring a tracker is not deleting it: the days it was kept stay worth
  -- looking at. The app reads live ones and leaves these behind.
  archived_at timestamptz,

  owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  visibility  public.visibility not null default 'family',

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  unique (id, family_id),

  -- One shape per schedule, so no row can mean two things at once. A
  -- 'weekly_count' row carrying weekdays would leave the app to guess which of
  -- the two questions it was answering.
  constraint trackers_schedule_shape check (
       (schedule = 'daily'        and weekdays is null and target is null)
    or (schedule = 'weekdays'     and target is null
                                  and weekdays is not null
                                  and array_length(weekdays, 1) between 1 and 7
                                  and weekdays <@ array[1,2,3,4,5,6,7]::smallint[])
    or (schedule = 'weekly_count' and weekdays is null and target between 1 and 7)
  )
);

create table public.tracker_shares (
  tracker_id uuid not null,
  family_id  uuid not null,
  user_id    uuid not null,
  created_at timestamptz not null default now(),

  primary key (tracker_id, user_id),
  foreign key (tracker_id, family_id) references public.trackers (id, family_id) on delete cascade,
  foreign key (family_id, user_id) references public.family_members (family_id, user_id) on delete cascade
);

-- One row per day a tracker was met. A tick is this row existing and an untick
-- is deleting it, so there is no `done` boolean to fall out of step and no way
-- to record a day as explicitly *not* done — which is right, because "missed"
-- is the absence of a check on a day the rule scheduled, and the rule is the
-- only thing that knows.
--
-- `done_by` is in the primary key rather than beside it. Today one tick settles
-- the day for the whole household, which is what "Müll rausbringen" wants; a
-- later "everybody has to tick" mode — "Zähne putzen" for two children on one
-- tracker — then needs a column on `trackers` and a rule in Dart, and no
-- migration of the rows written before it.
create table public.tracker_checks (
  tracker_id uuid not null,
  family_id  uuid not null,
  day        date not null,
  done_by    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  done_at    timestamptz not null default now(),

  primary key (tracker_id, day, done_by),
  foreign key (tracker_id, family_id) references public.trackers (id, family_id) on delete cascade
);

create index trackers_family_visibility_idx on public.trackers (family_id, visibility);
create index trackers_owner_idx             on public.trackers (owner_id);
create index trackers_assignee_idx          on public.trackers (assignee_id);
create index tracker_shares_user_idx        on public.tracker_shares (user_id);

-- No separate index on (tracker_id, day): the primary key is
-- (tracker_id, day, done_by), whose btree already answers "this tracker's
-- recent days" and can be scanned backwards for the newest first.

-- ---------------------------------------------------------------------------
-- Guards
-- ---------------------------------------------------------------------------

create trigger trackers_enforce_ownership
  before update on public.trackers
  for each row execute function public.enforce_container_ownership();

create trigger trackers_touch_updated_at
  before update on public.trackers
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Policy helpers
--
-- In `private`, not `public`. A `security definer` predicate sitting in `public`
-- is published at /rest/v1/rpc/<name> — that is what migration
-- 20260804110014 moved the other seventeen out of, and a new one in `public`
-- would walk it straight back. They call `private.my_family_id()` and friends by
-- qualified name because `search_path` is empty.
--
-- **No guest branch, unlike tasks.** `public.shareable_kind` is
-- ('list','box','task') and gains no value here: a tracker is a household
-- rhythm, and a share link handing an outsider a page of somebody's habits has
-- no reader worth the leak. Enforced twice over, the way calendars are.
-- ---------------------------------------------------------------------------

create or replace function private.can_read_tracker(p_tracker_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.trackers t
     where t.id = p_tracker_id
       and t.family_id = private.my_family_id()
       and (
             t.visibility = 'family'
          or t.owner_id = (select auth.uid())
          or (
               t.visibility = 'custom'
               and exists (
                     select 1
                       from public.tracker_shares s
                      where s.tracker_id = t.id
                        and s.user_id = (select auth.uid())
                   )
             )
           )
  );
$$;

-- Reading is the whole test: with no guest branch there is nobody who may see a
-- tracker without being in the household that owns it, and everyone in the
-- household may tick one off.
create or replace function private.can_write_tracker(p_tracker_id uuid)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select private.can_read_tracker(p_tracker_id);
$$;

-- **The grant is not optional here, unlike in `public`.** A new function is
-- created with EXECUTE for PUBLIC and nothing else, and the seventeen helpers
-- next door only kept `authenticated` because they were *moved* into this
-- schema carrying the explicit grants Supabase had given them in `public`.
-- Revoking PUBLIC without granting `authenticated` back would leave every
-- tracker policy evaluating a function the querying role may not execute, and
-- take the whole feature down with a permission error. This reproduces exactly
-- the ACL `private.can_read_task` has.
revoke all on function private.can_read_tracker(uuid)  from public, anon;
revoke all on function private.can_write_tracker(uuid) from public, anon;
grant execute on function private.can_read_tracker(uuid)  to authenticated, service_role;
grant execute on function private.can_write_tracker(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.trackers       enable row level security;
alter table public.tracker_shares enable row level security;
alter table public.tracker_checks enable row level security;

create policy "trackers_select" on public.trackers for select to authenticated
  using (private.can_read_tracker(id));

create policy "trackers_insert" on public.trackers for insert to authenticated
  with check (
    family_id = private.my_family_id()
    and owner_id = (select auth.uid())
  );

-- Editing somebody else's tracker is normal family behaviour and stays allowed;
-- enforce_container_ownership still keeps visibility, ownership and household
-- out of reach for everyone but the owner.
create policy "trackers_update" on public.trackers for update to authenticated
  using (private.can_write_tracker(id))
  with check (private.can_write_tracker(id));

create policy "trackers_delete" on public.trackers for delete to authenticated
  using (
    private.can_read_tracker(id)
    and (
      owner_id = (select auth.uid())
      or (private.is_admin() and family_id = private.my_family_id())
    )
  );

create policy "tracker_shares_select" on public.tracker_shares for select to authenticated
  using (private.can_read_tracker(tracker_id));

create policy "tracker_shares_insert" on public.tracker_shares for insert to authenticated
  with check (
    exists (select 1 from public.trackers t where t.id = tracker_id and t.owner_id = (select auth.uid()))
  );

create policy "tracker_shares_delete" on public.tracker_shares for delete to authenticated
  using (
    exists (select 1 from public.trackers t where t.id = tracker_id and t.owner_id = (select auth.uid()))
  );

create policy "tracker_checks_select" on public.tracker_checks for select to authenticated
  using (private.can_read_tracker(tracker_id));

-- Ticking is yours to do and nobody else's to do for you: `done_by` is who
-- carried it out, and a row claiming somebody else did the washing-up would
-- make the record worthless.
create policy "tracker_checks_insert" on public.tracker_checks for insert to authenticated
  with check (
    private.can_write_tracker(tracker_id)
    and done_by = (select auth.uid())
    and family_id = private.my_family_id()
  );

-- Deleting is not restricted to the ticker. Somebody ticking the wrong tracker
-- at breakfast and a parent undoing it an hour later is the ordinary case, and
-- the row carries no information worth defending that hard.
create policy "tracker_checks_delete" on public.tracker_checks for delete to authenticated
  using (private.can_write_tracker(tracker_id));

-- ---------------------------------------------------------------------------
-- Member removal
--
-- A new container table has to be named here or it is stranded the first time
-- somebody leaves: a `private` tracker whose owner is gone can never be read by
-- anyone again, and a family-visible one would keep pointing at a user who is
-- no longer in the household. Same two rules as the other four — private
-- content goes with its owner, shared content is handed to an admin.
--
-- `create or replace` keeps the OID, so the trigger and the revoked grants from
-- 20260803100900 both survive untouched.
-- ---------------------------------------------------------------------------
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
  delete from public.trackers
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
    update public.trackers  set owner_id = v_admin
     where family_id = old.family_id and owner_id = old.user_id;
    update public.calendars set owner_id = v_admin
     where family_id = old.family_id and owner_id = old.user_id;
  end if;

  return old;
end;
$$;
