import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/tokens.dart';
import 'app_sheet.dart';
import '../l10n/l10n.dart';

/// A URL the app was handed **once**, with copying as the whole card rather
/// than a small button beside it — a share link just minted, the invitation
/// link `invite-member` returns exactly once. Only the token's hash is stored
/// in either case, so this is the single moment the URL exists in the app: a
/// link whose address was never copied can be revoked, not recovered, which is
/// what [footnote] says by default.
///
/// [onDismiss] adds the X that puts it away, for the one caller that keeps
/// showing it after the moment has passed (the share sheet, where the card sits
/// above a form that stays open).
class CopyLinkCard extends StatefulWidget {
  final String url;
  final String label;
  final String? footnote;
  final VoidCallback? onDismiss;

  const CopyLinkCard({
    super.key,
    required this.url,
    required this.label,
    this.footnote,
    this.onDismiss,
  });

  @override
  State<CopyLinkCard> createState() => _CopyLinkCardState();
}

class _CopyLinkCardState extends State<CopyLinkCard> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.link, size: 15, color: accent),
                  const SizedBox(width: 8),
                  Text(widget.label, style: AppText.rowTitle),
                  if (widget.onDismiss case final onDismiss?) ...[
                    const Spacer(),
                    GestureDetector(
                      onTap: onDismiss,
                      behavior: HitTestBehavior.opaque,
                      child: Icon(LucideIcons.x, size: 16, color: AppColors.mutedLight),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.url,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(fontWeight: FontWeight.w400, color: AppColors.inkSecondary),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: widget.url));
                  if (mounted) setState(() => _copied = true);
                },
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Icon(_copied ? LucideIcons.check : LucideIcons.copy, size: 15, color: accent),
                    const SizedBox(width: 7),
                    Text(
                      _copied ? L.s.copied : L.s.copyLink,
                      style: AppText.buttonSmall.copyWith(color: accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(widget.footnote ?? L.s.linkShownOnce, style: AppText.label.copyWith(fontSize: 11.5)),
            ],
          ),
        ),
      ],
    );
  }
}
