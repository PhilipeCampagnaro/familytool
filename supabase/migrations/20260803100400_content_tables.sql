-- Aporah backend — content: Listen, Box, Board, Kalender.
--
-- Four containers (lists, boxes, tasks, calendars) share one visibility
-- contract: family_id + owner_id + visibility, plus a *_shares child table for
-- the 'custom' case. That uniformity is deliberate — it is what lets a single
-- read predicate be reused verbatim four times instead of four predicates
-- drifting apart over time.
--
-- Each container also carries `unique (id, family_id)`, which looks redundant
-- next to the primary key but is not: it is the target of the composite foreign
-- key from its share table, and that FK is what makes sharing with a
-- non-member structurally impossible.

-- ---------------------------------------------------------------------------
-- Listen
-- ---------------------------------------------------------------------------

create table public.lists (
  id         uuid primary key default gen_random_uuid(),
  family_id  uuid not null references public.families (id) on delete cascade,
  name       text not null check (length(trim(name)) between 1 and 120),
  icon_asset text,
  kind       public.list_kind not null default 'other',
  -- Cascade rather than set-null: an account deletion should take its owner's
  -- content with it. Removal from a *household* is the common case and is
  -- handled far more gently, by reassign_content_on_member_removal.
  owner_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  visibility public.visibility not null default 'family',
  position   integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (id, family_id)
);

create table public.list_shares (
  list_id    uuid not null,
  family_id  uuid not null,
  user_id    uuid not null,
  created_at timestamptz not null default now(),

  primary key (list_id, user_id),
  foreign key (list_id, family_id) references public.lists (id, family_id) on delete cascade,
  -- Sharing internally with someone who is not in the household is not
  -- "validated against" — it cannot be represented. Removing a member also
  -- deletes their shares, with no cleanup code involved.
  foreign key (family_id, user_id) references public.family_members (family_id, user_id) on delete cascade
);

create table public.list_items (
  id          uuid primary key default gen_random_uuid(),
  list_id     uuid not null references public.lists (id) on delete cascade,
  text        text not null check (length(trim(text)) between 1 and 400),
  sub         text,
  icon_asset  text,
  assignee_id uuid references auth.users (id) on delete set null,
  done        boolean not null default false,
  done_by     uuid references auth.users (id) on delete set null,
  done_at     timestamptz,
  position    integer not null default 0,
  created_by  uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table public.list_item_attachments (
  id           uuid primary key default gen_random_uuid(),
  item_id      uuid not null references public.list_items (id) on delete cascade,
  storage_path text not null,
  name         text not null,
  is_image     boolean not null default false,
  created_by   uuid default auth.uid() references auth.users (id) on delete set null,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Box
-- ---------------------------------------------------------------------------

create table public.boxes (
  id         uuid primary key default gen_random_uuid(),
  family_id  uuid not null references public.families (id) on delete cascade,
  name       text not null check (length(trim(name)) between 1 and 120),
  place      text,
  tone       smallint not null default 0 check (tone between 0 and 4),
  owner_id   uuid not null default auth.uid() references auth.users (id) on delete cascade,
  visibility public.visibility not null default 'family',
  position   integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (id, family_id)
);

create table public.box_shares (
  box_id     uuid not null,
  family_id  uuid not null,
  user_id    uuid not null,
  created_at timestamptz not null default now(),

  primary key (box_id, user_id),
  foreign key (box_id, family_id) references public.boxes (id, family_id) on delete cascade,
  foreign key (family_id, user_id) references public.family_members (family_id, user_id) on delete cascade
);

create table public.box_items (
  id         uuid primary key default gen_random_uuid(),
  box_id     uuid not null references public.boxes (id) on delete cascade,
  name       text not null check (length(trim(name)) between 1 and 200),
  size       text,
  qty        integer not null default 1 check (qty > 0),
  note       text,
  position   integer not null default 0,
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Board
--
-- A Board task is both container and item — there is nothing inside it — so it
-- carries the visibility contract directly. `due_date` replaces the app's
-- current day-of-month integer, which only worked because the mock week was
-- pinned to August 2026.
-- ---------------------------------------------------------------------------

create table public.tasks (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references public.families (id) on delete cascade,
  due_date    date not null,
  text        text not null check (length(trim(text)) between 1 and 400),
  meta        text,
  assignee_id uuid references auth.users (id) on delete set null,
  done        boolean not null default false,
  done_by     uuid references auth.users (id) on delete set null,
  done_at     timestamptz,
  owner_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  visibility  public.visibility not null default 'family',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  unique (id, family_id)
);

create table public.task_shares (
  task_id    uuid not null,
  family_id  uuid not null,
  user_id    uuid not null,
  created_at timestamptz not null default now(),

  primary key (task_id, user_id),
  foreign key (task_id, family_id) references public.tasks (id, family_id) on delete cascade,
  foreign key (family_id, user_id) references public.family_members (family_id, user_id) on delete cascade
);

-- ---------------------------------------------------------------------------
-- Kalender
--
-- Visibility lives on the calendar, never on the event: picking a calendar is
-- already the act of deciding who sees what. Calendars are also the one
-- container that is never externally shareable — see public.shareable_kind.
-- ---------------------------------------------------------------------------

create table public.calendars (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null references public.families (id) on delete cascade,
  name         text not null check (length(trim(name)) between 1 and 120),
  provider     text not null default 'aporah'
                 check (provider in ('aporah', 'google', 'icloud', 'outlook',
                                     'iserv', 'ferien', 'abfall')),
  -- ARGB, matching CalendarEvent.srcColor in the Flutter app.
  color        integer not null default 0,
  is_read_only boolean not null default false,
  external_id  text,
  owner_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  visibility   public.visibility not null default 'family',
  position     integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  unique (id, family_id)
);

create table public.calendar_shares (
  calendar_id uuid not null,
  family_id   uuid not null,
  user_id     uuid not null,
  created_at  timestamptz not null default now(),

  primary key (calendar_id, user_id),
  foreign key (calendar_id, family_id) references public.calendars (id, family_id) on delete cascade,
  foreign key (family_id, user_id) references public.family_members (family_id, user_id) on delete cascade
);

create table public.events (
  id               uuid primary key default gen_random_uuid(),
  calendar_id      uuid not null references public.calendars (id) on delete cascade,
  title            text not null check (length(trim(title)) between 1 and 300),
  starts_at        timestamptz not null,
  ends_at          timestamptz not null,
  all_day          boolean not null default false,
  location         text,
  location_sub     text,
  notes            text,
  online           boolean not null default false,
  url              text,
  reminder_minutes integer,
  -- iCalendar UID, for dedup against a synced provider.
  external_uid     text,
  created_by       uuid default auth.uid() references auth.users (id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),

  check (ends_at >= starts_at)
);

-- ---------------------------------------------------------------------------
-- Indexes
--
-- Every foreign key gets one: unindexed FKs are both a per-row RLS cost and the
-- most common finding from Supabase's performance advisor.
-- ---------------------------------------------------------------------------

create index lists_family_visibility_idx      on public.lists (family_id, visibility);
create index lists_owner_idx                  on public.lists (owner_id);
create index list_shares_user_idx             on public.list_shares (user_id);
create index list_items_list_position_idx     on public.list_items (list_id, position);
create index list_items_assignee_idx          on public.list_items (assignee_id);
create index list_item_attachments_item_idx   on public.list_item_attachments (item_id);

create index boxes_family_visibility_idx      on public.boxes (family_id, visibility);
create index boxes_owner_idx                  on public.boxes (owner_id);
create index box_shares_user_idx              on public.box_shares (user_id);
create index box_items_box_position_idx       on public.box_items (box_id, position);

create index tasks_family_due_idx             on public.tasks (family_id, due_date);
create index tasks_owner_idx                  on public.tasks (owner_id);
create index tasks_assignee_idx               on public.tasks (assignee_id);
create index task_shares_user_idx             on public.task_shares (user_id);

create index calendars_family_visibility_idx  on public.calendars (family_id, visibility);
create index calendars_owner_idx              on public.calendars (owner_id);
create index calendar_shares_user_idx         on public.calendar_shares (user_id);
create index events_calendar_starts_idx       on public.events (calendar_id, starts_at);
