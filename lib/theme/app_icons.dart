import 'package:flutter/widgets.dart';

/// **The app's icon set: Phosphor Duotone.**
///
/// Replaced Lucide, which is one monoline stroke weight by design and has no
/// duotone — fills are documented as unofficial, and the "Lucide duotone" that
/// turns up in searches is a Figma plugin's invention rather than the library's.
/// Phosphor is the one free family that ships every glyph in six weights
/// including a real duotone, which is why the swap was possible at all: 163
/// glyphs found an honest twin, and none had to be drawn by hand.
///
/// ## A duotone glyph is two codepoints, not one
///
/// The font holds an under-layer and an over-layer at adjacent codepoints, and
/// the icon is the two drawn on top of each other with the lower one faded —
/// which is all [AppIcon] does. Nearly always the under-layer is the
/// over-layer's codepoint minus one, but **not always**: 48 of Phosphor's 1510
/// pairs break that rule (`buildings`, `crane`, most of the `file*` set), so
/// the pairing is a table rather than arithmetic.
///
/// ## Everything here is `const`, and it has to be
///
/// A release build runs `--tree-shake-icons`, which walks the program's
/// constant `IconData` instantiations and keeps only the glyphs it can see
/// named. An `IconData` assembled at runtime from an `int` is invisible to it
/// and the build **fails** rather than quietly shipping the whole 567 KB font.
/// That is why [_underLayers] spells its values out instead of adding one to a
/// codepoint. Tree-shaking then cuts the font to about 20 KB.
///
/// ## Why the font is vendored rather than depended on
///
/// `phosphor_flutter` is the obvious way to get this and it **does not
/// compile**: its `PhosphorIconData extends IconData`, and Flutter has since
/// made `IconData` a final class. It has not shipped since May 2024, so there
/// is no fixed version to wait for — and note that `flutter analyze` passes on
/// it, because the analyzer does not enforce `final class` on a dependency's
/// superclass the way the front-end compiler does. So
/// `assets/icons/Phosphor-Duotone.ttf` is vendored (MIT, licence beside it, the
/// same arrangement as the Meteocons) and the codepoints are named here.
///
/// ## Adding one
///
/// Take both codepoints from Phosphor's `Duotone` font — the over-layer for
/// [AppIcons], the under-layer for [_underLayers] — and add a line to each.
/// Forget the second and the glyph still draws, just flat, which is the one
/// mistake this file cannot catch for you.

/// The vendored fonts' families, as declared in `pubspec.yaml`. Two weights of
/// the same set: [_family] is what an icon is *named* in, [_regularFamily] is
/// what it is drawn in whenever the duotone is not wanted — see [_regular].
const _family = 'PhosphorDuotone';
const _regularFamily = 'PhosphorRegular';

/// Every glyph the app draws, under Phosphor's own names.
///
/// Where two Lucide names collapsed into one Phosphor glyph the collapse is
/// deliberate and was already true of the drawings: `home`/`house`,
/// `trash`/`trash2`, `box`/`package`, `user`/`userRound`, and
/// `circleCheck`/`circleCheckBig` were pairs the old set distinguished on paper
/// and not on screen.
abstract final class AppIcons {
  static const airplane = IconData(0xe003, fontFamily: _family);
  static const archive = IconData(0xe00d, fontFamily: _family);
  static const arrowLeft = IconData(0xe059, fontFamily: _family);
  static const arrowRight = IconData(0xe06d, fontFamily: _family);
  static const arrowSquareOut = IconData(0xe5df, fontFamily: _family);
  static const arrowUUpLeft = IconData(0xe08b, fontFamily: _family);
  static const arrowUp = IconData(0xe08f, fontFamily: _family);
  static const baby = IconData(0xe775, fontFamily: _family);
  static const bandaids = IconData(0xe0b3, fontFamily: _family);
  static const barbell = IconData(0xe0b7, fontFamily: _family);
  static const barcode = IconData(0xe0b9, fontFamily: _family);
  static const basket = IconData(0xe965, fontFamily: _family);
  static const bathtub = IconData(0xe81f, fontFamily: _family);
  static const batteryCharging = IconData(0xe0bb, fontFamily: _family);
  static const bed = IconData(0xe0cd, fontFamily: _family);
  static const beerStein = IconData(0xeb63, fontFamily: _family);
  static const bell = IconData(0xe0cf, fontFamily: _family);
  static const bicycle = IconData(0xe0d7, fontFamily: _family);
  static const boat = IconData(0xe787, fontFamily: _family);
  static const book = IconData(0xe0e3, fontFamily: _family);
  static const bookOpenText = IconData(0xe8f3, fontFamily: _family);
  static const briefcase = IconData(0xe0ef, fontFamily: _family);
  static const bus = IconData(0xe107, fontFamily: _family);
  static const cake = IconData(0xe781, fontFamily: _family);
  static const calendar = IconData(0xe109, fontFamily: _family);
  static const calendarDots = IconData(0xe7b5, fontFamily: _family);
  static const calendarPlus = IconData(0xe715, fontFamily: _family);
  static const calendarSlash = IconData(0xea13, fontFamily: _family);
  static const camera = IconData(0xe10f, fontFamily: _family);
  static const car = IconData(0xe113, fontFamily: _family);
  static const caretDown = IconData(0xe137, fontFamily: _family);
  static const caretLeft = IconData(0xe139, fontFamily: _family);
  static const caretRight = IconData(0xe13b, fontFamily: _family);
  static const caretUp = IconData(0xe13d, fontFamily: _family);
  static const caretUpDown = IconData(0xe141, fontFamily: _family);
  static const check = IconData(0xe183, fontFamily: _family);
  static const checkCircle = IconData(0xe185, fontFamily: _family);
  static const circle = IconData(0xe18b, fontFamily: _family);
  static const circleDashed = IconData(0xe603, fontFamily: _family);
  static const circleHalf = IconData(0xe18d, fontFamily: _family);
  static const clipboardText = IconData(0xe199, fontFamily: _family);
  static const clock = IconData(0xe19b, fontFamily: _family);
  static const coffee = IconData(0xe1c3, fontFamily: _family);
  static const confetti = IconData(0xe81b, fontFamily: _family);
  static const cookingPot = IconData(0xe765, fontFamily: _family);
  static const copy = IconData(0xe1cb, fontFamily: _family);
  static const couch = IconData(0xe7f7, fontFamily: _family);
  static const creditCard = IconData(0xe1d3, fontFamily: _family);
  static const deviceMobile = IconData(0xe1e1, fontFamily: _family);
  static const doorOpen = IconData(0xe7e7, fontFamily: _family);
  static const dotsThreeVertical = IconData(0xe209, fontFamily: _family);
  static const drop = IconData(0xe211, fontFamily: _family);
  static const egg = IconData(0xe813, fontFamily: _family);
  static const envelope = IconData(0xe215, fontFamily: _family);
  static const envelopeOpen = IconData(0xe217, fontFamily: _family);
  static const eye = IconData(0xe221, fontFamily: _family);
  static const eyeSlash = IconData(0xe225, fontFamily: _family);
  static const eyeglasses = IconData(0xe7bb, fontFamily: _family);
  static const fileText = IconData(0xe23b, fontFamily: _family);
  static const flame = IconData(0xe625, fontFamily: _family);
  static const flower = IconData(0xe75f, fontFamily: _family);
  static const flowerTulip = IconData(0xeacd, fontFamily: _family);
  static const folder = IconData(0xe24b, fontFamily: _family);
  static const footprints = IconData(0xea89, fontFamily: _family);
  static const forkKnife = IconData(0xe263, fontFamily: _family);
  static const gameController = IconData(0xe26f, fontFamily: _family);
  static const gasPump = IconData(0xe769, fontFamily: _family);
  static const gift = IconData(0xe277, fontFamily: _family);
  static const graduationCap = IconData(0xe62d, fontFamily: _family);
  static const hammer = IconData(0xe80f, fontFamily: _family);
  static const hardHat = IconData(0xed47, fontFamily: _family);
  static const headphones = IconData(0xe2a7, fontFamily: _family);
  static const heart = IconData(0xe2a9, fontFamily: _family);
  static const heartbeat = IconData(0xe2ad, fontFamily: _family);
  static const house = IconData(0xe2c3, fontFamily: _family);
  static const iceCream = IconData(0xe805, fontFamily: _family);
  static const image = IconData(0xe2cb, fontFamily: _family);
  static const info = IconData(0xe2cf, fontFamily: _family);
  static const key = IconData(0xe2d7, fontFamily: _family);
  static const keyboard = IconData(0xe2d9, fontFamily: _family);
  static const lamp = IconData(0xe639, fontFamily: _family);
  static const laptop = IconData(0xe587, fontFamily: _family);
  static const layout = IconData(0xe6d7, fontFamily: _family);
  static const leaf = IconData(0xe2db, fontFamily: _family);
  static const link = IconData(0xe2e3, fontFamily: _family);
  static const linkBreak = IconData(0xe2e5, fontFamily: _family);
  static const list = IconData(0xe2f1, fontFamily: _family);
  static const listChecks = IconData(0xeadd, fontFamily: _family);
  static const listPlus = IconData(0xe2f9, fontFamily: _family);
  static const lock = IconData(0xe2fb, fontFamily: _family);
  static const magnifyingGlass = IconData(0xe30d, fontFamily: _family);
  static const mapPin = IconData(0xe317, fontFamily: _family);
  static const mapTrifold = IconData(0xe31b, fontFamily: _family);
  static const minus = IconData(0xe32b, fontFamily: _family);
  static const money = IconData(0xe589, fontFamily: _family);
  static const monitor = IconData(0xe32f, fontFamily: _family);
  static const moon = IconData(0xe331, fontFamily: _family);
  static const musicNotes = IconData(0xe341, fontFamily: _family);
  static const navigationArrow = IconData(0xeadf, fontFamily: _family);
  static const package = IconData(0xe391, fontFamily: _family);
  static const paintRoller = IconData(0xe6f5, fontFamily: _family);
  static const palette = IconData(0xe6c9, fontFamily: _family);
  static const paperPlaneTilt = IconData(0xe399, fontFamily: _family);
  static const paperclip = IconData(0xe39b, fontFamily: _family);
  static const pawPrint = IconData(0xe649, fontFamily: _family);
  static const pencilSimple = IconData(0xe3b5, fontFamily: _family);
  static const pill = IconData(0xe701, fontFamily: _family);
  static const pizza = IconData(0xe797, fontFamily: _family);
  static const plant = IconData(0xebaf, fontFamily: _family);
  static const plug = IconData(0xe947, fontFamily: _family);
  static const plugsConnected = IconData(0xeb5b, fontFamily: _family);
  static const plus = IconData(0xe3d5, fontFamily: _family);
  static const printer = IconData(0xe3dd, fontFamily: _family);
  static const qrCode = IconData(0xe3e7, fontFamily: _family);
  static const receipt = IconData(0xe3f1, fontFamily: _family);
  static const recycle = IconData(0xe75b, fontFamily: _family);
  static const repeat = IconData(0xe3f9, fontFamily: _family);
  static const ruler = IconData(0xe6b9, fontFamily: _family);
  static const scan = IconData(0xebb7, fontFamily: _family);
  static const scissors = IconData(0xeae1, fontFamily: _family);
  static const screwdriver = IconData(0xe86f, fontFamily: _family);
  static const shapes = IconData(0xec5f, fontFamily: _family);
  static const shieldCheck = IconData(0xe40f, fontFamily: _family);
  static const shoppingBag = IconData(0xe417, fontFamily: _family);
  static const shoppingCart = IconData(0xe41f, fontFamily: _family);
  static const shovel = IconData(0xe9e7, fontFamily: _family);
  static const signOut = IconData(0xe42b, fontFamily: _family);
  static const snowflake = IconData(0xe5ab, fontFamily: _family);
  static const sparkle = IconData(0xe6a3, fontFamily: _family);
  static const spinnerGap = IconData(0xe66d, fontFamily: _family);
  static const sprayBottle = IconData(0xe7e8, fontFamily: _family);
  static const stack = IconData(0xe467, fontFamily: _family);
  static const stackSimple = IconData(0xe469, fontFamily: _family);
  static const star = IconData(0xe46b, fontFamily: _family);
  static const stethoscope = IconData(0xe7eb, fontFamily: _family);
  static const storefront = IconData(0xe471, fontFamily: _family);
  static const suitcaseRolling = IconData(0xe9b1, fontFamily: _family);
  static const sun = IconData(0xe473, fontFamily: _family);
  static const syringe = IconData(0xe969, fontFamily: _family);
  static const tShirt = IconData(0xe671, fontFamily: _family);
  static const tag = IconData(0xe479, fontFamily: _family);
  static const television = IconData(0xe755, fontFamily: _family);
  static const tent = IconData(0xe8bb, fontFamily: _family);
  static const train = IconData(0xe497, fontFamily: _family);
  static const translate = IconData(0xe4a3, fontFamily: _family);
  static const trash = IconData(0xe4a7, fontFamily: _family);
  static const tree = IconData(0xe6db, fontFamily: _family);
  static const treeEvergreen = IconData(0xe6dd, fontFamily: _family);
  static const umbrella = IconData(0xe685, fontFamily: _family);
  static const user = IconData(0xe4c3, fontFamily: _family);
  static const userCheck = IconData(0xeafb, fontFamily: _family);
  static const userMinus = IconData(0xe4cf, fontFamily: _family);
  static const userPlus = IconData(0xe4d1, fontFamily: _family);
  static const users = IconData(0xe4d7, fontFamily: _family);
  static const wallet = IconData(0xe68b, fontFamily: _family);
  static const warehouse = IconData(0xecd5, fontFamily: _family);
  static const warning = IconData(0xe4e1, fontFamily: _family);
  static const washingMachine = IconData(0xede9, fontFamily: _family);
  static const watch = IconData(0xe4e7, fontFamily: _family);
  static const wind = IconData(0xe5d3, fontFamily: _family);
  static const wine = IconData(0xe6b3, fontFamily: _family);
  static const wrench = IconData(0xe5d5, fontFamily: _family);
  static const x = IconData(0xe4f7, fontFamily: _family);
  static const xCircle = IconData(0xe4f9, fontFamily: _family);
}

/// Each over-layer codepoint paired with the under-layer that goes behind it.
/// Keyed by `int` rather than `IconData` so the map itself can be `const`:
/// `IconData` overrides `==`, and Dart refuses a constant map key that does.
///
/// ## Fourteen glyphs are deliberately missing, and must stay missing
///
/// `check`, `minus`, `plus`, `x`, `dotsThreeVertical`, the four `arrow*` and
/// the five `caret*`. **Do not add pairs for them** — the absence is what makes
/// [AppIcon] draw them flat, and drawing them flat is the point.
///
/// A duotone icon works because the drawing has two things in it: a lens and a
/// handle, an envelope and its flap, a battery and its body. A bare mark has
/// only itself, and Phosphor's duotone handles that in two ways, both of which
/// look wrong at the sizes this app uses them:
///
/// - **A placeholder box.** `check`, `x`, `plus`, `minus` and
///   `dotsThreeVertical` get a faint rounded rectangle around the mark's
///   bounding box — a stand-in for a second layer, not a part of the drawing.
///   On the sheet header's confirm button it reads as a check *inside a box*.
/// - **A solid copy of the mark itself.** Every `caret*` and `arrow*` puts the
///   filled shape underneath and leaves only its **outline** on top, so a
///   chevron comes out as a hollow triangle instead of the crisp mark a
///   disclosure row needs.
///
/// Telling those apart from a real under-layer is a judgement, not a rule a
/// script can apply: `laptop`, `monitor`, `signOut`, `batteryCharging`,
/// `gasPump`, `headphones`, `iceCream` and `recycle` all have rounded-rect
/// under-layers too, and in every one of those the rectangle *is* something —
/// a screen, a door, a battery body. Those keep their pairs.
///
/// The under-layer glyphs of the fourteen are then referenced by nothing, so
/// tree-shaking drops them from the font as well.
const Map<int, IconData> _underLayers = {
  0xe003: IconData(0xe002, fontFamily: _family),
  0xe00d: IconData(0xe00c, fontFamily: _family),
  0xe5df: IconData(0xe5de, fontFamily: _family),
  0xe775: IconData(0xe774, fontFamily: _family),
  0xe0b3: IconData(0xe0b2, fontFamily: _family),
  0xe0b7: IconData(0xe0b6, fontFamily: _family),
  0xe0b9: IconData(0xe0b8, fontFamily: _family),
  0xe965: IconData(0xe964, fontFamily: _family),
  0xe81f: IconData(0xe81e, fontFamily: _family),
  0xe0bb: IconData(0xe0ba, fontFamily: _family),
  0xe0cd: IconData(0xe0cc, fontFamily: _family),
  0xeb63: IconData(0xeb62, fontFamily: _family),
  0xe0cf: IconData(0xe0ce, fontFamily: _family),
  0xe0d7: IconData(0xe0d6, fontFamily: _family),
  0xe787: IconData(0xe786, fontFamily: _family),
  0xe0e3: IconData(0xe0e2, fontFamily: _family),
  0xe8f3: IconData(0xe8f2, fontFamily: _family),
  0xe0ef: IconData(0xe0ee, fontFamily: _family),
  0xe107: IconData(0xe106, fontFamily: _family),
  0xe781: IconData(0xe780, fontFamily: _family),
  0xe109: IconData(0xe108, fontFamily: _family),
  0xe7b5: IconData(0xe7b4, fontFamily: _family),
  0xe715: IconData(0xe714, fontFamily: _family),
  0xea13: IconData(0xea12, fontFamily: _family),
  0xe10f: IconData(0xe10e, fontFamily: _family),
  0xe113: IconData(0xe112, fontFamily: _family),
  0xe185: IconData(0xe184, fontFamily: _family),
  0xe18b: IconData(0xe18a, fontFamily: _family),
  0xe603: IconData(0xe602, fontFamily: _family),
  0xe18d: IconData(0xe18c, fontFamily: _family),
  0xe199: IconData(0xe198, fontFamily: _family),
  0xe19b: IconData(0xe19a, fontFamily: _family),
  0xe1c3: IconData(0xe1c2, fontFamily: _family),
  0xe81b: IconData(0xe81a, fontFamily: _family),
  0xe765: IconData(0xe764, fontFamily: _family),
  0xe1cb: IconData(0xe1ca, fontFamily: _family),
  0xe7f7: IconData(0xe7f6, fontFamily: _family),
  0xe1d3: IconData(0xe1d2, fontFamily: _family),
  0xe1e1: IconData(0xe1e0, fontFamily: _family),
  0xe7e7: IconData(0xe7e6, fontFamily: _family),
  0xe211: IconData(0xe210, fontFamily: _family),
  0xe813: IconData(0xe812, fontFamily: _family),
  0xe215: IconData(0xe214, fontFamily: _family),
  0xe217: IconData(0xe216, fontFamily: _family),
  0xe221: IconData(0xe220, fontFamily: _family),
  0xe225: IconData(0xe224, fontFamily: _family),
  0xe7bb: IconData(0xe7ba, fontFamily: _family),
  0xe23b: IconData(0xe23a, fontFamily: _family),
  0xe625: IconData(0xe624, fontFamily: _family),
  0xe75f: IconData(0xe75e, fontFamily: _family),
  0xeacd: IconData(0xeacc, fontFamily: _family),
  0xe24b: IconData(0xe24a, fontFamily: _family),
  0xea89: IconData(0xea88, fontFamily: _family),
  0xe263: IconData(0xe262, fontFamily: _family),
  0xe26f: IconData(0xe26e, fontFamily: _family),
  0xe769: IconData(0xe768, fontFamily: _family),
  0xe277: IconData(0xe276, fontFamily: _family),
  0xe62d: IconData(0xe62c, fontFamily: _family),
  0xe80f: IconData(0xe80e, fontFamily: _family),
  0xed47: IconData(0xed46, fontFamily: _family),
  0xe2a7: IconData(0xe2a6, fontFamily: _family),
  0xe2a9: IconData(0xe2a8, fontFamily: _family),
  0xe2ad: IconData(0xe2ac, fontFamily: _family),
  0xe2c3: IconData(0xe2c2, fontFamily: _family),
  0xe805: IconData(0xe804, fontFamily: _family),
  0xe2cb: IconData(0xe2ca, fontFamily: _family),
  0xe2cf: IconData(0xe2ce, fontFamily: _family),
  0xe2d7: IconData(0xe2d6, fontFamily: _family),
  0xe2d9: IconData(0xe2d8, fontFamily: _family),
  0xe639: IconData(0xe638, fontFamily: _family),
  0xe587: IconData(0xe586, fontFamily: _family),
  0xe6d7: IconData(0xe6d6, fontFamily: _family),
  0xe2db: IconData(0xe2da, fontFamily: _family),
  0xe2e3: IconData(0xe2e2, fontFamily: _family),
  0xe2e5: IconData(0xe2e4, fontFamily: _family),
  0xe2f1: IconData(0xe2f0, fontFamily: _family),
  0xeadd: IconData(0xeadc, fontFamily: _family),
  0xe2f9: IconData(0xe2f8, fontFamily: _family),
  0xe2fb: IconData(0xe2fa, fontFamily: _family),
  0xe30d: IconData(0xe30c, fontFamily: _family),
  0xe317: IconData(0xe316, fontFamily: _family),
  0xe31b: IconData(0xe31a, fontFamily: _family),
  0xe589: IconData(0xe588, fontFamily: _family),
  0xe32f: IconData(0xe32e, fontFamily: _family),
  0xe331: IconData(0xe330, fontFamily: _family),
  0xe341: IconData(0xe340, fontFamily: _family),
  0xeadf: IconData(0xeade, fontFamily: _family),
  0xe391: IconData(0xe390, fontFamily: _family),
  0xe6f5: IconData(0xe6f4, fontFamily: _family),
  0xe6c9: IconData(0xe6c8, fontFamily: _family),
  0xe399: IconData(0xe398, fontFamily: _family),
  0xe39b: IconData(0xe39a, fontFamily: _family),
  0xe649: IconData(0xe648, fontFamily: _family),
  0xe3b5: IconData(0xe3b4, fontFamily: _family),
  0xe701: IconData(0xe700, fontFamily: _family),
  0xe797: IconData(0xe796, fontFamily: _family),
  0xebaf: IconData(0xebae, fontFamily: _family),
  0xe947: IconData(0xe946, fontFamily: _family),
  0xeb5b: IconData(0xeb5a, fontFamily: _family),
  0xe3dd: IconData(0xe3dc, fontFamily: _family),
  0xe3e7: IconData(0xe3e6, fontFamily: _family),
  0xe3f1: IconData(0xe3ec, fontFamily: _family),
  0xe75b: IconData(0xe75a, fontFamily: _family),
  0xe3f9: IconData(0xe3f6, fontFamily: _family),
  0xe6b9: IconData(0xe6b8, fontFamily: _family),
  0xebb7: IconData(0xebb6, fontFamily: _family),
  0xeae1: IconData(0xeae0, fontFamily: _family),
  0xe86f: IconData(0xe86e, fontFamily: _family),
  0xec5f: IconData(0xec5e, fontFamily: _family),
  0xe40f: IconData(0xe40c, fontFamily: _family),
  0xe417: IconData(0xe416, fontFamily: _family),
  0xe41f: IconData(0xe41e, fontFamily: _family),
  0xe9e7: IconData(0xe9e6, fontFamily: _family),
  0xe42b: IconData(0xe42a, fontFamily: _family),
  0xe5ab: IconData(0xe5aa, fontFamily: _family),
  0xe6a3: IconData(0xe6a2, fontFamily: _family),
  0xe66d: IconData(0xe66c, fontFamily: _family),
  0xe7e8: IconData(0xe7e4, fontFamily: _family),
  0xe467: IconData(0xe466, fontFamily: _family),
  0xe469: IconData(0xe468, fontFamily: _family),
  0xe46b: IconData(0xe46a, fontFamily: _family),
  0xe7eb: IconData(0xe7ea, fontFamily: _family),
  0xe471: IconData(0xe470, fontFamily: _family),
  0xe9b1: IconData(0xe9b0, fontFamily: _family),
  0xe473: IconData(0xe472, fontFamily: _family),
  0xe969: IconData(0xe968, fontFamily: _family),
  0xe671: IconData(0xe670, fontFamily: _family),
  0xe479: IconData(0xe478, fontFamily: _family),
  0xe755: IconData(0xe754, fontFamily: _family),
  0xe8bb: IconData(0xe8ba, fontFamily: _family),
  0xe497: IconData(0xe496, fontFamily: _family),
  0xe4a3: IconData(0xe4a2, fontFamily: _family),
  0xe4a7: IconData(0xe4a6, fontFamily: _family),
  0xe6db: IconData(0xe6da, fontFamily: _family),
  0xe6dd: IconData(0xe6dc, fontFamily: _family),
  0xe685: IconData(0xe684, fontFamily: _family),
  0xe4c3: IconData(0xe4c2, fontFamily: _family),
  0xeafb: IconData(0xeafa, fontFamily: _family),
  0xe4cf: IconData(0xe4ce, fontFamily: _family),
  0xe4d1: IconData(0xe4d0, fontFamily: _family),
  0xe4d7: IconData(0xe4d6, fontFamily: _family),
  0xe68b: IconData(0xe68a, fontFamily: _family),
  0xecd5: IconData(0xecd4, fontFamily: _family),
  0xe4e1: IconData(0xe4e0, fontFamily: _family),
  0xede9: IconData(0xede8, fontFamily: _family),
  0xe4e7: IconData(0xe4e6, fontFamily: _family),
  0xe5d3: IconData(0xe5d2, fontFamily: _family),
  0xe6b3: IconData(0xe6b2, fontFamily: _family),
  0xe5d5: IconData(0xe5d4, fontFamily: _family),
  0xe4f9: IconData(0xe4f8, fontFamily: _family),
};

/// The **Regular** weight of each glyph, keyed by its duotone over-layer
/// codepoint — the single-weight icon Phosphor draws when there is no second
/// layer, which is a different drawing from the duotone's top layer and not
/// merely the same one without a fill.
///
/// That distinction is the whole reason this table exists. The duotone
/// `caret-right` is drawn as a hollow **triangle**; the regular one is the thin
/// **chevron** a disclosure row wants, and they share nothing but a name.
/// `arrow-right` is the same story, and the duotone `check` is shrunk to fit
/// inside its placeholder box, so used alone it comes out visibly smaller than
/// the real one. For most glyphs the two weights *are* the same drawing —
/// `pencilSimple`, `trash`, `camera`, `qrCode`, `calendarPlus` are identical —
/// but "most" is not something a button should depend on.
///
/// So: **flat means the Regular weight**, not the duotone with its under-layer
/// left off. [AppIcon] reads this whenever it is not stacking two layers, which
/// covers both `flat: true` controls and the fourteen bare marks.
const Map<int, IconData> _regular = {
  0xe003: IconData(0xe002, fontFamily: _regularFamily),
  0xe00d: IconData(0xe00c, fontFamily: _regularFamily),
  0xe059: IconData(0xe058, fontFamily: _regularFamily),
  0xe06d: IconData(0xe06c, fontFamily: _regularFamily),
  0xe5df: IconData(0xe5de, fontFamily: _regularFamily),
  0xe08b: IconData(0xe08a, fontFamily: _regularFamily),
  0xe08f: IconData(0xe08e, fontFamily: _regularFamily),
  0xe775: IconData(0xe774, fontFamily: _regularFamily),
  0xe0b3: IconData(0xe0b2, fontFamily: _regularFamily),
  0xe0b7: IconData(0xe0b6, fontFamily: _regularFamily),
  0xe0b9: IconData(0xe0b8, fontFamily: _regularFamily),
  0xe965: IconData(0xe964, fontFamily: _regularFamily),
  0xe81f: IconData(0xe81e, fontFamily: _regularFamily),
  0xe0bb: IconData(0xe0ba, fontFamily: _regularFamily),
  0xe0cd: IconData(0xe0cc, fontFamily: _regularFamily),
  0xeb63: IconData(0xeb62, fontFamily: _regularFamily),
  0xe0cf: IconData(0xe0ce, fontFamily: _regularFamily),
  0xe0d7: IconData(0xe0d6, fontFamily: _regularFamily),
  0xe787: IconData(0xe786, fontFamily: _regularFamily),
  0xe0e3: IconData(0xe0e2, fontFamily: _regularFamily),
  0xe8f3: IconData(0xe8f2, fontFamily: _regularFamily),
  0xe0ef: IconData(0xe0ee, fontFamily: _regularFamily),
  0xe107: IconData(0xe106, fontFamily: _regularFamily),
  0xe781: IconData(0xe780, fontFamily: _regularFamily),
  0xe109: IconData(0xe108, fontFamily: _regularFamily),
  0xe7b5: IconData(0xe7b4, fontFamily: _regularFamily),
  0xe715: IconData(0xe714, fontFamily: _regularFamily),
  0xea13: IconData(0xea12, fontFamily: _regularFamily),
  0xe10f: IconData(0xe10e, fontFamily: _regularFamily),
  0xe113: IconData(0xe112, fontFamily: _regularFamily),
  0xe137: IconData(0xe136, fontFamily: _regularFamily),
  0xe139: IconData(0xe138, fontFamily: _regularFamily),
  0xe13b: IconData(0xe13a, fontFamily: _regularFamily),
  0xe13d: IconData(0xe13c, fontFamily: _regularFamily),
  0xe141: IconData(0xe140, fontFamily: _regularFamily),
  0xe183: IconData(0xe182, fontFamily: _regularFamily),
  0xe185: IconData(0xe184, fontFamily: _regularFamily),
  0xe18b: IconData(0xe18a, fontFamily: _regularFamily),
  0xe603: IconData(0xe602, fontFamily: _regularFamily),
  0xe18d: IconData(0xe18c, fontFamily: _regularFamily),
  0xe199: IconData(0xe198, fontFamily: _regularFamily),
  0xe19b: IconData(0xe19a, fontFamily: _regularFamily),
  0xe1c3: IconData(0xe1c2, fontFamily: _regularFamily),
  0xe81b: IconData(0xe81a, fontFamily: _regularFamily),
  0xe765: IconData(0xe764, fontFamily: _regularFamily),
  0xe1cb: IconData(0xe1ca, fontFamily: _regularFamily),
  0xe7f7: IconData(0xe7f6, fontFamily: _regularFamily),
  0xe1d3: IconData(0xe1d2, fontFamily: _regularFamily),
  0xe1e1: IconData(0xe1e0, fontFamily: _regularFamily),
  0xe7e7: IconData(0xe7e6, fontFamily: _regularFamily),
  0xe209: IconData(0xe208, fontFamily: _regularFamily),
  0xe211: IconData(0xe210, fontFamily: _regularFamily),
  0xe813: IconData(0xe812, fontFamily: _regularFamily),
  0xe215: IconData(0xe214, fontFamily: _regularFamily),
  0xe217: IconData(0xe216, fontFamily: _regularFamily),
  0xe221: IconData(0xe220, fontFamily: _regularFamily),
  0xe225: IconData(0xe224, fontFamily: _regularFamily),
  0xe7bb: IconData(0xe7ba, fontFamily: _regularFamily),
  0xe23b: IconData(0xe23a, fontFamily: _regularFamily),
  0xe625: IconData(0xe624, fontFamily: _regularFamily),
  0xe75f: IconData(0xe75e, fontFamily: _regularFamily),
  0xeacd: IconData(0xeacc, fontFamily: _regularFamily),
  0xe24b: IconData(0xe24a, fontFamily: _regularFamily),
  0xea89: IconData(0xea88, fontFamily: _regularFamily),
  0xe263: IconData(0xe262, fontFamily: _regularFamily),
  0xe26f: IconData(0xe26e, fontFamily: _regularFamily),
  0xe769: IconData(0xe768, fontFamily: _regularFamily),
  0xe277: IconData(0xe276, fontFamily: _regularFamily),
  0xe62d: IconData(0xe62c, fontFamily: _regularFamily),
  0xe80f: IconData(0xe80e, fontFamily: _regularFamily),
  0xed47: IconData(0xed46, fontFamily: _regularFamily),
  0xe2a7: IconData(0xe2a6, fontFamily: _regularFamily),
  0xe2a9: IconData(0xe2a8, fontFamily: _regularFamily),
  0xe2ad: IconData(0xe2ac, fontFamily: _regularFamily),
  0xe2c3: IconData(0xe2c2, fontFamily: _regularFamily),
  0xe805: IconData(0xe804, fontFamily: _regularFamily),
  0xe2cb: IconData(0xe2ca, fontFamily: _regularFamily),
  0xe2cf: IconData(0xe2ce, fontFamily: _regularFamily),
  0xe2d7: IconData(0xe2d6, fontFamily: _regularFamily),
  0xe2d9: IconData(0xe2d8, fontFamily: _regularFamily),
  0xe639: IconData(0xe638, fontFamily: _regularFamily),
  0xe587: IconData(0xe586, fontFamily: _regularFamily),
  0xe6d7: IconData(0xe6d6, fontFamily: _regularFamily),
  0xe2db: IconData(0xe2da, fontFamily: _regularFamily),
  0xe2e3: IconData(0xe2e2, fontFamily: _regularFamily),
  0xe2e5: IconData(0xe2e4, fontFamily: _regularFamily),
  0xe2f1: IconData(0xe2f0, fontFamily: _regularFamily),
  0xeadd: IconData(0xeadc, fontFamily: _regularFamily),
  0xe2f9: IconData(0xe2f8, fontFamily: _regularFamily),
  0xe2fb: IconData(0xe2fa, fontFamily: _regularFamily),
  0xe30d: IconData(0xe30c, fontFamily: _regularFamily),
  0xe317: IconData(0xe316, fontFamily: _regularFamily),
  0xe31b: IconData(0xe31a, fontFamily: _regularFamily),
  0xe32b: IconData(0xe32a, fontFamily: _regularFamily),
  0xe589: IconData(0xe588, fontFamily: _regularFamily),
  0xe32f: IconData(0xe32e, fontFamily: _regularFamily),
  0xe331: IconData(0xe330, fontFamily: _regularFamily),
  0xe341: IconData(0xe340, fontFamily: _regularFamily),
  0xeadf: IconData(0xeade, fontFamily: _regularFamily),
  0xe391: IconData(0xe390, fontFamily: _regularFamily),
  0xe6f5: IconData(0xe6f4, fontFamily: _regularFamily),
  0xe6c9: IconData(0xe6c8, fontFamily: _regularFamily),
  0xe399: IconData(0xe398, fontFamily: _regularFamily),
  0xe39b: IconData(0xe39a, fontFamily: _regularFamily),
  0xe649: IconData(0xe648, fontFamily: _regularFamily),
  0xe3b5: IconData(0xe3b4, fontFamily: _regularFamily),
  0xe701: IconData(0xe700, fontFamily: _regularFamily),
  0xe797: IconData(0xe796, fontFamily: _regularFamily),
  0xebaf: IconData(0xebae, fontFamily: _regularFamily),
  0xe947: IconData(0xe946, fontFamily: _regularFamily),
  0xeb5b: IconData(0xeb5a, fontFamily: _regularFamily),
  0xe3d5: IconData(0xe3d4, fontFamily: _regularFamily),
  0xe3dd: IconData(0xe3dc, fontFamily: _regularFamily),
  0xe3e7: IconData(0xe3e6, fontFamily: _regularFamily),
  0xe3f1: IconData(0xe3ec, fontFamily: _regularFamily),
  0xe75b: IconData(0xe75a, fontFamily: _regularFamily),
  0xe3f9: IconData(0xe3f6, fontFamily: _regularFamily),
  0xe6b9: IconData(0xe6b8, fontFamily: _regularFamily),
  0xebb7: IconData(0xebb6, fontFamily: _regularFamily),
  0xeae1: IconData(0xeae0, fontFamily: _regularFamily),
  0xe86f: IconData(0xe86e, fontFamily: _regularFamily),
  0xec5f: IconData(0xec5e, fontFamily: _regularFamily),
  0xe40f: IconData(0xe40c, fontFamily: _regularFamily),
  0xe417: IconData(0xe416, fontFamily: _regularFamily),
  0xe41f: IconData(0xe41e, fontFamily: _regularFamily),
  0xe9e7: IconData(0xe9e6, fontFamily: _regularFamily),
  0xe42b: IconData(0xe42a, fontFamily: _regularFamily),
  0xe5ab: IconData(0xe5aa, fontFamily: _regularFamily),
  0xe6a3: IconData(0xe6a2, fontFamily: _regularFamily),
  0xe66d: IconData(0xe66c, fontFamily: _regularFamily),
  0xe7e8: IconData(0xe7e4, fontFamily: _regularFamily),
  0xe467: IconData(0xe466, fontFamily: _regularFamily),
  0xe469: IconData(0xe468, fontFamily: _regularFamily),
  0xe46b: IconData(0xe46a, fontFamily: _regularFamily),
  0xe7eb: IconData(0xe7ea, fontFamily: _regularFamily),
  0xe471: IconData(0xe470, fontFamily: _regularFamily),
  0xe9b1: IconData(0xe9b0, fontFamily: _regularFamily),
  0xe473: IconData(0xe472, fontFamily: _regularFamily),
  0xe969: IconData(0xe968, fontFamily: _regularFamily),
  0xe671: IconData(0xe670, fontFamily: _regularFamily),
  0xe479: IconData(0xe478, fontFamily: _regularFamily),
  0xe755: IconData(0xe754, fontFamily: _regularFamily),
  0xe8bb: IconData(0xe8ba, fontFamily: _regularFamily),
  0xe497: IconData(0xe496, fontFamily: _regularFamily),
  0xe4a3: IconData(0xe4a2, fontFamily: _regularFamily),
  0xe4a7: IconData(0xe4a6, fontFamily: _regularFamily),
  0xe6db: IconData(0xe6da, fontFamily: _regularFamily),
  0xe6dd: IconData(0xe6dc, fontFamily: _regularFamily),
  0xe685: IconData(0xe684, fontFamily: _regularFamily),
  0xe4c3: IconData(0xe4c2, fontFamily: _regularFamily),
  0xeafb: IconData(0xeafa, fontFamily: _regularFamily),
  0xe4cf: IconData(0xe4ce, fontFamily: _regularFamily),
  0xe4d1: IconData(0xe4d0, fontFamily: _regularFamily),
  0xe4d7: IconData(0xe4d6, fontFamily: _regularFamily),
  0xe68b: IconData(0xe68a, fontFamily: _regularFamily),
  0xecd5: IconData(0xecd4, fontFamily: _regularFamily),
  0xe4e1: IconData(0xe4e0, fontFamily: _regularFamily),
  0xede9: IconData(0xede8, fontFamily: _regularFamily),
  0xe4e7: IconData(0xe4e6, fontFamily: _regularFamily),
  0xe5d3: IconData(0xe5d2, fontFamily: _regularFamily),
  0xe6b3: IconData(0xe6b2, fontFamily: _regularFamily),
  0xe5d5: IconData(0xe5d4, fontFamily: _regularFamily),
  0xe4f7: IconData(0xe4f6, fontFamily: _regularFamily),
  0xe4f9: IconData(0xe4f8, fontFamily: _regularFamily),
};

/// How faint the under-layer sits behind the over-layer. Phosphor's own default
/// is 0.20; the app's ink is nearly black, and at 0.20 on white the under-layer
/// reads as a smudge rather than as a shape.
const double _secondaryOpacity = 0.26;

/// **Draw an icon with this, not with `Icon`.** A bare `Icon` renders the
/// over-layer alone, which is a thin, oddly hollow version of the glyph — the
/// duotone only exists once the under-layer is behind it.
///
/// Deliberately the same shape as `Icon`: same positional argument, same
/// optional [size] and [color], same fallback to the surrounding `IconTheme`
/// when they are left off. That is what let the swap be a rename at 112 call
/// sites rather than a rewrite of each one.
///
/// A glyph with no under-layer falls through to a plain `Icon`. That covers two
/// different things on purpose. **The fourteen bare marks** listed on
/// [_underLayers] are meant to land here — a check, an x, a caret and an arrow
/// are drawn flat because their duotone is a placeholder box or a hollow
/// outline. **Anything else** that lands here is an accident — a Material or
/// Cupertino icon that wandered in, or a Phosphor one whose pair nobody added —
/// and it will look flat next to its neighbours, which is the right amount of
/// wrong: visible, not broken.
class AppIcon extends StatelessWidget {
  /// Nullable, exactly as `Icon`'s is — a row that has no glyph to show passes
  /// null and gets the same empty box of the right size that `Icon` gives it.
  final IconData? icon;
  final double? size;
  final Color? color;

  /// Overrides [_secondaryOpacity] for one icon. The accent glyph on a filled
  /// accent pill is the case that needs it: the under-layer there is competing
  /// with a coloured ground rather than with white.
  final double? secondaryOpacity;

  /// **Draw the outline alone: this glyph is a control, not a label.**
  ///
  /// The rule the app follows is about what an icon is *for*, not what it looks
  /// like. An icon that names a thing — a settings row, a menu row, a list, a
  /// box, an empty state — keeps its duotone, because the second layer is
  /// carrying weight and meaning. An icon that *is* the control you press —
  /// the glyph on a glass button, a disclosure caret — is drawn flat.
  ///
  /// Two reasons, and the second is the one that decided it:
  ///
  /// - A control is small, and often sits on a filled or frosted ground where
  ///   a 26%-opacity under-layer has nothing to be read against.
  /// - A duotone glyph is a little picture, and a button is not a picture. The
  ///   button's own material already provides the mass; the glyph on it only
  ///   has to say which button it is, and a second layer makes that read
  ///   slower rather than richer.
  ///
  /// Set by the glass button widgets rather than by their callers, so a button
  /// is flat wherever it is used and nobody has to remember. The fourteen bare
  /// marks on [_underLayers] are flat regardless, for an unrelated reason.
  final bool flat;

  const AppIcon(this.icon, {super.key, this.size, this.color, this.secondaryOpacity, this.flat = false});

  @override
  Widget build(BuildContext context) {
    final glyph = icon;
    final under = flat || glyph == null ? null : _underLayers[glyph.codePoint];
    // Not stacking two layers, so draw the real single-weight icon rather than
    // the duotone's top layer on its own — see [_regular] for why those are not
    // the same picture.
    if (under == null) {
      return Icon(glyph == null ? null : _regular[glyph.codePoint] ?? glyph, size: size, color: color);
    }

    // Resolved rather than passed straight through, because the two layers have
    // to agree on a colour and the under one needs to know what it is fading.
    // `IconTheme` is where `Icon` would have got it, so an `AppIcon` with
    // neither argument lands exactly where the `Icon` it replaced did.
    final theme = IconTheme.of(context);
    final resolved = color ?? theme.color ?? const Color(0xFF000000);
    final drawnSize = size ?? theme.size;
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(under, size: drawnSize, color: resolved.withValues(alpha: secondaryOpacity ?? _secondaryOpacity)),
        Icon(icon, size: drawnSize, color: resolved),
      ],
    );
  }
}
