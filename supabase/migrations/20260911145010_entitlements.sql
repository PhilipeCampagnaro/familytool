-- Aporah backend — the household's subscription.
--
-- **Per household, not per user.** One family pays once and every member is on
-- Plus, which is why these columns sit on `families` rather than on `profiles`:
-- the other parent must not have to buy it again, and a child's phone must not
-- be the one account that cannot see the second calendar.
--
-- **No client may write any of it, admin included.** That is the whole point of
-- this migration and it is not expressible as an RLS policy: the existing
-- `families_update_admin` policy already lets an admin update their own row, so
-- adding a `plan` column to this table would, on its own, let any admin grant
-- themselves Plus with a single PostgREST call. RLS decides *which rows* a
-- statement may touch and says nothing about which columns, so the lock is a
-- column-level grant — the same mechanism `share_links.revoked_at` and
-- `family_invites.status` already use here.
--
-- The only writer is the `store-webhook` Edge Function (Phase 4), which runs as
-- `service_role`, verifies Apple's and Google's signatures and is the one place
-- that has ever seen a receipt. Nothing in `lib/` writes these, and nothing in
-- `lib/` should ever be able to.

alter table public.families
  -- Text plus a check rather than an enum, matching `family_invites.status`:
  -- a third tier is a constraint change reviewable in the diff.
  add column plan text not null default 'free'
    check (plan in ('free', 'plus')),

  -- Which store the subscription came from, so a cancellation arriving from
  -- Apple cannot retire a Play subscription and vice versa. 'manual' is for the
  -- family and friends who are not paying and for support making something
  -- right — it is deliberately a first-class value rather than a hack, because
  -- the alternative is somebody editing `plan` by hand and leaving no record of
  -- why.
  add column plan_source text
    check (plan_source in ('app_store', 'play_store', 'manual')),

  -- When the current paid period runs out. **Not the same question as `plan`**,
  -- and both are needed: a household that cancels keeps Plus until the period
  -- ends, and a store that fails to charge a card enters a retry window during
  -- which Apple and Google both expect the subscription to keep working. The
  -- webhook moves `plan` back to 'free'; this is what the app reads to know how
  -- long it has. Null for 'manual' and for a household that has never paid.
  add column plan_expires_at timestamptz,

  -- The store's own identifier for the subscription across every renewal —
  -- Apple's `originalTransactionId`, Google's `purchaseToken` lineage. It is
  -- how a renewal notification finds the household that bought it, months after
  -- the purchase and with no session attached, and how a re-purchase is told
  -- from a restore.
  add column plan_original_txn_id text;

-- One household per store subscription, enforced rather than assumed: without
-- this, a purchase restored onto a second account would quietly entitle two
-- families off one payment. Partial, because null is the ordinary state.
create unique index families_plan_txn_unique
  on public.families (plan_original_txn_id)
  where plan_original_txn_id is not null;

-- A renewal notification arrives with a transaction id and nothing else, and
-- has to find its household by it.
create index families_plan_expires_idx
  on public.families (plan_expires_at)
  where plan_expires_at is not null;

-- ---------------------------------------------------------------------------
-- The lock
-- ---------------------------------------------------------------------------
--
-- `revoke all` then grant back exactly what the app legitimately writes. The
-- four subscription columns are absent from the update grant, so an admin
-- sending `{"plan":"plus"}` is refused by the grant before any policy is
-- consulted — `permission denied for table families`.
--
-- Select stays whole-table: every one of these columns is the household's own
-- business and the app needs to read them to draw "Plus bis 12. Oktober".
-- Nothing here is a secret; a receipt is not stored on this table.
--
-- No insert or delete grant, matching the policies: households are made by
-- `handle_new_user` and `rehome_removed_member`, and dissolved by the
-- accept-invite function — all of which run privileged and bypass this.
revoke all on public.families from authenticated;

grant select on public.families to authenticated;

-- Renaming the household, setting the address for Abfall, finishing onboarding,
-- and the household picture. Exactly what `families_update_admin` was written
-- for; the policy still decides *whose* row, this decides which columns.
--
-- **Adding a column to `families` does not add it here.** That is the intended
-- failure mode: a new column is unwritable until someone deliberately lists it.
grant update (name, address, onboarding_done, avatar_url)
  on public.families to authenticated;

comment on column public.families.plan is
  'free | plus. Written only by the store-webhook Edge Function; no client holds an update grant on this column.';
