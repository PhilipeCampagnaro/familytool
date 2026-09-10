-- ---------------------------------------------------------------------------
-- A to-do can name an hour as well as a day
--
-- `due_date` stays a `date`, on purpose. A to-do due Donnerstag is due
-- Donnerstag wherever the phone is, and turning the column into a
-- `timestamptz` to make room for a clock would drag a zone into a field that
-- deliberately has none — every existing row would acquire an hour it was
-- never given, and a family flying to Spain would watch their week move.
--
-- So the hour is its own nullable column beside it. Every to-do written before
-- this migration is simply one with no time, which is also what most of them
-- will go on being: a time is for the school run and the bin, not for
-- "Geschenk kaufen".
--
-- `time without time zone`, matching `due_date`: the pair is a local wall
-- clock reading, not an instant. `timetz` exists and is the wrong tool — it
-- fixes an offset to a value that has no date to apply it on, which is why
-- Postgres' own documentation advises against it.
--
-- **A time without a day is meaningless**, so the check refuses it. It is the
-- same shape as `tasks_event_link_complete` next door: the database, not the
-- client, is what makes a half-written row unrepresentable.
--
-- **This does not change when a to-do becomes overdue.** That stays a question
-- about the day — see `boardSectionOf`. A board that moved a row into
-- "Überfällig" at 09:01 of the day it was planned for would be nagging inside
-- the one section people actually open. The hour positions the to-do in the
-- Kalender agenda; it does not start a clock against it.
--
-- No policy touched: an additive nullable column on a table whose RLS is
-- row-shaped needs none.
-- ---------------------------------------------------------------------------

alter table public.tasks
  add column if not exists due_time time without time zone;

alter table public.tasks
  drop constraint if exists tasks_due_time_needs_date;

alter table public.tasks
  add constraint tasks_due_time_needs_date
  check (due_time is null or due_date is not null);

comment on column public.tasks.due_time is
  'Optional wall-clock hour beside due_date. Null on most rows. Does not affect overdue, which is a question about the day.';
