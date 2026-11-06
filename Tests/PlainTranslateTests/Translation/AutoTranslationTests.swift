// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import XCTest
@testable import PlainTranslate

@MainActor
final class AutoTranslationTests: XCTestCase {
    func testTypingSubmitsOnlyTheLatestTextAfterThePause() async throws {
        try await withFixture { model, delay in
            model.editInput("First draft")
            try await self.waitFor { delay.pending == 1 }
            model.editInput("Final sentence.")
            try await self.waitFor { delay.pending == 2 }
            XCTAssertNil(model.request)
            delay.releaseAll()
            try await self.waitFor { model.request != nil }
            let request = try XCTUnwrap(model.request)
            XCTAssertEqual(request.text, "Final sentence.")
            XCTAssertEqual(request.engine, .apple)
            model.finish(request.id, result: .success("最後一句。"))
            XCTAssertEqual(model.output, "最後一句。")
        }
    }

    func testEditingCancelsAnActiveRequestAndRejectsItsOldResult() async throws {
        try await withFixture { model, delay in
            model.editInput("First sentence.")
            try await self.waitFor { delay.pending == 1 }
            delay.releaseAll()
            try await self.waitFor { model.request != nil }
            let old = try XCTUnwrap(model.request)
            model.editInput("Changed sentence.")
            XCTAssertNil(model.request)
            XCTAssertFalse(model.busy)
            model.finish(old.id, result: .success("Stale output"))
            XCTAssertTrue(model.output.isEmpty)
            try await self.waitFor { delay.pending == 1 }
            delay.releaseAll()
            try await self.waitFor { model.request != nil }
            XCTAssertEqual(model.request?.text, "Changed sentence.")
            XCTAssertNotEqual(model.request?.id, old.id)
        }
    }

    func testEmptyTextCancelCloseAndSettingsPreventPendingSubmissions() async throws {
        for action in 0..<4 {
            try await withFixture { model, delay in
                model.editInput("Pending sentence.")
                try await self.waitFor { delay.pending == 1 }
                switch action {
                case 0: model.editInput(" \n ")
                case 1: model.cancel()
                case 2: model.close()
                default: model.hideForSettings()
                }
                delay.releaseAll()
                try await self.waitFor { delay.returned == 1 }
                XCTAssertNil(model.request)
                XCTAssertFalse(model.busy)
                XCTAssertEqual(delay.pending, 0)
            }
        }
    }

    func testAnImmediateTranslationDoesNotSubmitAgainAfterThePause() async throws {
        try await withFixture { model, delay in
            model.editInput("Copied sentence.")
            try await self.waitFor { delay.pending == 1 }
            model.translate()
            let request = try XCTUnwrap(model.request)
            delay.releaseAll()
            try await self.waitFor { delay.returned == 1 }
            XCTAssertEqual(model.request?.id, request.id)
        }
    }

    private func withFixture(_ check: (TranslationService, ManualDelay) async throws -> Void) async rethrows {
        let defaults = UserDefaults.standard
        let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var fixture = previous
        fixture[DefaultsKey.translationEngine] = TranslationEngine.apple.rawValue
        defaults.setVolatileDomain(fixture, forName: UserDefaults.argumentDomain)
        let delay = ManualDelay()
        let model = TranslationService(autoTranslationDelay: { await delay.pause() })
        defer {
            model.close()
            delay.releaseAll()
            defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain)
        }
        try await check(model, delay)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertTrue(condition(), "Timed out waiting for the scheduled work")
    }

    @MainActor
    private final class ManualDelay {
        private var continuations: [CheckedContinuation<Void, Never>] = []
        private(set) var returned = 0
        var pending: Int { continuations.count }

        func pause() async {
            await withCheckedContinuation { continuations.append($0) }
            returned += 1
        }

        func releaseAll() {
            let pending = continuations
            continuations.removeAll()
            pending.forEach { $0.resume() }
        }
    }
}
