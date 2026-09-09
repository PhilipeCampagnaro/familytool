import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Scans one QR code with the system camera, over the "aporah/scanner" channel
/// registered in `ios/Runner/AppDelegate.swift` (see
/// `ios/Runner/CodeScanner.swift`).
///
/// There is exactly one code in this app worth scanning — the one WebUntis
/// prints under Profil → Freigaben → "Zugriff über Untis Mobile" — and every
/// screen that offers the scan also offers the four lines underneath it as a
/// typed form. So each way this can fail resolves to "type it in instead"
/// rather than to a dead end, which is why the outcome is an enum and not an
/// exception.
enum ScanOutcome {
  /// A code was read. [ScanResult.value] holds it.
  scanned,

  /// Backed out of the camera screen. Say nothing — they know.
  cancelled,

  /// Camera access refused. Recoverable in iOS Settings, and worth saying so.
  denied,

  /// No camera to scan with: every platform but iOS, the simulator, a device
  /// with the camera restricted. Same fallback, different sentence.
  unavailable,
}

typedef ScanResult = ({ScanOutcome outcome, String? value});

/// Puts up the camera and waits. Never throws: a channel that is not there is
/// [ScanOutcome.unavailable], like any other device that cannot scan.
///
/// [title] and [hint] are drawn over the preview by UIKit, so they arrive as
/// text rather than being rendered here — a Flutter overlay above a camera
/// preview is the composition case this app has already been bitten by.
Future<ScanResult> scanCode({
  required String cancelLabel,
  required bool dark,
  String? title,
  String? hint,
}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return (outcome: ScanOutcome.unavailable, value: null);
  }

  try {
    final payload = await const MethodChannel('aporah/scanner').invokeMethod<String>('scan', {
      'cancel': cancelLabel,
      'dark': dark,
      'title': title,
      'hint': hint,
    });
    return payload == null || payload.isEmpty
        ? (outcome: ScanOutcome.cancelled, value: null)
        : (outcome: ScanOutcome.scanned, value: payload);
  } on PlatformException catch (e) {
    return (
      outcome: e.code == 'denied' ? ScanOutcome.denied : ScanOutcome.unavailable,
      value: null,
    );
  } on MissingPluginException {
    return (outcome: ScanOutcome.unavailable, value: null);
  }
}
