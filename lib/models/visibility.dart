/// How a container is visible *inside* the household — `public.visibility`.
///
/// One enum for lists, boxes and Board tasks, because it is one Postgres type
/// and one predicate shape (`can_read_list` / `_box` / `_task` differ only in the
/// table they read). Deliberately not the app's older single `who` string —
/// `'all'`, `'private'` or a member id — which conflated *who may see this* with
/// *who is meant to do it*; those are now [ItemVisibility] and an `assignee_id`,
/// and they move independently.
///
/// `custom` is spelled out by rows in the matching `*_shares` table, carried on
/// the model as `sharedWith`. `private` needs no member list at all: it resolves
/// to the owner alone, and no admin has a way in — see docs/backend.md.
///
/// External sharing (guests, share links) is a third axis again and is not
/// represented here.
enum ItemVisibility { family, private, custom }

ItemVisibility visibilityFrom(String? value) => switch (value) {
  'private' => ItemVisibility.private,
  'custom' => ItemVisibility.custom,
  _ => ItemVisibility.family,
};
