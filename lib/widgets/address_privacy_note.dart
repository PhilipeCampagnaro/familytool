import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';

/// The shield under both address pickers — the onboarding's and the Abfall
/// connect sheet's — saying what the address is for, at the moment the
/// household is asked to type a house number. One sentence on purpose: a
/// paragraph under a form field is a paragraph nobody reads.
///
/// **A promise, not decoration.** "Only for waste collection, holidays and
/// weather" holds because the household's own label is kept on its
/// `family_feeds` row and never on the feed the street shares, and because
/// `families.address` holds only the postcode and town. Use the address for
/// anything else and this line has to change with it.
///
/// **Never `const`-construct this**: it reads the palette and [L.s] in build.
class AddressPrivacyNote extends StatelessWidget {
  const AddressPrivacyNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(AppIcons.shieldCheck, size: 18, color: AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(L.s.addressPrivacyNote, style: AppText.caption.copyWith(color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}
