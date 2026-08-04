-- Aporah backend — RLS for the identity tables.
--
-- Conventions used by every policy in this project:
--
--   * `to authenticated` on everything, so anonymous requests are rejected
--     before the predicate is even evaluated. Nothing in Aporah is public.
--   * `(select auth.uid())` rather than bare `auth.uid()`. The subselect form is
--     hoisted into an InitPlan and evaluated once per statement instead of once
--     per row — the single biggest RLS performance factor at this scale.
--   * One policy per command. `for all` would force read and write rules to
--     share a predicate, and here they deliberately differ.
--
-- Note: RLS is ENABLEd but not FORCEd. Forcing would apply these policies to
-- the table owner too, which would break the signup trigger and every
-- service_role Edge Function — precisely the paths that are supposed to be
-- privileged. Bypass is restricted to postgres/service_role, which never ship
-- in the app binary.

alter table public.families       enable row level security;
alter table public.profiles       enable row level security;
alter table public.family_members enable row level security;
alter table public.family_invites enable row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

create policy "profiles_select_visible"
  on public.profiles for select to authenticated
  using (public.can_see_profile(id));

create policy "profiles_update_own"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- No insert or delete policy: profiles are created by handle_new_user and
-- removed by the cascade from auth.users. There is no legitimate client path.

-- ---------------------------------------------------------------------------
-- families
-- ---------------------------------------------------------------------------

create policy "families_select_own_household"
  on public.families for select to authenticated
  using (id = public.my_family_id());

-- Renaming the household, setting the address, finishing onboarding.
create policy "families_update_admin"
  on public.families for update to authenticated
  using (id = public.my_family_id() and public.is_admin())
  with check (id = public.my_family_id() and public.is_admin());

-- No insert policy: households are created by handle_new_user (signup) and by
-- rehome_removed_member. No delete policy: dissolution happens in the
-- accept-invite Edge Function, which needs to bypass RLS anyway.

-- ---------------------------------------------------------------------------
-- family_members
-- ---------------------------------------------------------------------------

-- Everyone in the household sees the roster — the "who" pickers, avatars and
-- assignment chips are built on it.
create policy "family_members_select_own_household"
  on public.family_members for select to authenticated
  using (family_id = public.my_family_id());

-- Role changes. enforce_last_admin and enforce_membership_immutable constrain
-- what an admin can actually do; this policy only decides who may try.
create policy "family_members_update_admin"
  on public.family_members for update to authenticated
  using (family_id = public.my_family_id() and public.is_admin())
  with check (family_id = public.my_family_id() and public.is_admin());

-- Removing someone else. Self-removal is excluded on purpose: leaving a
-- household is a different operation (it has to land you somewhere), and
-- rehome_removed_member handles the person being removed, not the remover.
create policy "family_members_delete_admin"
  on public.family_members for delete to authenticated
  using (
    family_id = public.my_family_id()
    and public.is_admin()
    and user_id <> (select auth.uid())
  );

-- No insert policy. Joining a household only ever happens through the
-- accept-invite Edge Function, which verifies a token the client cannot forge.
-- A client-side insert here would let anyone add themselves to any household.

-- ---------------------------------------------------------------------------
-- family_invites
-- ---------------------------------------------------------------------------

create policy "family_invites_select_admin"
  on public.family_invites for select to authenticated
  using (family_id = public.my_family_id() and public.is_admin());

create policy "family_invites_update_admin"
  on public.family_invites for update to authenticated
  using (family_id = public.my_family_id() and public.is_admin())
  with check (family_id = public.my_family_id() and public.is_admin());

create policy "family_invites_delete_admin"
  on public.family_invites for delete to authenticated
  using (family_id = public.my_family_id() and public.is_admin());

-- Column privileges, layered under RLS. RLS decides which *rows* an admin
-- reaches; these decide which *columns*.
--
-- token_hash is excluded from select entirely: an admin has no reason to read
-- it, and a leaked hash plus a weak token generator is a way into someone
-- else's household. Updates are narrowed to `status`, so "revoke this invite"
-- is expressible while re-pointing an invite at another household or role is
-- not.
revoke all on public.family_invites from authenticated;

grant select (
  id, family_id, email, name, role, status,
  invited_by, created_at, expires_at, accepted_at, accepted_by
) on public.family_invites to authenticated;

grant update (status) on public.family_invites to authenticated;
grant delete on public.family_invites to authenticated;
