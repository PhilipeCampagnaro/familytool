import '../models/shopping_list.dart';

const _g = 'assets/grocery/';

/// Not seed data: "Alle Artikel" is a view computed across every list the user
/// can see, not a stored row. It has no counterpart in `public.list_kind` (see
/// supabase/migrations/…_types.sql) and stays regardless of how many real lists
/// exist — which is why [ShoppingList.summary] refuses to be written.
///
/// Lists and their articles themselves come from Supabase now; nothing ships
/// with the app. See `data/repositories/list_repository.dart`.
const allList = ShoppingList.summary(iconKey: '${_g}General_Shopping_cart.png');

/// Suggestions while typing aren't seeded here — they come out of the whole
/// `assets/grocery/` catalog, see `data/grocery_search.dart`.
