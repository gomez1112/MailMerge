import CoreGraphics
import AppKit
import Foundation
let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let selected = windows.compactMap { item -> [String: String]? in
    guard let title = item[kCGWindowName as String] as? String, title.hasPrefix("MergeformShot:"),
          let id = item[kCGWindowNumber as String] as? Int,
          let pid = item[kCGWindowOwnerPID as String] as? Int32,
          let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return nil }
    return ["id": String(id), "title": title]
}
let data = try JSONSerialization.data(withJSONObject: selected)
print(String(decoding: data, as: UTF8.self))
