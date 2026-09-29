import XCTest
@testable import Doer

@MainActor
final class ForumBottomBarTabTests: XCTestCase {
    func testChatIsAConfigurableDynamicTab() {
        XCTAssertEqual(AppSettings.ForumDynamicTabItem.chat.rawValue, "chat")
        XCTAssertEqual(AppSettings.ForumDynamicTabItem.storedValue("chat"), .chat)
        XCTAssertTrue(AppSettings.ForumDynamicTabItem.allCases.contains(.chat))
    }

    func testDefaultVisibleTabsAreHomeAndMeOnly() {
        // Dexo-style default: the bar ships with 首页 + 我的; every dynamic
        // entry point is opt-in from 设置 → 底栏布局.
        XCTAssertTrue(AppSettings.defaultForumDynamicTabItems.isEmpty)
        XCTAssertTrue(
            AppSettings.defaultForumDynamicTabItems
                .prefix(AppSettings.maximumVisibleForumDynamicTabItems)
                .isEmpty
        )
    }

    func testSanitizerKeepsAnEmptyConfiguredList() {
        // An empty list is a legal configuration (home + me only) and must
        // survive sanitization instead of falling back to a non-empty default.
        XCTAssertTrue(AppSettings.sanitizedForumDynamicTabItems([]).isEmpty)
        XCTAssertTrue(AppSettings.sanitizedForumTabItemIDs([]).isEmpty)
    }

    func testSanitizedTabIDsKeepChatAndDropUnknown() {
        XCTAssertEqual(
            AppSettings.sanitizedForumTabItemIDs(["history", "chat", "not-a-tab", "chat"]),
            ["history", "chat"]
        )
        XCTAssertEqual(
            AppSettings.sanitizedForumDynamicTabItems([.chat, .bookmarks, .chat]),
            [.chat, .bookmarks]
        )
    }

    func testChatCanBeRemovedFromAConfiguredList() {
        let withoutChat = AppSettings.sanitizedForumDynamicTabItems(
            [.history, .notifications, .bookmarks]
        )
        XCTAssertFalse(withoutChat.contains(.chat))
        XCTAssertEqual(withoutChat, [.history, .notifications, .bookmarks])
    }

    func testDynamicTabSubtitlesLocalizeWithoutHardcodedChinese() {
        let keys: [(AppSettings.ForumDynamicTabItem, String)] = [
            (.history, "settings.bottom_bar.history.subtitle"),
            (.search, "settings.bottom_bar.search.subtitle"),
            (.notifications, "settings.bottom_bar.notifications.subtitle"),
            (.messages, "settings.bottom_bar.messages.subtitle"),
            (.bookmarks, "settings.bottom_bar.bookmarks.subtitle"),
            (.chat, "settings.bottom_bar.chat.subtitle"),
        ]
        XCTAssertEqual(keys.map(\.0), AppSettings.ForumDynamicTabItem.allCases)

        for (item, key) in keys {
            let english = String(localized: String.LocalizationValue(key), locale: Locale(identifier: "en"))
            let chinese = String(localized: String.LocalizationValue(key), locale: Locale(identifier: "zh-Hans"))
            XCTAssertFalse(english.isEmpty, "\(item) English subtitle")
            XCTAssertFalse(chinese.isEmpty, "\(item) Chinese subtitle")
            XCTAssertNotEqual(english, chinese, "\(item) en/zh-Hans should differ")
            XCTAssertFalse(
                english.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF },
                "\(item) English subtitle leaked CJK: \(english)"
            )
            XCTAssertTrue(
                chinese.unicodeScalars.contains { $0.value >= 0x4E00 && $0.value <= 0x9FFF },
                "\(item) Chinese subtitle missing CJK: \(chinese)"
            )
            XCTAssertFalse(item.subtitle.isEmpty, "\(item) runtime subtitle")
        }
    }
}
