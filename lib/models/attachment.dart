/// A file that belongs to a list article — one `public.list_item_attachments`
/// row, and one object in the private `list-attachments` bucket.
///
/// These used to live in a `Map<String, List<…>>` on `ListState` and die with
/// the process: the table had been there since the first migration but had no
/// bucket behind it, so a photo of the shelf survived until the next launch and
/// never reached the other parent at all. It is stored now.
class ItemAttachment {
  final String id;

  /// The object path in the `list-attachments` bucket,
  /// `<list_id>/<uuid>.<ext>` — filed under the **list**, because that is what
  /// the storage policy can ask about (an article has no visibility of its own).
  final String storagePath;

  final String name;

  /// Images are shown as the row's thumbnail; anything else only as a name.
  final bool isImage;

  /// A signed URL for [storagePath], resolved at load time. Null when signing
  /// failed, which costs a thumbnail and nothing else.
  final String? url;

  /// The copy still sitting in `Documents/attachments/` from the session that
  /// picked it. Drawn in preference to [url] while it is there — it is already
  /// on the disk, so there is nothing to fetch — and gone on the next launch,
  /// when [url] takes over. Never a reason to consider the file saved.
  final String? localPath;

  const ItemAttachment({
    required this.id,
    required this.storagePath,
    required this.name,
    required this.isImage,
    this.url,
    this.localPath,
  });

  factory ItemAttachment.fromMap(Map<String, dynamic> map, {String? url}) => ItemAttachment(
    id: map['id'] as String,
    storagePath: map['storage_path'] as String,
    name: map['name'] as String,
    isImage: map['is_image'] as bool? ?? false,
    url: url,
  );

  ItemAttachment copyWith({String? url, String? localPath}) => ItemAttachment(
    id: id,
    storagePath: storagePath,
    name: name,
    isImage: isImage,
    url: url ?? this.url,
    localPath: localPath ?? this.localPath,
  );
}
