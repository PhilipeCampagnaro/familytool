-- Demo spending for one household, so the Ausgaben page can be looked at with a
-- month in it. Six months ending with the current one, which stops at today.
--
-- `category` and `kind` are deliberately left out of the column list. Leaving
-- them null is how the `spends_classify` BEFORE INSERT trigger gets to do its
-- job, so this also shows honestly what the classifier makes of these merchant
-- names rather than what we wish it made of them.
--
-- Nothing here is a migration and nothing runs it automatically: it is a file
-- you point `supabase db query --linked --file` at when you want to look at the
-- page with a month in it. Run it twice and you get two months of shopping.
--
-- To take it all out again, every spend of the household, seeded or not:
--   delete from public.spends
--   where family_id = (select id from public.families order by created_at limit 1);

with household as (
  -- Whose money this is. The first household and its admin, because that is who
  -- the page is for — spends are admin-only and there is no second tenant here
  -- to disambiguate against.
  select f.id as family_id, m.user_id as payer_id
  from public.families f
  join public.family_members m on m.family_id = f.id and m.role = 'admin'
  order by f.created_at, m.joined_at
  limit 1
),
months as (
  select
    d::date                                                            as first_day,
    least((d + interval '1 month' - interval '1 day')::date, current_date) as last_day,
    row_number() over (order by d) - 1                                 as idx
  from generate_series(
         date_trunc('month', current_date) - interval '5 months',
         date_trunc('month', current_date),
         interval '1 month') d
),
-- merchant, times a month, cents low, cents high, share typed in by hand
catalog (merchant, per_month, lo, hi, manual_share) as (values
  ('REWE City 4471',    6, 1800,  7400, 0.10),
  ('EDEKA Neukauf',     3, 2400,  8900, 0.10),
  ('ALDI SÜD',          3, 1500,  5200, 0.10),
  ('LIDL',              2, 1900,  6100, 0.10),
  ('Kaufland',          1, 4200,  9800, 0.10),
  ('dm-drogerie markt', 2,  900,  3800, 0.15),
  ('Rossmann',          1, 1100,  3200, 0.15),
  ('Shell Tankstelle',  2, 5200,  8600, 0.05),
  ('Aral',              1, 4800,  7900, 0.05),
  ('Bäckerei Kamps',    4,  320,  1450, 0.25),
  ('Starbucks',         1,  480,  1120, 0.20),
  ('Dönerhaus Ali',     2,  850,  2400, 0.30),
  ('L''Osteria',        1, 3400,  8700, 0.30),
  ('Lieferando',        2, 1900,  4600, 0.10),
  ('Amazon.de',         4, 1100, 12900, 0.05),
  ('Zalando SE',        1, 3900, 15400, 0.05),
  ('H&M',               1, 2400,  8900, 0.20),
  ('Netflix',           1, 1799,  1799, 0.00),
  ('Spotify AB',        1, 1099,  1099, 0.00),
  ('Deutsche Bahn',     1, 1590,  8900, 0.20),
  ('Apotheke am Markt', 1,  780,  4200, 0.30),
  ('DHL Paketshop',     1,  490,  1890, 0.40)
),
slots as (
  select c.*, m.first_day, m.last_day, m.idx,
         (m.last_day - m.first_day + 1) as days
  from catalog c cross join months m
),
draws as (
  -- A part-finished month gets a part-month's worth of rows, so the current
  -- total is not flattered by a full month of shopping done in eleven days.
  select s.*
  from slots s
  cross join lateral generate_series(1, greatest(1, round(s.per_month * s.days / 30.0))::int) g
)
insert into public.spends
  (family_id, payer_id, merchant, amount_cents, occurred_at, source, card_label)
select
  h.family_id,
  h.payer_id,
  merchant,
  -- A subscription costs what it costs; only variable spending drifts up a few
  -- percent a month, which is what gives the "mehr als im Vormonat" line
  -- something to say.
  case when lo = hi then lo
       else round((lo + random() * (hi - lo)) * (1 + idx * 0.04))::bigint
  end,
  first_day
    + (floor(random() * days))::int * interval '1 day'
    + (8 + floor(random() * 13))::int * interval '1 hour'
    + (floor(random() * 60))::int * interval '1 minute',
  case when random() < manual_share then 'manual' else 'wallet' end::public.spend_source,
  case when random() < manual_share then null
       else (array['Sparkasse', 'DKB Visa', 'Apple Card'])[1 + floor(random() * 3)]
  end
from draws cross join household h;

-- The rows that are not a weekly rhythm: one large purchase a household makes
-- a few times a year, two the Transaction trigger handed over with a hole in
-- them, and two carrying a note.
with household as (
  select f.id as family_id, m.user_id as payer_id
  from public.families f
  join public.family_members m on m.family_id = f.id and m.role = 'admin'
  order by f.created_at, m.joined_at
  limit 1
)
insert into public.spends
  (family_id, payer_id, merchant, amount_cents, occurred_at, source, card_label, note, needs_review)
select h.family_id, h.payer_id, v.merchant, v.cents,
       date_trunc('month', current_date) - (v.months_ago || ' months')::interval
         + (v.day - 1) * interval '1 day' + interval '15 hours',
       v.source::public.spend_source, v.card, v.note, v.review
from household h, (values
  ('IKEA Deutschland',   24900, 5, 14, 'manual', null,        null,                                 false),
  ('MediaMarkt',         49900, 4,  9, 'wallet', 'Sparkasse', null,                                 false),
  ('Lufthansa',          31800, 3, 22, 'manual', null,        'Flüge Herbstferien',                 false),
  ('Bauhaus',             8740, 1,  6, 'wallet', 'DKB Visa',  null,                                 false),
  ('Zahnarzt Dr. Weber', 12400, 0,  3, 'manual', null,        null,                                 false),
  ('Amazon.de',           5990, 1, 22, 'wallet', 'Apple Card','Druckerpatronen',                    false),
  ('REWE City 4471',      8930, 0,  6, 'manual', null,        'Einkauf für das Grillen am Samstag', false),
  -- Apple's known defect: an empty merchant and a zero amount. Kept and
  -- flagged rather than dropped, which is what puts the review banner at the
  -- top of the page.
  ('Unbekannt',           3450, 0,  4, 'wallet', 'Sparkasse', null,                                 true),
  ('Unbekannt',              0, 0,  9, 'wallet', 'DKB Visa',  null,                                 true)
) as v(merchant, cents, months_ago, day, source, card, note, review)
where date_trunc('month', current_date) - (v.months_ago || ' months')::interval
        + (v.day - 1) * interval '1 day' <= current_date;
