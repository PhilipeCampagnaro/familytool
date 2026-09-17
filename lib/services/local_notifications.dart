import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether this platform can schedule a notification at all.
bool get localNotificationsAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

/// Whether iOS's quiet, prompt-free grant exists here. Android has no such
/// thing: a grant there is the dialog or nothing.
bool get provisionalNotificationsAvailable => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Where the OS stands on this app posting notifications.
enum NotificationAccess {
  /// Never asked.
  notDetermined,

  /// Refused, in the dialog or later in system settings. Only system settings
  /// can undo it; asking again shows nothing.
  denied,

  /// iOS only: delivered silently to Notification Centre, granted without a
  /// dialog. Asking again without `provisional` puts up the real prompt.
  provisional,

  authorized;

  /// Whether a scheduled notice will reach the phone in some form.
  bool get delivers => this == provisional || this == authorized;

  static NotificationAccess parse(String? raw) => switch (raw) {
    'denied' => denied,
    'provisional' => provisional,
    'authorized' => authorized,
    _ => notDetermined,
  };
}

/// One notification to be posted at [at].
///
/// **Text rendered now, in the language of now.** A notice is a string by the
/// time it reaches the OS, which is why a language change re-derives the whole
/// set rather than waiting for it to fire in the old one.
class ScheduledNotice {
  /// Stable across re-derivations, so an unchanged notice is the same request.
  final String id;
  final DateTime at;
  final String title;
  final String body;

  /// Groups notices on the lock screen — every Abfall evening under one stack.
  final String? thread;

  const ScheduledNotice({
    required this.id,
    required this.at,
    required this.title,
    required this.body,
    this.thread,
  });

  Map<String, Object?> toWire() => {
    'id': id,
    'at': at.millisecondsSinceEpoch,
    'title': title,
    'body': body,
    if (thread != null) 'thread': thread,
  };

  /// What makes two derivations the same schedule — cheap to compare, and what
  /// keeps an unchanged calendar from crossing the channel every 30 seconds.
  String get signature => '$id|${at.millisecondsSinceEpoch}|$title|$body';
}

/// The device's notification centre, over "aporah/notifications" — implemented
/// by hand on both sides, `ios/Runner/LocalNotifications.swift` and
/// `android/.../LocalNotifications.kt`, for the reason given there. A no-op off
/// both.
class LocalNotifications {
  const LocalNotifications();

  static const _channel = MethodChannel('aporah/notifications');

  Future<NotificationAccess> status() async {
    if (!localNotificationsAvailable) return NotificationAccess.denied;
    return NotificationAccess.parse(await _invoke<String>('status'));
  }

  /// Asks the OS. [provisional] is honoured on iOS only.
  Future<NotificationAccess> request({bool provisional = false}) async {
    if (!localNotificationsAvailable) return NotificationAccess.denied;
    final raw = await _invoke<String>('request', {
      'provisional': provisional && provisionalNotificationsAvailable,
    });
    return NotificationAccess.parse(raw);
  }

  /// The system's own notification settings for this app — the only place a
  /// refusal can be undone.
  Future<void> openSettings() => _invoke<void>('openSettings');

  /// Replaces every pending notice of ours with [notices].
  ///
  /// [channelName] is what Android's system settings call the category, and so
  /// is in the user's language like everything else.
  Future<void> replaceAll(List<ScheduledNotice> notices, {required String channelName}) async {
    if (!localNotificationsAvailable) return;
    await _invoke<void>('replaceAll', {
      'items': [for (final n in notices) n.toWire()],
      'channelName': channelName,
    });
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
