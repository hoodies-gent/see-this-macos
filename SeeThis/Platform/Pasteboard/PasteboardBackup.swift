import AppKit
import Foundation

/// nspasteboard.org sentinel: writing this type tells clipboard managers
/// (Maccy / Paste / Alfred / OnText / etc.) to ignore the current pasteboard
/// contents. We attach it whenever we restore a pasteboard we just clobbered
/// to trigger the app's own Copy command.
enum NSPasteboardSentinel {
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
}

struct PasteboardBackup {
    let types: [NSPasteboard.PasteboardType]
    let data: [NSPasteboard.PasteboardType: Data]
    let changeCount: Int

    static func snapshot(_ pasteboard: NSPasteboard = .general) -> PasteboardBackup {
        let types = pasteboard.types ?? []
        var data: [NSPasteboard.PasteboardType: Data] = [:]
        for type in types {
            if let value = pasteboard.data(forType: type) {
                data[type] = value
            }
        }
        return PasteboardBackup(
            types: types,
            data: data,
            changeCount: pasteboard.changeCount
        )
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        var restoredTypes = types
        if !restoredTypes.contains(NSPasteboardSentinel.transient) {
            restoredTypes.append(NSPasteboardSentinel.transient)
        }
        pasteboard.declareTypes(restoredTypes, owner: nil)
        for type in types {
            if let value = data[type] {
                pasteboard.setData(value, forType: type)
            }
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        pasteboard.setString(timestamp, forType: NSPasteboardSentinel.transient)
    }
}

enum PasteboardChangePoller {
    static let defaultTimeoutSeconds: TimeInterval = 0.15
    static let pollIntervalSeconds: TimeInterval = 0.005

    /// Blocks until `pasteboard.changeCount != baseline` or `timeout` elapses.
    /// Returns `true` if a change was observed. Runs on the calling thread.
    @discardableResult
    static func waitForChange(
        from baseline: Int,
        pasteboard: NSPasteboard = .general,
        timeout: TimeInterval = defaultTimeoutSeconds,
        pollInterval: TimeInterval = pollIntervalSeconds
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != baseline {
                return true
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return pasteboard.changeCount != baseline
    }
}
