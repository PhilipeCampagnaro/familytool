import Flutter
import StoreKit
import SwiftUI
import UIKit

/// aporah Plus through StoreKit 2 — the "aporah/store" channel.
///
/// **This file sells and reports, and it grants nothing.** Every transaction it
/// hands Dart is Apple's own signed JWS, which Dart posts to `store-verify`
/// untouched; the Edge Function checks Apple's signature chain and is what
/// writes `families.plan`. So a jailbroken phone that lies from here gets a
/// household that is still on free — the app's view of the plan is read back
/// off the household row, never off this channel.
///
/// **A transaction is finished only once the server has it** (`finish`). An
/// unfinished one is handed back by `StoreKit.Transaction.unfinished` and
/// `StoreKit.Transaction.updates` on every launch, which is the retry: a purchase made
/// on a train with no signal, or one whose post to `store-verify` failed,
/// reaches the household the next time the app opens rather than being charged
/// and lost.
///
/// **The choice between monthly and yearly is the store's own screen.** On iOS
/// 17+ that is `SubscriptionStoreView` — prices, the trial, Apple's wording of
/// the renewal terms, restore and the policy links App Review asks for, all
/// localised by the system. Below 17 it is a plain action sheet of the two
/// products, since the view does not exist there. See
/// `lib/services/store_billing.dart`.
final class StoreKitBridge {
  private weak var channel: FlutterMethodChannel?
  private var updates: Task<Void, Never>?

  /// Starts listening for transactions that arrive outside a purchase call —
  /// renewals, Ask to Buy approvals, a purchase finished on another device, a
  /// refund. Apple asks for this listener to exist from launch, or such
  /// transactions are missed.
  func attach(_ channel: FlutterMethodChannel) {
    self.channel = channel
    updates?.cancel()
    updates = Task.detached { [weak self] in
      for await result in StoreKit.Transaction.updates {
        guard case .verified(let transaction) = result else { continue }
        await self?.forward(Self.wire(result.jwsRepresentation, transaction))
      }
    }
  }

  @MainActor
  private func forward(_ transaction: [String: Any]) {
    channel?.invokeMethod("transaction", arguments: transaction)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "products":
      let ids = args["ids"] as? [String] ?? []
      Task { @MainActor in
        do {
          result(try await Self.describe(ids))
        } catch {
          result(FlutterError(code: "store", message: error.localizedDescription, details: nil))
        }
      }

    case "showStore":
      let ids = args["ids"] as? [String] ?? []
      guard let token = UUID(uuidString: args["accountToken"] as? String ?? "") else {
        result(FlutterError(code: "args", message: "accountToken must be a uuid", details: nil))
        return
      }
      Task { @MainActor in
        guard let scene = Self.activeScene(), let host = Self.topController(in: scene) else {
          result(["status": "unavailable"])
          return
        }
        if #available(iOS 17.0, *) {
          Self.presentStoreView(
            ids: ids,
            token: token,
            terms: URL(string: args["termsUrl"] as? String ?? ""),
            privacy: URL(string: args["privacyUrl"] as? String ?? ""),
            over: host,
            result: result
          )
        } else {
          await Self.presentActionSheet(
            ids: ids,
            token: token,
            title: args["title"] as? String,
            cancel: args["cancel"] as? String ?? "Cancel",
            over: host,
            scene: scene,
            result: result
          )
        }
      }

    case "current":
      Task { result(await Self.collect(StoreKit.Transaction.currentEntitlements)) }

    case "unfinished":
      Task { result(await Self.collect(StoreKit.Transaction.unfinished)) }

    case "restore":
      Task {
        do {
          // Asks the App Store for this Apple ID's purchases. May put up a
          // sign-in prompt, which is why it is only ever run from a button.
          try await AppStore.sync()
        } catch StoreKitError.userCancelled {
          result(nil)
          return
        } catch {
          result(FlutterError(code: "store", message: error.localizedDescription, details: nil))
          return
        }
        result(await Self.collect(StoreKit.Transaction.currentEntitlements))
      }

    case "finish":
      let id = args["id"] as? String ?? ""
      Task {
        for await item in StoreKit.Transaction.unfinished {
          guard case .verified(let transaction) = item, String(transaction.id) == id else { continue }
          await transaction.finish()
        }
        result(nil)
      }

    case "manage":
      Task { @MainActor in
        guard let scene = Self.activeScene() else {
          result(false)
          return
        }
        do {
          try await AppStore.showManageSubscriptions(in: scene)
          result(true)
        } catch {
          result(false)
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Purchasing

  /// The system's own subscription screen. Answers once, whichever way it
  /// closes — bought, pending, or dismissed.
  @available(iOS 17.0, *)
  @MainActor
  private static func presentStoreView(
    ids: [String],
    token: UUID,
    terms: URL?,
    privacy: URL?,
    over host: UIViewController,
    result: @escaping FlutterResult
  ) {
    let once = Once(result)
    var controller: UIViewController?
    let view = PlusStoreView(ids: ids, token: token, terms: terms, privacy: privacy) { answer in
      once.send(answer)
      controller?.dismiss(animated: true)
    } onDisappear: {
      // Swiped down or closed with the store's own button: nothing was bought.
      once.send(["status": "cancelled"])
    }
    let hosting = UIHostingController(rootView: view)
    controller = hosting
    host.present(hosting, animated: true)
  }

  /// iOS 15 and 16: the two products as a system action sheet, then Apple's
  /// purchase sheet for the one picked.
  @MainActor
  private static func presentActionSheet(
    ids: [String],
    token: UUID,
    title: String?,
    cancel: String,
    over host: UIViewController,
    scene: UIWindowScene,
    result: @escaping FlutterResult
  ) async {
    let products: [Product]
    do {
      products = try await Product.products(for: ids).sorted { $0.price < $1.price }
    } catch {
      result(FlutterError(code: "store", message: error.localizedDescription, details: nil))
      return
    }
    guard !products.isEmpty else {
      result(["status": "unavailable"])
      return
    }

    let once = Once(result)
    let sheet = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
    for product in products {
      sheet.addAction(UIAlertAction(title: "\(product.displayName) · \(product.displayPrice)", style: .default) { _ in
        Task { @MainActor in
          once.send(await purchase(product, token: token, scene: scene))
        }
      })
    }
    sheet.addAction(UIAlertAction(title: cancel, style: .cancel) { _ in
      once.send(["status": "cancelled"])
    })
    // An iPad presents an action sheet as a popover, which needs an anchor.
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = host.view
      popover.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.maxY, width: 0, height: 0)
      popover.permittedArrowDirections = []
    }
    host.present(sheet, animated: true)
  }

  @MainActor
  private static func purchase(_ product: Product, token: UUID, scene: UIWindowScene) async -> [String: Any] {
    do {
      let outcome: Product.PurchaseResult
      if #available(iOS 17.0, *) {
        outcome = try await product.purchase(confirmIn: scene, options: [.appAccountToken(token)])
      } else {
        outcome = try await product.purchase(options: [.appAccountToken(token)])
      }
      return answer(for: outcome)
    } catch {
      return ["status": "failed", "message": error.localizedDescription]
    }
  }

  fileprivate static func answer(for outcome: Product.PurchaseResult) -> [String: Any] {
    switch outcome {
    case .success(let verification):
      // A transaction that fails StoreKit's own check is not forwarded: the
      // server would refuse it too, and saying "purchased" over it would be
      // a lie told to the one person who just paid.
      guard case .verified(let transaction) = verification else {
        return ["status": "failed", "message": "unverified"]
      }
      return ["status": "purchased", "transaction": wire(verification.jwsRepresentation, transaction)]
    case .pending:
      // Ask to Buy, or a bank's own confirmation. The transaction arrives
      // later through `StoreKit.Transaction.updates`.
      return ["status": "pending"]
    case .userCancelled:
      return ["status": "cancelled"]
    @unknown default:
      return ["status": "cancelled"]
    }
  }

  // MARK: - Reading

  private static func describe(_ ids: [String]) async throws -> [[String: Any]] {
    let products = try await Product.products(for: ids)
    var out: [[String: Any]] = []
    for product in products {
      var row: [String: Any] = [
        "id": product.id,
        "displayName": product.displayName,
        "displayPrice": product.displayPrice,
      ]
      if let subscription = product.subscription {
        row["period"] = switch subscription.subscriptionPeriod.unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "unknown"
        }
        var trial = false
        if subscription.introductoryOffer != nil {
          trial = await Product.SubscriptionInfo.isEligibleForIntroOffer(for: subscription.subscriptionGroupID)
        }
        row["trial"] = trial
      }
      out.append(row)
    }
    return out
  }

  private static func collect(_ sequence: StoreKit.Transaction.Transactions) async -> [[String: Any]] {
    var out: [[String: Any]] = []
    for await result in sequence {
      guard case .verified(let transaction) = result else { continue }
      out.append(wire(result.jwsRepresentation, transaction))
    }
    return out
  }

  /// What crosses the channel for one transaction: Apple's signed JWS, which
  /// is the only thing the server believes, and the id `finish` needs back.
  fileprivate static func wire(_ jws: String, _ transaction: StoreKit.Transaction) -> [String: Any] {
    ["jws": jws, "id": String(transaction.id)]
  }

  // MARK: - UIKit

  private static func activeScene() -> UIWindowScene? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
  }

  private static func topController(in scene: UIWindowScene) -> UIViewController? {
    var top = scene.windows.first(where: \.isKeyWindow)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

/// A Flutter result that may be answered from two places — the purchase
/// completing and the view going away — and must be answered exactly once.
private final class Once {
  private var result: FlutterResult?
  init(_ result: @escaping FlutterResult) { self.result = result }
  func send(_ value: Any?) {
    result?(value)
    result = nil
  }
}

@available(iOS 17.0, *)
private struct PlusStoreView: View {
  let ids: [String]
  let token: UUID
  let terms: URL?
  let privacy: URL?
  let onAnswer: ([String: Any]) -> Void
  let onDisappear: () -> Void

  var body: some View {
    policies(
      SubscriptionStoreView(productIDs: ids)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        // The household is the customer, not the Apple ID: the token is the
        // family's id, and it rides every renewal Apple ever reports, which
        // is how `store-webhook` can find a household whose own post to
        // `store-verify` never arrived.
        .inAppPurchaseOptions { _ in [.appAccountToken(token)] }
        .onInAppPurchaseCompletion { _, outcome in
          switch outcome {
          case .success(let purchase):
            let answer = StoreKitBridge.answer(for: purchase)
            // A cancelled Apple sheet leaves the store screen up, which is
            // where the reader was — only a real outcome closes it.
            if answer["status"] as? String != "cancelled" { onAnswer(answer) }
          case .failure(let error):
            onAnswer(["status": "failed", "message": error.localizedDescription])
          }
        }
        .onDisappear(perform: onDisappear)
    )
  }

  @ViewBuilder
  private func policies(_ view: some View) -> some View {
    switch (terms, privacy) {
    case let (terms?, privacy?):
      view
        .subscriptionStorePolicyDestination(url: terms, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: privacy, for: .privacyPolicy)
    default:
      view
    }
  }
}
