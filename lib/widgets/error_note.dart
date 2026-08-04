import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/tokens.dart';
import '../l10n/l10n.dart';
import 'toast_chip.dart';

/// The app's error surface, in the two shapes anything backed by the network
/// needs. Listen is the first user; Board, Box and Kalender get the same two
/// when their repositories land.
///
/// Both take **German copy written for the user** — never a raw PostgREST or
/// GoTrue message. The notifier is where that translation happens (see
/// `ListNotifier`), so nothing here has to guess.

/// A failed *write*: the screen still has content, one action didn't land.
/// Transient, because the state it reports is transient — the next tap may well
/// succeed.
///
/// The same floating glass capsule a confirmation gets (`toast_chip.dart`), in red
/// rather than green — a write landing and a write failing are one event with
/// two outcomes, so they are one component with two colours. Kept under this
/// name because the ~8 call sites read as what they are.
void showErrorSnack(BuildContext context, String message) => showToast(context, message, kind: ToastKind.error);

/// A failed *read*: there is nothing on screen and no reason to believe the
/// next frame will fix it, so the message stays put and offers the retry.
///
/// Same look as the sign-in screen's error note, one size up with an action.
class ErrorNote extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorNote({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.cardSmall)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 17, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppText.body,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onRetry,
              behavior: HitTestBehavior.opaque,
              child: Text(
                L.s.reload,
                style: AppText.caption.copyWith(color: accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
