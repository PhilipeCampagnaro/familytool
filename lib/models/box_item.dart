import 'visibility.dart';

DateTime? _timeFrom(Object? value) => value == null ? null : DateTime.tryParse(value as String)?.toLocal();

/// One box in the household's storage — a `public.boxes` row.
///
/// Carries the same four-column visibility contract every container does
/// (`family_id`, `owner_id`, `visibility`, plus rows in `box_shares`), so the
/// Listen model, this one and the Board task differ only in what they hold.
class StorageBox {
  final String id;
  final String name;

  /// Where it physically is — "Keller", "Dachboden". Nullable in the column but
  /// empty rather than null here: the detail header prints it unconditionally.
  final String place;

  final int tone;

  /// What to draw in front of the box — the same `iconKey` string a list
  /// carries, see `data/icon_suggestions.dart`. Filled in from the name as it is
  /// typed ("Keller" → Lager, "Weihnachtsdeko" → Tannenbaum) and overridable
  /// from the picker. Stored in `icon_asset`, the same column the lists use.
  final String? iconKey;

  /// A photograph of the box itself, as an object path in the private
  /// `box-photos` bucket — `<box_id>/<uuid>.jpg`, never a URL, so nothing here
  /// expires. It **replaces** [iconKey] wherever the box is drawn: a picture of
  /// the actual crate in the cellar is what makes it findable, and a symbol
  /// under it would only be a second answer to the same question. [iconKey]
  /// stays as the fallback for the boxes that have no picture.
  final String? photoPath;

  /// The household this box belongs to. Written on insert and **never** used to
  /// filter a read — see `BoxRepository`.
  final String familyId;

  final String ownerId;
  final ItemVisibility visibility;

  /// The user ids in `box_shares`, when [visibility] is
  /// [ItemVisibility.custom]. The owner is implicit and not repeated.
  final List<String> sharedWith;

  final int position;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const StorageBox({
    required this.id,
    required this.name,
    required this.familyId,
    required this.ownerId,
    this.place = '',
    this.tone = 0,
    this.iconKey,
    this.photoPath,
    this.visibility = ItemVisibility.family,
    this.sharedWith = const [],
    this.position = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory StorageBox.fromMap(Map<String, dynamic> map, {List<String> sharedWith = const []}) {
    return StorageBox(
      id: map['id'] as String,
      name: map['name'] as String,
      place: map['place'] as String? ?? '',
      tone: (map['tone'] as num?)?.toInt() ?? 0,
      iconKey: map['icon_asset'] as String?,
      photoPath: map['photo_path'] as String?,
      familyId: map['family_id'] as String,
      ownerId: map['owner_id'] as String,
      visibility: visibilityFrom(map['visibility'] as String?),
      sharedWith: sharedWith,
      position: (map['position'] as num?)?.toInt() ?? 0,
      createdAt: _timeFrom(map['created_at']),
      updatedAt: _timeFrom(map['updated_at']),
    );
  }

  /// `owner_id`/`family_id` only on insert — on update
  /// `enforce_container_ownership` rejects them from anyone but the owner.
  Map<String, dynamic> toMap({bool forInsert = false}) => {
    'name': name,
    'place': place.isEmpty ? null : place,
    'tone': tone,
    'icon_asset': iconKey,
    'photo_path': photoPath,
    'visibility': visibility.name,
    'position': position,
    if (forInsert) ...{'family_id': familyId, 'owner_id': ownerId},
  };

  StorageBox copyWith({
    String? name,
    String? place,
    int? tone,
    String? iconKey,
    bool clearIconKey = false,
    String? photoPath,
    bool clearPhotoPath = false,
    ItemVisibility? visibility,
    List<String>? sharedWith,
    int? position,
  }) => StorageBox(
    id: id,
    name: name ?? this.name,
    place: place ?? this.place,
    tone: tone ?? this.tone,
    iconKey: clearIconKey ? null : (iconKey ?? this.iconKey),
    photoPath: clearPhotoPath ? null : (photoPath ?? this.photoPath),
    familyId: familyId,
    ownerId: ownerId,
    visibility: visibility ?? this.visibility,
    sharedWith: sharedWith ?? this.sharedWith,
    position: position ?? this.position,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// One thing inside a box — a `public.box_items` row.
///
/// No visibility of its own: it inherits the box's, the way a list article
/// inherits its list's. Everything inside a shared box is shared.
class BoxItem {
  final String id;

  /// Non-nullable: every item belongs to exactly one box, and that is where an
  /// edit has to be written back — including from the search results, which mix
  /// items from several boxes.
  final String boxId;

  final String name;
  final String? size;
  final int qty;
  final String? note;

  /// The picture the item's own name produced — a stored item is a thing, and
  /// "Bohrmaschine" is far easier to spot as a drill than as one more line of
  /// text. Same key format as [StorageBox.iconKey].
  final String? iconKey;

  /// A photograph of the thing, and the reason this feature exists: a symbol
  /// can say "Werkzeug", only a picture says *which* drill. Object path in the
  /// private `box-photos` bucket, filed under the **box** id rather than the
  /// item's — an item inherits its box's visibility, so the box is the unit the
  /// storage policy can key on. Replaces [iconKey] wherever the item is drawn.
  final String? photoPath;

  final String? createdBy;
  final int position;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BoxItem({
    required this.id,
    required this.boxId,
    required this.name,
    this.size,
    this.qty = 1,
    this.note,
    this.iconKey,
    this.photoPath,
    this.createdBy,
    this.position = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory BoxItem.fromMap(Map<String, dynamic> map) => BoxItem(
    id: map['id'] as String,
    boxId: map['box_id'] as String,
    name: map['name'] as String,
    size: map['size'] as String?,
    qty: (map['qty'] as num?)?.toInt() ?? 1,
    note: map['note'] as String?,
    iconKey: map['icon_asset'] as String?,
    photoPath: map['photo_path'] as String?,
    createdBy: map['created_by'] as String?,
    position: (map['position'] as num?)?.toInt() ?? 0,
    createdAt: _timeFrom(map['created_at']),
    updatedAt: _timeFrom(map['updated_at']),
  );

  Map<String, dynamic> toMap({bool forInsert = false}) => {
    'box_id': boxId,
    'name': name,
    'size': size,
    'qty': qty,
    'note': note,
    'icon_asset': iconKey,
    'photo_path': photoPath,
    'position': position,
    if (forInsert) 'created_by': createdBy,
  };

  BoxItem copyWith({
    String? name,
    String? size,
    bool clearSize = false,
    int? qty,
    String? note,
    bool clearNote = false,
    String? iconKey,
    bool clearIconKey = false,
    String? photoPath,
    bool clearPhotoPath = false,
    int? position,
  }) => BoxItem(
    id: id,
    boxId: boxId,
    name: name ?? this.name,
    size: clearSize ? null : (size ?? this.size),
    qty: qty ?? this.qty,
    note: clearNote ? null : (note ?? this.note),
    iconKey: clearIconKey ? null : (iconKey ?? this.iconKey),
    photoPath: clearPhotoPath ? null : (photoPath ?? this.photoPath),
    createdBy: createdBy,
    position: position ?? this.position,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  String get meta => [size, '×$qty', note].where((e) => e != null && e.isNotEmpty).join(' · ');
}
