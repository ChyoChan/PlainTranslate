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
        .environment(\.locale, Locale(identifier: l10n.language.rawValue))
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
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent(text.engine) {
                    Picker(text.engine, selection: Binding(get: { model.engine }, set: { model.setEngine($0) })) {
                        Label("Apple", systemImage: "cpu").tag(TranslationEngine.apple)
                        Label("Google", systemImage: "cloud").tag(TranslationEngine.google)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 210)
                    .accessibilityIdentifier("settingsTranslationEngine")
                }
                // Keep cloud transmission and cost information beside the engine choice.
                caption(model.privacyNotice)
            }
            if model.engine == .google { credentialsSection.id(Self.googleCredentialsID) }
            else { AppleLanguagePackSetup(language: l10n.language) }
        }
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(text.pdfLineBreakCleanup, isOn: $pdfCleanup)
                caption(text.pdfLineBreakCleanupCaption)
            }
        }
        Section {
            Picker(l10n.language.text("Interface language", "介面語言", "界面语言", "表示言語"), selection: Binding(
                get: { l10n.language }, set: { l10n.setLanguage($0) }
            )) {
                ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                    Text(language.displayName).tag(language)
                }
            }
        }
    }

    @ViewBuilder private var shortcutSettings: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(text.enable, isOn: $doubleCopy)
                    .onChange(of: doubleCopy) { _, _ in
                        permissions.refresh()
                        model.syncWithPreferences()
                    }
                caption(text.caption)
            }
        } footer: {
            caption(l10n.language.text("Enable double ⌘C in only one translation app to avoid duplicate popups.", "請只在一個翻譯 App 啟用雙 ⌘C，避免重複彈窗。", "请只在一个翻译 App 中启用双按 ⌘C，避免重复弹窗。", "ポップアップの重複を避けるため、⌘C の 2 回押しは 1 つの翻訳アプリだけで有効にしてください。"))
        }
        Section {
            Toggle(l10n.language.text("Custom translation shortcut", "自訂翻譯快捷鍵", "自定义翻译快捷键", "翻訳ショートカットをカスタマイズ"), isOn: $customShortcutEnabled)
                .onChange(of: customShortcutEnabled) { _, _ in
                    permissions.refresh()
                    model.syncWithPreferences()
                }
            if customShortcutEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(l10n.language.text("Shortcut", "快捷鍵", "快捷键", "ショートカット")) {
                        HStack(spacing: 12) {
                            TranslationShortcutRecorder(shortcut: $shortcut, onRecordingChanged: model.setRecordingShortcut)
                                .frame(width: 180, height: 30)
                                .onChange(of: shortcut) { _, value in
                                    value.save(to: .standard)
                                    model.syncWithPreferences()
                                }
                            Button(l10n.language.text("Reset", "重設", "重置", "リセット")) { shortcut = .defaultValue }
                        }
                    }
                    caption(l10n.language.text("Click to record a shortcut with ⌘, ⌃ or ⌥. Press Esc to cancel.", "按快捷鍵欄位錄製，須包含 ⌘、⌃ 或 ⌥；按 Esc 取消。", "点击快捷键栏进行录制，须包含 ⌘、⌃ 或 ⌥；按 Esc 取消。", "欄をクリックして、⌘、⌃、⌥ のいずれかを含むキーを押してください。Esc でキャンセルできます。"))
                    if model.customShortcutUnavailable {
                        Label(l10n.language.text("This shortcut is unavailable or used by another app. Choose another combination.", "此快捷鍵無法使用或已被其他 App 佔用，請選擇其他組合。", "此快捷键不可用或已被其他 App 占用，请选择其他组合。", "このショートカットは使用できないか、別のアプリで使われています。別の組み合わせを選んでください。"),
                              systemImage: "exclamationmark.triangle")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("translationShortcutConflict")
                    }
                }
            }
        }
        if doubleCopy || customShortcutEnabled {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(permissions.accessibility ? l10n.language.text("Accessibility access granted", "已授予輔助使用權限", "已授予辅助功能权限", "アクセシビリティは許可済みです") : text.permission,
                          systemImage: permissions.accessibility ? "checkmark.circle" : "lock.shield")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if !permissions.accessibility {
                        Button(l10n.language.text("Open Accessibility Settings…", "開啟輔助使用設定…", "打开辅助功能设置…", "アクセシビリティ設定を開く…")) { permissions.requestAccessibility() }
                    }
                }
            } footer: {
                caption(l10n.language.text("Select text in another app, then use the shortcut. Typing and pasting work without permission.", "在其他 App 選取文字後按快捷鍵翻譯；未授權仍可輸入或貼上。", "在其他 App 选中文字后按快捷键翻译；未授权仍可输入或粘贴。", "ほかのアプリでテキストを選び、ショートカットを使ってください。入力や貼り付けには権限は不要です。"))
            }
        }
    }

    @ViewBuilder private var appearanceSettings: some View {
        Section {
            LabeledContent(text.popupWidth) {
                HStack(spacing: 12) {
                    Slider(value: Binding(
                        get: { TranslationCompactLayout.width(popupWidth) },
                        set: { popupWidth = $0; model.applyPopupAppearance() }
                    ), in: TranslationCompactLayout.widthRange, step: 10) { Text(text.popupWidth) }
                        .labelsHidden()
                        .accessibilityLabel(text.popupWidth)
                    Text("\(Int(TranslationCompactLayout.width(popupWidth))) pt")
                        .monospacedDigit().foregroundStyle(.primary)
                        .frame(minWidth: 64, alignment: .trailing)
                }
            }
            LabeledContent(text.popupFontSize) {
                HStack(spacing: 12) {
                    Slider(value: Binding(
                        get: { TranslationCompactLayout.fontSize(popupFontSize) },
                        set: { popupFontSize = $0 }
                    ), in: TranslationCompactLayout.fontSizeRange, step: 1) { Text(text.popupFontSize) }
                        .labelsHidden()
                        .accessibilityLabel(text.popupFontSize)
                    Text("\(Int(TranslationCompactLayout.fontSize(popupFontSize))) pt")
                        .monospacedDigit().foregroundStyle(.primary)
                        .frame(minWidth: 64, alignment: .trailing)
                }
            }
            HStack(spacing: 12) {
                Button(text.resetAppearance) {
                    popupWidth = TranslationCompactLayout.defaultWidth
                    popupFontSize = TranslationCompactLayout.defaultFontSize
                    model.applyPopupAppearance()
                }
                Spacer()
                Button(text.previewPopup) { model.open(.compact) }
            }
        } footer: {
            caption(text.popupAppearanceCaption)
        }
        Section {
            VStack(alignment: .leading, spacing: 0) {
                Text("A clear space for every thought.")
                    .font(.body).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                Divider()
                Text(l10n.language.text("讓每個想法，都有清晰的表達空間。", "讓每個想法，都有清晰的表達空間。", "让每个想法，都有清晰的表达空间。", "どんな思いも、すっきり伝わる。"))
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
        } header: {
            Text(l10n.language.text("Reading preview", "閱讀預覽", "阅读预览", "表示プレビュー"))
        } footer: {
            caption(l10n.language.text("Preview width is limited by this pane. Open the popup for its actual size.", "預覽受面板寬度限制；開啟彈窗可查看實際大小。", "预览受面板宽度限制；打开弹窗可查看实际大小。", "プレビューの幅は設定画面に合わせて表示します。実際のサイズはポップアップで確認してください。"))
        }
    }

    @ViewBuilder private var speechSettings: some View {
        Section {
            Picker(text.chineseVoice, selection: $chineseVoice) {
                Text(text.cantonese).tag("yue-HK")
                Text(text.mandarin).tag("zh-TW")
            }
            .onChange(of: chineseVoice) { _, _ in model.syncWithPreferences() }
        } footer: {
            caption(text.speechCaption)
        }
        TranslationSpeechSettings(model: model)
    }

    @ViewBuilder private var usageSettings: some View {
        GoogleTranslationUsageView()
        Section {
            HStack {
                Text(text.cacheCount(model.cachedTranslationCount))
                Spacer()
                Button(text.clearCache) { model.clearTranslationCache() }
                    .disabled(model.cachedTranslationCount == 0)
                    .accessibilityIdentifier("clearTranslationCache")
            }
        } header: {
            Text(text.cacheTitle)
        } footer: {
            caption(text.cacheCaption)
        }
    }

    @ViewBuilder private var aboutSettings: some View {
        ReleaseUpdateSection()
        Section {
            HStack(spacing: 16) {
                Link("GitHub", destination: URL(string: "https://github.com/ChyoChan/PlainTranslate")!)
                Link("GPL-3.0-or-later", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
            }
        } header: {
            Text(l10n.language.text("About PlainTranslate", "關於 PlainTranslate", "关于 PlainTranslate", "PlainTranslate について"))
        }
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GoogleAPISetupGuide(language: l10n.language)
            Divider()
            Text(text.apiKey).font(.body.weight(.medium))
            SecureField(text.apiKey, text: $keyDraft, prompt: Text(text.keyPlaceholder))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .textContentType(.password)
                .privacySensitive()
                .accessibilityLabel(text.apiKey)
                .disabled(credentials.busy)
                .focused($keyFocused)
            caption(credentialStatus)
            HStack(spacing: 12) {
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
                Spacer(minLength: 8)
                Link(l10n.language.text("Set up Cloud Translation API", "設定 Cloud Translation API", "设置 Cloud Translation API", "Cloud Translation API を設定"),
                     destination: URL(string: "https://docs.cloud.google.com/translate/docs/setup")!)
            }
        }
    }

    private var credentialStatus: String {
        switch credentials.status {
        case .none: return credentials.hasKey ? text.keyPresent : text.keyMissing
        case .saved: return text.keySaved
        case .removed: return text.keyRemoved
        case .failed: return text.keychainFailed
        case .invalid: return text.keyInvalid
        case .exists: return text.keyExists
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
        Text(value).font(.callout).foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

}
