//
//  WebViewScreenSaverView.swift
//  WebViewScreenSaver
//
//  Created by Alastair Tse on 8/8/10.
//
//  Copyright 2015 Alastair Tse.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import ScreenSaver
import WebKit

/// A screen saver that shows a configurable list of web pages.
///
/// The ObjC name must stay "WebViewScreenSaverView": it is the NSPrincipalClass in Info.plist.
@objc(WebViewScreenSaverView)
final class WebViewScreenSaverView: ScreenSaverView {
  /// ScreenSaverDefaults module name.
  private static let moduleName = "WebViewScreenSaver"

  /// Posted (cross-process) when the options sheet is closed, so stale instances can stop.
  static let configDismissedNotification = Notification.Name("webviewscreensaver.config.dismissed")

  private var config: WVSSConfig
  private var configController: WVSSConfigController?
  private var webView: WKWebView?
  private var logoView: NSImageView?
  private var timer: Timer?
  private var currentIndex = 0

  /// Our own "running" flag. Don't rely on `isAnimating`: under the macOS 26 screen saver
  /// host it isn't reliably true by the time `startAnimation` runs, and checking it meant
  /// the first page was never loaded (black screen).
  private var isRunning = false
  private var isSubscribed = false

  // Crash-reload limit: at most `maxCrashReloads` reloads per `crashWindow` seconds.
  private static let maxCrashReloads = 3
  private static let crashWindow: TimeInterval = 10 * 60
  private var crashTimes: [Date] = []
  private var pendingReload: DispatchWorkItem?

  // MARK: - Init

  /// Called by System Settings / the screen saver engine.
  override init?(frame: NSRect, isPreview: Bool) {
    let prefs = ScreenSaverDefaults(forModuleWithName: Self.moduleName) ?? .standard
    config = WVSSConfig(userDefaults: prefs)
    super.init(frame: frame, isPreview: isPreview)
    commonInit()
  }

  /// Used by the test rig app with its own defaults.
  init?(frame: NSRect, isPreview: Bool, prefsStore: UserDefaults) {
    config = WVSSConfig(userDefaults: prefsStore)
    super.init(frame: frame, isPreview: isPreview)
    commonInit()
  }

  required init?(coder: NSCoder) {
    config = WVSSConfig(
      userDefaults: ScreenSaverDefaults(forModuleWithName: Self.moduleName) ?? .standard)
    super.init(coder: coder)
    commonInit()
  }

  private func commonInit() {
    wvssLog(self, description)
    autoresizesSubviews = true
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor

    // The small preview in System Settings only shows the thumbnail.
    if isPreview {
      let image = Bundle(for: WebViewScreenSaverView.self).image(forResource: "thumbnail")
      let logo = NSImageView(frame: bounds)
      logo.image = image
      logo.imageScaling = .scaleProportionallyUpOrDown
      logo.autoresizingMask = [.width, .height]
      addSubview(logo)
      logoView = logo
    }
  }

  deinit {
    wvssLog(self)
    DistributedNotificationCenter.default().removeObserver(self)
    timer?.invalidate()
  }

  override class func performGammaFade() -> Bool {
    false
  }

  override var description: String {
    func str(_ r: NSRect) -> String {
      String(format: "(x=%.f, y=%.f, w=%.f, h=%.f)", r.origin.x, r.origin.y, r.width, r.height)
    }
    let windowFrame = window.map { str($0.frame) } ?? "-"
    let scale = window?.backingScaleFactor ?? 0
    return "preview:\(isPreview) frame:\(str(frame)) window:\(windowFrame) scale:\(scale)"
  }

  // MARK: - Layout

  // Keep the web view exactly the size of the saver view. On macOS 26 the view is often
  // created small (or zero-sized) and resized later; relying on autoresizing alone left a
  // small black square in the corner.
  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    syncSubviewFrames()
  }

  override func layout() {
    super.layout()
    syncSubviewFrames()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    wvssLog(self, description)
    syncSubviewFrames()
  }

  private func syncSubviewFrames() {
    if let webView = webView, webView.frame != bounds { webView.frame = bounds }
    if let logoView = logoView, logoView.frame != bounds { logoView.frame = bounds }
  }

  // MARK: - Configure Sheet

  override var hasConfigureSheet: Bool { true }

  override var configureSheet: NSWindow? {
    wvssLog(self, description)
    let controller = WVSSConfigController(config: config)
    controller.delegate = self
    configController = controller
    return controller.sheet
  }

  // MARK: - ScreenSaverView

  override func startAnimation() {
    super.startAnimation()
    wvssLog(self, description)
    isRunning = true

    if isPreview || webView != nil { return }

    let webView = Self.makeWebView(frame: bounds)
    webView.uiDelegate = self
    webView.navigationDelegate = self
    // The saver window belongs to another process and looks hidden to WebKit, which then
    // pauses drawing, animations and JS. Turn that detection off.
    webView.wvss_setWindowOcclusionDetectionEnabled(false)
    addSubview(webView)
    self.webView = webView
    syncSubviewFrames()

    config.onAddressesChanged = { [weak self] in
      // A fetched list arrived. Start over if nothing useful is showing yet.
      guard let self = self, self.isRunning, self.webView != nil else { return }
      if self.webView?.url == nil || self.timer == nil { self.loadFromStart() }
    }

    loadFromStart()
    subscribeForNotifications()
  }

  override func stopAnimation() {
    super.stopAnimation()
    wvssLog(self)
    teardown()
  }

  override func animateOneFrame() {
    super.animateOneFrame()
  }

  private func teardown() {
    wvssLog(self, description)
    isRunning = false
    unsubscribeFromNotifications()

    timer?.invalidate()
    timer = nil
    pendingReload?.cancel()
    pendingReload = nil
    crashTimes = []

    if let webView = webView {
      webView.stopLoading()
      webView.navigationDelegate = nil
      webView.uiDelegate = nil
      webView.removeFromSuperview()
    }
    webView = nil
    config.onAddressesChanged = nil
  }

  // MARK: - Web view

  static func makeWebView(frame: NSRect) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    let preferences = WKPreferences()
    preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.preferences = preferences
    // Nobody can click "play" on a screen saver.
    configuration.mediaTypesRequiringUserActionForPlayback = []

    let webView = WKWebView(frame: frame, configuration: configuration)
    webView.autoresizingMask = [.width, .height]
    webView.wantsLayer = true
    webView.layer?.backgroundColor = NSColor.black.cgColor
    webView.underPageBackgroundColor = .black
    // Pages without a background show black instead of white. Private, so only if present.
    webView.wvss_setDrawsTransparentBackground(true)
    return webView
  }

  static func load(_ address: WVSSAddress, into webView: WKWebView) {
    let urlString = address.url.trimmingCharacters(in: .whitespacesAndNewlines)
    var url = URL(string: urlString)

    // Plain paths like /Users/me/saver/index.html
    if url?.scheme == nil {
      url = URL(fileURLWithPath: (urlString as NSString).expandingTildeInPath)
    }
    guard let url = url, let scheme = url.scheme?.lowercased() else {
      wvssLog(nil, "Can't load \(urlString)")
      return
    }

    switch scheme {
    case "http", "https":
      webView.load(URLRequest(url: url))
    case "file":
      webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    default:
      wvssLog(nil, "Unsupported scheme: \(urlString)")
    }
  }

  // MARK: - Loading URLs

  private func loadFromStart() {
    wvssLog(self, "running: \(isRunning)")
    guard isRunning else { return }
    currentIndex = -1
    loadNext()
  }

  @objc private func loadNext() {
    guard isRunning, let webView = webView else { return }

    let count = config.addresses.count

    // Last element, re-fetch the list if needed.
    if count > 0, currentIndex == count - 1 {
      config.fetchIfNeeded()
    }

    var address = WVSSAddress.makeDefault()
    var nextIndex = currentIndex
    if count > 0 {
      nextIndex = (currentIndex + 1) % count
      address = config.addresses[nextIndex]
    } else if config.shouldFetchAddressList {
      // Still waiting for the fetched list; onAddressesChanged starts us.
      wvssLog(self, "waiting for fetched addresses")
      return
    }

    wvssLog(self, "loading \(address)")
    Self.load(address, into: webView)
    currentIndex = nextIndex

    timer?.invalidate()
    timer = nil
    if address.duration < 0 { return }  // Stay forever.

    let timer = Timer(
      timeInterval: TimeInterval(max(address.duration, 1)), target: self,
      selector: #selector(loadNext), userInfo: nil, repeats: false)
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  // MARK: - Focus overrides

  // Capture all input so the web view never gets keyboard focus.
  override func hitTest(_ point: NSPoint) -> NSView? { self }
  override var acceptsFirstResponder: Bool { false }
  override func resignFirstResponder() -> Bool { false }

  // MARK: - Notifications

  private func subscribeForNotifications() {
    guard !isSubscribed else { return }
    isSubscribed = true
    let center = DistributedNotificationCenter.default()
    center.addObserver(
      self, selector: #selector(screensaverWillStop(_:)),
      name: Notification.Name("com.apple.screensaver.willstop"), object: nil)
    center.addObserver(
      self, selector: #selector(configDismissed(_:)),
      name: Self.configDismissedNotification, object: nil)
    // NOTE: the old version also tore down on a "preview stopped" broadcast. On macOS 26
    // the System Settings preview is stopped right as the real saver starts, which killed
    // the real saver's web view and left a black screen (issue #97). Removed.
  }

  private func unsubscribeFromNotifications() {
    guard isSubscribed else { return }
    isSubscribed = false
    DistributedNotificationCenter.default().removeObserver(self)
  }

  private func postNotification(_ name: Notification.Name) {
    DistributedNotificationCenter.default().postNotificationName(
      name, object: nil, userInfo: nil, deliverImmediately: true)
  }

  /// The options sheet only closes in System Settings, never while the real saver is up.
  /// Stops leftover instances that macOS 26 sometimes keeps alive.
  @objc private func configDismissed(_ notification: Notification) {
    wvssLog(self)
    teardown()
  }

  // Inspired by: https://github.com/JohnCoates/Aerial/commit/8c78e7cc4f77f4417371966ae7666125d87496d1
  // Since Sonoma, stopAnimation isn't always called, so stop on this instead.
  @objc private func screensaverWillStop(_ notification: Notification) {
    wvssLog(self)
    teardown()
  }
}

// MARK: - WVSSConfigControllerDelegate

extension WebViewScreenSaverView: WVSSConfigControllerDelegate {
  func configController(_ controller: WVSSConfigController, dismissConfigSheet sheet: NSWindow) {
    if let parent = sheet.sheetParent {
      parent.endSheet(sheet)
    } else {
      // Old-style sheet run by the System Settings host. -[NSApplication endSheet:] is
      // deprecated, so call it by selector to keep the build warning-free.
      NSApp.perform(NSSelectorFromString("endSheet:"), with: sheet)
    }
    sheet.orderOut(nil)
    configController = nil
    postNotification(Self.configDismissedNotification)
  }
}

// MARK: - WKNavigationDelegate / WKUIDelegate

extension WebViewScreenSaverView: WKNavigationDelegate, WKUIDelegate {
  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    // Don't open new windows. (The old code called the handler twice here, which makes
    // WebKit throw and kills the saver.)
    if navigationAction.targetFrame == nil {
      decisionHandler(.cancel)
      return
    }
    decisionHandler(.allow)
  }

  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    nil
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    wvssLog(self, "finished \(webView.url?.absoluteString ?? "-")")
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    wvssLog(self, "failed provisional: \(error.localizedDescription)")
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    wvssLog(self, "failed: \(error.localizedDescription)")
  }

  /// The page's web process died (or was killed). Reload instead of staying black, but
  /// only a few times: a page that keeps crashing must not loop forever.
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    guard isRunning else { return }

    let now = Date()
    crashTimes = crashTimes.filter { now.timeIntervalSince($0) < Self.crashWindow }
    crashTimes.append(now)

    if crashTimes.count > Self.maxCrashReloads {
      // Give up on reloading. The timer still moves on to the next address, if any.
      wvssLog(self, "web content process terminated \(crashTimes.count) times, not reloading")
      return
    }

    // Wait a little longer after each crash: 2 s, 4 s, 8 s.
    let delay = pow(2.0, Double(crashTimes.count))
    wvssLog(self, "web content process terminated, reloading in \(delay)s")
    pendingReload?.cancel()
    let reload = DispatchWorkItem { [weak self, weak webView] in
      guard let self = self, self.isRunning, let webView = webView, webView === self.webView
      else { return }
      if webView.url != nil {
        webView.reload()
      } else {
        self.loadFromStart()
      }
    }
    pendingReload = reload
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: reload)
  }
}
