-- Aporah backend — shared enum types.
--
-- `shareable_kind` is deliberately narrow. It is the structural guarantee that
-- Kalender and the future Finanzen module can never be shared outside the
-- household: there is simply no enum value that names one, so no future code
-- path can reference one by accident. Adding a value here is a security
-- decision, not a refactor.

create type public.member_role as enum ('admin', 'member', 'kid');

-- How a container (list / box / task / calendar) is visible *inside* the
-- household. 'private' needs no member list — it resolves to the owner alone.
create type public.visibility as enum ('family', 'private', 'custom');

-- ListType.summary in the Flutter app ("Alle Artikel") is a computed view over
-- every list, not a stored row, so it has no counterpart here.
create type public.list_kind as enum ('grocery', 'other');

create type public.shareable_kind as enum ('list', 'box', 'task');
