import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../models/entitlements.dart';
import '../services/app_review.dart';
import '../state/entitlement_state.dart';
import '../theme/app_icons.dart';
import '../theme/tokens.dart';
import 'app_sheet.dart';

/// **A gate never hides a feature, it explains it.**
///
/// The one rule this widget exists to keep. A control that is simply missing,
/// or greyed out with nothing beside it, reads as a bug — the household
/// concludes the app is broken rather than that they have reached the end of
/// what free covers. So every limit in `lib/models/entitlements.dart` ends
/// here, at a sheet that says what they ran into, what Plus does about it and
/// what it costs.
///
/// **A sheet, not a screen**, like `showRenameSheet` and the share sheet: it
/// stacks over wherever the reader already was, and dismissing it puts them
/// back exactly there. Someone who tapped "+" on a fourth box wanted a box, not
/// a trip to a shop; the way out has to be one gesture.
///
/// It is told which [Feature] was reached, and that is the only thing it takes.
/// The copy comes from [paywallTitle] and [paywallBody], so a paywall that
/// names the wrong feature is not expressible.
Future<void> showPaywallSheet(BuildContext context, Feature feature) {
  // Somebody who has just been shown a price is not who to ask for a rating.
  reviewPrompt.notePaywall();
  return showAppSheet<void>(
    context: context,
    title: L.s.plusName,
    heightFactor: 0.72,
    child: _PaywallBody(feature: feature),
  );
}

/// **The one line a screen writes to put a gate up.**
///
/// `if (!await requireFeature(context, ref, Feature.photos)) return;` — true
/// means carry on, false means the paywall is already on screen and the caller
/// is done. Returning a bool rather than taking a callback keeps the action
/// where it was: the code that adds a photograph stays in the method that adds
/// a photograph, with one guard above it.
///
/// Use this for a feature the household either has or does not — Ausgaben,
/// photographs. For one they have a number of, use [requireAnother].
Future<bool> requireFeature(BuildContext context, WidgetRef ref, Feature feature) async {
  if (ref.read(entitlementProvider).allows(feature)) return true;
  await showPaywallSheet(context, feature);
  return false;
}

/// The same guard for a counted limit: [current] is how many the household has
/// now, and the paywall goes up only when one more would be too many.
///
/// **The count is the caller's because only the caller knows what counts.**
/// Members are people plus invitations still outstanding; share links are the
/// ones still live rather than every one ever made. A shared helper reaching
/// for a count would get one of those wrong.
Future<bool> requireAnother(
  BuildContext context,
  WidgetRef ref,
  Feature feature,
  int current,
) async {
  if (ref.read(entitlementProvider).allowsAnother(feature, current)) return true;
  await showPaywallSheet(context, feature);
  return false;
}

class _PaywallBody extends ConsumerWidget {
  final Feature feature;

  const _PaywallBody({required this.feature});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitlements = ref.watch(entitlementProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // The feature's own mark, big enough to be the first thing read. It
          // says which door they walked into before any of the words do.
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.iconTile + 5),
            ),
            child: AppIcon(_icon, size: 30, color: AppColors.accent),
          ),
          const SizedBox(height: 18),

          Text(paywallTitle(feature), style: AppText.detailTitle, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            paywallBody(feature),
            style: AppText.body.copyWith(color: AppColors.inkSecondary, height: 1.45),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 22),
          _PriceRow(),
          const SizedBox(height: 12),

          Text(
            L.s.plusTrialNote,
            style: AppText.label,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 20),
          // **Nothing is wired to a store yet** — StoreKit 2 and Play Billing
          // land in Phase 4, behind one Dart interface. Until then this is
          // deliberately inert rather than absent: every screen that gates
          // something needs somewhere real to send the reader while the rest of
          // the app is built, and a button that is missing would hide the one
          // thing this sheet exists to say.
          OutlinedSheetAction(
            icon: AppIcons.sparkle,
            label: L.s.plusUpgrade,
            onTap: () {},
          ),
          const SizedBox(height: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                L.s.plusNotNow,
                style: AppText.rowTitle.copyWith(color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // Only while the developer switch is forcing a plan. It is here
          // rather than in a corner of Settings because this is the screen a
          // screenshot gets taken of, and a simulated plan that looks real in a
          // store listing is the mistake worth making impossible.
          if (entitlements.overridden) ...[
            const SizedBox(height: 4),
            Text(
              L.s.plusDebugOverride,
              style: AppText.caption.copyWith(color: AppColors.danger),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  /// The same glyph the feature wears everywhere else in the app, so the sheet
  /// is recognisably about the thing they just tapped.
  IconData get _icon => switch (feature) {
    Feature.calendarAccounts => AppIcons.calendarDots,
    Feature.trackers => AppIcons.circleDashed,
    Feature.boxes => AppIcons.package,
    Feature.members => AppIcons.users,
    Feature.shareLinks => AppIcons.link,
    Feature.photos => AppIcons.image,
    Feature.spend => AppIcons.wallet,
  };
}

/// The two prices side by side, monthly plain and yearly carrying the saving.
///
/// Both, rather than the yearly alone at a monthly-looking price: a household
/// deciding whether a family app is worth anything has not yet decided it is
/// worth a year, and hiding the monthly option to make the yearly look cheap is
/// the kind of trick that gets a refund request rather than a subscriber.
class _PriceRow extends StatelessWidget {
  const _PriceRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _PriceTile(price: L.s.plusPriceMonthly)),
        const SizedBox(width: 10),
        Expanded(child: _PriceTile(price: L.s.plusPriceYearly, note: L.s.plusYearlySaving)),
      ],
    );
  }
}

class _PriceTile extends StatelessWidget {
  final String price;
  final String? note;

  const _PriceTile({required this.price, this.note});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Text(price, style: AppText.rowTitle, textAlign: TextAlign.center),
          if (note != null) ...[
            const SizedBox(height: 3),
            Text(
              note!,
              style: AppText.caption.copyWith(color: AppColors.success),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
