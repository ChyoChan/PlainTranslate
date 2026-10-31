// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import AppKit
import SwiftUI

struct SettingsView: View {
    let pane: SettingsPane
    let inspectCredentials: Bool
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var model = TranslationService.shared
    @ObservedObject private var credentials = TranslationCredentials.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var navigation: SettingsNavigation
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

    init(pane: SettingsPane = .translation, inspectCredentials: Bool = true,
         navigation: SettingsNavigation = .shared) {
        self.pane = pane
        self.inspectCredentials = inspectCredentials
        self.navigation = navigation
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(pane.title(for: l10n.language)).font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(pane.subtitle(for: l10n.language)).font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 6)
            ScrollViewReader { proxy in
                Form {
                    switch pane {
                    case .translation: translationSettings
                    case .shortcuts: shortcutSettings
                    case .appearance: appearanceSettings
                    case .speech: speechSettings
                    case .usage: usageSettings
                    case .about: aboutSettings
                    }
                }
                .formStyle(.grouped)
                .onAppear { focusGoogleCredentials(using: proxy) }
                .onChange(of: navigation.focusGoogleCredentials) { _, _ in focusGoogleCredentials(using: proxy) }
                .onChange(of: credentials.busy) { _, busy in
                    if !busy { focusGoogleCredentials(using: proxy) }
                }
            }
        }
        .toggleStyle(.switch)
        .frame(minWidth: 620, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("settingsPane-" + pane.rawValue)
        .task {
            if inspectCredentials && pane == .translation { await credentials.refresh() }
            if pane == .shortcuts { permissions.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if pane == .shortcuts { permissions.refresh() }
            model.syncWithPreferences()
        }
        .onDisappear {
            keyDraft = ""
            keyFocused = false
        }
        .onChange(of: model.engine) { _, _ in keyDraft = "" }
    }

    @ViewBuilder private var translationSettings: some View {
        Section {
            LabeledContent(text.engine) {
                Picker(text.engine, selection: Binding(get: { model.engine }, set: { model.setEngine($0) })) {
                    Label("Apple", systemImage: "cpu").tag(TranslationEngine.apple)
                    Label("Google", systemImage: "cloud").tag(TranslationEngine.google)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 210)
                .accessibilityIdentifier("settingsTranslationEngine")
            }
            // Cloud transmission and cost information stays visible at the point of choice.
            Text(model.privacyNotice).font(.caption).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if model.engine == .google { credentialsSection.id(Self.googleCredentialsID) }
        }
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(text.pdfLineBreakCleanup, isOn: $pdfCleanup)
                caption(label("Join mid-sentence line breaks, preserving paragraphs and lists.",
                              "合併句子中途的斷行，保留段落與清單。"))
                DisclosureGroup(label("Processing details", "更多處理細節")) {
                    caption(text.pdfLineBreakCleanupCaption)
                }
            }
        }
        Section {
            Picker(label("Interface language", "介面語言"), selection: Binding(
                get: { l10n.language }, set: { l10n.setLanguage($0) }
            )) {
                Text("English").tag(AppLanguage.en)
                Text("繁體中文（香港）").tag(AppLanguage.zhHK)
                Text("繁體中文（台灣）").tag(AppLanguage.zhTW)
            }
        }
    }

    @ViewBuilder private var shortcutSettings: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(text.enable, isOn: $doubleCopy)
                    .onChange(of: doubleCopy) { _, _ in
                        permissions.refresh()
                        model.syncWithPreferences()
                    }
                caption(text.caption)
                caption(label("Enable double ⌘C in only one translation app to avoid duplicate popups.",
                              "請只在一個翻譯 App 啟用雙 ⌘C，避免重複彈窗。"))
            }
        }
        Section {
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
                    Button(label("Reset", "重設")) { shortcut = .defaultValue }
                }
                caption(label("Click the shortcut and press a combination with Command, Control or Option. Escape cancels recording.",
                              "按一下快捷鍵，再按包含 Command、Control 或 Option 的組合鍵；Escape 可取消錄製。"))
                if model.customShortcutUnavailable {
                    Label(label("This shortcut is unavailable or used by another app. Choose another combination.",
                                "此快捷鍵無法使用或已被其他 App 佔用，請選擇其他組合。"),
                          systemImage: "exclamationmark.triangle")
                        .font(.callout).accessibilityIdentifier("translationShortcutConflict")
                }
            }
        }
        if doubleCopy || customShortcutEnabled {
            Section {
                Label(permissions.accessibility ? label("Accessibility access granted", "已授予輔助使用權限") : text.permission,
                      systemImage: permissions.accessibility ? "checkmark.circle" : "lock.shield")
                    .font(.callout)
                if !permissions.accessibility {
                    Button(label("Open Accessibility Settings…", "開啟輔助使用設定…")) { permissions.requestAccessibility() }
                }
                caption(label("Select text in another app and use the shortcut to copy and translate it with the selected engine. You can still type or paste without Accessibility access.",
                              "在其他 App 選取文字後使用快捷鍵，便會複製並以目前引擎翻譯。未授權時仍可在翻譯視窗輸入或貼上文字。"))
            }
        }
    }

    @ViewBuilder private var appearanceSettings: some View {
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
        Section(label("Reading preview", "閱讀預覽")) {
            VStack(alignment: .leading, spacing: 0) {
                Text("A clear space for every thought.")
                    .font(.body).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                Divider()
                Text("讓每個想法，都有清晰的表達空間。")
                    .font(.system(size: TranslationCompactLayout.fontSize(popupFontSize)))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                HStack {
                    Image(systemName: "speaker.wave.2")
                    Spacer()
                    Image(systemName: "doc.on.doc")
                }.foregroundStyle(.secondary).padding([.horizontal, .bottom], 16).accessibilityHidden(true)
            }
            .frame(maxWidth: TranslationCompactLayout.width(popupWidth))
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("translationAppearancePreview")
            caption(label("The preview fits this pane. Open the popup to see its actual size.",
                          "預覽會配合此面板縮窄；開啟彈窗可查看實際大小。"))
        }
    }

    @ViewBuilder private var speechSettings: some View {
            Section(text.speechOptions) {
                Picker(text.chineseVoice, selection: $chineseVoice) {
                    Text(text.cantonese).tag("yue-HK")
                    Text(text.mandarin).tag("zh-TW")
                }
                .onChange(of: chineseVoice) { _, _ in model.syncWithPreferences() }
                caption(text.speechCaption)
                TranslationSpeechSettings(model: model)
            }
    }

    @ViewBuilder private var usageSettings: some View {
        Section { GoogleTranslationUsageView() }
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
    }

    @ViewBuilder private var aboutSettings: some View {
        ReleaseUpdateSection()
            Section(label("About PlainTranslate", "關於 PlainTranslate")) {
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

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text.apiKey).font(.subheadline.weight(.medium))
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
        guard pane == .translation, navigation.selectedPane == .translation,
              navigation.focusGoogleCredentials, model.engine == .google else { return }
        proxy.scrollTo(Self.googleCredentialsID, anchor: .top)
        guard !credentials.busy else { return }
        DispatchQueue.main.async {
            guard pane == .translation, navigation.selectedPane == .translation,
                  navigation.focusGoogleCredentials, model.engine == .google, !credentials.busy else { return }
            proxy.scrollTo(Self.googleCredentialsID, anchor: .top)
            keyFocused = true
            navigation.focusGoogleCredentials = false
        }
    }

    private func caption(_ value: String) -> some View {
        Text(value).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ english: String, _ chinese: String) -> String {
        l10n.language == .en ? english : chinese
    }
}
