// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import AppKit
import Combine
import SwiftUI

enum SettingsPane: String, CaseIterable {
    case translation, shortcuts, appearance, speech, usage, about

    func title(for language: AppLanguage) -> String {
        let chinese = language != .en
        switch self {
        case .translation: return chinese ? "翻譯" : "Translation"
        case .shortcuts: return chinese ? "快捷鍵" : "Shortcuts"
        case .appearance: return chinese ? "彈窗外觀" : "Popup"
        case .speech: return chinese ? "朗讀" : "Read Aloud"
        case .usage: return chinese ? "用量與暫存" : "Usage & Cache"
        case .about: return chinese ? "關於與更新" : "About & Updates"
        }
    }

    func subtitle(for language: AppLanguage) -> String {
        let chinese = language != .en
        switch self {
        case .translation: return chinese ? "選擇翻譯引擎及文字處理方式。" : "Choose a translation engine and text preparation options."
        case .shortcuts: return chinese ? "從其他 App 選取文字，快速開啟翻譯。" : "Translate selected text from other apps."
        case .appearance: return chinese ? "比較字體與寬度調整後的閱讀效果。" : "Preview the popup's text size and width."
        case .speech: return chinese ? "使用這部 Mac 上已安裝的語音。" : "Choose from the voices installed on this Mac."
        case .usage: return chinese ? "檢視這個 App 的本機統計與暫存。" : "Review this app's local submission estimates and cache."
        case .about: return chinese ? "PlainTranslate · 簡單、獨立的 Mac 翻譯工具。" : "PlainTranslate · A small, independent Mac translator."
        }
    }

    var symbol: String {
        switch self {
        case .translation: return "character.bubble"
        case .shortcuts: return "keyboard"
        case .appearance: return "macwindow"
        case .speech: return "speaker.wave.2"
        case .usage: return "externaldrive"
        case .about: return "info.circle"
        }
    }
}

/// The translator is hosted by AppKit, so it cannot rely on a Settings scene environment.
final class SettingsNavigation: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = SettingsNavigation()
    @Published var focusGoogleCredentials = false
    @Published private(set) var selectedPane: SettingsPane
    private let defaults: UserDefaults
    private var window: NSWindow?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedPane = SettingsPane(rawValue: defaults.string(forKey: DefaultsKey.settingsPane) ?? "") ?? .translation
        super.init()
    }

    func selectPane(_ pane: SettingsPane) {
        precondition(Thread.isMainThread)
        guard selectedPane != pane else { return }
        selectedPane = pane
        defaults.set(pane.rawValue, forKey: DefaultsKey.settingsPane)
        if let controller = window?.contentViewController as? SettingsTabController,
           let index = SettingsPane.allCases.firstIndex(of: pane), controller.selectedTabViewItemIndex != index {
            controller.selectedTabViewItemIndex = index
        }
    }

    func prepareGoogleCredentials() {
        precondition(Thread.isMainThread)
        TranslationService.shared.setEngine(.google)
        selectPane(.translation)
        focusGoogleCredentials = true
    }

    func requestGoogleCredentials() {
        prepareGoogleCredentials()
        show()
    }

    func makeWindow(inspectCredentials: Bool = true) -> NSWindow {
        precondition(Thread.isMainThread)
        if let window { return window }
        let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 660),
                               styleMask: [.titled, .closable, .resizable],
                               backing: .buffered, defer: false)
        created.isReleasedWhenClosed = false
        created.contentMinSize = NSSize(width: 620, height: 560)
        let controller = SettingsTabController(navigation: self, inspectCredentials: inspectCredentials)
        created.contentViewController = controller
        created.delegate = self
        window = created
        controller.configureWindow()
        created.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        created.standardWindowButton(.zoomButton)?.isEnabled = false
        created.center()
        return created
    }

    func show() {
        precondition(Thread.isMainThread)
        TranslationService.shared.hideForSettings()
        let window = makeWindow()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func returnToTranslation() {
        precondition(Thread.isMainThread)
        window?.close()
        TranslationService.shared.open(TranslationService.shared.presentation)
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        focusGoogleCredentials = false
        window?.contentViewController = nil
        window = nil
    }
}
