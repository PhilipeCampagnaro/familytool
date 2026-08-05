import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/attachment.dart';

/// Which system picker to put up.
enum AttachmentSource {
  /// The photo library (`PHPickerViewController`).
  photos('photo'),

  /// The camera (`UIImagePickerController`).
  camera('camera'),

  /// The Files app (`UIDocumentPickerViewController`).
  files('file');

  final String method;

  const AttachmentSource(this.method);
}

/// Presents one of the system pickers and returns what came back, or null if
/// the user cancelled (or there's no camera, or we're not on iOS).
///
/// The native side is `ios/Runner/MediaPicker.swift` — three system view
/// controllers behind one channel, rather than `image_picker` + `file_picker`
/// and their pod install. Off iOS there's no handler, the same trade the
/// native tab bar, switch and search field make.
const _channel = MethodChannel('aporah/media');

/// The longest edge a profile picture is stored at.
///
/// It is drawn at 64px at the very largest, so this is already generous — and
/// the point is the other end: a straight-from-the-camera 12MP HEIC is several
/// megabytes of upload for a circle the size of a thumbnail.
const avatarMaxDimension = 512;

/// [maxDimension] caps the longest edge of a picked *image*, in pixels; null
/// keeps it as it was picked. The native side also re-encodes anything Flutter
/// cannot decode — HEIC above all, which is what an iPhone camera produces by
/// default — so what comes back here is always drawable.
Future<ItemAttachment?> pickAttachment(AttachmentSource source, {int? maxDimension}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return null;
  try {
    final picked = await _channel.invokeMapMethod<String, dynamic>(
      source.method,
      {'maxDimension': maxDimension},
    );
    if (picked == null) return null;
    return ItemAttachment(
      path: picked['path'] as String,
      name: picked['name'] as String,
      isImage: picked['isImage'] as bool? ?? false,
    );
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
