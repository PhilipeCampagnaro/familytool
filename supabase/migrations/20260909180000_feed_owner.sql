-- Whose day a Ferien or Abfall feed belongs to.
--
-- `calendars.owner_member_id` / `owner_label` already answer this for every
-- connected calendar, and Kalender's chip row is built from the answer. A
-- subscribed feed had no such pair, so it was pinned to the family chip in code
-- — `calendar-events` wrote `group_id: FAMILY_GROUP` for every one of them.
--
-- That was a guess about how households live, and the wrong one often enough to
-- be worth undoing. A Schulferien feed is the *schoolchild's* year, and a
-- household with one child at school and a toddler at home reads it as hers;
-- Papa is the one who puts the bins out on Thursday, and the family that says so
-- gets a bin day on his chip rather than one more row under "Familie". The
-- default is unchanged — both null is still the household, which is what every
-- existing subscription keeps.
--
-- **Not visibility.** Same rule as `calendars`: everybody in the household sees
-- every feed, before and after this. It only says whose chip it sits under. And
-- it is written on *this household's subscription*, never on the shared
-- `public_feeds` row — a hundred families read that row, and filing the bins
-- under Papa must not file them under Papa for the whole street.
alter table public.family_feeds
  add column owner_member_id uuid references auth.users (id) on delete set null,
  add column owner_label     text check (owner_label is null or length(trim(owner_label)) between 1 and 60);

comment on column public.family_feeds.owner_member_id is
  'Whose day this feed belongs to — NOT who may see it. Null with owner_label null means the whole household.';
comment on column public.family_feeds.owner_label is
  'The person this feed belongs to when they have no account. See calendars.owner_label.';

-- The grants on this table are column-level, so a new column is unreadable and
-- unwritable until it is named here. The row's policies already decide who may
-- touch it at all: reading is the household, writing is the household minus the
-- kids, and neither changes.
grant select (owner_member_id, owner_label),
      update (owner_member_id, owner_label)
   on public.family_feeds
   to authenticated;
