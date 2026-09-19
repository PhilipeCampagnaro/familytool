import Flutter
import UIKit
import WebKit

/// The town's own waste-calendar page, opened inside the app so that the file
/// its "iCal export" button produces comes back to us rather than going to
/// Apple Calendar. Behind the "aporah/calendarPage" channel that
/// `lib/services/calendar_page_browser.dart` calls; registered in AppDelegate.
///
/// **Why this exists at all.** A town that keeps its dates from apps (the
/// `upload` flag in abfall_providers.ts) leaves the household one route: fetch
/// the `.ics` themselves and hand it over. On an iPhone, Safari never lets
/// them have it — a `text/calendar` response goes straight to the "Add to
/// Calendar" sheet, and there is no file to pick afterwards. Here the same
/// page runs in a `WKWebView`, and any response that is a calendar is taken as
/// a `WKDownload` instead of being shown.
///
/// It is a browser, not a scraper: the household navigates the town's page
/// themselves, on their own phone, and taps the export the town offers them.
/// Nothing is fetched that they did not ask for, and nothing is kept — the
/// data store is non-persistent, and the file goes back to Dart, which reads
/// it and deletes it.
///
/// The result is the media picker's shape (`path`, `name`, `isImage`), or nil
/// when the page was closed without a calendar.
final class CalendarPageBrowser: NSObject {
  private var pending: FlutterResult?
  private weak var navigation: UINavigationController?
  private weak var webView: WKWebView?
  private var labels: [String: String] = [:]
  /// Whether a PDF plan counts as the calendar — `pdfUploadAvailable` on the
  /// Dart side, off until the server can read one.
  private var acceptPdf = false
  private var observations: [NSKeyValueObservation] = []
  private var backItem: UIBarButtonItem?
  private var forwardItem: UIBarButtonItem?

  /// Where each running download is being written, and the name the server
  /// suggested for it.
  private var downloads: [ObjectIdentifier: (url: URL, name: String)] = [:]

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "open",
          let arguments = call.arguments as? [String: Any],
          let raw = arguments["url"] as? String,
          let url = URL(string: raw),
          url.scheme?.lowercased() == "https"
    else {
      result(FlutterError(code: "bad_url", message: "https URL required", details: nil))
      return
    }
    labels = arguments["labels"] as? [String: String] ?? [:]
    acceptPdf = arguments["acceptPdf"] as? Bool ?? false
    present(url, result)
  }

  // MARK: - Presenting

  private func present(_ url: URL, _ result: @escaping FlutterResult) {
    guard let host = topViewController else {
      result(FlutterError(code: "no_host", message: "nothing to present from", details: nil))
      return
    }
    finish(nil)
    pending = result

    let configuration = WKWebViewConfiguration()
    // Cookie banners come back every time; in exchange the town's page leaves
    // nothing behind in the app.
    configuration.websiteDataStore = .nonPersistent()
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.allowsBackForwardNavigationGestures = true

    let page = UIViewController()
    page.view = webView
    page.title = url.host
    page.navigationItem.prompt = labels["prompt"]
    page.navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .close, target: self, action: #selector(close))

    let back = UIBarButtonItem(
      image: UIImage(systemName: "chevron.backward"), style: .plain, target: webView,
      action: #selector(WKWebView.goBack))
    let forward = UIBarButtonItem(
      image: UIImage(systemName: "chevron.forward"), style: .plain, target: webView,
      action: #selector(WKWebView.goForward))
    back.isEnabled = false
    forward.isEnabled = false
    page.toolbarItems = [back, .fixedSpace(24), forward, .flexibleSpace()]
    backItem = back
    forwardItem = forward
    observations = [
      webView.observe(\.canGoBack) { [weak self] view, _ in self?.backItem?.isEnabled = view.canGoBack },
      webView.observe(\.canGoForward) { [weak self] view, _ in self?.forwardItem?.isEnabled = view.canGoForward },
    ]

    let navigation = UINavigationController(rootViewController: page)
    navigation.isToolbarHidden = false
    navigation.presentationController?.delegate = self
    self.navigation = navigation
    self.webView = webView

    webView.load(URLRequest(url: url))
    host.present(navigation, animated: true)
  }

  @objc private func close() {
    navigation?.dismiss(animated: true)
    finish(nil)
  }

  /// The controller to present from: the key window's root, walked down past
  /// anything already up.
  private var topViewController: UIViewController? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    var controller = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = controller?.presentedViewController {
      controller = presented
    }
    return controller
  }

  private func finish(_ value: Any?) {
    pending?(value)
    pending = nil
    observations = []
    for (_, target) in downloads { try? FileManager.default.removeItem(at: target.url) }
    downloads = [:]
  }

  // MARK: - What is a calendar

  private static let calendarTypes: Set<String> = ["text/calendar", "application/ics", "text/x-vcalendar"]
  private static let calendarExtensions: Set<String> = ["ics", "ical", "icalendar", "ifb", "vcs"]

  private func isCalendar(_ response: URLResponse) -> Bool {
    if let mime = response.mimeType?.lowercased(), Self.calendarTypes.contains(mime) { return true }
    let name = response.suggestedFilename ?? response.url?.lastPathComponent ?? ""
    return Self.calendarExtensions.contains((name as NSString).pathExtension.lowercased())
  }

  /// A printed plan. WebKit would happily show it inline, which is exactly
  /// what must not happen once it is wanted: shown, it is a picture of dates;
  /// downloaded, it is a file the server can read.
  private func isPdf(_ response: URLResponse) -> Bool {
    guard acceptPdf else { return false }
    if response.mimeType?.lowercased() == "application/pdf" { return true }
    let name = response.suggestedFilename ?? response.url?.lastPathComponent ?? ""
    return (name as NSString).pathExtension.lowercased() == "pdf"
  }

  /// A finished download: handed back if it opens like an iCalendar file (or,
  /// with [acceptPdf], like a PDF), otherwise thrown away with a word to the
  /// household, who stay on the page.
  private func examine(_ file: URL, name: String) {
    let head = (try? FileHandle(forReadingFrom: file)).flatMap { handle -> Data? in
      defer { try? handle.close() }
      return try? handle.read(upToCount: 4096)
    }
    if acceptPdf, let head, head.starts(with: Array("%PDF".utf8)) {
      let base = (name as NSString).deletingPathExtension
      navigation?.dismiss(animated: true)
      finish(["path": file.path, "name": "\(base.isEmpty ? "Abfallkalender" : base).pdf", "isImage": false])
      return
    }
    let text = head.map { String(decoding: $0, as: UTF8.self).uppercased() } ?? ""
    guard text.contains("BEGIN:VCALENDAR") else {
      try? FileManager.default.removeItem(at: file)
      alert(labels["notCalendar"])
      return
    }
    let ext = (name as NSString).pathExtension.lowercased()
    let filename = Self.calendarExtensions.contains(ext) ? name : "\(name).ics"
    navigation?.dismiss(animated: true)
    finish(["path": file.path, "name": filename, "isImage": false])
  }

  private func alert(_ message: String?) {
    guard let message, let navigation else { return }
    let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: labels["ok"] ?? "OK", style: .default))
    navigation.present(alert, animated: true)
  }
}

// MARK: - Navigation

extension CalendarPageBrowser: WKNavigationDelegate {
  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    if navigationAction.shouldPerformDownload {
      decisionHandler(.download)
      return
    }
    guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
      decisionHandler(.allow)
      return
    }
    switch scheme {
    case "http", "https", "about", "blob", "data":
      decisionHandler(.allow)
    case "webcal", "webcals":
      // A subscription link: in Safari it would subscribe Apple Calendar to
      // the feed. Here it is fetched once, over https, as the file it is.
      decisionHandler(.cancel)
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      components?.scheme = "https"
      if let https = components?.url {
        webView.startDownload(using: URLRequest(url: https)) { [weak self] download in
          download.delegate = self
        }
      }
    default:
      // mailto:, tel:, an app's own scheme — nothing a waste calendar needs,
      // and nothing to leave the app for from here.
      decisionHandler(.cancel)
    }
  }

  func webView(
    _ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    // A calendar, or anything the web view could not show — an octet-stream
    // with a `.ics` name, say. Whatever it is gets examined once it is here.
    if isCalendar(navigationResponse.response) || isPdf(navigationResponse.response)
      || !navigationResponse.canShowMIMEType
    {
      decisionHandler(.download)
    } else {
      decisionHandler(.allow)
    }
  }

  func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
    download.delegate = self
  }

  func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
    download.delegate = self
  }
}

extension CalendarPageBrowser: WKUIDelegate {
  /// A link with `target="_blank"` — town pages love them for the export —
  /// opens in this same view rather than nowhere.
  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
    return nil
  }
}

// MARK: - Downloads

extension CalendarPageBrowser: WKDownloadDelegate {
  func download(
    _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
    completionHandler: @escaping (URL?) -> Void
  ) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("calendar-page", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let target = folder.appendingPathComponent(UUID().uuidString)
    downloads[ObjectIdentifier(download)] = (target, suggestedFilename)
    completionHandler(target)
  }

  func downloadDidFinish(_ download: WKDownload) {
    guard let target = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
    examine(target.url, name: target.name)
  }

  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    if let target = downloads.removeValue(forKey: ObjectIdentifier(download)) {
      try? FileManager.default.removeItem(at: target.url)
    }
    alert(labels["failed"])
  }
}

// MARK: - Swiped down

extension CalendarPageBrowser: UIAdaptivePresentationControllerDelegate {
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    finish(nil)
  }
}
