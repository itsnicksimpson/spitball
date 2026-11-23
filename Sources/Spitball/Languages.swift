import Foundation

/// Languages you can dictate in. Auto uses Parakeet, which hears 25 European
/// languages and follows you when you switch mid-sentence. Anything else runs on
/// Apple's on-device engine in that language. All offline.
nonisolated enum Languages {
    /// Parakeet v3-family languages (ISO 639-1).
    static let parakeet: Set<String> = ["bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
                                         "lv", "lt", "mt", "pl", "pt", "ro", "sk", "sl", "es", "sv", "ru", "uk"]

    static func parakeetSpeaks(_ id: String) -> Bool {
        id == "auto" || parakeet.contains(Locale(identifier: id).language.languageCode?.identifier ?? "")
    }

    static let choices: [String] = ["auto", "en_US", "en_GB", "en_AU", "en_IN", "es_ES", "es_MX", "fr_FR", "fr_CA", "de_DE", "it_IT",
                                    "pt_BR", "pt_PT", "nl_NL", "sv_SE", "da_DK", "nb_NO", "fi_FI", "pl_PL", "cs_CZ", "ro_RO", "hu_HU",
                                    "el_GR", "ru_RU", "uk_UA", "tr_TR", "he_IL", "ar_SA", "hi_IN", "th_TH", "vi_VN", "id_ID", "ms_MY",
                                    "ja_JP", "ko_KR", "zh_CN", "zh_TW", "yue_CN"]

    static func name(_ id: String) -> String {
        id == "auto" ? "Auto (25 languages, switch any time)" : (Locale.current.localizedString(forIdentifier: id) ?? id)
    }
}

extension Notification.Name { static let spitballLanguageChanged = Notification.Name("spitballLanguageChanged") }
