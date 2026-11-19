//
//  AppDelegate.swift
//  WebViewScreenSaverRig
//
//  Created by Alastair Tse on 26/04/2015.
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

import Cocoa

/// Test app that hosts the screen saver view in a normal window.
/// The ObjC name must stay "AppDelegate" for MainMenu.xib.
@objc(AppDelegate)
final class AppDelegate: NSObject, NSApplicationDelegate, WVSSConfigControllerDelegate {
  @IBOutlet weak var window: NSWindow!

  private var config: WVSSConfig!
  private var configController: WVSSConfigController?
  private var saverView: WebViewScreenSaverView?

  func applicationDidFinishLaunching(_ notification: Notification) {
    config = WVSSConfig(userDefaults: .standard)
    reloadWebView()
    window.makeKey()

    DispatchQueue.main.async { [weak self] in self?.showPreferences(nil) }
  }

  func configController(_ controller: WVSSConfigController, dismissConfigSheet sheet: NSWindow) {
    reloadWebView()
    window.endSheet(sheet)
    configController = nil
  }

  @IBAction func showPreferences(_ sender: Any?) {
    let controller = WVSSConfigController(config: config)
    controller.delegate = self
    configController = controller
    if let sheet = controller.sheet {
      window.beginSheet(sheet, completionHandler: nil)
    }
  }

  func reloadWebView() {
    // Remove the old saver view.
    if let old = saverView {
      old.stopAnimation()
      old.removeFromSuperview()
    }

    guard let contentView = window.contentView,
      let view = WebViewScreenSaverView(
        frame: contentView.bounds, isPreview: false, prefsStore: .standard)
    else { return }
    view.autoresizingMask = [.width, .height]
    contentView.addSubview(view)
    view.startAnimation()
    saverView = view
  }
}
