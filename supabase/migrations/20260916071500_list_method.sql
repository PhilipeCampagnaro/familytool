-- The method a Vorhaben wrote, kept with the list it became.
--
-- Until now the plan's `steps` and `recipe` lived for exactly as long as the
-- card was on screen: you read how to cook the thing, tapped "Liste erstellen",
-- and the articles became a Liste while the method was thrown away. So the
-- household stood in the kitchen with the shopping done and went to look the
-- recipe up somewhere else — which is the one place the feature was asked to
-- help and did not.
--
-- **This is the first model output the app stores, and that is a real change
-- rather than a detail.** `list-plan` neither stores nor logs the goal or the
-- answer, and it still does not: what is kept is what the household chose to
-- keep by making a list of it, on the row they already own, under the same RLS
-- as the articles beside it. The *goal* they typed is still nowhere. The note
-- in docs/list-planner.md saying the answer is never stored is updated with
-- this migration rather than left to quietly stop being true.
--
-- Two columns rather than one jsonb: they are read separately, drawn
-- separately, and a text[] is what `steps` already is on the wire.
--
-- Null on every list that was not made by a Vorhaben, which is most of them —
-- and null is drawn as "no chip under the title" rather than as an empty sheet.
-- `authenticated` holds table-level grants on public.lists, so the new columns
-- need no GRANT of their own; RLS is row-level and already decides who may read
-- the row these sit on.
alter table public.lists
  add column steps text[],
  add column recipe text;
