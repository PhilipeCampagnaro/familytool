import Flutter
import Foundation
import UIKit

/// Where this device keeps its permission to file Apple Pay transactions.
///
/// The whole design turns on one fact: the App Intent that receives a
/// transaction runs with the phone locked, seconds after a payment, with no
/// Flutter engine guaranteed to be alive and no Supabase session to present. So
/// it cannot ask Dart for anything. Everything it needs has to be sitting here
/// already, put there once at enrolment by `lib/services/spend_intent.dart`.
///
/// `kSecAttrAccessibleAfterFirstUnlock` is the load-bearing attribute. The
/// obvious choice, `WhenUnlocked`, would make the token unreadable at exactly
/// the moment it is wanted — a Personal Automation fires while the phone is in a
/// pocket. `AfterFirstUnlock` means readable once the user has unlocked at least
/// once since boot, which for a phone somebody is paying with is always.
///
/// `ThisDeviceOnly` because the token names *this* device on the server. Letting
/// it sync to iCloud Keychain would put one device's credential on another,
/// where the revoke list in Settings would name a phone that is not the one
/// writing.
enum SpendCredential {
  private static let service = "app.aporah.spend"
  private static let tokenAccount = "ingest-token"
  private static let endpointAccount = "ingest-endpoint"
  private static let apiKeyAccount = "ingest-api-key"

  struct Stored {
    let token: String
    let endpoint: URL
    let apiKey: String
  }

  static func save(token: String, endpoint: String, apiKey: String) {
    write(tokenAccount, token)
    write(endpointAccount, endpoint)
    write(apiKeyAccount, apiKey)
  }

  static func clear() {
    [tokenAccount, endpointAccount, apiKeyAccount].forEach(delete)
  }

  static func hasToken() -> Bool {
    read(tokenAccount)?.isEmpty == false
  }

  /// All three or nothing. A token with no endpoint is not a usable credential,
  /// and posting to a stale address would fail silently in the background where
  /// nobody would ever see it.
  static func load() -> Stored? {
    guard let token = read(tokenAccount), !token.isEmpty,
          let endpoint = read(endpointAccount), let url = URL(string: endpoint),
          let apiKey = read(apiKeyAccount)
    else { return nil }
    return Stored(token: token, endpoint: url, apiKey: apiKey)
  }

  // MARK: - Keychain

  private static func query(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private static func write(_ account: String, _ value: String) {
    delete(account)
    guard let data = value.data(using: .utf8) else { return }
    var attributes = query(account)
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    SecItemAdd(attributes as CFDictionary, nil)
  }

  private static func read(_ account: String) -> String? {
    var attributes = query(account)
    attributes[kSecReturnData as String] = true
    attributes[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    guard SecItemCopyMatching(attributes as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private static func delete(_ account: String) {
    SecItemDelete(query(account) as CFDictionary)
  }
}

/// Posts one transaction to `spend-ingest`.
///
/// Deliberately dumb: it does not retry, does not queue, and does not care what
/// the server says beyond whether it answered. The endpoint dedupes and repairs
/// on its side, and an App Intent has a short leash — a retry loop here would
/// spend it and get the intent killed mid-flight, which is worse than one lost
/// row that the user can add by hand.
enum SpendIngest {
  /// Cents, so nothing can pick up a rounding error between the intent and the
  /// column. Shortcuts hands the intent a `Double`; this is the only place it is
  /// one.
  static func post(
    merchant: String,
    amountCents: Int,
    occurredAt: Date,
    cardLabel: String?
  ) async -> Bool {
    guard let credential = SpendCredential.load() else { return false }

    var request = URLRequest(url: credential.endpoint)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // The function runs with `verify_jwt = false`, so this identifies the
    // project to the gateway rather than the user to the function. The device
    // token in the body is what authorises the write.
    request.setValue(credential.apiKey, forHTTPHeaderField: "apikey")
    request.timeoutInterval = 20

    let payload: [String: Any] = [
      "token": credential.token,
      "merchant": merchant,
      "amount_cents": amountCents,
      "occurred_at": ISO8601DateFormatter().string(from: occurredAt),
      "card_label": cardLabel as Any,
    ]

    guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }
    request.httpBody = body

    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      let code = (response as? HTTPURLResponse)?.statusCode ?? 0
      return (200..<300).contains(code)
    } catch {
      return false
    }
  }
}

/// The method channel Dart talks to. Registered in `AppDelegate.swift` under
/// "aporah/spend", like every other service in `lib/services/`.
enum SpendChannel {
  static func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "hasToken":
      result(SpendCredential.hasToken())

    case "storeToken":
      guard let args = call.arguments as? [String: Any],
            let token = args["token"] as? String,
            let endpoint = args["endpoint"] as? String,
            let apiKey = args["api_key"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "token, endpoint and api_key required", details: nil))
        return
      }
      SpendCredential.save(token: token, endpoint: endpoint, apiKey: apiKey)
      result(nil)

    case "clearToken":
      SpendCredential.clear()
      result(nil)

    case "describeDevice":
      result([
        "label": UIDevice.current.name,
        // Empty only if the system refuses it, which it does not on a device
        // that has been unlocked. Dart treats an empty id as an enrolment it
        // cannot name and says so rather than writing a row keyed on nothing.
        "uid": UIDevice.current.identifierForVendor?.uuidString ?? "",
        // App Intents arrived in iOS 16; the deployment target is 15.
        "can_run_intents": ProcessInfo.processInfo.isOperatingSystemAtLeast(
          OperatingSystemVersion(majorVersion: 16, minorVersion: 0, patchVersion: 0)
        ),
      ])

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
