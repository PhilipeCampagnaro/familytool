import Flutter
import PhotosUI
import UIKit

/// The three system pickers a Listen item's row menu offers — photo library,
/// camera, Files — behind the "aporah/media" channel that
/// `lib/services/media_picker.dart` calls. Registered in AppDelegate.
///
/// Hand-rolled rather than `image_picker` + `file_picker` for the same reason
/// the tab bar, switch and search field are: these are three system view
/// controllers, and taking on two plugins (and their pod install) to present
/// them buys nothing this file doesn't already do.
///
/// Whatever is picked is copied into `Documents/attachments/` and its path
/// handed back — the item it belongs to is Dart's business. A pick returns
/// `nil` when the user cancels, so cancelling is not an error.
final class MediaPicker: NSObject {
  /// The pending pick's callback. Only one picker can be up at a time; a
  /// second request finishes the first as a cancel rather than stranding it.
  private var pending: FlutterResult?

  /// The longest edge the caller will accept, in pixels, or nil for "as
  /// picked". Set per request — the profile picture asks for a small square,
  /// a Listen attachment wants the photo it took.
  private var pendingMaxDimension: CGFloat?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    pendingMaxDimension = (arguments?["maxDimension"] as? NSNumber).map { CGFloat(truncating: $0) }

    switch call.method {
    case "photo":
      presentPhotoLibrary(result)
    case "camera":
      presentCamera(result)
    case "file":
      presentFiles(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Pickers

  private func presentPhotoLibrary(_ result: @escaping FlutterResult) {
    // PHPicker where it exists (iOS 14+): it runs out of process, so it needs
    // no photo-library permission at all — the user hands over exactly what
    // they picked and nothing else. The app still targets iOS 13, where the
    // image picker's read-only library mode is the equivalent, and has needed
    // no usage description of its own since iOS 11.
    if #available(iOS 14.0, *) {
      var config = PHPickerConfiguration()
      config.filter = .images
      config.selectionLimit = 1
      let picker = PHPickerViewController(configuration: config)
      picker.delegate = self
      present(picker, result)
    } else {
      let picker = UIImagePickerController()
      picker.sourceType = .photoLibrary
      picker.delegate = self
      present(picker, result)
    }
  }

  private func presentCamera(_ result: @escaping FlutterResult) {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      // The simulator has no camera; let Dart treat that as "nothing picked"
      // rather than presenting an empty controller.
      result(nil)
      return
    }
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.delegate = self
    present(picker, result)
  }

  private func presentFiles(_ result: @escaping FlutterResult) {
    // Both forms ask for a *copy* in the app's own temp directory, so there's
    // no security-scoped URL to keep alive after this returns.
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(documentTypes: ["public.item"], in: .import)
    }
    picker.delegate = self
    picker.allowsMultipleSelection = false
    present(picker, result)
  }

  private func present(_ controller: UIViewController, _ result: @escaping FlutterResult) {
    guard let host = topViewController else {
      result(nil)
      return
    }
    finish(nil)
    pending = result
    host.present(controller, animated: true)
  }

  /// The controller a picker can be presented from: the key window's root,
  /// walked down past anything Flutter already has up (a modal sheet).
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

  // MARK: - Storage

  /// Copies a picked file somewhere it will still exist after the picker's own
  /// temporary copy is cleaned up. The name is prefixed with a UUID so two
  /// picks of the same "IMG_0001.jpg" don't collide.
  private func store(_ source: URL, name: String?) -> [String: Any]? {
    guard let data = try? Data(contentsOf: source) else { return nil }
    let filename = name ?? source.lastPathComponent
    guard isImage(filename) else { return write(data, name: filename, isImage: false) }
    let (normalised, normalisedName) = normalise(data, name: filename)
    return write(normalised, name: normalisedName, isImage: true)
  }

  /// Makes a picked image something Flutter can actually draw, and no larger
  /// than the caller asked for.
  ///
  /// **HEIC is why this exists.** It is the iPhone's default camera format, and
  /// Flutter's image codecs cannot decode it — a HEIC avatar or attachment
  /// thumbnail silently renders as nothing at all. So an image that isn't
  /// already a format Skia knows is re-encoded as JPEG, and while it is decoded
  /// anyway, it is scaled down to [pendingMaxDimension] if one was given.
  ///
  /// Anything that fails to decode is handed back untouched rather than lost:
  /// the file is still what the user picked, and the caller will show its
  /// fallback.
  private func normalise(_ data: Data, name: String) -> (Data, String) {
    let ext = (name as NSString).pathExtension.lowercased()
    let needsTranscode = !skiaReadableExtensions.contains(ext)
    let limit = pendingMaxDimension

    guard needsTranscode || limit != nil, let image = UIImage(data: data) else { return (data, name) }

    let scaled = limit.map { resize(image, longestEdge: $0) } ?? image
    // A no-op resize on an already-readable format isn't worth a re-encode.
    guard needsTranscode || scaled !== image, let jpeg = scaled.jpegData(compressionQuality: 0.9) else {
      return (data, name)
    }
    return (jpeg, ((name as NSString).deletingPathExtension as NSString).appendingPathExtension("jpg") ?? name)
  }

  /// Aspect-preserving downscale. Returns the original untouched when it is
  /// already small enough, which is what lets [normalise] skip the re-encode.
  private func resize(_ image: UIImage, longestEdge: CGFloat) -> UIImage {
    let size = image.size
    let longest = max(size.width, size.height)
    guard longest > longestEdge, longest > 0 else { return image }

    let scale = longestEdge / longest
    let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    // Scale 1 so `target` is in pixels rather than points — a 3x screen would
    // otherwise triple everything this is here to shrink.
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
  }

  /// The image formats Flutter can decode. Deliberately not the same set as
  /// [isImage], which answers "does this row get a thumbnail" and happily
  /// includes HEIC.
  private let skiaReadableExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp"]

  private func write(_ data: Data, name: String, isImage: Bool) -> [String: Any]? {
    let directory = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0])
      .appendingPathComponent("attachments", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    guard (try? data.write(to: target)) != nil else { return nil }
    return ["path": target.path, "name": name, "isImage": isImage]
  }

  /// By extension rather than by uniform type: `UTType` is iOS 14+, and this
  /// only decides whether the row shows a thumbnail.
  private func isImage(_ name: String) -> Bool {
    let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp"]
    return imageExtensions.contains((name as NSString).pathExtension.lowercased())
  }
}

// MARK: - Photo library

@available(iOS 14.0, *)
extension MediaPicker: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    let type = "public.image"
    guard let provider = results.first?.itemProvider, provider.hasItemConformingToTypeIdentifier(type) else {
      finish(nil)
      return
    }
    let name = provider.suggestedName
    provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, _ in
      // The URL is only valid for the length of this callback, so the copy has
      // to happen here rather than back on the main queue.
      let stored = url.flatMap { source -> [String: Any]? in
        let filename = name.map { "\($0).\(source.pathExtension)" } ?? source.lastPathComponent
        return self?.store(source, name: filename)
      }
      DispatchQueue.main.async { self?.finish(stored) }
    }
  }
}

// MARK: - Camera

extension MediaPicker: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
    picker.dismiss(animated: true)
    guard let picked = (info[.editedImage] ?? info[.originalImage]) as? UIImage else {
      finish(nil)
      return
    }
    // Already JPEG, so this only ever has the size limit left to apply — but it
    // goes through the same path so "the avatar is at most 512px" is one rule,
    // not one per picker.
    let image = pendingMaxDimension.map { resize(picked, longestEdge: $0) } ?? picked
    guard let data = image.jpegData(compressionQuality: 0.9) else {
      finish(nil)
      return
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    finish(write(data, name: "Foto \(formatter.string(from: Date())).jpg", isImage: true))
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    finish(nil)
  }
}

// MARK: - Files

extension MediaPicker: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      finish(nil)
      return
    }
    finish(store(url, name: url.lastPathComponent))
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finish(nil)
  }
}
