-- Aporah backend — Abfall coverage requests: the address no vendor of ours serves yet.
--
-- The onboarding address step and the Abfall connect flow both used to end, for
-- a town outside the six vendor families, in "für diese Adresse nicht gefunden"
-- and nothing to do about it. This table turns that dead end into a queue: one
-- tap files the town, and the vendor map is grown from what households actually
-- asked for rather than from a list of big cities we guessed at.
--
-- **No street and no house number.** A vendor is found per municipality — a
-- Landkreis, a Stadt — so the town and its postcode are all the work needs. The
-- household's street already lives on `families.address` and is not copied here.
--
-- **`authenticated` holds no INSERT grant**, the same lock `list_plan_runs` and
-- `spend_ingest_devices` use: only `abfall-lookup`, running as service_role,
-- writes a row, after checking the caller belongs to a household. The household
-- can read its own rows, so the screen says "angefragt" on the next visit rather
-- than offering the button twice; `status` is ours to move and nobody else's.

create table public.abfall_requests (
  id                uuid primary key default gen_random_uuid(),
  family_id         uuid not null references public.families (id) on delete cascade,
  -- Set null rather than cascade: the town is still waiting for its vendor
  -- when the person who asked leaves the household.
  created_by        uuid references auth.users (id) on delete set null,
  created_at        timestamptz not null default now(),
  town              text not null check (length(trim(town)) between 1 and 120),
  postcode          text check (postcode is null or postcode ~ '^[0-9]{5}$'),
  -- Two-letter Bundesland code where the geocoder knew it. Grouping only.
  state             text check (state is null or state ~ '^[A-Z]{2}$'),
  status            text not null default 'open'
                    check (status in ('open', 'done', 'declined')),
  -- Filled in by hand when the vendor ships: the provider id from
  -- abfall_providers.ts, and when. A row moves to 'done' at the same time.
  resolved_provider text check (resolved_provider is null or length(resolved_provider) <= 80),
  resolved_at       timestamptz
);

-- One row per household and town: tapping "Anfragen" twice, or from both the
-- onboarding and the connect flow, is one request. A postcode the geocoder did
-- not know folds to '' so the index still holds.
create unique index abfall_requests_family_town_idx
  on public.abfall_requests (family_id, lower(town), coalesce(postcode, ''));

-- The queue as we read it: open ones, oldest first.
create index abfall_requests_status_idx on public.abfall_requests (status, created_at);

alter table public.abfall_requests enable row level security;

create policy "abfall_requests_select" on public.abfall_requests for select to authenticated
  using (family_id = private.my_family_id());

-- `revoke all` first: every table born in `public` gets full privileges from
-- Supabase's default grants, and the missing grant refuses an INSERT regardless
-- of what policies come later.
revoke all on public.abfall_requests from authenticated, anon;
grant select on public.abfall_requests to authenticated;
