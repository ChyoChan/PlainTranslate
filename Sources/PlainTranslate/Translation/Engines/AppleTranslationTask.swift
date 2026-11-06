// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import Translation

/// Recreated for each immutable request. SwiftUI cancellation and the service's
/// request ID guard prevent old results replacing newer edits or closed panels.
@available(macOS 15.0, *)
struct AppleTranslationTask: View {
    let request: TranslationRequest
    let completion: (UUID, Result<String, Error>) -> Void

    var body: some View {
        Color.clear.translationTask(TranslationSession.Configuration(
            source: request.source.map { Locale.Language(identifier: $0) },
            target: Locale.Language(identifier: request.target))) { session in
                do {
                    if let source = request.source {
                        let status = await LanguageAvailability().status(
                            from: Locale.Language(identifier: source),
                            to: Locale.Language(identifier: request.target))
                        guard status != .unsupported else { throw TranslationError.unsupportedLanguagePairing }
                    }
                    try Task.checkCancellation()
                    // translate() owns detection and any download consent UI.
                    // prepareTranslation() with source=nil always throws
                    // unableToIdentifyLanguage, even with installed languages.
                    let translated = try await TranslationTextPlan.translate(request.text) { text in
                        let response = try await session.translate(text)
                        return response.targetText
                    }
                    try Task.checkCancellation()
                    await MainActor.run { completion(request.id, .success(translated)) }
                } catch {
                    await MainActor.run { completion(request.id, .failure(error)) }
                }
            }
    }
}
