-- Spend tracking — Apple Pay transactions captured on the device, plus whatever
-- the household types in by hand.
--
-- Two tables and one rule. `spends` is the record; `spend_ingest_devices` is how
-- a phone proves it may write to it with nobody signed in.
--
-- **Admin only.** Unlike lists, boxes and tasks there is no `visibility` column
-- and no `spend_shares` table: a spend row is not a container anybody can own a
-- private copy of, it is the household's money. The permission matrix in
-- docs/backend.md pencilled Finanzen in as admin + member; this ships admin-only
-- because that is the smaller promise to walk back. Widening it later is one
-- `or private.my_role() = 'member'` in four policies.
--
-- `shareable_kind` still names no value for a spend, so none of this can be
-- shared outward. That was already a structural guarantee and stays one.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- The curated category set. An enum rather than free text because the app draws
-- an icon and a colour per category, and a typo'd string would render as a hole
-- in the chart. There is deliberately no 'uncategorised': a merchant we cannot
-- place is 'other', which is a real answer and shows up honestly in the ring.
--
-- Adding a value here means a migration, which is the point — the set is small
-- on purpose and every member of it has to earn its slice of the donut.
create type public.spend_category as enum (
  'groceries',     -- Supermarkt
  'drugstore',     -- Drogerie
  'fuel',          -- Tankstelle
  'restaurant',    -- Restaurant, Imbiss, Lieferdienst
  'cafe',          -- Bäckerei, Café
  'shipping',      -- Post, Paketdienst
  'clothing',      -- Kleidung
  'shopping',      -- allgemeiner Handel, Online-Marktplatz
  'electronics',   -- Elektronik
  'transport',     -- Bahn, Flug, Taxi, ÖPNV
  'entertainment', -- Streaming, Kino, Spiele
  'health',        -- Apotheke, Arzt, Optiker
  'home',          -- Möbel, Baumarkt
  'other'
);

-- Where the row came from. This is not decoration: a 'wallet' row was written
-- by a device token with no session behind it, so it is the one kind that can
-- arrive incomplete (see `needs_review`), and the one kind the user did not
-- consciously confirm.
create type public.spend_source as enum ('wallet', 'manual');

-- Planned spend the household expects every month, versus everything else.
-- Carried from the old web app's BG/EX split, spelled out. There is no budget
-- feature to compare against yet; this is what will make one possible without a
-- backfill.
create type public.spend_kind as enum ('budget', 'extra');

-- ---------------------------------------------------------------------------
-- The record
-- ---------------------------------------------------------------------------

create table public.spends (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null references public.families (id) on delete cascade,

  -- Who paid. Set from the enrolled device's owner for a wallet row and from
  -- the session for a manual one, so "wo gibt Lea das Geld aus" is answerable
  -- without a second axis. `on delete set null` rather than cascade: a member
  -- leaving the household must not silently delete the household's spending
  -- history, which is the opposite of how `reassign_content_on_member_removal`
  -- treats a private list. Money that was spent stays spent.
  payer_id     uuid references auth.users (id) on delete set null,

  merchant     text not null check (length(trim(merchant)) between 1 and 200),

  -- Integer cents, always positive — the row's existence is what makes it a
  -- spend, and a sign would only invite a refund to be modelled as a negative
  -- spend rather than as the separate thing it is. The old web app kept this as
  -- `text` and documented that one mis-mapped Shortcut field could make the
  -- whole family's view throw; there is no parse here to throw.
  amount_cents bigint not null check (amount_cents >= 0),
  currency     text not null default 'EUR' check (currency ~ '^[A-Z]{3}$'),

  occurred_at  timestamptz not null,

  -- No default, and filled by `spends_classify` when the writer leaves it null.
  -- A BEFORE INSERT trigger runs ahead of the NOT NULL check, so "omit it and
  -- the database decides" and "set it and the database keeps out of it" are both
  -- expressible in the same column. That is what keeps the merchant rules in one
  -- place instead of one copy in the ingest function and another in Dart.
  category     public.spend_category not null,
  kind         public.spend_kind not null,
  source       public.spend_source not null,

  -- What the Wallet automation reported the card as ("Sparkasse", "Apple Card").
  -- Display only, and never the number: the Transaction trigger does not hand
  -- one over and we would not keep it if it did.
  card_label   text check (card_label is null or length(card_label) <= 120),
  note         text check (note is null or length(note) <= 500),

  -- Apple's own Transaction trigger sometimes hands a custom App Intent an empty
  -- merchant or an amount of zero — reported to DTS, unresolved as of now. A row
  -- that arrives that way is kept and flagged rather than dropped, because the
  -- user cannot see what was rejected and the payment really happened. The Spend
  -- page surfaces these for a two-second fix.
  needs_review boolean not null default false,

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  -- Lets a future child row hang off (id, family_id) the way box_shares does,
  -- without restating the tenant.
  unique (id, family_id)
);

-- Every query the Spend page makes is "this household, this month", newest
-- first. One index answers all of them.
create index spends_family_occurred_idx
  on public.spends (family_id, occurred_at desc);

create trigger spends_touch_updated_at
  before update on public.spends
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------------
-- Naming the category, in exactly one place
-- ---------------------------------------------------------------------------

-- Merchant name in, category out. Ported from the old web app's
-- `SPEND_CATEGORIES` patterns, which a German household tuned against its own
-- receipts over a couple of years — that tuning is the value here, not the
-- regex.
--
-- **Why SQL and not Dart or TypeScript.** Two paths write a spend: the ingest
-- function, running as service_role with no app code near it, and the Flutter
-- client inserting a row the user typed. A copy of these rules in each would be
-- two copies that drift, and the drift would show up as the same shop landing in
-- different slices of the same pie chart depending on how it got there. The
-- database is the one place both paths already pass through.
--
-- First match wins and the order is deliberate: several patterns are short
-- enough to collide (`dm`, `bp`, `hit`, `db`), so the broad everyday categories
-- are asked first. Postgres word boundaries are `\y`, not `\b` — `\b` is a
-- backspace character here and would silently match nothing.
create function private.classify_merchant(p_merchant text)
returns public.spend_category
language sql
immutable
set search_path = ''
as $$
  select case
    when p_merchant is null or trim(p_merchant) = '' then 'other'::public.spend_category

    when p_merchant ~* '^(rewe|lidl|aldi|edeka|netto|penny|kaufland|tegut|globus|metro|billa|norma)'
      or p_merchant ~* '(marktkauf|supermarkt|lebensmittel|inkoop)'
      or p_merchant ~* '\y(spar|hit)\y'                          then 'groceries'

    when p_merchant ~* '(rossmann|budni|m.ller|mueller)'
      or p_merchant ~* '\y(dm|pens)\y'                           then 'drugstore'

    when p_merchant ~* '(tankstelle|benzin|tanken)'
      or p_merchant ~* '\y(aral|total|shell|esso|bp|q1|jet|agip)\y' then 'fuel'

    when p_merchant ~* '(mcdonald|burger.?king|subway|pizza|d.ner|kebab|sushi|restaurant|bistro|imbiss|lieferando|wolt|uber.?eat|domino)'
      or p_merchant ~* '\ykfc\y'                                 then 'restaurant'

    when p_merchant ~* '(starbucks|mccafe|backwerk|b.cker|konditorei|cafe|kaffee)'
      or p_merchant ~* '\ycosta\y'                               then 'cafe'

    when p_merchant ~* '(hermes|deutsche.?post)'
      or p_merchant ~* '\y(dhl|ups|gls|fedex|dpd)\y'             then 'shipping'

    when p_merchant ~* '(primark|about.?you|bonprix|shein|uniqlo|peek.und.cloppenburg|takko|new.?yorker|vero.?moda|jack.?jones|s\.oliver|ernsting)'
      or p_merchant ~* '\y(zara|h&m|hm|c&a|p&c|kik|mango)\y'     then 'clothing'

    when p_merchant ~* '(amazon|zalando|temu)'
      or p_merchant ~* '\y(otto|ebay)\y'                         then 'shopping'

    when p_merchant ~* '(saturn|media.?markt|cyberport|notebooksb)'
      or p_merchant ~* '\ydyson\y'                               then 'electronics'

    when p_merchant ~* '(deutsche.?bahn|flixbus|ryanair|lufthansa|easyjet)'
      or p_merchant ~* '\y(db|bvg|mvg|mvv|uber|lyft|taxi)\y'     then 'transport'

    when p_merchant ~* '(netflix|spotify|disney|kino|cinema|theater|dazn|prime.?video|apple.?tv)'
      or p_merchant ~* '\y(steam|sky)\y'                         then 'entertainment'

    when p_merchant ~* '(apotheke|pharmacy|zahnarzt|optiker|doctolib|gesundheit)'
      or p_merchant ~* '\yasa\y'                                 then 'health'

    when p_merchant ~* '(h.ffner|segm.ller|wayfair|home24|westwing|m.max)'
      or p_merchant ~* '\y(ikea|roller|poco|xxxl|porta|bauhaus)\y' then 'home'

    else 'other'
  end;
$$;

-- `anon` and `public` lose it; `authenticated` keeps EXECUTE, and has to.
-- `spends_classify` is not SECURITY DEFINER, so the call inside it is evaluated
-- as the role doing the insert — revoking it there would make every manual
-- entry fail with a permission error on a function the user never named. Living
-- in `private` is what keeps this off the API, exactly as it does for
-- `private.is_admin()`; the grant is not what was protecting it.
revoke all on function private.classify_merchant(text) from public, anon;

-- Fills in what the writer left out, on insert only.
--
-- On insert only, because re-classifying on update would undo the user's own
-- correction the moment they fixed anything else about the row — which is
-- exactly the row they are most likely to be editing.
--
-- `kind` follows the category: the things a household buys every month
-- regardless are Budget, and everything else is Extra. It is a starting guess
-- the user can change, not a verdict.
create function public.spends_classify()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.category is null then
    new.category := private.classify_merchant(new.merchant);
  end if;

  if new.kind is null then
    new.kind := case new.category
      when 'groceries' then 'budget'
      when 'drugstore' then 'budget'
      when 'fuel'      then 'budget'
      when 'shipping'  then 'budget'
      when 'transport' then 'budget'
      when 'health'    then 'budget'
      else 'extra'
    end::public.spend_kind;
  end if;

  return new;
end;
$$;

-- PostgreSQL does not check EXECUTE when firing a trigger, so revoking costs
-- nothing and takes the function off `/rest/v1/rpc/`. Same treatment as every
-- other trigger function here — see
-- `20260803100900_harden_function_grants.sql`.
revoke all on function public.spends_classify() from public, anon, authenticated;

create trigger spends_classify
  before insert on public.spends
  for each row execute function public.spends_classify();

-- ---------------------------------------------------------------------------
-- How a phone writes with nobody signed in
-- ---------------------------------------------------------------------------

-- An Apple Pay automation fires in the background with no session, so the App
-- Intent cannot present a user JWT. It presents a per-device token instead,
-- minted by `spend-enroll` and kept in the device Keychain where the user never
-- sees it.
--
-- Per *device*, not per family. The old web app had one `families.ingest_token`
-- that the user copied and pasted into the Shortcut, which meant it could be
-- read by anyone who could see a clipboard, identified no particular person, and
-- could only be rotated for the whole household at once. This one stamps the
-- payer for free and is revoked one phone at a time.
create table public.spend_ingest_devices (
  id           uuid primary key default gen_random_uuid(),
  family_id    uuid not null references public.families (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade,

  -- SHA-256 of the token, never the token. Same contract as `family_invites`
  -- and `share_links`: the raw value is handed back exactly once, at enrolment,
  -- and a dump of this table yields nothing that can write.
  token_hash   text not null unique,

  -- "Philipes iPhone" — whatever the device calls itself, so the revoke list in
  -- Settings names something the user recognises.
  label        text not null check (length(trim(label)) between 1 and 120),

  -- iOS `identifierForVendor`, which is stable for this vendor on this device
  -- and resets when the app is deleted. It is what makes re-enrolment *replace*
  -- rather than accumulate: without it, every reinstall would leave a second
  -- working token behind a row nobody recognises in the revoke list.
  device_uid   text not null check (length(trim(device_uid)) between 1 and 200),

  created_at   timestamptz not null default now(),
  last_used_at timestamptz,
  revoked_at   timestamptz,

  -- One row per phone per person. `spend-enroll` rotates this row's hash instead
  -- of inserting beside it.
  unique (user_id, device_uid),

  -- Enrolment dies with the membership, no cleanup code.
  foreign key (family_id, user_id)
    references public.family_members (family_id, user_id) on delete cascade
);

create index spend_ingest_devices_family_idx
  on public.spend_ingest_devices (family_id);

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.spends               enable row level security;
alter table public.spend_ingest_devices enable row level security;

-- Read: an admin of the owning household. There is no guest branch, and adding
-- one would be a security decision — a spend row is the one kind of content in
-- this schema that names what the household buys and when it is out of the
-- house.
create policy "spends_select" on public.spends for select to authenticated
  using (family_id = private.my_family_id() and private.is_admin());

-- Write: same gate, plus the row must be stamped with the writer. `payer_id` is
-- free to name another member — one parent entering what the other spent in
-- cash is the normal case — so it is not pinned to auth.uid().
--
-- Unlike lists/boxes/tasks this SELECT policy reads only the row's own columns
-- and session state, so `insert ... returning` would in fact work here. The
-- client still generates the id, to match how every other write in the app is
-- shaped and so an optimistic row can be reconciled by id.
create policy "spends_insert" on public.spends for insert to authenticated
  with check (family_id = private.my_family_id() and private.is_admin());

create policy "spends_update" on public.spends for update to authenticated
  using (family_id = private.my_family_id() and private.is_admin())
  with check (family_id = private.my_family_id() and private.is_admin());

create policy "spends_delete" on public.spends for delete to authenticated
  using (family_id = private.my_family_id() and private.is_admin());

-- The device list is readable by the admin whose household it is, so Settings
-- can show "Diese Geräte erfassen Ausgaben" and revoke one.
create policy "spend_ingest_devices_select" on public.spend_ingest_devices
  for select to authenticated
  using (family_id = private.my_family_id() and private.is_admin());

-- Revoking is the only client-side write, and it is the only column that moves:
-- no INSERT policy exists at all, because a device row may only be created by
-- `spend-enroll` after it has minted a token nobody else has seen. Same shape as
-- `share_links`, and the same reason.
create policy "spend_ingest_devices_revoke" on public.spend_ingest_devices
  for update to authenticated
  using (family_id = private.my_family_id() and private.is_admin())
  with check (family_id = private.my_family_id() and private.is_admin());

-- `token_hash` is never selectable, so a compromised session cannot read back
-- even the hash to attack offline. Nor is the whole table writable: an UPDATE
-- grant on it would let an admin move a device to another household or rewrite
-- its hash, so only `revoked_at` and `label` may move. The Edge Functions run as
-- service_role and are unaffected by all of this.
--
-- **`revoke all` first, then grant the columns back.** A column-level
-- `revoke select (token_hash)` does nothing while a table-level SELECT grant
-- stands — and every table born in `public` gets one from Supabase's default
-- privileges, so the column revoke on its own would have silently left the
-- hashes readable. This is the same shape `share_links` uses, for the same
-- reason.
revoke all on public.spend_ingest_devices from authenticated, anon;

grant select (
  id, family_id, user_id, label, device_uid, created_at, last_used_at, revoked_at
) on public.spend_ingest_devices to authenticated;

grant update (revoked_at, label) on public.spend_ingest_devices to authenticated;

-- `anon` keeps no table privileges anywhere in `public` — see
-- `20260804180000_harden_item_authorship_and_anon_grants.sql`. Spend rows are
-- the last thing that should be the exception.
revoke all on public.spends from anon;

-- There is deliberately **no** token-lookup RPC to go with this table.
--
-- `spend-ingest` runs as service_role, which bypasses RLS, so it resolves a
-- token by selecting `spend_ingest_devices` directly. A SECURITY DEFINER
-- function would have added a second privileged path to the same rows and, had
-- it been put in `public` to make PostgREST able to call it, would have been
-- reachable as `/rest/v1/rpc/<name>` by anyone holding the publishable key —
-- taking a guessable-shaped argument and answering with a family id. The
-- unlocked index on `token_hash` is what makes the direct lookup cheap.
