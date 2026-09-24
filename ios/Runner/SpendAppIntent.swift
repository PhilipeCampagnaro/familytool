import AppIntents
import Foundation

/// The action a household picks in Shortcuts, and the whole point of rebuilding
/// spend capture natively.
///
/// ## What this replaces
///
/// The old web app's flow was: copy a family-wide token to the clipboard,
/// download a shortcut from an iCloud link, paste the token at an import prompt,
/// add the shortcut, then build a Transaction automation around a "Get Contents
/// of URL" action. The user handled a credential, and every step of that was a
/// place to get it wrong.
///
/// An `AppShortcutsProvider` donation appears in Shortcuts **on install**, with
/// nothing downloaded and nothing pasted. What remains is the automation itself:
/// Shortcuts → Automation → Wallet → pick cards → pick "Ausgabe erfassen" → fill
/// Händler and Betrag with the trigger's variables. The trigger was called
/// "Transaction" before iOS renamed it; the setup steps in `lib/l10n/` name it.
///
/// ## What could not be removed, and why
///
/// **No app can install a Personal Automation.** There is no API, and there
/// never has been. Apps that look pre-configured in Shortcuts are donating
/// *actions*, exactly as this one does — a trigger is always the user's to
/// create. Do not go looking for a deep link that creates one; `shortcuts://`
/// has no verb for it.
///
/// ## The parameters are not to be trusted
///
/// Apple's own Transaction trigger sometimes hands a custom App Intent an empty
/// merchant or an amount of `0.0`. It was reported to DTS, who reproduced that
/// built-in actions receive the same variables intact, and it is unresolved. So
/// nothing is validated away here: whatever arrives is posted, and
/// `spend-ingest` files it with a `needs_review` flag. Dropping a payment the
/// user watched happen, on a locked phone, with no way to tell them, is the one
/// outcome worse than a row that needs a two-second fix.
///
/// ## The titles are localized, and not through `lib/l10n/`
///
/// Everything else in the app goes through `lib/l10n/`, and even the native tab
/// bar has its labels pushed over a method channel. This cannot: the system
/// reads an intent's title out of the app bundle to list it in Shortcuts and
/// Spotlight, long before any Flutter engine exists to ask.
///
/// So the German literals below are **keys**, and the four translations live in
/// `Localizable.xcstrings` (this intent) and `AppShortcuts.xcstrings` (the Siri
/// phrases), both in the Runner target. Adding a string here means adding it
/// there, in all four languages — there is no compiler to catch a missing one,
/// which is exactly the guarantee `AppStrings` gives on the Dart side and this
/// cannot.
///
/// **`Localizable.xcstrings`'s "Ausgabe erfassen" and `AppStrings`'s
/// `spendWalletStep4` name the same thing and must agree.** The setup steps tell
/// the user which action to pick out of a list; if the two drift, the app names
/// an action that is not there, in a screen whose only job is to be followed
/// literally.
@available(iOS 16.0, *)
struct LogSpendIntent: AppIntent {
  static var title: LocalizedStringResource = "Ausgabe erfassen"

  static var description = IntentDescription(
    "Speichert eine Apple-Pay-Zahlung in aporah. Am besten mit einer Kurzbefehl-Automation „Wallet\" verbinden."
  )

  /// Runs in the background. Opening the app for this would put Aporah on screen
  /// a second after every payment, which is not what anybody wants from a
  /// spending tracker.
  static var openAppWhenRun = false

  @Parameter(title: "Händler")
  var merchant: String

  @Parameter(title: "Betrag")
  var amount: Double

  /// Optional, and defaulted to now in `perform`. A Transaction automation can
  /// supply the payment's own date; a user running the action by hand has no
  /// reason to be asked for one.
  @Parameter(title: "Datum")
  var date: Date?

  @Parameter(title: "Karte")
  var card: String?

  static var parameterSummary: some ParameterSummary {
    Summary("\(\.$amount) bei \(\.$merchant) in aporah erfassen") {
      \.$date
      \.$card
    }
  }

  func perform() async throws -> some IntentResult {
    guard SpendCredential.hasToken() else {
      // Surfaced when somebody runs the action by hand before switching spend
      // tracking on in the app. In a background automation nobody sees it, which
      // is why the app's own setup screen checks the same thing up front.
      throw AporahIntentError.notEnrolled
    }

    // Cents, rounded once, here. Currency arithmetic on a Double is fine for the
    // single multiplication it takes to leave Double behind; carrying the Double
    // any further is what drifts.
    let cents = Int((abs(amount) * 100).rounded())

    let sent = await SpendIngest.post(
      merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
      amountCents: cents,
      occurredAt: date ?? Date(),
      cardLabel: card?.trimmingCharacters(in: .whitespacesAndNewlines)
    )

    guard sent else { throw AporahIntentError.notSent }
    return .result()
  }
}

@available(iOS 16.0, *)
enum AporahIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
  case notEnrolled
  case notSent

  var localizedStringResource: LocalizedStringResource {
    switch self {
    case .notEnrolled:
      return "Ausgaben-Erfassung ist in aporah noch nicht aktiviert."
    case .notSent:
      return "Die Ausgabe konnte nicht gespeichert werden."
    }
  }
}

/// What makes the action show up in Shortcuts without the user installing
/// anything.
///
/// The phrases are what Siri listens for. `applicationName` resolves to the
/// app's display name, so they stay right if it is ever renamed — and at least
/// one phrase must contain it, or the provider fails to build.
@available(iOS 16.0, *)
struct AporahShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: LogSpendIntent(),
      phrases: [
        "Ausgabe in \(.applicationName) erfassen",
        "Zahlung in \(.applicationName) speichern",
        "Log a spend in \(.applicationName)",
      ],
      shortTitle: "Ausgabe erfassen",
      systemImageName: "creditcard"
    )
  }
}
