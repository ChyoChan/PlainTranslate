// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import AppKit
import SwiftUI

struct SettingsView: View {
    var inspectCredentials = true
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var model = TranslationService.shared
    @ObservedObject private var credentials = TranslationCredentials.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var navigation = SettingsNavigation.shared
    @AppStorage(DefaultsKey.translationDoubleCopyEnabled) private var doubleCopy = false
    @AppStorage(DefaultsKey.translationCustomShortcutEnabled) private var customShortcutEnabled = false
    @State private var shortcut = TranslationShortcut.load(from: .standard)
    @AppStorage(DefaultsKey.translationPDFLineBreakCleanup) private var pdfCleanup = true
    @AppStorage(DefaultsKey.translationPopupWidth) private var popupWidth = TranslationCompactLayout.defaultWidth
    @AppStorage(DefaultsKey.translationPopupFontSize) private var popupFontSize = TranslationCompactLayout.defaultFontSize
    @AppStorage(DefaultsKey.translationChineseVoice) private var chineseVoice = TranslationSpeechLanguage.defaultChineseVoice
    @State private var keyDraft = ""
    @FocusState private var keyFocused: Bool
    private static let googleCredentialsID = "googleCredentials"
    private var text: TranslationStrings { TranslationStrings(language: l10n.language) }

    private var settingsForm: some View {
        Form {
            Section(label("General", "一般")) {
                Picker(label("Interface language", "介面語言"), selection: Binding(
                    get: { l10n.language }, set: { l10n.setLanguage($0) }
                )) {
                    Text("English").tag(AppLanguage.en)
                    Text("繁體中文（香港）").tag(AppLanguage.zhHK)
                    Text("繁體中文（台灣）").tag(AppLanguage.zhTW)
                }
            }
            Section(text.engine) {
                Picker(text.engine, selection: Binding(get: { model.engine }, set: { model.setEngine($0) })) {
                    Text(text.localEngine).tag(TranslationEngine.apple)
                    Text(text.googleEngine).tag(TranslationEngine.google)
                }
                caption(model.privacyNotice)
                if model.engine == .google {
                    credentialsSection
                        .id(Self.googleCredentialsID)
                    GoogleTranslationUsageView()
                }
            }
            Section(label("Shortcut", "快捷鍵")) {
                Toggle(text.enable, isOn: $doubleCopy)
                    .onChange(of: doubleCopy) { _, _ in
                        permissions.refresh()
                        model.syncWithPreferences()
                    }
                caption(text.caption)
                caption(label(
                    "Off by default so another translator can keep using this shortcut. Enable it in only one app.",
                    "預設關閉，方便與其他翻譯 App 並存。請只在一個 App 啟用此快捷鍵。"))
                Toggle(label("Custom translation shortcut", "自訂翻譯快捷鍵"), isOn: $customShortcutEnabled)
                    .onChange(of: customShortcutEnabled) { _, _ in
                        permissions.refresh()
                        model.syncWithPreferences()
                    }
                if customShortcutEnabled {
                    HStack {
                        Text(label("Shortcut", "快捷鍵"))
                        Spacer()
                        TranslationShortcutRecorder(shortcut: $shortcut, onRecordingChanged: model.setRecordingShortcut)
                        .frame(width: 180, height: 30)
                        .onChange(of: shortcut) { _, value in
                            value.save(to: .standard)
                            model.syncWithPreferences()
                        }
                        Button(label("Reset", "重設")) {
                            shortcut = .defaultValue
                        }
                    }
                    caption(label(
                        "Click the shortcut, then press a key with Command, Control or Option. Escape cancels recording. Select text in another app and use this shortcut to copy (⌘C) and translate it with the selected engine. Accessibility access is required.",
                        "按一下快捷鍵，再按包含 Command、Control 或 Option 的組合鍵；Escape 可取消錄製。在其他 App 選取文字後按此快捷鍵，便會複製（⌘C）並以目前引擎翻譯。需要輔助使用權限。"))
                    if model.customShortcutUnavailable {
                        Label(label("This shortcut is unavailable or used by another app. Choose another combination.",
                                    "此快捷鍵無法使用或已被其他 App 佔用，請選擇其他組合。"),
                              systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .accessibilityIdentifier("translationShortcutConflict")
                    }
                }
                if doubleCopy || customShortcutEnabled {
                    Label(permissions.accessibility
                          ? label("Accessibility access granted", "已授予輔助使用權限")
                          : text.permission,
                          systemImage: permissions.accessibility ? "checkmark.circle" : "lock.shield")
                        .font(.callout)
                    if !permissions.accessibility {
                        Button(label("Open Accessibility Settings…", "開啟輔助使用設定…")) {
                            permissions.requestAccessibility()
                        }
                    }
                }
                Button(text.open) { model.open() }
            }
            Section(text.popupAppearance) {
                HStack {
                    Text(text.popupWidth).frame(width: 100, alignment: .leading)
                    Slider(value: Binding(
                        get: { TranslationCompactLayout.width(popupWidth) },
                        set: { popupWidth = $0; model.applyPopupAppearance() }
                    ), in: TranslationCompactLayout.widthRange, step: 10) { Text(text.popupWidth) }
                        .labelsHidden()
                        .accessibilityLabel(text.popupWidth)
                    Text("\(Int(TranslationCompactLayout.width(popupWidth))) pt")
                        .monospacedDigit().frame(width: 64, alignment: .trailing)
                }
                HStack {
                    Text(text.popupFontSize).frame(width: 100, alignment: .leading)
                    Slider(value: Binding(
                        get: { TranslationCompactLayout.fontSize(popupFontSize) },
                        set: { popupFontSize = $0 }
                    ), in: TranslationCompactLayout.fontSizeRange, step: 1) { Text(text.popupFontSize) }
                        .labelsHidden()
                        .accessibilityLabel(text.popupFontSize)
                    Text("\(Int(TranslationCompactLayout.fontSize(popupFontSize))) pt")
                        .monospacedDigit().frame(width: 64, alignment: .trailing)
                }
                HStack {
                    Button(text.previewPopup) { model.open(.compact) }
                    Button(text.resetAppearance) {
                        popupWidth = TranslationCompactLayout.defaultWidth
                        popupFontSize = TranslationCompactLayout.defaultFontSize
                        model.applyPopupAppearance()
                    }
                }
                caption(text.popupAppearanceCaption)
            }
            Section(text.pdfLineBreakCleanup) {
                Toggle(text.pdfLineBreakCleanup, isOn: $pdfCleanup)
                caption(text.pdfLineBreakCleanupCaption)
            }
            Section(text.cacheTitle) {
                HStack {
                    Text(text.cacheCount(model.cachedTranslationCount))
                    Spacer()
                    Button(text.clearCache) { model.clearTranslationCache() }
                        .disabled(model.cachedTranslationCount == 0)
                        .accessibilityIdentifier("clearTranslationCache")
                }
                caption(text.cacheCaption)
            }
            Section(text.speechOptions) {
                Picker(text.chineseVoice, selection: $chineseVoice) {
                    Text(text.cantonese).tag("yue-HK")
                    Text(text.mandarin).tag("zh-TW")
                }
                .onChange(of: chineseVoice) { _, _ in model.syncWithPreferences() }
                caption(text.speechCaption)
                TranslationSpeechSettings(model: model)
            }
            Section(label("About PlainTranslate", "關於 PlainTranslate")) {
                LabeledContent(label("Version", "版本"), value:
                    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.3")
                caption(label(
                    "Independent, open-source translation app. Translation components adapted from Vorssaint under GPL-3.0-or-later.",
                    "獨立開源翻譯 App。翻譯元件改編自 Vorssaint，採用 GPL-3.0-or-later 授權。"))
                caption(label("Provided without warranty. Apple and Google provide the translation engines.",
                              "本程式不提供擔保。翻譯引擎由 Apple 及 Google 提供。"))
                HStack {
                    Link("GitHub", destination: URL(string: "https://github.com/ChyoChan/PlainTranslate")!)
                    Link("GPL-3.0-or-later", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
                    Link(label("Original project", "原始專案"), destination: URL(string: "https://github.com/vorssaint/vorssaint-utils")!)
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { navigation.returnToTranslation() } label: {
                    Label(label("Back", "返回"), systemImage: "chevron.left")
                }
                .accessibilityLabel(label("Back to translation", "返回翻譯"))
                .help(label("Back to translation", "返回翻譯"))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                settingsForm
                    .onAppear { focusGoogleCredentials(using: proxy) }
                    .onChange(of: navigation.focusGoogleCredentials) { _, _ in
                        focusGoogleCredentials(using: proxy)
                    }
                    .onChange(of: credentials.busy) { _, busy in
                        if !busy { focusGoogleCredentials(using: proxy) }
                    }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 680)
        .navigationTitle(label("PlainTranslate Settings", "PlainTranslate 設定"))
        .task {
            if inspectCredentials { await credentials.refresh() }
            permissions.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
            model.syncWithPreferences()
        }
        .onDisappear {
            keyDraft = ""
            keyFocused = false
            navigation.focusGoogleCredentials = false
        }
        .onChange(of: model.engine) { _, _ in keyDraft = "" }
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField(text.keyPlaceholder, text: $keyDraft)
                .textFieldStyle(.roundedBorder)
                .textContentType(.password)
                .privacySensitive()
                .accessibilityLabel(text.apiKey)
                .disabled(credentials.busy)
                .focused($keyFocused)
            HStack {
                Button(text.saveKey) {
                    let draft = keyDraft
                    model.cancel()
                    Task { if await credentials.save(draft) { keyDraft = "" } }
                }
                .disabled(credentials.busy || keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(text.removeKey, role: .destructive) {
                    model.cancel()
                    Task { await credentials.remove() }
                }
                .disabled(credentials.busy || !credentials.hasKey)
                if credentials.busy { ProgressView().controlSize(.small) }
            }
            caption(credentialStatus)
            Link(label("Set up Cloud Translation API", "設定 Cloud Translation API"),
                 destination: URL(string: "https://docs.cloud.google.com/translate/docs/setup")!)
        }
    }

    private var credentialStatus: String {
        switch credentials.status {
        case .none: return credentials.hasKey ? text.keyPresent : text.keyMissing
        case .saved: return text.keySaved
        case .removed: return text.keyRemoved
        case .failed: return text.keychainFailed
        case .invalid: return text.keyInvalid
        }
    }

    private func focusGoogleCredentials(using proxy: ScrollViewProxy) {
        guard navigation.focusGoogleCredentials, model.engine == .google else { return }
        proxy.scrollTo(Self.googleCredentialsID, anchor: .top)
        guard !credentials.busy else { return }
        DispatchQueue.main.async {
            guard navigation.focusGoogleCredentials, !credentials.busy else { return }
            proxy.scrollTo(Self.googleCredentialsID, anchor: .top)
            keyFocused = true
            navigation.focusGoogleCredentials = false
        }
    }

    private func caption(_ value: String) -> some View {
        Text(value).font(.caption).foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ english: String, _ chinese: String) -> String {
        l10n.language == .en ? english : chinese
    }
}
