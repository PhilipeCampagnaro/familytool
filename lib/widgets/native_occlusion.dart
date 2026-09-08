import 'package:flutter/widgets.dart';

/// Whether a route now sits **above** the one [context] belongs to — in which
/// case nothing built here may be an iOS platform view.
///
/// Every piece of native chrome in this app is a `UiKitView`: the tab bar
/// ([NativeTabBar]), the search field ([NativeSearchField]), the switch
/// ([NativeSwitch]) and the real `UIGlassEffect` behind [GlassSurface]. A
/// `UiKitView` is a UIKit view *composited into* the Flutter scene rather than
/// painted by it, and Flutter is supposed to lift anything drawn above one into
/// an overlay layer stacked over it. Where that fails, the native view simply
/// stays on top of everything — including a whole route.
///
/// That is what emptied every sheet in the app. A `showAppSheet` is a
/// **non-opaque** modal route, so the screen underneath keeps painting, native
/// chrome and all: the Listen/Boxen search field and the tab bar punched
/// straight through the sheet, and with enough of them on screen at once the
/// sheet's entire body went with them — the two glass buttons in its header
/// were all that was left, being platform views themselves. The tell is a sheet
/// whose chrome is right and whose content isn't there, which is the same tell
/// [showAppSheet] and [SheetSwitch] already document at a smaller scale.
///
/// So a native view stands down for as long as it is covered, and every caller
/// already has the fallback to stand down *to*: the branch each of these
/// widgets takes off iOS. [ModalRoute.isCurrentOf] is false exactly while
/// another route sits on top of this one, and reading it subscribes this
/// context to that one aspect — so the swap happens as the sheet opens and
/// reverses as it closes, with no navigator observer and no global state.
///
/// Null (no enclosing route at all) means nothing can be covering it.
bool occludedByRoute(BuildContext context) => ModalRoute.isCurrentOf(context) == false;
