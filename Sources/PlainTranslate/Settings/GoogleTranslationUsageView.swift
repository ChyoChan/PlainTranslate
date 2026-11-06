// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import Combine

struct GoogleTranslationUsageView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var usage = GoogleTranslationUsageStore.shared.snapshot()
    @AppStorage(DefaultsKey.translationGoogleUsageReminderEnabled) private var reminderEnabled = true
    private var text: TranslationStrings { TranslationStrings(language: l10n.language) }
    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            Section {
                LabeledContent(text.googleSubmittedCharacters) {
                    Text(usage.characters, format: .number).monospacedDigit().foregroundStyle(.primary)
                }
                LabeledContent(text.googleRequestCount) {
                    Text(usage.requests, format: .number).monospacedDigit().foregroundStyle(.primary)
                }
                if usage.characters >= GoogleTranslationUsageReminder.thresholdCharacters {
                    Label {
                        Text(text.googleUsageReminderHUD)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("googleUsageThresholdWarning")
                }
                Link(text.googleUsageConsole, destination: URL(string: "https://console.cloud.google.com/apis/api/translate.googleapis.com/metrics")!)
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.googleUsageTitle)
                    Text("\(usage.month) · \(text.hongKongTime)").font(.callout).foregroundStyle(.primary)
                }
            } footer: {
                Text(text.googleUsageCaption).font(.callout).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            }
            .onAppear { refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .receive(on: DispatchQueue.main)) { _ in refresh() }
            .onReceive(refreshTimer) { date in usage = GoogleTranslationUsageStore.shared.snapshot(at: date) }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }

            Section {
                Toggle(text.googleUsageReminder, isOn: $reminderEnabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("googleUsageReminderToggle")
            } footer: {
                Text(text.googleUsageReminderCaption).font(.callout).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(2)
            }
        }
    }

    private func refresh() { usage = GoogleTranslationUsageStore.shared.snapshot() }
}
