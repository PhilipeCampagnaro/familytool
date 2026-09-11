import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// `hide PickedFile`: image_picker exports a deprecated class of that name, and
// ours — lib/models/picked_file.dart — is the one the whole app passes around.
import 'package:image_picker/image_picker.dart' hide PickedFile;
import 'package:path_provider/path_provider.dart';
import '../models/picked_file.dart';

/// Which system picker to put up.
enum AttachmentSource {
  /// The photo library — `PHPickerViewController`, or Android's photo picker.
  photos('photo'),

  /// The camera.
  camera('camera'),

  /// The Files app, or Android's document picker.
  ///
  /// The [method] strings are the iOS channel's method names; Android branches
  /// on the enum itself and never sends them.
  files('file');

  final String method;

  const AttachmentSource(this.method);
}

/// Presents one of the system pickers and returns what came back, or null if
/// the user cancelled, or there is no camera, or the platform has no picker.
///
/// **Two implementations, one contract.** iOS goes to
/// `ios/Runner/MediaPicker.swift` — three system view controllers behind one
/// channel — and Android to `image_picker` + `file_picker`. See [_pickAndroid]
/// for why that is a deliberate split rather than a lapse. Everywhere else
/// there is still nothing, and this still answers null.
const _channel = MethodChannel('aporah/media');

/// The longest edge a profile picture is stored at.
///
/// It is drawn at 64px at the very largest, so this is already generous — and
/// the point is the other end: a straight-from-the-camera 12MP HEIC is several
/// megabytes of upload for a circle the size of a thumbnail.
const avatarMaxDimension = 512;

/// The longest edge a picture of a *thing* is stored at.
///
/// Far more generous than [avatarMaxDimension], and for the opposite reason: an
/// avatar is only ever a circle the size of a thumbnail, whereas the point of
/// photographing what is in a box is being able to look at it — the serial
/// number on the drill, which of the three cables it is. Still a cap, because
/// the alternative is a household uploading twelve megapixels per screwdriver.
const itemPhotoMaxDimension = 1600;

/// [maxDimension] caps the longest edge of a picked *image*, in pixels; null
/// keeps it as it was picked. The native side also re-encodes anything Flutter
/// cannot decode — HEIC above all, which is what an iPhone camera produces by
/// default — so what comes back here is always drawable.
Future<PickedFile?> pickAttachment(AttachmentSource source, {int? maxDimension}) async {
  if (kIsWeb) return null;
  if (defaultTargetPlatform == TargetPlatform.iOS) return _pickIOS(source, maxDimension);
  if (defaultTargetPlatform == TargetPlatform.android) return _pickAndroid(source, maxDimension);
  return null;
}

Future<PickedFile?> _pickIOS(AttachmentSource source, int? maxDimension) async {
  try {
    final picked = await _channel.invokeMapMethod<String, dynamic>(
      source.method,
      {'maxDimension': maxDimension},
    );
    if (picked == null) return null;
    return PickedFile(
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

/// The same three pickers, assembled from plugins instead of written out.
///
/// Not the inconsistency it looks like. The iOS side is native because the app
/// is built on iOS system controls and a plugin's approximation beside a real
/// `UITabBar` is exactly what the design refuses; Android has no such
/// requirement, and hand-writing the photo picker, a camera `FileProvider` and
/// SAF in Kotlin would be several hundred lines to arrive in the same place.
///
/// **What this side must reproduce rather than merely provide** is the contract
/// the callers already rely on: the longest edge capped at [maxDimension], and
/// the result living in our own `Documents/attachments/`. The bucket size
/// limits in the storage migrations assume the first, and
/// [readPickedText] deleting its input assumes the second — a picker's own temp
/// file is not ours to delete.
Future<PickedFile?> _pickAndroid(AttachmentSource source, int? maxDimension) async {
  try {
    switch (source) {
      case AttachmentSource.photos:
      case AttachmentSource.camera:
        final picker = ImagePicker();
        final shot = await picker.pickImage(
          source: source == AttachmentSource.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          // The plugin caps both edges; passing the same number to each caps the
          // longest one and leaves the aspect ratio alone, which is what
          // `maxDimension` means on the iOS side.
          maxWidth: maxDimension?.toDouble(),
          maxHeight: maxDimension?.toDouble(),
          imageQuality: 90,
        );
        if (shot == null) return null;
        return await _adopt(shot.path, shot.name, isImage: true);

      case AttachmentSource.files:
        final result = await FilePicker.platform.pickFiles(withData: false);
        final file = result?.files.single;
        final path = file?.path;
        if (file == null || path == null) return null;
        return await _adopt(path, file.name, isImage: _looksLikeImage(file.name));
    }
  } on PlatformException {
    // A denied permission, or no camera. Both are "nothing was picked" from
    // every caller's point of view, and each of them already draws that.
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// Copies a picked file into `Documents/attachments/` and hands back its new
/// home, so the rest of the app never holds a path inside a plugin's cache —
/// which Android is free to clear underneath us between the pick and the upload.
Future<PickedFile?> _adopt(String sourcePath, String name, {required bool isImage}) async {
  try {
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/attachments');
    await dir.create(recursive: true);
    // A fresh name every time, for the same reason the photo bucket uses one:
    // two pictures picked from the same camera roll are both `image.jpg`, and
    // the second must not quietly become the first.
    final unique = '${DateTime.now().microsecondsSinceEpoch}_$name';
    final copy = await File(sourcePath).copy('${dir.path}/$unique');
    return PickedFile(path: copy.path, name: name, isImage: isImage);
  } on FileSystemException {
    return null;
  }
}

bool _looksLikeImage(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0) return false;
  return const {'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'gif'}
      .contains(name.substring(dot + 1).toLowerCase());
}

/// Reads a picked text file and then removes the copy the picker made.
///
/// Two encodings, because German waste vendors and Vereine publish `.ics` files
/// written by anything: UTF-8 is what an iCalendar file is supposed to be, and
/// a file that is not valid UTF-8 is almost always Latin-1 with umlauts in it.
/// Guessing wrong there costs a calendar whose every umlaut is a replacement
/// character, so the fallback is worth the four lines.
///
/// The copy goes because it is the only unencrypted copy of the household's
/// calendar anywhere on the device once the upload has been sealed server-side,
/// and nothing in the app ever wants to read it again.
Future<String?> readPickedText(PickedFile picked) async {
  final file = File(picked.path);
  try {
    final bytes = await file.readAsBytes();
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes, allowInvalid: true);
    }
  } on FileSystemException {
    return null;
  } finally {
    try {
      await file.delete();
    } on FileSystemException {
      // A file we could not delete is a stray copy in our own sandbox, not a
      // failed upload — the caller has the text and must not be told otherwise.
    }
  }
}
