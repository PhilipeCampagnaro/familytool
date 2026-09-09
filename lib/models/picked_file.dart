/// A file the user just picked from the photo library, the camera or Files.
///
/// [path] points into the app's own `Documents/attachments/` — the picker
/// copies what it hands over, so nothing here depends on the file staying put
/// wherever it came from.
///
/// **This is a file, not yet an attachment.** It is what
/// `services/media_picker.dart` returns and what an uploader takes; the thing
/// that has landed in Storage and belongs to a row is [ItemAttachment], in
/// `models/attachment.dart`. Keeping them apart is what stops a picked file
/// from being rendered as though it were saved — which is exactly what the
/// device-local attachment map used to do.
class PickedFile {
  final String path;
  final String name;

  /// Images are shown as a thumbnail; anything else only as a name.
  final bool isImage;

  const PickedFile({required this.path, required this.name, required this.isImage});
}
