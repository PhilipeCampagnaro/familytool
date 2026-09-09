import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/supabase.dart';
import 'list_repository.dart' show newUuidV4;

/// The one file that knows pictures are kept in Supabase Storage.
///
/// Same job for the two private buckets `20260909170000_item_photos.sql`
/// creates as the `*Repository` classes do for their tables: the bucket names,
/// the object layout and the signing live here, and the notifiers above speak
/// only in paths and URLs.
///
/// **The layout is the access rule.** Every object is filed under the id of the
/// *container* it belongs to — `<box_id>/<uuid>.jpg`, `<list_id>/<uuid>.pdf` —
/// because that is the only thing the storage policies can ask about, and the
/// only thing worth asking: an item inside a box has no visibility of its own.
/// Change the layout and the policies stop matching, silently and only for the
/// people who aren't the owner.
class PhotoRepository {
  PhotoRepository([SupabaseClient? client]) : _db = client ?? AporahSupabase.client;

  final SupabaseClient _db;

  /// The picture on a box or on one of its items.
  static const boxBucket = 'box-photos';

  /// Everything the Listen attach menu can produce — a photo, but also the
  /// receipt from Dateien.
  static const listBucket = 'list-attachments';

  /// A week, and re-signed on every load — the same reasoning as the avatars'
  /// TTL: a short expiry would only buy a broken thumbnail in an app that was
  /// left open over a weekend.
  static const _urlTtl = Duration(days: 7);

  /// Uploads [file] under [containerId] and returns the object path to store.
  ///
  /// A fresh name every time rather than a fixed one per box: signed URLs
  /// already handed out (and every image cache holding one) would go on serving
  /// the old picture after a replacement, which is the bug the avatars went
  /// through first.
  ///
  /// Throws on failure — the caller decides whether that is a snackable error
  /// or a silently dropped thumbnail.
  Future<String> upload({required String bucket, required String containerId, required File file}) async {
    final extension = extensionOf(file.path);
    final path = '$containerId/${newUuidV4()}.$extension';
    await _db.storage.from(bucket).upload(
      path,
      file,
      fileOptions: FileOptions(contentType: contentTypeFor(extension)),
    );
    return path;
  }

  /// Path → signed URL for a whole screenful at once.
  ///
  /// One request rather than one per picture, and a total failure is not fatal:
  /// an empty map means every row falls back to its symbol, which is exactly
  /// what a box without a photo already shows.
  Future<Map<String, String>> signUrls(String bucket, Iterable<String> paths) async {
    final wanted = paths.toSet().toList();
    if (wanted.isEmpty) return const {};
    try {
      final signed = await _db.storage.from(bucket).createSignedUrlsResult(wanted, _urlTtl.inSeconds);
      return {
        // One object that has gone missing is not a reason to drop the other
        // eleven — hence the per-path result type rather than the older
        // list-of-urls call.
        for (final s in signed)
          if (s is SignedUrlSuccess) s.path: s.signedUrl,
      };
    } catch (_) {
      return const {};
    }
  }

  /// Copies an object under a **new** container id, and returns its new path.
  ///
  /// This is what undo needs. Restoring a deleted box re-inserts it under a
  /// fresh uuid (the old row is gone, and with it any chance of reusing its
  /// id), and the object layout keys on the container — so a restored box that
  /// kept its old `photo_path` would name an object filed under an id no box
  /// has any more, which the read policy correctly refuses. Copying is the only
  /// honest answer: undo either gives the pictures back or it isn't undo.
  Future<String> copyTo({required String bucket, required String fromPath, required String containerId}) async {
    final to = '$containerId/${newUuidV4()}.${extensionOf(fromPath)}';
    await _db.storage.from(bucket).copy(fromPath, to);
    return to;
  }

  /// Best-effort: an orphaned object costs a few kilobytes, and a failed delete
  /// must never be what stops a row from being removed.
  Future<void> remove(String bucket, Iterable<String> paths) async {
    final doomed = paths.toSet().toList();
    if (doomed.isEmpty) return;
    try {
      await _db.storage.from(bucket).remove(doomed);
    } catch (_) {}
  }
}

/// The file's own extension, or `jpg` for a name that hasn't got a usable one.
///
/// **Kept as it is even when unknown**, which matters more than it looks: an
/// extension that is quietly rewritten to `jpg` gets [contentTypeFor]'s image
/// type with it, and the bucket would then accept a `.docx` labelled as a
/// photograph. Falling back only for an *absent* extension leaves the unknown
/// ones to be refused by the allowlist, out loud.
String extensionOf(String path) {
  final dot = path.lastIndexOf('.');
  final ext = dot == -1 ? '' : path.substring(dot + 1).toLowerCase();
  return RegExp(r'^[a-z0-9]{1,8}$').hasMatch(ext) ? ext : 'jpg';
}

/// Storage matches the upload against the bucket's `allowed_mime_types`, and
/// the SDK's default is on neither list — so the type has to be named rather
/// than left to the server to guess.
///
/// An unknown extension deliberately gets a type no bucket allows: the upload
/// then fails and is snacked, which is the honest outcome for a file the
/// backend was not set up to hold.
String contentTypeFor(String extension) => _contentTypes[extension] ?? 'application/octet-stream';

const _contentTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'heic': 'image/heic',
  'heif': 'image/heif',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
};

/// The one repository provider that does **not** live beside a notifier.
///
/// Every other one sits in the state file of the screen that owns it, because
/// exactly one screen does. Pictures are the exception: Boxen and Listen both
/// need this, and putting it in either notifier's file would make the other
/// import a sibling screen's state to reach a repository.
final photoRepositoryProvider = Provider<PhotoRepository>((ref) => PhotoRepository(AporahSupabase.client));
