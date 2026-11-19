//
//  WVSSAddressListFetcher.swift
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

/// Downloads a JSON list of addresses: `[{"url": "...", "duration": 60}, ...]`.
final class WVSSAddressListFetcher {
  enum FetchError: LocalizedError {
    case invalidURL(String)
    case unexpected(String)

    var errorDescription: String? {
      switch self {
      case .invalidURL(let url): return "Invalid URL: \(url)"
      case .unexpected(let reason): return reason
      }
    }
  }

  private var task: URLSessionDataTask?

  /// Starts fetching right away. `completion` is called on the main queue.
  init(url: String, completion: @escaping (Result<[WVSSAddress], Error>) -> Void) {
    guard let requestURL = URL(string: url) else {
      DispatchQueue.main.async { completion(.failure(FetchError.invalidURL(url))) }
      return
    }
    task = URLSession.shared.dataTask(with: requestURL) { data, _, error in
      let result: Result<[WVSSAddress], Error>
      if let error = error {
        result = .failure(error)
      } else {
        result = Result { try Self.parse(data ?? Data()) }
      }
      DispatchQueue.main.async { completion(result) }
    }
    task?.resume()
  }

  deinit {
    task?.cancel()
  }

  static func parse(_ data: Data) throws -> [WVSSAddress] {
    let json = try JSONSerialization.jsonObject(with: data)
    guard let items = json as? [Any] else {
      throw FetchError.unexpected("Expected NSArray but got \(type(of: json))")
    }
    return try items.map { item in
      guard let dict = item as? [String: Any] else {
        throw FetchError.unexpected("Expected NSDictionary but got \(type(of: item))")
      }
      guard let url = dict["url"] as? String else {
        throw FetchError.unexpected("Expected NSString for url")
      }
      guard let duration = dict["duration"] as? NSNumber else {
        throw FetchError.unexpected("Expected NSNumber for duration")
      }
      return WVSSAddress(url: url, duration: duration.intValue)
    }
  }
}
