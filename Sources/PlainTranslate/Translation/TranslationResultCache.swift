// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Session-only LRU. Text never goes to preferences, disk, or another app.
struct TranslationResultCache {
    private struct Entry {
        let request: TranslationRequest
        let output: String
        var bytes: Int { request.text.utf8.count + output.utf8.count }
        func matches(_ other: TranslationRequest) -> Bool {
            request.text.utf8.elementsEqual(other.text.utf8) && request.source == other.source &&
                request.target == other.target && request.engine == other.engine
        }
    }
    private var entries: [Entry] = []
    var count: Int { entries.count }

    mutating func value(for request: TranslationRequest) -> String? {
        guard let index = entries.firstIndex(where: { $0.matches(request) }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.output
    }

    mutating func insert(_ output: String, for request: TranslationRequest) {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let entry = Entry(request: request, output: output)
        guard entry.bytes <= 500_000 else { return }
        entries.removeAll { $0.matches(request) }
        entries.append(entry)
        while entries.count > 20 || entries.reduce(0, { $0 + $1.bytes }) > 500_000 {
            entries.removeFirst()
        }
    }

    mutating func removeAll() { entries.removeAll() }
}
