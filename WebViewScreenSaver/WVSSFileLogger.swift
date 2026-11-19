//
//  WVSSFileLogger.swift
//  WebViewScreenSaver
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
import os

/// Logs a line to the rotating log file and to the system log (Console.app, subsystem
/// "net.liquidx.WebViewScreenSaver").
func wvssLog(_ caller: AnyObject?, _ message: String = "", function: String = #function) {
  let pointer = caller.map { String(describing: Unmanaged.passUnretained($0).toOpaque()) } ?? "-"
  let line = "\(pointer) \(function) \(message)"
  WVSSFileLogger.osLog.log("\(line, privacy: .public)")
  WVSSFileLogger.shared.log(line)
}

final class WVSSFileLogger {
  static let osLog = Logger(subsystem: "net.liquidx.WebViewScreenSaver", category: "saver")

  static let shared: WVSSFileLogger = {
    let library =
      FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
    let logs = library
      .appendingPathComponent("Logs")
      .appendingPathComponent(Bundle.main.bundleIdentifier ?? "WebViewScreenSaver")
    return WVSSFileLogger(
      logDirectory: logs.path, logFileName: "wvss.log", maxFileSize: 1024 * 1024, maxFiles: 3)
  }()

  let logDirectory: String
  let logFileName: String
  let maxFileSize: UInt64
  let maxFiles: Int

  private let logFilePath: String
  private var fileHandle: FileHandle?
  private let dateFormatter = ISO8601DateFormatter()
  private let queue = DispatchQueue(label: "net.liquidx.WebViewScreenSaver.log")

  init(logDirectory: String, logFileName: String, maxFileSize: UInt64, maxFiles: Int) {
    self.logDirectory = logDirectory
    self.logFileName = logFileName
    self.maxFileSize = maxFileSize
    self.maxFiles = max(1, maxFiles)
    self.logFilePath = (logDirectory as NSString).appendingPathComponent(logFileName)

    try? FileManager.default.createDirectory(
      atPath: logDirectory, withIntermediateDirectories: true)
    openLogFile()
  }

  deinit {
    try? fileHandle?.close()
  }

  private func openLogFile() {
    let fm = FileManager.default
    if !fm.fileExists(atPath: logFilePath) {
      fm.createFile(atPath: logFilePath, contents: nil)
    }
    fileHandle = FileHandle(forWritingAtPath: logFilePath)
    _ = try? fileHandle?.seekToEnd()
  }

  func log(_ message: String) {
    let entry = "\(dateFormatter.string(from: Date())) \(message)\n"
    guard let data = entry.data(using: .utf8) else { return }

    queue.async { [self] in
      guard let handle = fileHandle else { return }
      let size = (try? handle.seekToEnd()) ?? 0
      if size + UInt64(data.count) > maxFileSize {
        rotateLogs()
      }
      guard let handle = fileHandle else { return }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
      try? handle.synchronize()
    }
  }

  private func rotateLogs() {
    try? fileHandle?.close()
    fileHandle = nil

    let fm = FileManager.default
    // Drop the oldest file, then shift: wvss.log.2 -> .3, wvss.log.1 -> .2, wvss.log -> .1
    try? fm.removeItem(atPath: rotatedFilePath(maxFiles - 1))
    var i = maxFiles - 2
    while i >= 0 {
      let src = i == 0 ? logFilePath : rotatedFilePath(i - 1)
      if fm.fileExists(atPath: src) {
        try? fm.moveItem(atPath: src, toPath: rotatedFilePath(i))
      }
      i -= 1
    }
    openLogFile()
  }

  private func rotatedFilePath(_ index: Int) -> String {
    (logDirectory as NSString).appendingPathComponent("\(logFileName).\(index + 1)")
  }
}
