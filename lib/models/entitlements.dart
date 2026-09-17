/// What the household has paid for, and every number that follows from it.
///
/// **One file holds the whole free/Plus line.** Not because it is tidy, but
/// because the line will move: the first price and the first set of limits are
/// a guess, and the only way to change a guess cheaply is to have written it in
/// one place. A screen asks [Entitlements.allows] or [Entitlements.allowsAnother]
/// and never knows which plan it is on — see the rules in
/// `docs/production-plan.md`, of which this file is the first.
///
/// **Per household, not per user.** The row is on `public.families`, so one
/// parent's purchase entitles the whole family. A member is never asked to buy
/// something the household already has.
library;

import '../l10n/l10n.dart';

/// What the household is on. Mirrors `families.plan` exactly.
enum Plan {
  free,
  plus;

  /// Anything unrecognised is [free], deliberately. A client one version behind
  /// a new tier must degrade to the safe answer rather than throw on startup —
  /// and a household reading `plan` as null, because the column failed to
  /// arrive, is a household we cannot prove has paid.
  static Plan fromWire(String? value) => value == 'plus' ? Plan.plus : Plan.free;
}

/// A thing a free household eventually reaches the end of.
///
/// Everything gated in the app is a value here, so the list itself is the
/// answer to "what does Plus actually get you" — and the paywall copy is keyed
/// on it, so a new gate cannot ship without a sentence explaining itself.
enum Feature {
  /// Connected calendar accounts. **The one that matters**, and the reason the
  /// gate is here rather than on writing an event.
  ///
  /// **Two, because a household is at least two adults** (raised from one,
  /// 2026-09-16). A family organizer whose free tier holds a single account is
  /// a calendar app for one parent — and the second parent's week beside the
  /// first *is* the thing this app is for, so charging for it means most
  /// households never once see the app do its job. Two accounts is both adults
  /// in. The **third** — the school's feed, a teenager's own, the shared one
  /// nobody remembers making — is a household growing into the app rather than
  /// tasting it, and that is what Plus is for. IServ, WebUntis, GMX and any
  /// iCal link arrive with it.
  calendarAccounts,

  /// Rhythms on the Board.
  trackers,

  /// Boxen.
  boxes,

  /// People in the household.
  members,

  /// Photographs on boxes, box items and list articles, and file attachments.
  /// The only gated feature with a real marginal cost behind it — Storage and
  /// egress — which is why it is off rather than capped.
  photos,

  /// Ausgaben.
  ///
  /// **Two independent questions, and both must say yes.** This one is about
  /// the plan; `spendAvailable` in `lib/services/spend_intent.dart` is about the
  /// platform, and is false on the web whatever the household has paid.
  spend,
}

/// The household's plan and what it is allowed, as one immutable answer.
class Entitlements {
  final Plan plan;

  /// `families.plan_expires_at` — when the current paid period runs out. Null
  /// for a household that has never paid and for a manual grant, which is why
  /// null never means "expired".
  final DateTime? expiresAt;

  /// True when this is not the household's real plan but a debug override.
  /// Nothing but the developer menu sets it, and the paywall shows a marker
  /// while it is on so a screenshot cannot be mistaken for the real thing.
  final bool overridden;

  const Entitlements({required this.plan, this.expiresAt, this.overridden = false});

  /// What a household looks like before its row has arrived.
  ///
  /// **Free, not Plus.** The load is a couple of hundred milliseconds and the
  /// two wrong answers are not equal: opening a paywall to somebody who has
  /// paid is a support mail, and briefly showing a Plus feature to somebody who
  /// has not is a feature that vanishes in their hands.
  static const unknown = Entitlements(plan: Plan.free);

  /// The plan after the expiry backstop, which is the one every limit is read
  /// from.
  ///
  /// **The webhook is the source of truth and this is not a second opinion.**
  /// `store-webhook` moves `plan` back to free when Apple or Google say the
  /// subscription ended; this only catches the case where that notification
  /// never arrived at all. Hence [_expiryGrace] being absurdly long: Apple's
  /// billing retry runs up to 16 days and Google's up to 30, and during those
  /// the household is still a paying customer whose card simply failed. Cutting
  /// them off on the day `expiresAt` passes would take Plus away from somebody
  /// mid-renewal, which is a worse failure than a month of unpaid Plus for the
  /// rare household whose webhook was lost.
  Plan get effectivePlan {
    if (plan != Plan.plus) return plan;
    final until = expiresAt;
    if (until == null) return Plan.plus;
    return DateTime.now().isBefore(until.add(_expiryGrace)) ? Plan.plus : Plan.free;
  }

  static const _expiryGrace = Duration(days: 35);

  bool get isPlus => effectivePlan == Plan.plus;

  /// How many of [feature] this household may have. **Null means no limit**;
  /// zero means the feature is not theirs at all.
  int? limitFor(Feature feature) => _limits[effectivePlan]![feature];

  /// Whether the household may use [feature] at all — the question a whole
  /// screen or a menu row asks (Ausgaben, photographs).
  bool allows(Feature feature) => limitFor(feature) != 0;

  /// Whether one more of [feature] may be created, given how many there are
  /// now. The question every "+" button asks.
  ///
  /// [current] is the count the household can actually see. For members that is
  /// people already in the family *plus* invitations still outstanding — an
  /// invite that has been sent is a seat that is spoken for, and counting only
  /// accepted ones lets a free household invite six people and discover the
  /// limit when the last two cannot join.
  bool allowsAnother(Feature feature, int current) {
    final limit = limitFor(feature);
    if (limit == null) return true;
    return current < limit;
  }

  /// **Every number in the product, in one table.**
  ///
  /// Free is a complete app for a household with two calendars, and that is the
  /// design: a free tier that is worse than the calendar already on the phone
  /// converts nobody, because nobody stays long enough to be converted. So all
  /// of Kalender, Home and Board are here, **including creating, editing and
  /// deleting events** — the gate is on how many places you can write to, not
  /// on whether you can write.
  static const _limits = <Plan, Map<Feature, int?>>{
    Plan.free: {
      Feature.calendarAccounts: 2,
      Feature.trackers: 3,
      Feature.boxes: 1,
      Feature.members: 4,
      Feature.photos: 0,
      Feature.spend: 0,
    },
    Plan.plus: {
      Feature.calendarAccounts: null,
      Feature.trackers: null,
      Feature.boxes: null,
      Feature.members: null,
      Feature.photos: null,
      Feature.spend: null,
    },
  };

  Entitlements copyWith({Plan? plan, DateTime? expiresAt, bool? overridden}) => Entitlements(
    plan: plan ?? this.plan,
    expiresAt: expiresAt ?? this.expiresAt,
    overridden: overridden ?? this.overridden,
  );
}

/// What the paywall says it is about, keyed on the feature that was reached.
///
/// Here rather than in the sheet because the sheet is one widget and these are
/// seven different promises — and because a new [Feature] should not compile
/// until somebody has written the sentence that explains it, the same trade
/// `AppStrings` makes for the rest of the app.
String paywallTitle(Feature feature) => switch (feature) {
  Feature.calendarAccounts => L.s.paywallCalendarsTitle,
  Feature.trackers => L.s.paywallTrackersTitle,
  Feature.boxes => L.s.paywallBoxesTitle,
  Feature.members => L.s.paywallMembersTitle,
  Feature.photos => L.s.paywallPhotosTitle,
  Feature.spend => L.s.paywallSpendTitle,
};

String paywallBody(Feature feature) => switch (feature) {
  Feature.calendarAccounts => L.s.paywallCalendarsBody,
  Feature.trackers => L.s.paywallTrackersBody,
  Feature.boxes => L.s.paywallBoxesBody,
  Feature.members => L.s.paywallMembersBody,
  Feature.photos => L.s.paywallPhotosBody,
  Feature.spend => L.s.paywallSpendBody,
};
