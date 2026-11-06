// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 ChyoChan

import AppKit
import SwiftUI

@main
struct PlainTranslateApp: App {
    @NSApplicationDelegateAdaptor(PlainTranslateDelegate.self) private var delegate
    @ObservedObject private var l10n = L10n.shared

    init() {
        AppPreferences.registerDefaults()
    }

    var body: some Scene {
        MenuBarExtra {
            Button(l10n.language.text("Open translator…", "開啟翻譯…", "打开翻译…", "翻訳を開く…")) {
                TranslationService.shared.open()
            }
            Button(l10n.language.text("Translate copied text", "翻譯已複製文字", "翻译已复制文字", "コピーしたテキストを翻訳")) {
                TranslationService.shared.useCopiedText(presentation: .compact)
            }
            Divider()
            Button(l10n.language.text("Settings…", "設定…", "设置…", "設定…")) { SettingsNavigation.shared.show() }
                .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button(l10n.language.text("Quit PlainTranslate", "結束 PlainTranslate", "退出 PlainTranslate", "PlainTranslate を終了")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image("BrandMarkTemplate")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .accessibilityLabel("PlainTranslate")
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(l10n.language.text("Settings…", "設定…", "设置…", "設定…")) { SettingsNavigation.shared.show() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

}

final class PlainTranslateDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Permissions.shared.refresh()
        TranslationService.shared.start()
        TranslationService.shared.open()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        TranslationService.shared.open()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        TranslationService.shared.stop()
    }
}
