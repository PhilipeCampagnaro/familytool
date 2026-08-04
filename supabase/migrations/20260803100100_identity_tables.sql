-- Aporah backend — identity: households, profiles, membership, invites.
--
-- Every user belongs to exactly one household, always. A household is created
-- for them at signup (see handle_new_user in the next migration), and accepting
-- an invite dissolves their own household rather than adding a second one. That
-- invariant is enforced by `family_members_one_household` below, not by
-- application code.

create table public.families (
  id              uuid primary key default gen_random_uuid(),
  name            text not null check (length(trim(name)) between 1 and 80),
  -- Street address, used to resolve the Abfall (waste collection) calendar.
  address         text,
  onboarding_done boolean not null default false,
  created_by      uuid references auth.users (id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (length(trim(display_name)) between 1 and 80),
  -- Two letters shown in the avatar circle when there is no picture ("AR").
  initials     text not null check (length(initials) between 1 and 2),
  -- Index into AppTones.list (lib/theme/tokens.dart) — five avatar colours.
  tone         smallint not null default 0 check (tone between 0 and 4),
  avatar_url   text,
  language     text not null default 'de' check (language in ('de', 'en')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create table public.family_members (
  family_id uuid not null references public.families (id) on delete cascade,
  user_id   uuid not null references auth.users (id) on delete cascade,
  role      public.member_role not null default 'member',
  joined_at timestamptz not null default now(),

  primary key (family_id, user_id),

  -- One household per user, as a database fact rather than a convention. This
  -- is what makes public.my_family_id() single-valued, which in turn lets every
  -- content policy compare `family_id = my_family_id()` instead of running an
  -- EXISTS subquery per row.
  --
  -- Relaxing this later (separated parents, grandparents across two homes)
  -- means dropping this constraint and revisiting my_family_id() — family_id is
  -- already carried on every content row, so nothing else has to move.
  constraint family_members_one_household unique (user_id)
);

create table public.family_invites (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references public.families (id) on delete cascade,
  email       text not null check (position('@' in email) > 1),
  name        text,
  role        public.member_role not null default 'member',
  -- Only ever the hash. The raw token is returned once, by the invite-member
  -- Edge Function, and is never stored or readable afterwards.
  token_hash  text not null unique,
  status      text not null default 'pending'
                check (status in ('pending', 'accepted', 'revoked', 'expired')),
  invited_by  uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '14 days',
  accepted_at timestamptz,
  accepted_by uuid references auth.users (id) on delete set null
);

-- At most one live invite per address per household; re-inviting after a
-- revoke or an acceptance stays possible.
create unique index family_invites_one_pending_per_email
  on public.family_invites (family_id, lower(email))
  where status = 'pending';

create index family_invites_family_id_idx on public.family_invites (family_id);
create index families_created_by_idx on public.families (created_by);

-- family_members(user_id) is already covered by family_members_one_household.
