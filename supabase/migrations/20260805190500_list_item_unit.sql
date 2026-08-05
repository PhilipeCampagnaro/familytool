-- An article's quantity is two things, and `sub` was holding both as one
-- string: "2 Liter" is a count and a unit. The row now renders them apart — the
-- count in the circle at the end of the line, the unit under the name — and a
-- picker writes the unit, so the two have to be stored apart as well. Splitting
-- them in Dart would mean parsing the free text back out on every read, which
-- is the kind of guess that eventually renders "Packung" inside a circle.
--
-- `unit` holds a **key**, not a word: 'piece' | 'g' | 'kg' | 'ml' | 'l' |
-- 'pack' | 'can' | 'bottle' | 'bunch' | 'glass' (see lib/models/grocery_unit.dart).
-- The app switches language live, so a stored "Liter" would stay German in an
-- English household. No check constraint on the values: an older free-text unit
-- that no key matches still has to survive a round trip and render as itself.
--
-- `null` *is* the default — an article with no unit is one of it — so 'piece'
-- is never stored.
alter table public.list_items add column if not exists unit text;

alter table public.list_items drop constraint if exists list_items_unit_length;
alter table public.list_items
  add constraint list_items_unit_length check (unit is null or length(btrim(unit)) between 1 and 40);

-- Backfill, in the order the cases exclude each other.

-- "2 Liter" -> sub '2', unit 'Liter'. Both expressions read the row as it was,
-- so the second one still sees the whole old string.
update public.list_items
   set sub  = substring(sub from '^\s*([0-9]+(?:[.,][0-9]+)?)'),
       unit = nullif(btrim(regexp_replace(sub, '^\s*[0-9]+(?:[.,][0-9]+)?\s*', '')), '')
 where sub is not null
   and sub ~ '^\s*[0-9]';

-- "Packung" with no number in front of it was never a count; it was always the
-- unit, written in the only field there was.
update public.list_items
   set unit = btrim(sub),
       sub  = null
 where sub is not null
   and btrim(sub) <> ''
   and sub !~ '^\s*[0-9]';

-- The words those two steps recovered, mapped onto the keys the app writes from
-- now on. Anything unrecognised is left exactly as it was found.
update public.list_items
   set unit = case lower(btrim(unit))
                when 'stück' then 'piece'
                when 'stueck' then 'piece'
                when 'stk' then 'piece'
                when 'stk.' then 'piece'
                when 'st' then 'piece'
                when 'pcs' then 'piece'
                when 'piece' then 'piece'
                when 'gramm' then 'g'
                when 'gr' then 'g'
                when 'g' then 'g'
                when 'kilo' then 'kg'
                when 'kilogramm' then 'kg'
                when 'kg' then 'kg'
                when 'ml' then 'ml'
                when 'liter' then 'l'
                when 'litre' then 'l'
                when 'l' then 'l'
                when 'packung' then 'pack'
                when 'packungen' then 'pack'
                when 'pckg' then 'pack'
                when 'pack' then 'pack'
                when 'dose' then 'can'
                when 'dosen' then 'can'
                when 'can' then 'can'
                when 'flasche' then 'bottle'
                when 'flaschen' then 'bottle'
                when 'bottle' then 'bottle'
                when 'bund' then 'bunch'
                when 'bunch' then 'bunch'
                when 'glas' then 'glass'
                when 'gläser' then 'glass'
                when 'jar' then 'glass'
                else unit
              end
 where unit is not null;

-- The default is stored as nothing at all.
update public.list_items set unit = null where unit = 'piece';
