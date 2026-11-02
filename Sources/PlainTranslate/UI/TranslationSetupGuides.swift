// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import SwiftUI
import Translation

struct AppleSetupPair: Hashable {
    var source = "en"
    var target = "zh-Hant"
    var isSupportedChoice: Bool {
        source != target && TranslationLanguageDefaults.languages.contains(source) &&
            TranslationLanguageDefaults.languages.contains(target)
    }
    var configuration: TranslationSession.Configuration? {
        guard isSupportedChoice else { return nil }
        return .init(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
    }
}

struct AppleLanguagePackSetup: View {
    let language: AppLanguage
    @State private var pair = AppleSetupPair()
    @State private var availability: LanguageAvailability.Status?
    @State private var configuration: TranslationSession.Configuration?
    @State private var busy = false
    @State private var failed = false
    private func label(_ en: String, _ zh: String) -> String { language == .en ? en : zh }

    var body: some View {
        DisclosureGroup(label("Apple language packs", "Apple 語言包")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(label("Choose both languages, then allow macOS to download them. An internet connection is needed for downloads; translation stays on this Mac.",
                           "選擇原文及譯文語言，然後允許 macOS 下載。下載需要網絡連線；翻譯會在此 Mac 上進行。"))
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    languagePicker(label("From", "原文"), selection: $pair.source)
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                    languagePicker(label("To", "譯文"), selection: $pair.target)
                }
                .disabled(busy)
                Text(status).font(.callout).accessibilityIdentifier("appleLanguagePackStatus")
                HStack {
                    Button(label("Download language packs…", "下載語言包…")) {
                        guard let request = pair.configuration else { return }
                        failed = false
                        busy = true
                        configuration = request
                    }
                    .disabled(busy || !pair.isSupportedChoice || availability == nil || availability == .installed || availability == .unsupported)
                    .accessibilityIdentifier("downloadAppleLanguages")
                    if busy { ProgressView().controlSize(.small) }
                }
            }
            .padding(.top, 8)
        }
        .onDisappear { configuration = nil; busy = false }
        .task(id: pair) {
            availability = nil
            failed = false
            guard pair.isSupportedChoice else { return }
            let checked = await LanguageAvailability().status(from: Locale.Language(identifier: pair.source), to: Locale.Language(identifier: pair.target))
            guard !Task.isCancelled else { return }
            availability = checked
        }
        .translationTask(configuration) { session in
            guard configuration != nil else { return }
            do {
                try await session.prepareTranslation()
                let checked = await LanguageAvailability().status(from: Locale.Language(identifier: pair.source), to: Locale.Language(identifier: pair.target))
                guard !Task.isCancelled else { return }
                availability = checked
            } catch {
                guard !Task.isCancelled else { return }
                failed = true
            }
            busy = false
            configuration = nil
        }
    }

    private var status: String {
        if !pair.isSupportedChoice { return label("Choose two different languages.", "請選擇兩種不同的語言。") }
        if busy { return label("Follow the macOS download prompt…", "請按 macOS 的下載提示操作…") }
        if failed { return label("Setup did not finish. Check your connection and try again. Downloads may continue in the background.", "設定未完成，請檢查網絡後重試。下載可能仍在背景進行。") }
        switch availability {
        case .installed: return label("Ready for on-device translation.", "已可使用本機翻譯。")
        case .supported: return label("Language packs are needed or still downloading. Use the button to open Apple's download prompt.", "需要語言包，或下載仍在進行。按下方按鈕開啟 Apple 下載提示。")
        case .unsupported: return label("Apple does not support this language pair on this Mac.", "此 Mac 的 Apple 翻譯不支援這個語言組合。")
        case nil: return label("Checking language packs…", "正在檢查語言包…")
        @unknown default: return label("Language availability is unknown. Try another pair.", "未能確認語言支援狀態，請選擇其他組合。")
        }
    }

    private func languagePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(TranslationLanguageDefaults.languages, id: \.self) { code in
                Text(Locale(identifier: language.rawValue).localizedString(forIdentifier: code) ?? code).tag(code)
            }
        }
    }
}
