//
//  WVSSAddress.swift
//  WebViewScreenSaver
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

import Foundation

/// One web page to show, and for how many seconds. A negative duration means "forever".
@objc(WVSSAddress)
final class WVSSAddress: NSObject {
  // Keys for the dictionaries stored in user defaults. Must not change.
  static let urlKey = "kScreenSaverURL"
  static let timeKey = "kScreenSaverTime"

  static let defaultDuration = 5 * 60
  private static let defaultURLInfoKey = "WVSSDefaultAddressURL"

  var url: String
  var duration: Int

  init(url: String, duration: Int) {
    self.url = url
    self.duration = duration
    super.init()
  }

  static var defaultAddressURL: String {
    // Use the screensaver's own bundle, not the host process' main bundle.
    let info = Bundle(for: WVSSAddress.self).infoDictionary
    return info?[defaultURLInfoKey] as? String ?? "https://www.google.com/"
  }

  static func makeDefault() -> WVSSAddress {
    WVSSAddress(url: defaultAddressURL, duration: defaultDuration)
  }

  var dictionaryRepresentation: [String: Any] {
    [Self.urlKey: url, Self.timeKey: duration]
  }

  override var description: String {
    "<WVSSAddress : \(url) for \(duration)>"
  }
}
