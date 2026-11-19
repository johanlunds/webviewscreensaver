//
//  WVSSConfigController.swift
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

import AppKit
import WebKit

protocol WVSSConfigControllerDelegate: AnyObject {
  func configController(_ controller: WVSSConfigController, dismissConfigSheet sheet: NSWindow)
}

/// Owner of ConfigureSheet.xib. The ObjC name must stay "WVSSConfigController" for the nib.
@objc(WVSSConfigController)
final class WVSSConfigController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  private static let rowPasteboardType = NSPasteboard.PasteboardType("kURLTableRow")

  // Column identifiers set in the nib.
  private static let columnURL = NSUserInterfaceItemIdentifier("url")
  private static let columnTime = NSUserInterfaceItemIdentifier("time")
  private static let columnPreview = NSUserInterfaceItemIdentifier("preview")

  weak var delegate: WVSSConfigControllerDelegate?

  @IBOutlet var sheet: NSWindow!
  @IBOutlet var sheetContents: NSView!
  @IBOutlet var urlTable: NSTableView!
  @IBOutlet var urlsURLField: NSTextField!
  @IBOutlet var fetchURLCheckbox: NSButton!

  private let config: WVSSConfig
  private var previewWindows: [NSWindowController] = []

  init(config: WVSSConfig) {
    self.config = config
    super.init()
    wvssLog(self)
    loadSheet()
  }

  deinit {
    wvssLog(self)
  }

  private func loadSheet() {
    let bundle = Bundle(for: WVSSConfigController.self)
    if !bundle.loadNibNamed("ConfigureSheet", owner: self, topLevelObjects: nil) {
      wvssLog(self, "Unable to load configuration sheet")
      return
    }

    urlsURLField.stringValue = config.addressListURL ?? ""

    urlTable.setDraggingSourceOperationMask(.move, forLocal: true)
    urlTable.registerForDraggedTypes([Self.rowPasteboardType])

    fetchURLCheckbox.state = config.shouldFetchAddressList ? .on : .off
    urlsURLField.isEnabled = config.shouldFetchAddressList
  }

  private func synchronize() {
    config.addressListURL = urlsURLField.stringValue
    config.synchronize()
  }

  // MARK: - Actions

  @IBAction func addRow(_ sender: Any?) {
    config.addresses.append(WVSSAddress.makeDefault())
    urlTable.reloadData()
  }

  @IBAction func removeRow(_ sender: Any?) {
    let row = urlTable.selectedRow
    guard row >= 0, row < config.addresses.count else { return }
    config.addresses.remove(at: row)
    urlTable.reloadData()
  }

  @IBAction func resetData(_ sender: Any?) {
    let alert = NSAlert()
    alert.messageText = "Clear History"
    alert.informativeText = "Clears history, cookies, cache and more."
    alert.icon = NSImage(named: NSImage.cautionName)
    alert.addButton(withTitle: "Clear Data")
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning
    alert.beginSheetModal(for: sheet) { [weak self] response in
      if response == .alertFirstButtonReturn {
        self?.clearWebViewHistory()
      }
    }
  }

  private func clearWebViewHistory() {
    WKWebsiteDataStore.default().removeData(
      ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
      modifiedSince: Date(timeIntervalSince1970: 0)
    ) {
      wvssLog(nil, "Web cache cleared")
    }
  }

  @IBAction func openLogsFolder(_ sender: Any?) {
    NSWorkspace.shared.open(URL(fileURLWithPath: WVSSFileLogger.shared.logDirectory))
  }

  @IBAction func dismissConfigSheet(_ sender: Any?) {
    synchronize()
    delegate?.configController(self, dismissConfigSheet: sheet)
  }

  @IBAction func toggleFetchingURLs(_ sender: Any?) {
    config.shouldFetchAddressList.toggle()
    fetchURLCheckbox.state = config.shouldFetchAddressList ? .on : .off
    urlsURLField.isEnabled = config.shouldFetchAddressList
  }

  @IBAction func tableViewCellDidEdit(_ sender: NSTextField) {
    let column = urlTable.column(for: sender)
    var row = urlTable.row(for: sender)
    if row < 0 { row = urlTable.selectedRow }
    // Possible when removing the row that is being edited.
    guard column >= 0, row >= 0, row < config.addresses.count else { return }

    let address = config.addresses[row]
    switch urlTable.tableColumns[column].identifier {
    case Self.columnURL:
      address.url = sender.stringValue
    case Self.columnTime:
      address.duration = Int(sender.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
    default:
      break
    }
  }

  @IBAction func previewButtonClicked(_ sender: NSButton) {
    let row = urlTable.row(for: sender)
    guard row >= 0, row < config.addresses.count else { return }
    openAddress(config.addresses[row])
  }

  private func openAddress(_ address: WVSSAddress) {
    let mouse = NSEvent.mouseLocation
    let bounds = NSRect(x: 0, y: 0, width: 1024, height: 768)
    let frame = bounds.offsetBy(dx: mouse.x - bounds.width / 2, dy: mouse.y - bounds.height / 2)
    let window = NSWindow(
      contentRect: frame.integral,
      styleMask: [.closable, .titled, .resizable],
      backing: .buffered,
      defer: true)
    window.isReleasedWhenClosed = false

    let webView = WebViewScreenSaverView.makeWebView(frame: bounds)
    webView.autoresizingMask = [.width, .height]
    window.contentView?.addSubview(webView)

    let controller = NSWindowController(window: window)
    previewWindows.append(controller)
    controller.showWindow(nil)
    WebViewScreenSaverView.load(address, into: webView)
  }

  // MARK: - NSTableViewDataSource / Delegate

  func numberOfRows(in tableView: NSTableView) -> Int {
    config.addresses.count
  }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard let identifier = tableColumn?.identifier, row < config.addresses.count else { return nil }
    let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
    let address = config.addresses[row]

    switch identifier {
    case Self.columnURL:
      cell?.textField?.stringValue = address.url
    case Self.columnTime:
      cell?.textField?.stringValue = String(address.duration)
    case Self.columnPreview:
      break
    default:
      wvssLog(self, "Unhandled table column identifier \(identifier.rawValue)")
    }
    return cell
  }

  func tableView(
    _ tableView: NSTableView, pasteboardWriterForRow row: Int
  ) -> NSPasteboardWriting? {
    let item = NSPasteboardItem()
    item.setString(String(row), forType: Self.rowPasteboardType)
    return item
  }

  func tableView(
    _ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
    proposedDropOperation dropOperation: NSTableView.DropOperation
  ) -> NSDragOperation {
    if dropOperation == .on {
      tableView.setDropRow(row, dropOperation: .above)
    }
    return .move
  }

  func tableView(
    _ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
    dropOperation: NSTableView.DropOperation
  ) -> Bool {
    guard
      let string = info.draggingPasteboard.pasteboardItems?.first?.string(
        forType: Self.rowPasteboardType),
      let dragRow = Int(string), dragRow >= 0, dragRow < config.addresses.count
    else { return false }

    let moved = config.addresses.remove(at: dragRow)
    let target = dragRow < row ? row - 1 : row
    config.addresses.insert(moved, at: min(max(target, 0), config.addresses.count))
    urlTable.reloadData()
    return true
  }
}
