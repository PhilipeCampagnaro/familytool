-- Aporah backend — Vorhaben usage, one row per plan the model actually answered.
--
-- **This table exists so the Mistral key can leave the app.** The first build
-- called Mistral straight from the device with the key compiled in, where anyone
-- who unzipped the `.ipa` could read it. `list-plan` now holds the key as a
-- function secret, and a paid call behind a server needs a count the server can
-- trust — that is this table and nothing more.
--
-- **The prompt and the answer are not stored. Neither one, ever.** A household's
-- dinner plans are not ours to keep; the Liste the reader makes is the artifact.
-- A row says *that* a plan was made, by whom and at what token cost.
--
-- **`authenticated` holds no INSERT grant**, the same lock `share_links` and
-- `spend_ingest_devices` use: only `list-plan`, running as service_role, writes
-- a row, and only after the model answered — so a failed generation never counts
-- against the household and the count cannot be forged or erased from a client.

create table public.list_plan_runs (
  id                uuid primary key default gen_random_uuid(),
  family_id         uuid not null references public.families (id) on delete cascade,
  -- Set null rather than cascade: a member leaving must not hand the household
  -- its month's quota back.
  created_by        uuid references auth.users (id) on delete set null,
  created_at        timestamptz not null default now(),
  -- Cost telemetry. Null when the provider did not report usage.
  prompt_tokens     integer,
  completion_tokens integer
);

-- The two questions `list-plan` asks on every call: this household this month
-- (the plan cap) and this user today (the abuse limit).
create index list_plan_runs_family_created_idx on public.list_plan_runs (family_id, created_at);
create index list_plan_runs_user_created_idx on public.list_plan_runs (created_by, created_at);

alter table public.list_plan_runs enable row level security;

-- Readable by the household, so the screen can one day print "noch 2 diesen
-- Monat" without a second route. Nothing on the row is content.
create policy "list_plan_runs_select" on public.list_plan_runs for select to authenticated
  using (family_id = private.my_family_id());

-- `revoke all` first: every table born in `public` gets full privileges from
-- Supabase's default grants, and a policy-less INSERT is refused by RLS only as
-- long as nobody ever adds a policy. The missing grant refuses it regardless.
revoke all on public.list_plan_runs from authenticated, anon;
grant select on public.list_plan_runs to authenticated;
