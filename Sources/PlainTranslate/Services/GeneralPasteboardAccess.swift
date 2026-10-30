// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Serializes every access the app makes to the general pasteboard.
/// NSPasteboard keeps a mutable type cache on its shared instance, so reading
/// it from two queues at once can race inside AppKit, and a read has no time
/// limit: content can be promised and rendered only on demand, so an app that
/// stops answering leaves the reader hanging. Hence one serial lane, off the
/// main thread, and no way to wait for it — a caller waiting on the main
/// thread is a frozen app (issue #887).
final class GeneralPasteboardAccess {
    static let shared = GeneralPasteboardAccess()

    private let queue = DispatchQueue(label: "PlainTranslate.Pasteboard.general", qos: .utility)

    private init() {}

    /// A deadline limits result delivery and prevents expired queued work
    /// from starting. It cannot interrupt an AppKit call already in progress.
    /// `didFinish` runs on main only when the actual queue operation ends,
    /// even if `completion` already received nil at the deadline. Callers use
    /// it to keep admission bounded while a provider is unresponsive.
    func async<T>(timeout: TimeInterval,
                   _ work: @escaping () -> T?,
                   then completion: @escaping (T?) -> Void,
                   didFinish: @escaping (T?) -> Void = { _ in }) {
        let deadline = DispatchTime.now() + timeout
        let delivery = PasteboardResultDelivery(completion)
        let timeoutWork = DispatchWorkItem { delivery.complete(nil) }
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: timeoutWork)
        queue.async {
            let value = DispatchTime.now() >= deadline ? nil : work()
            DispatchQueue.main.async {
                timeoutWork.cancel()
                didFinish(value)
                delivery.complete(DispatchTime.now() >= deadline ? nil : value)
            }
        }
    }
}

/// Both deadline and queue completion deliver on main. Clearing the callback
/// before invoking it also makes reentrant callers safe.
private final class PasteboardResultDelivery<Value> {
    private var completion: ((Value?) -> Void)?

    init(_ completion: @escaping (Value?) -> Void) {
        self.completion = completion
    }

    func complete(_ value: Value?) {
        precondition(Thread.isMainThread)
        let callback = completion
        completion = nil
        callback?(value)
    }
}
