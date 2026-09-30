import Foundation

/// Reads the app's source string catalog directly.
///
/// `String(localized:locale:)` cannot be used to compare two languages from a test:
/// the app replaces `Bundle.main`'s class at launch with a runtime bundle that serves
/// the user's chosen language and ignores the requested locale, so every locale
/// resolves to the process language. The catalog is the source of truth for
/// "English must not leak Chinese", so tests read it here instead.
enum LocalizationCatalog {
    static func value(for key: String, locale: String) -> String? {
        table[key]?[locale]
    }

    private static let table: [String: [String: String]] = {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogURL = projectRoot.appendingPathComponent("Doer/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: catalogURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = root["strings"] as? [String: Any] else {
            return [:]
        }

        var result: [String: [String: String]] = [:]
        for (key, entry) in strings {
            guard let entry = entry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else { continue }
            var perLocale: [String: String] = [:]
            for (locale, localization) in localizations {
                guard let localization = localization as? [String: Any],
                      let unit = localization["stringUnit"] as? [String: Any],
                      let value = unit["value"] as? String else { continue }
                perLocale[locale] = value
            }
            result[key] = perLocale
        }
        return result
    }()
}
