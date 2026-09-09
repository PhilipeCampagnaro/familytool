import AVFoundation
import Flutter
import UIKit

/// A full-screen QR scanner, behind the "aporah/scanner" channel that
/// `lib/services/code_scanner.dart` calls. Registered in AppDelegate.
///
/// Native for the same reason the photo picker is: a camera preview is a live
/// `AVCaptureVideoPreviewLayer`, and the alternative is a plugin that ships its
/// own one anyway. This is the whole of it — no torch, no gallery import, no
/// format zoo — because there is exactly one code in this app to scan, the one
/// WebUntis prints under "Zugriff über Untis Mobile", and everything beyond
/// that is a setting nobody asked for.
///
/// Answers the payload string, `nil` when the user backed out, and a
/// FlutterError otherwise: "denied" when camera access was refused, and
/// "unavailable" when the device has no camera to offer. Dart turns each into a
/// different sentence, because "point it at the code" and "type it in instead"
/// are different instructions.
final class CodeScanner: NSObject {
  private var pending: FlutterResult?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "scan", let host = topViewController else {
      result(FlutterMethodNotImplemented)
      return
    }

    // A second request finishes the first as a cancel rather than stranding it.
    finish(nil)

    let args = call.arguments as? [String: Any] ?? [:]
    guard AVCaptureDevice.default(for: .video) != nil else {
      result(FlutterError(code: "unavailable", message: "no camera", details: nil))
      return
    }

    pending = result

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      present(from: host, args: args)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          guard let self else { return }
          if granted {
            self.present(from: host, args: args)
          } else {
            self.finish(FlutterError(code: "denied", message: "camera denied", details: nil))
          }
        }
      }
    default:
      finish(FlutterError(code: "denied", message: "camera denied", details: nil))
    }
  }

  private func present(from host: UIViewController, args: [String: Any]) {
    let controller = ScannerViewController(
      title: args["title"] as? String,
      hint: args["hint"] as? String,
      cancelLabel: args["cancel"] as? String ?? "Abbrechen"
    )
    // Aporah's dark mode is its own switch in Settings, not the device's — the
    // same contract every native surface in this app keeps.
    controller.overrideUserInterfaceStyle = (args["dark"] as? Bool == true) ? .dark : .light
    controller.onFinish = { [weak self] payload in
      self?.finish(payload)
    }
    controller.modalPresentationStyle = .fullScreen
    host.present(controller, animated: true)
  }

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
  }
}

// ---------------------------------------------------------------------------

/// The camera screen itself: a preview, a cutout to aim through, and one way
/// out. It stops the session on the first code it reads, so a code that stays
/// in frame cannot fire twice.
private final class ScannerViewController: UIViewController {
  var onFinish: ((String?) -> Void)?

  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "aporah.scanner.session")
  private var preview: AVCaptureVideoPreviewLayer?
  private var done = false

  private let titleText: String?
  private let hintText: String?
  private let cancelLabel: String

  init(title: String?, hint: String?, cancelLabel: String) {
    self.titleText = title
    self.hintText = hint
    self.cancelLabel = cancelLabel
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("not supported") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    guard let device = AVCaptureDevice.default(for: .video),
          let input = try? AVCaptureDeviceInput(device: device),
          session.canAddInput(input)
    else {
      finish(nil)
      return
    }
    session.addInput(input)

    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else {
      finish(nil)
      return
    }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    // Set *after* the output is added to the session — the list of available
    // types is empty until then, and assigning an unsupported type raises.
    output.metadataObjectTypes = output.availableMetadataObjectTypes.contains(.qr) ? [.qr] : []

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.frame = view.bounds
    view.layer.addSublayer(layer)
    preview = layer

    addChrome()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    // startRunning blocks; off the main thread it goes, or the presentation
    // animation stutters on every device.
    sessionQueue.async { [session] in
      if !session.isRunning { session.startRunning() }
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sessionQueue.async { [session] in
      if session.isRunning { session.stopRunning() }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    preview?.frame = view.bounds
  }

  /// Portrait only. The sheet this is opened from is portrait, and a rotating
  /// preview would need the connection's video orientation kept in step for a
  /// screen nobody spends ten seconds on.
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

  private func addChrome() {
    let dimmer = UIView(frame: view.bounds)
    dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.45)
    dimmer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(dimmer)

    // The aiming square, punched out of the dim layer so the preview shows
    // through it at full brightness.
    let side = min(view.bounds.width, view.bounds.height) * 0.66
    let window = CGRect(
      x: (view.bounds.width - side) / 2,
      y: (view.bounds.height - side) / 2,
      width: side,
      height: side
    )
    let mask = CAShapeLayer()
    let path = UIBezierPath(rect: dimmer.bounds)
    path.append(UIBezierPath(roundedRect: window, cornerRadius: 20).reversing())
    mask.path = path.cgPath
    dimmer.layer.mask = mask

    let frame = UIView(frame: window)
    frame.layer.borderColor = UIColor.white.cgColor
    frame.layer.borderWidth = 2
    frame.layer.cornerRadius = 20
    frame.layer.cornerCurve = .continuous
    view.addSubview(frame)

    let label = UILabel()
    label.text = hintText
    label.textColor = .white
    label.font = .preferredFont(forTextStyle: .subheadline)
    label.numberOfLines = 0
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(label)

    let heading = UILabel()
    heading.text = titleText
    heading.textColor = .white
    heading.font = .preferredFont(forTextStyle: .headline)
    heading.textAlignment = .center
    heading.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(heading)

    let cancel = UIButton(type: .system)
    cancel.setTitle(cancelLabel, for: .normal)
    cancel.setTitleColor(.white, for: .normal)
    cancel.titleLabel?.font = .preferredFont(forTextStyle: .body)
    cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    cancel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(cancel)

    let guide = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      heading.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
      heading.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
      heading.topAnchor.constraint(equalTo: guide.topAnchor, constant: 24),

      label.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 32),
      label.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -32),
      label.topAnchor.constraint(equalTo: frame.bottomAnchor, constant: 24),

      cancel.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
      cancel.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -24),
    ])
  }

  @objc private func cancelTapped() {
    finish(nil)
  }

  fileprivate func finish(_ payload: String?) {
    guard !done else { return }
    done = true
    // The annotation is load-bearing. `self?.onFinish?(payload)` chains two
    // optionals — the weak self and the callback — so the expression's type is
    // `Void?`, and an unannotated single-expression closure would infer
    // `() -> Void?`, which `dismiss(animated:completion:)` will not take.
    // Declaring the type discards the optional instead.
    let hand: () -> Void = { [weak self] in
      self?.onFinish?(payload)
    }
    if presentingViewController != nil {
      dismiss(animated: true, completion: hand)
    } else {
      hand()
    }
  }
}

extension ScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput objects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard !done,
          let code = objects.first as? AVMetadataMachineReadableCodeObject,
          let payload = code.stringValue, !payload.isEmpty
    else { return }

    // A short haptic is the whole of the feedback: the screen is about to go
    // away, so anything drawn on it would not be seen.
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    finish(payload)
  }
}
