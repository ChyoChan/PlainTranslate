// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import AppKit
import SwiftUI

struct TranslationShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: TranslationShortcut
    @ObservedObject private var l10n = L10n.shared
    var onRecordingChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        apply(to: button, enabled: context.environment.isEnabled)
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        apply(to: button, enabled: context.environment.isEnabled)
    }

    private func apply(to button: RecorderButton, enabled: Bool) {
        button.shortcut = shortcut
        button.isEnabled = enabled
        button.language = l10n.language
        button.capture = { shortcut = $0 }
        button.recordingChanged = onRecordingChanged
        button.setAccessibilityLabel(l10n.language.text("Set translation shortcut", "設定翻譯快捷鍵", "设置翻译快捷键", "翻訳ショートカットを設定"))
        button.toolTip = l10n.language.text("Click and press a shortcut; Escape cancels. Include Command, Control or Option.",
                                           "按一下後輸入快捷鍵；Esc 取消。須包含 ⌘、⌃ 或 ⌥。",
                                           "点击后输入快捷键；按 Esc 取消。须包含 ⌘、⌃ 或 ⌥。",
                                           "クリックしてキーを押してください。Esc でキャンセル。Command、Control、Option のいずれかを含めてください。")
        if !enabled { button.stopRecording() }
        button.refreshTitle()
    }

    static func dismantleNSView(_ button: RecorderButton, coordinator: ()) {
        button.stopRecording()
        button.capture = nil
        button.recordingChanged = nil
    }

    final class RecorderButton: NSButton {
        var shortcut = TranslationShortcut.defaultValue
        var language = AppLanguage.en
        var capture: ((TranslationShortcut) -> Void)?
        var recordingChanged: ((Bool) -> Void)?
        private var recording = false
        private var observers: [NSObjectProtocol] = []

        override var acceptsFirstResponder: Bool { true }

        @objc func beginRecording() {
            guard isEnabled, !recording, window?.makeFirstResponder(self) == true else { return }
            recording = true
            recordingChanged?(true)
            let center = NotificationCenter.default
            for (name, object) in [(NSApplication.didResignActiveNotification, nil),
                                   (NSWindow.willCloseNotification, window)] {
                observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    self?.stopRecording()
                })
            }
            refreshTitle()
        }

        func stopRecording() {
            guard recording else { return }
            recording = false
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            refreshTitle()
            recordingChanged?(false)
        }

        func refreshTitle() {
            title = recording ? language.text("Press shortcut…", "請按快捷鍵…", "请按快捷键…", "キーを押してください…") : shortcut.displayString
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
            record(event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            record(event)
        }

        private func record(_ event: NSEvent) {
            guard !event.isARepeat else { return }
            let shortcut = TranslationShortcut(event: event)
            if event.keyCode == 53, shortcut.modifiers == 0 { stopRecording(); return }
            if event.modifierFlags.contains(.function), event.keyCode < 64 { NSSound.beep(); return }
            guard shortcut.isValid else { NSSound.beep(); return }
            self.shortcut = shortcut
            stopRecording()
            capture?(shortcut)
        }

        override func resignFirstResponder() -> Bool {
            stopRecording()
            return super.resignFirstResponder()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stopRecording() }
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    }
}
