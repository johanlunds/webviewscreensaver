//
//  WVSSConfig.swift
//  WebViewScreenSaver
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

/// The saved settings: the list of addresses and the optional "fetch URLs" source.
final class WVSSConfig {
  // User default keys. Must not change, so old settings keep working.
  private static let fetchURLsKey = "kScreenSaverFetchURLs"  // Bool
  private static let urlsURLKey = "kScreenSaverURLsURL"  // String (URL)
  private static let urlListKey = "kScreenSaverURLList"  // [[String: Any]]

  private let userDefaults: UserDefaults
  private var fetcher: WVSSAddressListFetcher?

  var addresses: [WVSSAddress]
  var addressListURL: String?
  var shouldFetchAddressList: Bool
  /// Called on the main queue when a fetched address list replaces `addresses`.
  var onAddressesChanged: (() -> Void)?

  init(userDefaults: UserDefaults) {
    self.userDefaults = userDefaults
    addresses = Self.loadAddresses(from: userDefaults)
    addressListURL = userDefaults.string(forKey: Self.urlsURLKey)
    shouldFetchAddressList = userDefaults.bool(forKey: Self.fetchURLsKey)

    appendSampleAddressIfEmpty()
    fetchIfNeeded()
  }

  private func appendSampleAddressIfEmpty() {
    if shouldFetchAddressList { return }
    if addresses.isEmpty {
      addresses.append(WVSSAddress.makeDefault())
    }
  }

  private static func loadAddresses(from userDefaults: UserDefaults) -> [WVSSAddress] {
    let stored = userDefaults.array(forKey: urlListKey) as? [[String: Any]] ?? []
    return stored.compactMap { dict in
      guard let url = dict[WVSSAddress.urlKey] as? String else { return nil }
      let time = (dict[WVSSAddress.timeKey] as? NSNumber)?.intValue
        ?? Int(dict[WVSSAddress.timeKey] as? String ?? "") ?? 0
      return WVSSAddress(url: url, duration: time)
    }
  }

  func synchronize() {
    userDefaults.set(addresses.map(\.dictionaryRepresentation), forKey: Self.urlListKey)
    userDefaults.set(shouldFetchAddressList, forKey: Self.fetchURLsKey)

    if let url = addressListURL, !url.isEmpty {
      userDefaults.set(url, forKey: Self.urlsURLKey)
    } else {
      userDefaults.removeObject(forKey: Self.urlsURLKey)
    }
    userDefaults.synchronize()
  }

  func fetchIfNeeded() {
    guard shouldFetchAddressList,
      let url = addressListURL, !url.isEmpty,
      url.hasPrefix("http://") || url.hasPrefix("https://")
    else { return }

    fetcher = WVSSAddressListFetcher(url: url) { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .success(let list):
        self.addresses = list
        wvssLog(self, "fetching URLs finished: \(list.count) addresses")
        self.onAddressesChanged?()
      case .failure(let error):
        wvssLog(self, "Encountered issue: \(error.localizedDescription)")
      }
      self.fetcher = nil
    }
  }
}
