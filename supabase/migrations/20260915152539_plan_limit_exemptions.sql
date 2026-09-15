-- Accounts whose requests may lift the Vorhaben limits, for testing.
--
-- The app's debug switch only *asks* (`ignoreLimits` in the request body);
-- `list-plan` honours it for a caller listed here and ignores it from anybody
-- else. So the switch in a patched build is worth nothing, and the list is
-- edited by hand in the SQL editor, never from a client.
--
-- No policies and no grants: RLS on, `anon` and `authenticated` revoked, so the
-- table does not exist as far as PostgREST is concerned. Only `service_role`
-- (the function) reads it.
create table public.plan_limit_exemptions (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  note       text,
  created_at timestamptz not null default now()
);

alter table public.plan_limit_exemptions enable row level security;

revoke all on public.plan_limit_exemptions from anon, authenticated;
