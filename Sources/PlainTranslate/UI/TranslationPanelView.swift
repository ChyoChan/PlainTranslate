// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import Translation

@available(macOS 15.0, *)
struct TranslationPanelView: View {
    @ObservedObject var model: TranslationService
    @ObservedObject private var l10n = L10n.shared
    private var text: TranslationStrings { TranslationStrings(language: l10n.language) }
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredSourceLanguage: String?
    @State private var hoveredTargetLanguage: String?
    private static let resultAnchor = "translationResultStart"
    @AppStorage(DefaultsKey.translationPopupFontSize) private var popupFontSize = TranslationCompactLayout.defaultFontSize

    var body: some View {
        VStack(spacing: 0) {
            if model.presentation == .compact {
                compactContent
            } else {
                editorContent
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
        .background {
            // Keep the runner outside the presentation branches. Expanding the
            // same panel must not cancel an in-flight Apple Translation session.
            if let request = model.request, request.engine == .apple {
                TranslationTaskRunner(request: request, completion: model.finish)
                    .id(request.id)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        .onAppear { inputFocused = model.presentation == .editor }
        .onChange(of: model.presentation) { _, mode in inputFocused = mode == .editor }
    }

    private var targetSelection: Binding<String> {
        Binding(get: { model.target }, set: { model.setTarget($0) })
    }

    private var sourceSelection: Binding<String> {
        Binding(get: { model.source }, set: { model.setSource($0) })
    }

    private var enginePicker: some View {
        TranslationEngineControl(selection: Binding(get: { model.engine }, set: {
            model.setEngine($0)
            model.scheduleAutoTranslation()
        }), label: text.engine, appleHelp: text.privacy, googleHelp: text.googlePrivacy)
        .frame(width: 190, height: 28)
    }

    private var compactContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "character.bubble").font(.title3).accessibilityHidden(true)
                Spacer(minLength: 0)
                enginePicker
                closeButton
            }
            languagePicker(text.to, selection: targetSelection, detectsLanguage: false)
            resultText(compact: true)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            ViewThatFits(in: .horizontal) {
                compactActions
                compactActions.labelStyle(.iconOnly)
            }
            .controlSize(.large)
        }
        .padding(12)
    }

    private var compactActions: some View {
        HStack(spacing: 10) {
            copyButton.fixedSize()
            Button { model.open(.editor) } label: {
                Label(text.edit, systemImage: "square.and.pencil")
                    .frame(minHeight: 20)
            }
            .help(text.edit)
            .fixedSize()
            Spacer(minLength: 0)
            speechButton(.original).fixedSize()
            speechButton(.translation).fixedSize()
            if model.busy {
                Button(text.cancel) { model.cancel() }
            } else if model.output.isEmpty && !model.input.isEmpty {
                Button(text.translate) { model.translate() }
            }
        }
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(text.title, systemImage: "character.bubble")
                    .font(.headline)
                enginePicker
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Button { SettingsNavigation.shared.show() } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(TranslationToolbarButtonStyle())
                    .help(l10n.language == .en ? "Settings" : "設定")
                    .accessibilityLabel(l10n.language == .en ? "Settings" : "設定")
                    .accessibilityIdentifier("translationSettings")
                    Button { model.open(.compact) } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(TranslationToolbarButtonStyle())
                    .help(text.compact)
                    .accessibilityLabel(text.compact)
                    .accessibilityIdentifier("translationCompactView")
                    closeButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            HStack(spacing: 16) {
                languagePicker(text.from, selection: sourceSelection, detectsLanguage: true)
                Button { model.swapLanguages() } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.borderless)
                .frame(width: 28, height: 28)
                .accessibilityLabel(text.swap)
                .help(text.swap)
                .disabled(model.source == "auto" || model.busy)
                languagePicker(text.to, selection: targetSelection, detectsLanguage: false)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: Binding(get: { model.input }, set: model.editInput))
                        .font(.system(size: 18))
                        .scrollContentBackground(.hidden)
                        .focused($inputFocused)
                        .accessibilityLabel(text.source)
                    languageActions(.original)
                }
                .padding(16)
                .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 8) {
                    resultText(compact: false)
                    languageActions(.translation)
                }
                .padding(16)
                .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func languageActions(_ part: TranslationSpeechPart) -> some View {
        HStack {
            speechButton(part)
                .frame(width: 32, height: 32)
            Spacer(minLength: 8)
            if part == .original, model.busy {
                Button(text.cancel) { model.cancel() }.font(.callout)
                Spacer(minLength: 8)
            }
            if part == .original {
                Button { model.copyOriginal() } label: {
                    Label(model.copiedOriginal ? text.copied : text.copyOriginal,
                          systemImage: model.copiedOriginal ? "checkmark" : "doc.on.doc")
                }
                .disabled(model.input.isEmpty || model.busy)
                .help(model.copiedOriginal ? text.copied : text.copyOriginal)
                .accessibilityLabel(model.copiedOriginal ? text.copied : text.copyOriginal)
                .accessibilityIdentifier("translationCopyOriginal")
                .frame(width: 32, height: 32)
            } else {
                copyButton.frame(width: 32, height: 32)
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.system(size: 18))
    }

    private func speechButton(_ part: TranslationSpeechPart) -> some View {
        let speaking = model.speakingPart == part
        let label = speaking ? text.stopSpeech : (part == .original ? text.speakOriginal : text.speakTranslation)
        let content = part == .original ? model.input : model.output
        return Button { model.toggleSpeech(part) } label: {
            Label(label, systemImage: speaking ? "stop.fill" : "speaker.wave.2")
                .frame(minHeight: model.presentation == .compact ? 20 : nil)
        }
        .controlSize(model.presentation == .compact ? .large : .small)
        .disabled(model.busy || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel(label)
        .accessibilityValue(speaking ? text.speaking : "")
        .accessibilityIdentifier(part == .original ? "translationSpeakOriginal" : "translationSpeakResult")
        .help(label)
    }

    private var copyButton: some View {
        Button { model.copyOutput() } label: {
            Label(model.copied ? text.copied : text.copy,
                  systemImage: model.copied ? "checkmark" : "doc.on.doc")
                .frame(minHeight: model.presentation == .compact ? 20 : nil)
        }
        .disabled(model.output.isEmpty || model.busy)
        .help(model.copied ? text.copied : text.copy)
        .accessibilityLabel(model.copied ? text.copied : text.copy)
        .accessibilityIdentifier("translationCopyResult")
    }

    private var closeButton: some View {
        Button { model.close() } label: { Image(systemName: "xmark") }
            .buttonStyle(TranslationToolbarButtonStyle(isClose: true))
            .accessibilityLabel(text.close)
            .accessibilityIdentifier("translationClose")
            .help(text.close)
            .keyboardShortcut(.cancelAction)
    }

    private func resultText(compact: Bool) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if compact, !model.input.isEmpty {
                        Text(text.source).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                            .accessibilityAddTraits(.isHeader)
                        Text(model.input)
                            .font(.system(size: TranslationCompactLayout.fontSize(popupFontSize)))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider().id(Self.resultAnchor)
                        Text(text.result).font(.caption.weight(.semibold)).foregroundStyle(.primary)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if model.busy {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(model.message ?? text.loading).font(.callout)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        if model.output.isEmpty, let message = model.message {
                            VStack(alignment: .leading, spacing: 10) {
                                Label(text.translationUnavailable, systemImage: "exclamationmark.triangle")
                                    .font(.headline)
                                Text(message)
                                    .font(.system(size: compact ? TranslationCompactLayout.fontSize(popupFontSize) : 18))
                                    .textSelection(.enabled)
                                if model.offersGoogleKeySetup {
                                    Button { SettingsNavigation.shared.requestGoogleCredentials() } label: {
                                        Label(text.configureGoogleKey, systemImage: "key")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier("configureGoogleKey")
                                }
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("translationError")
                        } else {
                            Text(model.output.isEmpty ? (compact ? text.waiting : text.title) : model.output)
                                .font(.system(size: compact ? TranslationCompactLayout.fontSize(popupFontSize) : 18))
                                .foregroundStyle(model.output.isEmpty ? .secondary : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !model.output.isEmpty, let message = model.message {
                            Text(message).font(.callout).foregroundStyle(.primary)
                        }
                        if let message = model.speechMessage {
                            Text(message).font(.callout).foregroundStyle(.primary)
                                .accessibilityIdentifier("translationSpeechMessage")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(compact ? 12 : 0)
                .background {
                    if compact {
                        GeometryReader { geometry in
                            Color.clear.preference(key: TranslationResultHeight.self, value: geometry.size.height)
                        }
                    }
                }
            }
            .onPreferenceChange(TranslationResultHeight.self) { height in
                guard compact, height > 0 else { return }
                // Header (34), languages (38), footer (32), spacing (30), padding (24).
                model.fitCompactContent(height: height + 158)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(compact ? text.title : text.result)
            .onAppear { scrollToTranslation(proxy, compact: compact) }
            .onChange(of: model.output) { _, _ in scrollToTranslation(proxy, compact: compact) }
            .onChange(of: model.busy) { _, busy in
                if !busy { scrollToTranslation(proxy, compact: compact) }
            }
        }
    }

    private func scrollToTranslation(_ proxy: ScrollViewProxy, compact: Bool) {
        guard compact else { return }
        // Wait for the result and adaptive panel size to finish their layout.
        DispatchQueue.main.async { proxy.scrollTo(Self.resultAnchor, anchor: .top) }
    }

    private func languagePicker(_ title: String, selection: Binding<String>, detectsLanguage: Bool) -> some View {
        let recent = detectsLanguage ? model.recentSourceLanguages : model.recentTargetLanguages
        let hovered = detectsLanguage ? hoveredSourceLanguage : hoveredTargetLanguage
        let selectedLanguage = selection.wrappedValue
        return HStack(spacing: 4) {
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(recent, id: \.self) { language in
                            languageTab(language, selection: selection, detectsLanguage: detectsLanguage)
                        }
                    }
                    .frame(minWidth: geometry.size.width)
                    .overlayPreferenceValue(TranslationLanguageBounds.self) { bounds in
                        GeometryReader { coordinates in
                            if let anchor = bounds[selectedLanguage] {
                                let frame = coordinates[anchor]
                                // Keep one underline alive while its position and width change.
                                Rectangle().fill(Color.accentColor)
                                    .frame(width: frame.width, height: 2)
                                    .offset(x: frame.minX, y: frame.maxY - 2)
                                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: frame)
                            }
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
                }
            }
            Menu {
                if detectsLanguage {
                    languageMenuItem("auto", selection: selection)
                    Divider()
                }
                ForEach(TranslationLanguageDefaults.languages, id: \.self) { language in
                    languageMenuItem(language, selection: selection)
                }
            } label: {
                Image(systemName: "chevron.down").frame(width: 24, height: 38)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(title)
            .accessibilityLabel(title)
            .accessibilityValue(languageName(selection.wrappedValue))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 38)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .onDisappear {
            if detectsLanguage { hoveredSourceLanguage = nil }
            else { hoveredTargetLanguage = nil }
        }
    }

    private func languageTab(_ language: String, selection: Binding<String>, detectsLanguage: Bool) -> some View {
        let selected = selection.wrappedValue == language
        let hovered = (detectsLanguage ? hoveredSourceLanguage : hoveredTargetLanguage) == language
        return Button { selection.wrappedValue = language } label: {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(languageName(language))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected || hovered ? Color.primary : Color.secondary)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .frame(height: 38)
                    .anchorPreference(key: TranslationLanguageBounds.self, value: .bounds) { [language: $0] }
                    .overlay(alignment: .bottom) {
                        if hovered && !selected {
                            Rectangle().fill(Color.secondary)
                                .frame(height: 2)
                                .accessibilityHidden(true)
                        }
                    }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(hovered ? Color.primary.opacity(0.04) : .clear)
        .onHover { inside in
            if detectsLanguage {
                if inside { hoveredSourceLanguage = language }
                else if hoveredSourceLanguage == language { hoveredSourceLanguage = nil }
            } else {
                if inside { hoveredTargetLanguage = language }
                else if hoveredTargetLanguage == language { hoveredTargetLanguage = nil }
            }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("\(detectsLanguage ? "source" : "target")Language-\(language)")
    }

    private func languageMenuItem(_ language: String, selection: Binding<String>) -> some View {
        Button { selection.wrappedValue = language } label: {
            if selection.wrappedValue == language {
                Label(languageName(language), systemImage: "checkmark")
            } else {
                Text(languageName(language))
            }
        }
    }

    private func languageName(_ identifier: String) -> String {
        identifier == "auto" ? text.auto :
            (Locale(identifier: l10n.language.rawValue).localizedString(forIdentifier: identifier) ?? identifier)
    }
}

private struct TranslationLanguageBounds: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct TranslationToolbarButtonStyle: ButtonStyle {
    var isClose = false
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16))
            .foregroundStyle(hovered && isClose ? Color.red :
                (hovered || configuration.isPressed ? Color.primary : Color.secondary))
            .frame(width: 34, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.14) :
                        (hovered ? (isClose ? Color.red.opacity(0.12) : Color.primary.opacity(0.07)) : .clear))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct TranslationResultHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Recreated for each immutable request. SwiftUI cancellation and the service's
/// request ID guard prevent old results replacing newer edits or closed panels.
@available(macOS 15.0, *)
private struct TranslationTaskRunner: View {
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
                        guard status != .unsupported else { throw TranslationUnsupportedPair() }
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
                    let failure: Error
                    switch error {
                    case TranslationError.unsupportedSourceLanguage,
                         TranslationError.unsupportedTargetLanguage,
                         TranslationError.unsupportedLanguagePairing:
                        failure = TranslationUnsupportedPair()
                    case TranslationError.unableToIdentifyLanguage:
                        failure = TranslationUnknownSource()
                    default: failure = error
                    }
                    await MainActor.run { completion(request.id, .failure(failure)) }
                }
            }
    }
}
