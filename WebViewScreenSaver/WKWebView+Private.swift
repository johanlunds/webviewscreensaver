//
//  WKWebView+Private.swift
//  WebViewScreenSaver
//
//  Created by Alexandru Gologan on 24.02.2024.
//
//  Copyright 2024 Alexandru Gologan.
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

import WebKit

// Private WKWebView setters. Each one is only called if it still exists, so a future
// macOS that drops it doesn't crash the saver (the old code used KVC, which throws).
extension WKWebView {
  func wvss_setWindowOcclusionDetectionEnabled(_ enabled: Bool) {
    callPrivateBoolSetter("_setWindowOcclusionDetectionEnabled:", enabled)
  }

  func wvss_setDrawsTransparentBackground(_ transparent: Bool) {
    callPrivateBoolSetter("_setDrawsTransparentBackground:", transparent)
  }

  private func callPrivateBoolSetter(_ name: String, _ value: Bool) {
    let selector = NSSelectorFromString(name)
    guard responds(to: selector), let imp = method(for: selector) else {
      wvssLog(self, "\(name) not available")
      return
    }
    typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
    unsafeBitCast(imp, to: Setter.self)(self, selector, value)
  }
}
