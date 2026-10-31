// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import Foundation
import Combine

enum DefaultsKey {
    static let settingsPane = "settingsPane"
    static let appLanguage = "interfaceLanguage"
    static let translationDoubleCopyEnabled = "translationDoubleCopyEnabled"
    static let translationCustomShortcutEnabled = "translationCustomShortcutEnabled"
    static let translationShortcut = "translationShortcut"
    static let translationEngine = "translationEngine"
    static let translationRecentSourceLanguages = "translationRecentSourceLanguages"
    static let translationRecentTargetLanguages = "translationRecentTargetLanguages"
    static let translationSourceTabs = "translationSourceTabs"
    static let translationTargetTabs = "translationTargetTabs"
    static let translationGoogleUsage = "translationGoogleUsage"
    static let translationGoogleUsageReminderEnabled = "translationGoogleUsageReminderEnabled"
    static let translationGoogleUsageReminderMonth = "translationGoogleUsageReminderMonth"
    static let translationPopupWidth = "translationPopupWidth"
    static let translationPopupFontSize = "translationPopupFontSize"
    static let translationPDFLineBreakCleanup = "translationPDFLineBreakCleanup"
    static let translationChineseVoice = "translationChineseVoice"
    static let translationSpeechVoices = "translationSpeechVoices"
    static let translationSpeechRate = "translationSpeechRate"
}

enum AppPreferences {
    static let bundleIdentifier = "com.chyo.plaintranslate"

    static func registerDefaults(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: [
            DefaultsKey.translationDoubleCopyEnabled: false,
            DefaultsKey.translationCustomShortcutEnabled: false,
            DefaultsKey.translationEngine: TranslationEngine.apple.rawValue,
            DefaultsKey.translationPopupWidth: TranslationCompactLayout.defaultWidth,
            DefaultsKey.translationPopupFontSize: TranslationCompactLayout.defaultFontSize,
            DefaultsKey.translationPDFLineBreakCleanup: true,
            DefaultsKey.translationChineseVoice: TranslationSpeechLanguage.defaultChineseVoice,
            DefaultsKey.translationSpeechRate: TranslationSpeechPreferences.defaultRate,
            DefaultsKey.translationGoogleUsageReminderEnabled: true,
        ])
    }
}

enum AppLanguage: String {
    case en = "en", zhHK = "zh-HK", zhTW = "zh-TW", zhHans = "zh-Hans"
    static var system: AppLanguage {
        guard let preferred = Locale.preferredLanguages.first else { return .en }
        // The first release offers English and Traditional Chinese interface copy.
        if preferred.hasPrefix("zh-TW") { return .zhTW }
        return preferred.hasPrefix("zh") ? .zhHK : .en
    }
}

final class L10n: ObservableObject {
    static let shared = L10n()
    @Published var language: AppLanguage {
        didSet {
            if language != oldValue { UserDefaults.standard.set(language.rawValue, forKey: DefaultsKey.appLanguage) }
        }
    }
    var isChinese: Bool { language != .en }

    private init() {
        language = UserDefaults.standard.string(forKey: DefaultsKey.appLanguage).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func setLanguage(_ value: AppLanguage) { language = value }
}
