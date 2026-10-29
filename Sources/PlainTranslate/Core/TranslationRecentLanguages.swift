// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 PlainTranslate contributors

import Foundation

enum TranslationRecentLanguages {
    static func load(forSource: Bool, from defaults: UserDefaults = .standard) -> [String] {
        ordered(defaults.stringArray(forKey: key(forSource)) ?? [], forSource: forSource)
    }

    static func tabs(forSource: Bool, from defaults: UserDefaults = .standard) -> [String] {
        ordered(defaults.stringArray(forKey: tabKey(forSource)) ?? load(forSource: forSource, from: defaults),
                forSource: forSource)
    }

    @discardableResult
    static func record(_ language: String, forSource: Bool, in defaults: UserDefaults = .standard) -> [String] {
        guard TranslationLanguageDefaults.languages.contains(language) || (forSource && language == "auto") else {
            return load(forSource: forSource, from: defaults)
        }
        let previousTabs = tabs(forSource: forSource, from: defaults)
        let recent = ordered([language] + load(forSource: forSource, from: defaults), forSource: forSource)
        if defaults.stringArray(forKey: key(forSource)) != recent {
            defaults.set(recent, forKey: key(forSource))
        }
        // Keep visible buttons stationary; refresh the set only for an unseen choice.
        let visible = previousTabs.contains(language) ? previousTabs : recent
        if defaults.stringArray(forKey: tabKey(forSource)) != visible {
            defaults.set(visible, forKey: tabKey(forSource))
        }
        return recent
    }

    private static func ordered(_ values: [String], forSource: Bool) -> [String] {
        let fallback = forSource ? ["en", "ja", "zh-Hant"] : ["zh-Hant", "en", "ja"]
        let allowed = Set(TranslationLanguageDefaults.languages + (forSource ? ["auto"] : []))
        var result: [String] = []
        for language in values + fallback where allowed.contains(language) && !result.contains(language) {
            result.append(language)
            if result.count == 3 { break }
        }
        return result
    }

    private static func key(_ forSource: Bool) -> String {
        forSource ? DefaultsKey.translationRecentSourceLanguages : DefaultsKey.translationRecentTargetLanguages
    }

    private static func tabKey(_ forSource: Bool) -> String {
        forSource ? DefaultsKey.translationSourceTabs : DefaultsKey.translationTargetTabs
    }
}
