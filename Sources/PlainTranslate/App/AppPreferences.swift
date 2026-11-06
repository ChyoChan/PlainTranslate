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

enum AppLanguage: String, CaseIterable {
    case en = "en", zhHK = "zh-HK", zhTW = "zh-TW", zhHans = "zh-Hans", ja = "ja"

    var displayName: String {
        switch self {
        case .en: return "English"
        case .zhHK: return "繁體中文（香港）"
        case .zhTW: return "繁體中文（台灣）"
        case .zhHans: return "简体中文"
        case .ja: return "日本語"
        }
    }

    static var system: AppLanguage { preferred(in: Locale.preferredLanguages) }

    static func preferred(in identifiers: [String]) -> AppLanguage {
        for identifier in identifiers {
            let locale = Locale.Language(identifier: identifier)
            switch locale.languageCode?.identifier {
            case "en": return .en
            case "ja": return .ja
            case "zh":
                if locale.script?.identifier == "Hans" { return .zhHans }
                return locale.region?.identifier == "TW" ? .zhTW : .zhHK
            default: continue
            }
        }
        return .en
    }

    func text(_ english: String, _ traditional: String, _ simplified: String, _ japanese: String) -> String {
        switch self {
        case .en: return english
        case .zhHK, .zhTW: return traditional
        case .zhHans: return simplified
        case .ja: return japanese
        }
    }
}

final class L10n: ObservableObject {
    static let shared = L10n()
    @Published var language: AppLanguage {
        didSet {
            if language != oldValue { UserDefaults.standard.set(language.rawValue, forKey: DefaultsKey.appLanguage) }
        }
    }

    private init() {
        language = UserDefaults.standard.string(forKey: DefaultsKey.appLanguage).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    func setLanguage(_ value: AppLanguage) { language = value }
}
