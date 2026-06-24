import Flutter
import UIKit
import receive_sharing_intent

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var pendingColdStartFileURL: URL? = nil

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let url = launchOptions?[.url] as? URL {
      if isSupportedFile(url: url) {
        if injectFileIntoPlugin(url: url) {
          pendingColdStartFileURL = url
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    // Let the receive_sharing_intent plugin handle ShareMedia- prefixed URLs first
    if SwiftReceiveSharingIntentPlugin.instance.hasMatchingSchemePrefix(url: url) {
      return SwiftReceiveSharingIntentPlugin.instance.application(app, open: url, options: options)
    }

    // Handle direct file URLs (from iOS Share Sheet / "Open In...")
    if isSupportedFile(url: url) {
      return handleSharedFile(url: url)
    }

    return false
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)

    // Cold start: deliver pending file after Flutter event channel is ready
    if let url = pendingColdStartFileURL {
      pendingColdStartFileURL = nil
      // Schedule delivery - gives Flutter time to set up event channel via getMediaStream().listen()
      DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
        self?.deliverPendingFile(url: url)
      }
    }
  }

  private func deliverPendingFile(url: URL) {
    guard let bundleId = Bundle.main.bundleIdentifier else { return }
    let shareURL = URL(string: "\(kSchemePrefix)-\(bundleId)://data")!
    _ = SwiftReceiveSharingIntentPlugin.instance.application(
      UIApplication.shared, open: shareURL, options: [:])
  }

  private func isSupportedFile(url: URL) -> Bool {
    guard url.isFileURL else { return false }
    let ext = url.pathExtension.lowercased()
    return ["csv", "xlsx", "xls"].contains(ext)
  }

  private func handleSharedFile(url: URL) -> Bool {
    guard injectFileIntoPlugin(url: url) else { return false }

    guard let bundleId = Bundle.main.bundleIdentifier else { return false }
    let shareURL = URL(string: "\(kSchemePrefix)-\(bundleId)://data")!
    return SwiftReceiveSharingIntentPlugin.instance.application(
      UIApplication.shared, open: shareURL, options: [:])
  }

  private func injectFileIntoPlugin(url: URL) -> Bool {
    guard url.startAccessingSecurityScopedResource() else {
      print("[AppDelegate] Cannot access security-scoped resource: \(url)")
      return false
    }
    defer { url.stopAccessingSecurityScopedResource() }

    do {
      let tempDir = FileManager.default.temporaryDirectory
      let destURL = tempDir.appendingPathComponent(url.lastPathComponent)

      if FileManager.default.fileExists(atPath: destURL.path) {
        try FileManager.default.removeItem(at: destURL)
      }
      try FileManager.default.copyItem(at: url, to: destURL)

      let defaultGroupId = "group.\(Bundle.main.bundleIdentifier!)"
      let userDefaults = UserDefaults(suiteName: defaultGroupId)

      let sharedFile = SharedMediaFile(
        path: destURL.path,
        mimeType: nil,
        thumbnail: nil,
        duration: nil,
        message: nil,
        type: .file
      )
      let jsonData = try JSONEncoder().encode([sharedFile])
      userDefaults?.set(jsonData, forKey: "ShareKey")
      userDefaults?.synchronize()

      print("[AppDelegate] Successfully injected shared file: \(url.lastPathComponent)")
      return true
    } catch {
      print("[AppDelegate] Failed to inject file: \(error)")
      return false
    }
  }
}
