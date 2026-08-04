-- Boxen pick their own symbol from the name as it is typed ("Keller" -> Lager,
-- "Weihnachtsdeko" -> Tannenbaum), exactly as lists do, and the picker overrides
-- it. `lists`/`list_items` already carry that string in `icon_asset`; the box
-- tables were created before the feature existed, so the icon had nowhere to be
-- stored and a shelf of boxes would come back from the server unillustrated.
--
-- Same column name and same contents as the list side ('assets/...' or
-- 'lucide:<name>' — see lib/data/icon_suggestions.dart), so one Dart mapping
-- covers all four tables.
alter table public.boxes      add column if not exists icon_asset text;
alter table public.box_items  add column if not exists icon_asset text;
