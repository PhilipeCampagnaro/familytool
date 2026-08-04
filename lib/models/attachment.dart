/// A file picked from the photo library, the camera or Files and attached to a
/// list item. [path] points into the app's own `Documents/attachments/` — the
/// picker copies what it hands over, so nothing here depends on the file
/// staying put wherever it came from.
class ItemAttachment {
  final String path;
  final String name;

  /// Images are shown as the row's thumbnail; anything else only as a name.
  final bool isImage;

  const ItemAttachment({required this.path, required this.name, required this.isImage});
}
