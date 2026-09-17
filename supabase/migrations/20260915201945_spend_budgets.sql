-- Spending goals — "Lebensmittel: 800 € im Monat".
--
-- One row per household per category, holding a monthly amount and nothing
-- else. **How much of it is used is not stored.** It is a fold over this
-- month's `spends` rows, computed on the device for the same reason every other
-- figure on the Ausgaben page is: a stored "spent so far" is a second source of
-- truth that the next edit silently contradicts.
--
-- Monthly only, deliberately. A household thinks about groceries per month, and
-- a period column would be a second axis every screen has to ask about before
-- it can draw a ring. Adding one later is a column with a default.
--
-- Same access rule as `spends`: admin only, no guest branch, not shareable.
-- A goal says what a household expects to spend, which is the same kind of
-- information as what it did spend.

create table public.spend_budgets (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null references public.families (id) on delete cascade,
  category     public.spend_category not null,

  -- Integer cents, like `spends.amount_cents`, and never zero: a goal of
  -- nothing is not a goal, and dividing by it is how a ring draws NaN.
  amount_cents bigint not null check (amount_cents > 0),

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  -- One goal per category. Two would be two rings for one slice of the donut
  -- that disagree with each other.
  unique (family_id, category)
);

create trigger spend_budgets_touch_updated_at
  before update on public.spend_budgets
  for each row execute function public.touch_updated_at();

alter table public.spend_budgets enable row level security;

-- The SELECT policy reads only the row's own column and session state, so
-- `insert … returning` would work here as it does on `spends`. The client still
-- sends its own id, to match how every other write in the app is shaped.
create policy "spend_budgets_select" on public.spend_budgets for select to authenticated
  using (family_id = private.my_family_id() and private.is_admin());

create policy "spend_budgets_insert" on public.spend_budgets for insert to authenticated
  with check (family_id = private.my_family_id() and private.is_admin());

create policy "spend_budgets_update" on public.spend_budgets for update to authenticated
  using (family_id = private.my_family_id() and private.is_admin())
  with check (family_id = private.my_family_id() and private.is_admin());

create policy "spend_budgets_delete" on public.spend_budgets for delete to authenticated
  using (family_id = private.my_family_id() and private.is_admin());

revoke all on public.spend_budgets from anon;

-- The other admin's phone redraws its rings when a goal changes. See
-- `20260911131118_family_realtime.sql` for why this is a row trigger and why it
-- is currently dropped by the platform until `realtime.messages` has partitions.
create trigger broadcast_change
  after insert or update or delete on public.spend_budgets
  for each row execute function private.broadcast_family_change();
