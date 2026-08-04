import '../models/box_item.dart';

/// Nothing ships with the app. Boxes and their contents are created by the
/// household, and will come from Supabase once the backend is wired up.
///
/// Both are kept as named constants rather than being deleted outright: the Box
/// screen and `BoxScreenState` read through them, and they are the seam the
/// repository layer will replace.
/// Named `seedBoxes` rather than `boxes` on purpose: the screen reads
/// `BoxScreenState.boxes`, which is this plus everything created in the
/// session.
const List<StorageBox> seedBoxes = [];

const Map<String, List<BoxItem>> boxItemsById = {};
