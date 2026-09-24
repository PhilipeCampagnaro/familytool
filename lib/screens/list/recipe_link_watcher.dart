import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../services/external_links.dart';
import '../../services/recipe_fetch.dart';
import '../../state/list_planner_state.dart';
import '../../state/nav_state.dart';
import '../../widgets/toast_chip.dart';

/// Offers to build a Liste from a recipe link the reader has just copied.
///
/// ## Why a chip and not a button
///
/// This was a glass button beside the Vorhaben island first, and it was wrong
/// twice. It was **too much furniture** on a row whose job is one sentence, and
/// the glyph alone did not survive losing its label — a link mark on a header
/// is not a sentence anybody reads. It also sat on a UIKit platform view inside
/// the collapsing header, where the tap did not always arrive.
///
/// The chip has none of those problems and is a better fit besides: the app
/// already has exactly one transient surface above the nav bar, it is where
/// answers appear, and it can carry a word. A second bespoke suggestion
/// surface would have been a notification system.
///
/// ## When it appears, and why not more often
///
/// On **arrival in Listen** with a link on the clipboard — not on a timer, not
/// on every rebuild, and never while the reader is in another tab (every screen
/// is mounted at once, so that has to be asked: [activeTabProvider]).
///
/// **The clipboard is not read to decide this.** [clipboardHasUrl] asks iOS
/// whether there is a URL without looking at it, so the offer costs no paste
/// banner; the read happens on the tap, where it is earned. That is also why
/// the chip cannot name the site — it genuinely does not know it yet, and
/// finding out would be the thing it is avoiding.
///
/// ## Once per copy, not once per timer
///
/// The offer is keyed on the pasteboard's **generation** (iOS's
/// `changeCount`), so it comes back the moment something else is copied and
/// stays away for a link that has already been imported or declined. The first
/// version rationed by time instead, because it had no way to tell one copy
/// from the next — which got both halves wrong: copying a second recipe inside
/// the window produced nothing, and the same stale link came back round after
/// it.
///
/// That answer is kept in [_handledGenerationProvider] rather than in this
/// widget, which does not outlive a visit to a list. [_quiet] and
/// [_lastOfferProvider] survive only for Android, which has no such counter.
///
/// ## Why it also polls
///
/// Coming back from Safari is a resume, and that is the trigger that matters.
/// But a copy can happen with the app already in front — Split View, Stage
/// Manager, a simulator driven from a terminal — and then there is no lifecycle
/// event at all. So while Listen is on screen and the app is awake, the
/// generation is read every [_pollEvery]. It is one integer from UIKit with no
/// banner and no content, and the timer is cancelled the moment either
/// condition stops holding.
class RecipeLinkWatcher extends ConsumerStatefulWidget {
  const RecipeLinkWatcher({super.key});

  @override
  ConsumerState<RecipeLinkWatcher> createState() => _RecipeLinkWatcherState();
}

/// How long after one offer before another is possible, **where the platform
/// cannot say whether the clipboard has changed** — Android only.
const _quiet = Duration(minutes: 2);

/// How often the pasteboard's generation is checked while Listen is in front.
const _pollEvery = Duration(seconds: 2);

/// What the reader has already been offered: the pasteboard generation, and —
/// where the platform has no such counter — the time it happened.
///
/// **Outside the widget on purpose.** [RecipeLinkWatcher] sits in the
/// overview's header, and opening a list swaps that entire subtree for the
/// detail screen, so the widget is disposed and built afresh on every visit.
/// Held as fields, the answer was forgotten on the way *into* a list, and the
/// same link came back the moment the reader came out — including the one they
/// had just imported, and the one they had just closed with the X.
final _handledGenerationProvider = StateProvider<int?>((ref) => null);
final _lastOfferProvider = StateProvider<DateTime?>((ref) => null);

class _RecipeLinkWatcherState extends ConsumerState<RecipeLinkWatcher> with WidgetsBindingObserver {
  Timer? _poll;
  bool _awake = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Runs only while there is a reason to: Listen in front, and the app awake.
  void _syncPoll() {
    final wanted = _awake && ref.read(activeTabProvider) == listsTabIndex;
    if (wanted == (_poll != null)) return;
    if (wanted) {
      _poll = Timer.periodic(_pollEvery, (_) => _maybeOffer());
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Coming back from Safari with a link copied is the single most likely way
  /// this feature is reached, so the check runs again on resume — but only if
  /// Listen is what the reader will be looking at.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _awake = state == AppLifecycleState.resumed;
    _syncPoll();
    if (!_awake) return;
    if (ref.read(activeTabProvider) != listsTabIndex) return;
    _maybeOffer();
  }

  Future<void> _maybeOffer() async {
    // Already inside Vorhaben: the field is right there and an offer would be
    // the app talking over itself.
    if (ref.read(plannerProvider).open) return;

    final state = await clipboardState();
    if (!mounted || !state.hasUrl) return;
    if (ref.read(activeTabProvider) != listsTabIndex) return;

    final generation = state.generation;
    if (generation != null) {
      // The platform can tell one copy from the next: offer once per copy and
      // no more, however long the link sits there.
      if (generation == ref.read(_handledGenerationProvider)) return;
      ref.read(_handledGenerationProvider.notifier).state = generation;
    } else {
      final last = ref.read(_lastOfferProvider);
      if (last != null && DateTime.now().difference(last) < _quiet) return;
      ref.read(_lastOfferProvider.notifier).state = DateTime.now();
    }

    showActionToast(
      context,
      L.s.plannerLinkOnClipboard,
      actionLabel: L.s.plannerPasteLink,
      onAction: _import,
    );
  }

  /// **Never fails silently.** This read is the one place the feature can go
  /// wrong without the card ever appearing: iOS puts its paste banner up here,
  /// and a reader who does not allow it — or who copied something that turned
  /// out not to be a link after all — gets `null` back. The first version
  /// returned on that, which from the outside is a button that does nothing.
  Future<void> _import() async {
    final url = await clipboardUrl();
    if (!mounted) return;
    final uri = url == null ? null : recipePageUrl(url);
    if (uri == null) {
      showToast(context, L.s.plannerClipboardUnreadable, kind: ToastKind.error);
      return;
    }
    await ref.read(plannerProvider.notifier).runImport(uri);
  }

  @override
  Widget build(BuildContext context) {
    // Arrival in Listen, watched rather than polled.
    ref.listen<int>(activeTabProvider, (was, now) {
      _syncPoll();
      if (now == listsTabIndex && was != listsTabIndex) _maybeOffer();
    });
    // The tab may already be Listen on the first build — a restart lands
    // wherever the shell last was — so the timer is started here too.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPoll();
    });
    // Draws nothing: it is a listener that happens to need a place in the tree.
    return const SizedBox.shrink();
  }
}
