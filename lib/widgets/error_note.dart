import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/tokens.dart';

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
void showErrorSnack(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceAlt,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.cardSmall)),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Icon(LucideIcons.info, size: 17, color: AppColors.danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w300, color: AppColors.inkSecondary),
              ),
            ),
          ],
        ),
      ),
    );
}

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
              style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w300, color: AppColors.inkSecondary),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onRetry,
              behavior: HitTestBehavior.opaque,
              child: Text(
                'Erneut laden',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 13.5, fontWeight: FontWeight.w500, color: accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
