import XCTest
@testable import VanmoCore

final class AppLanguageTests: XCTestCase {
    func testDefaultPreferenceIsChinese() {
        XCTAssertEqual(AppLanguagePreference.defaultPreference, .chinese)
        XCTAssertEqual(AppLanguagePreference.storageKey, "app.interfaceLanguage")
    }

    func testForcedChineseIgnoresSystemEnglish() {
        XCTAssertEqual(
            AppLanguage.resolve(preference: .chinese, preferredLanguages: ["en-US"]),
            AppLanguage.chineseCode
        )
    }

    func testForcedEnglishIgnoresSystemChinese() {
        XCTAssertEqual(
            AppLanguage.resolve(preference: .english, preferredLanguages: ["zh-Hans-CN"]),
            AppLanguage.englishCode
        )
    }

    func testSystemChineseResolvesToChinese() {
        XCTAssertEqual(
            AppLanguage.resolve(preference: .system, preferredLanguages: ["zh-Hans-CN"]),
            AppLanguage.chineseCode
        )
        XCTAssertEqual(
            AppLanguage.resolve(preference: .system, preferredLanguages: ["zh-Hant-TW"]),
            AppLanguage.chineseCode
        )
    }

    func testSystemEnglishResolvesToEnglish() {
        XCTAssertEqual(
            AppLanguage.resolve(preference: .system, preferredLanguages: ["en-US"]),
            AppLanguage.englishCode
        )
    }

    func testSystemOtherResolvesToEnglish() {
        XCTAssertEqual(
            AppLanguage.resolve(preference: .system, preferredLanguages: ["ja-JP"]),
            AppLanguage.englishCode
        )
        XCTAssertEqual(
            AppLanguage.resolve(preference: .system, preferredLanguages: ["fr-FR"]),
            AppLanguage.englishCode
        )
        XCTAssertEqual(
            AppLanguage.resolve(preference: .system, preferredLanguages: []),
            AppLanguage.englishCode
        )
    }

    func testShortDurationChinese() {
        XCTAssertEqual(LocalizedFormat.shortDuration(45 * 60, languageCode: "zh-Hans"), "45分钟")
        XCTAssertEqual(LocalizedFormat.shortDuration(90 * 60, languageCode: "zh-Hans"), "1小时30分钟")
        XCTAssertEqual(LocalizedFormat.shortDuration(120 * 60, languageCode: "zh-Hans"), "2小时")
    }

    func testShortDurationEnglish() {
        XCTAssertEqual(LocalizedFormat.shortDuration(45 * 60, languageCode: "en"), "45m")
        XCTAssertEqual(LocalizedFormat.shortDuration(90 * 60, languageCode: "en"), "1h 30m")
        XCTAssertEqual(LocalizedFormat.shortDuration(120 * 60, languageCode: "en"), "2h")
    }

    func testSeasonAndEpisodeLabels() {
        XCTAssertEqual(LocalizedFormat.seasonLabel(1, languageCode: "zh-Hans"), "第1季")
        XCTAssertEqual(LocalizedFormat.seasonLabel(1, languageCode: "en"), "Season 1")
        XCTAssertEqual(LocalizedFormat.episodeLabel(12, languageCode: "zh-Hans"), "第12集")
        XCTAssertEqual(LocalizedFormat.episodeLabel(12, languageCode: "en"), "Episode 12")
        XCTAssertEqual(
            LocalizedFormat.episodeCode(season: 1, episode: 12, languageCode: "zh-Hans"),
            "第1季第12集"
        )
        XCTAssertEqual(
            LocalizedFormat.episodeCode(season: 1, episode: 12, languageCode: "en"),
            "S01E12"
        )
        XCTAssertEqual(
            LocalizedFormat.showEpisodeTitle(showTitle: "Show", season: 1, episode: 2, languageCode: "en"),
            "Show S01E02"
        )
    }

    func testEnglishTableCoversLanguageAndTabs() {
        XCTAssertEqual(L10nTable.english["设置"], "Settings")
        XCTAssertEqual(L10nTable.english["首页"], "Home")
        XCTAssertEqual(L10nTable.english["播放"], "Play")
        XCTAssertEqual(L10nTable.english["语言将在下次启动后生效"], "The language will apply after you restart the app")
    }
}
