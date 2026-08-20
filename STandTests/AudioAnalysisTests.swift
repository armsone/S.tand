import AVFoundation
import SwiftUI
import UIKit
import XCTest
@testable import STand

final class AudioAnalysisTests: XCTestCase {
    func testSleepSessionInsightBuildsActivityDistributionAndBusiestRange() throws {
        let start = Date(timeIntervalSinceReferenceDate: 100_000)
        let end = start.addingTimeInterval(12 * 60 * 60)
        let clips = [
            RecordingClip(
                url: URL(fileURLWithPath: "/tmp/first.m4a"),
                createdAt: start.addingTimeInterval(60 * 60 + 30),
                duration: 12
            ),
            RecordingClip(
                url: URL(fileURLWithPath: "/tmp/second.m4a"),
                createdAt: start.addingTimeInterval(60 * 60 + 90),
                duration: 18
            )
        ]
        let movement = SleepStartleEvent(
            id: UUID(),
            startedAt: start.addingTimeInterval(8 * 60 * 60),
            endedAt: start.addingTimeInterval(8 * 60 * 60 + 5)
        )
        let session = RecordingSessionGroup(
            id: "insight",
            startedAt: start,
            endedAt: end,
            clips: clips,
            startleEvents: [movement],
            isInferred: false
        )

        let insight = session.insight

        XCTAssertEqual(insight.sessionDuration, 12 * 60 * 60)
        XCTAssertEqual(insight.soundCount, 2)
        XCTAssertEqual(insight.soundDuration, 30)
        XCTAssertEqual(insight.movementCount, 1)
        XCTAssertEqual(insight.activityBuckets.count, SleepSessionInsight.bucketCount)
        XCTAssertEqual(insight.activityBuckets[1], 2)
        XCTAssertEqual(insight.activityBuckets[8], 1)
        XCTAssertEqual(insight.busiestBucketIndex, 1)
        XCTAssertEqual(insight.eventsPerHour, 0.25, accuracy: 0.000_001)
        let range = try XCTUnwrap(insight.busiestRange(sessionStart: start))
        XCTAssertEqual(range.lowerBound, start.addingTimeInterval(60 * 60))
        XCTAssertEqual(range.upperBound, start.addingTimeInterval(2 * 60 * 60))
    }

    func testFirstLaunchPermissionPromptShowsFirstThenEveryThreeToSevenLaunches() {
        let first = FirstLaunchPermissionPromptSchedule(
            hasShownPrompt: false,
            launchesUntilNextPrompt: nil
        )
        XCTAssertEqual(
            FirstLaunchPermissionPromptPolicy.evaluateLaunch(
                allPermissionsGranted: false,
                schedule: first
            ).0,
            .show
        )

        var schedule = FirstLaunchPermissionPromptPolicy.afterPrompt(interval: 5)
        for expectedRemaining in [4, 3, 2, 1] {
            let result = FirstLaunchPermissionPromptPolicy.evaluateLaunch(
                allPermissionsGranted: false,
                schedule: schedule
            )
            XCTAssertEqual(result.0, .skip)
            XCTAssertEqual(result.1.launchesUntilNextPrompt, expectedRemaining)
            schedule = result.1
        }
        XCTAssertEqual(
            FirstLaunchPermissionPromptPolicy.evaluateLaunch(
                allPermissionsGranted: false,
                schedule: schedule
            ).0,
            .show
        )

        XCTAssertEqual(
            FirstLaunchPermissionPromptPolicy.afterPrompt(interval: 1)
                .launchesUntilNextPrompt,
            3
        )
        XCTAssertEqual(
            FirstLaunchPermissionPromptPolicy.afterPrompt(interval: 9)
                .launchesUntilNextPrompt,
            7
        )
    }

    func testFirstLaunchPermissionPromptClearsScheduleWhenEverythingIsGranted() {
        let result = FirstLaunchPermissionPromptPolicy.evaluateLaunch(
            allPermissionsGranted: true,
            schedule: FirstLaunchPermissionPromptSchedule(
                hasShownPrompt: true,
                launchesUntilNextPrompt: 2
            )
        )

        XCTAssertEqual(result.0, .reset)
        XCTAssertEqual(
            result.1,
            FirstLaunchPermissionPromptSchedule(
                hasShownPrompt: false,
                launchesUntilNextPrompt: nil
            )
        )
    }

    func testBurnInProtectionMovesWithinAQuietFivePointRange() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let offsets = (0..<8).map {
            BurnInProtection.offset(at: start.addingTimeInterval(Double($0) * 60))
        }

        XCTAssertGreaterThan(Set(offsets.map { "\($0.width),\($0.height)" }).count, 1)
        XCTAssertTrue(offsets.allSatisfy { abs($0.width) <= 5 && abs($0.height) <= 3 })
    }

    func testExternalMusicTitleTapPlaysUnlessTheSelectedServiceIsPlaying() {
        for state in [
            ExternalMusicPlaybackState.idle,
            .loading,
            .paused,
            .unavailable
        ] {
            XCTAssertEqual(
                ExternalMusicTitleTapPolicy.action(isActive: true, playbackState: state),
                .play
            )
        }
        XCTAssertEqual(
            ExternalMusicTitleTapPolicy.action(isActive: false, playbackState: .playing),
            .play
        )
        XCTAssertEqual(
            ExternalMusicTitleTapPolicy.action(isActive: true, playbackState: .playing),
            .next
        )
    }

    func testInternetRadioTitleTapPlaysTappedChannelOrAdvancesWhilePlaying() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let ordered = [first, second, third]

        XCTAssertEqual(
            InternetRadioTitleTapPolicy.targetChannelID(
                tappedChannelID: second,
                activeChannelID: nil,
                playbackState: .idle,
                orderedChannelIDs: ordered
            ),
            second
        )
        XCTAssertEqual(
            InternetRadioTitleTapPolicy.targetChannelID(
                tappedChannelID: first,
                activeChannelID: second,
                playbackState: .playing,
                orderedChannelIDs: ordered
            ),
            third
        )
        XCTAssertEqual(
            InternetRadioTitleTapPolicy.targetChannelID(
                tappedChannelID: second,
                activeChannelID: third,
                playbackState: .playing,
                orderedChannelIDs: ordered
            ),
            first
        )
    }

    func testMacPresentationScaleProducesAOneAndAHalfTimesLogicalCanvas() {
        XCTAssertEqual(StandPresentationMetrics.macHomeScale, 1.5)
        XCTAssertEqual(
            StandPresentationMetrics.contentSize(
                for: CGSize(width: 1_500, height: 900),
                scale: StandPresentationMetrics.macHomeScale
            ),
            CGSize(width: 1_000, height: 600)
        )
    }

    func testClockCanBeMagnifiedUpToThreeHundredPercent() {
        XCTAssertEqual(AppSettings.minimumClockScale, 0.7)
        XCTAssertEqual(AppSettings.maximumClockScale, 3.0)
    }

    func testRecordingSwipeDeletesOnAFullDragOrQuickLeftFlickOnly() {
        XCTAssertTrue(
            RecordingSwipeDeletePolicy.isDeleteGesture(
                translation: CGSize(width: -60, height: 4),
                predictedEndTranslation: CGSize(width: -72, height: 5)
            )
        )
        XCTAssertTrue(
            RecordingSwipeDeletePolicy.isDeleteGesture(
                translation: CGSize(width: -34, height: 3),
                predictedEndTranslation: CGSize(width: -90, height: 4)
            )
        )
        XCTAssertFalse(
            RecordingSwipeDeletePolicy.isDeleteGesture(
                translation: CGSize(width: -48, height: 3),
                predictedEndTranslation: CGSize(width: -52, height: 4)
            )
        )
        XCTAssertFalse(
            RecordingSwipeDeletePolicy.isDeleteGesture(
                translation: CGSize(width: -80, height: 95),
                predictedEndTranslation: CGSize(width: -110, height: 120)
            )
        )
    }

    func testFlipClockSecondsAreTwiceAsVisible() {
        XCTAssertEqual(FlipClockSecondStyle.opacity(isDimmed: false), 0.40)
        XCTAssertEqual(FlipClockSecondStyle.opacity(isDimmed: true), 0.16)
    }

    func testBundledClockFontsAreRegistered() {
        for choice in ClockFontChoice.allCases {
            guard let postScriptName = choice.postScriptName else { continue }

            XCTAssertNotNil(
                UIFont(name: postScriptName, size: 24),
                "\(choice.displayName) 폰트가 앱에 등록되지 않았습니다: \(postScriptName)"
            )
        }
    }

    func testBundledClockFontLicensesAreIncluded() {
        for choice in ClockFontChoice.allCases {
            guard let filename = choice.licenseFilename else { continue }

            XCTAssertNotNil(
                Bundle.main.url(forResource: filename, withExtension: "txt"),
                "\(choice.displayName) 라이선스 파일이 앱에 포함되지 않았습니다: \(filename).txt"
            )
        }
    }

    func testRemovedSampleRecordingsAreNotBundled() {
        for name in ["sample-snore-5s", "sample-snore-10s", "sample-snore-15s"] {
            XCTAssertNil(
                Bundle.main.url(forResource: name, withExtension: "m4a"),
                "제거한 테스트 코골이 파일이 앱 번들에 다시 포함되었습니다: \(name).m4a"
            )
        }
    }

    func testLegacySettingsWithNoOrientationStillDecodes() throws {
        let legacyJSON = """
        {
          "lampIntensity": 0.72,
          "holdDuration": 60,
          "fadeDuration": 30,
          "soundThresholdDB": -36,
          "recordingEnabled": true
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)

        XCTAssertTrue(settings.torchEnabled)
        XCTAssertEqual(settings.torchIntensity, 0.25)
        XCTAssertFalse(settings.wakeOnSleepSound)
        XCTAssertEqual(settings.silhouetteIntensity, 0.05)
        XCTAssertEqual(settings.clockScale, AppSettings.defaultClockScale)
        XCTAssertEqual(settings.clockFont, .tenada)
        XCTAssertTrue(settings.preventAutoDimmingWhenScreenBright)
        XCTAssertFalse(settings.automaticDimmingEnabled)
        XCTAssertTrue(settings.multiStimulusWakeEnabled)
        XCTAssertTrue(settings.soundSensingEnabled)
        XCTAssertTrue(settings.weatherLocationEnabled)
        XCTAssertEqual(settings.portraitLayout, .portrait)
        XCTAssertEqual(settings.landscapeLayout, .landscape)
        XCTAssertEqual(settings.brightnessModeThreshold, 0.3)
        XCTAssertEqual(settings.modePreference, .automatic)
        XCTAssertFalse(settings.cameraAmbientSensingEnabled)
        XCTAssertNil(settings.internetRadio)
    }

    func testInternetRadioConfigurationAcceptsOnlySafeHTTPSStreams() throws {
        let configuration = try InternetRadioConfiguration(
            displayName: "  나의 라디오  ",
            urlString: "  https://radio.example.com/live.mp3  \n"
        )

        XCTAssertEqual(configuration.displayName, "나의 라디오")
        XCTAssertEqual(configuration.urlString, "https://radio.example.com/live.mp3")
        XCTAssertEqual(configuration.streamURL.host, "radio.example.com")

        let unnamed = try InternetRadioConfiguration(
            displayName: "  ",
            urlString: "https://radio.example.com/stream"
        )
        XCTAssertEqual(unnamed.displayName, InternetRadioConfiguration.defaultDisplayName)

        XCTAssertThrowsError(try InternetRadioConfiguration(displayName: "", urlString: ""))
        XCTAssertThrowsError(
            try InternetRadioConfiguration(
                displayName: "테스트",
                urlString: "http://radio.example.com/stream"
            )
        )
        XCTAssertThrowsError(
            try InternetRadioConfiguration(displayName: "테스트", urlString: "file:///tmp/radio")
        )
        XCTAssertThrowsError(
            try InternetRadioConfiguration(displayName: "테스트", urlString: "https:///stream")
        )
        XCTAssertThrowsError(
            try InternetRadioConfiguration(
                displayName: "테스트",
                urlString: "https://user:password@radio.example.com/stream"
            )
        )
    }

    func testInternetRadioBrowserAddressAcceptsOnlyCredentialFreeHTTPS() throws {
        let explicit = try InternetRadioBrowserAddress.secureURL(
            from: "  https://radio.example.com/live?token=public  "
        )
        let schemeLess = try InternetRadioBrowserAddress.secureURL(
            from: "radio.example.com/live.mp3"
        )

        XCTAssertEqual(
            explicit.absoluteString,
            "https://radio.example.com/live?token=public"
        )
        XCTAssertEqual(
            schemeLess.absoluteString,
            "https://radio.example.com/live.mp3"
        )
        XCTAssertTrue(InternetRadioBrowserAddress.isSecureWebURL(explicit))

        let searchURL = try InternetRadioBrowserAddress.browsingURL(from: "한국 라디오")
        XCTAssertEqual(searchURL.host, "www.google.com")
        XCTAssertEqual(searchURL.path, "/search")
        XCTAssertEqual(
            URLComponents(url: searchURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value,
            "한국 라디오"
        )

        for rejectedAddress in [
            "",
            "http://radio.example.com/live",
            "file:///tmp/radio.mp3",
            "https:///live.mp3",
            "https://user:password@radio.example.com/live.mp3"
        ] {
            XCTAssertThrowsError(
                try InternetRadioBrowserAddress.secureURL(from: rejectedAddress),
                "허용되지 않은 주소가 브라우저 검증을 통과했습니다: \(rejectedAddress)"
            )
        }

        let oversizedAddress = String(
            repeating: "a",
            count: InternetRadioConfiguration.maximumAddressLength + 1
        )
        XCTAssertThrowsError(
            try InternetRadioBrowserAddress.secureURL(from: oversizedAddress)
        )
    }

    func testInternetRadioBrowserUsesRequestedHomepageAndFavorites() {
        XCTAssertEqual(
            InternetRadioBrowserAddress.defaultHomepage.absoluteString,
            "https://www.google.com/"
        )
        XCTAssertEqual(
            InternetRadioBrowserFavorite.defaults.map(\.title),
            ["Google", "한국 라디오", "FMSTREAM", "Radio Browser"]
        )
        XCTAssertEqual(
            InternetRadioBrowserFavorite.defaults.map { $0.url.absoluteString },
            [
                "https://www.google.com/",
                "https://radio.bsod.kr/",
                "https://fmstream.org/",
                "https://www.radio-browser.info/"
            ]
        )
        XCTAssertTrue(InternetRadioBrowserFavorite.defaults[0].isHomepage)
        XCTAssertTrue(
            InternetRadioBrowserFavorite.defaults.dropFirst().allSatisfy {
                !$0.isHomepage
            }
        )
    }

    func testInternetRadioSettingsRoundTripWithoutBundledPreset() throws {
        XCTAssertNil(AppSettings.recommended.internetRadio)
        XCTAssertTrue(AppSettings.recommended.internetRadioChannels.isEmpty)

        let configuration = try InternetRadioConfiguration(
            displayName: "개인 방송",
            urlString: "https://stream.example.org/live.m3u8"
        )
        let original = AppSettings(internetRadio: configuration)
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded.internetRadio, configuration)
        XCTAssertEqual(decoded.internetRadioChannels, [configuration])
        XCTAssertEqual(decoded.selectedInternetRadioID, configuration.id)
    }

    func testLegacySingleInternetRadioMigratesToSelectedChannel() throws {
        let legacyJSON = """
        {
          "internetRadio": {
            "displayName": "예전 방송",
            "urlString": "https://legacy.example.com/live"
          }
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        let migrated = try XCTUnwrap(settings.internetRadio)

        XCTAssertEqual(settings.internetRadioChannels, [migrated])
        XCTAssertEqual(settings.selectedInternetRadioID, migrated.id)
        XCTAssertEqual(migrated.displayName, "예전 방송")
        XCTAssertEqual(migrated.urlString, "https://legacy.example.com/live")
    }

    @MainActor
    func testSettingsStorePersistsLegacyRadioMigrationWithStableID() throws {
        let suiteName = "STandTests.radio-migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacyJSON = """
        {
          "internetRadio": {
            "displayName": "예전 방송",
            "urlString": "https://legacy.example.com/live"
          }
        }
        """.data(using: .utf8)!
        defaults.set(legacyJSON, forKey: "appSettings")
        defaults.set(true, forKey: SettingsMigration.torchEnabledByDefaultKey)
        defaults.set(true, forKey: SettingsMigration.fiveSecondHoldDurationKey)

        let firstLoad = SettingsStore(defaults: defaults)
        let migratedID = try XCTUnwrap(firstLoad.value.selectedInternetRadioID)

        XCTAssertTrue(defaults.bool(forKey: SettingsMigration.internetRadioChannelsKey))
        let persistedData = try XCTUnwrap(defaults.data(forKey: "appSettings"))
        let persisted = try JSONDecoder().decode(AppSettings.self, from: persistedData)
        XCTAssertEqual(persisted.selectedInternetRadioID, migratedID)
        XCTAssertEqual(persisted.internetRadioChannels.count, 1)

        let secondLoad = SettingsStore(defaults: defaults)
        XCTAssertEqual(secondLoad.value.selectedInternetRadioID, migratedID)
    }

    func testInternetRadioChannelsRoundTripAndRepairMissingSelection() throws {
        let first = try InternetRadioConfiguration(
            displayName: "첫 방송",
            urlString: "https://one.example.com/live"
        )
        let second = try InternetRadioConfiguration(
            displayName: "둘째 방송",
            urlString: "https://two.example.com/live"
        )
        let original = AppSettings(
            internetRadioChannels: [first, second],
            selectedInternetRadioID: second.id
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)

        XCTAssertEqual(decoded.internetRadioChannels, [first, second])
        XCTAssertEqual(decoded.selectedInternetRadioID, second.id)
        XCTAssertEqual(decoded.internetRadio, second)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["selectedInternetRadioID"] = UUID().uuidString
        let repaired = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(repaired.selectedInternetRadioID, first.id)
        XCTAssertEqual(repaired.internetRadio, first)
    }

    func testInternetRadioChannelMutationsPreserveStableSelection() throws {
        let first = try InternetRadioConfiguration(
            displayName: "첫 방송",
            urlString: "https://one.example.com/live"
        )
        let second = try InternetRadioConfiguration(
            displayName: "둘째 방송",
            urlString: "https://two.example.com/live"
        )
        var settings = AppSettings(
            internetRadioChannels: [first, second],
            selectedInternetRadioID: first.id
        )

        let renamedSecond = try second.updated(
            displayName: "수정한 둘째 방송",
            urlString: "https://two.example.com/new-live"
        )
        XCTAssertTrue(settings.updateInternetRadioChannel(renamedSecond))
        XCTAssertEqual(settings.internetRadio, first)
        XCTAssertEqual(settings.internetRadioChannels[1], renamedSecond)

        XCTAssertTrue(settings.selectInternetRadioChannel(id: second.id))
        XCTAssertEqual(settings.internetRadio, renamedSecond)
        XCTAssertEqual(settings.removeInternetRadioChannel(id: second.id), renamedSecond)
        XCTAssertEqual(settings.internetRadio, first)

        settings.addInternetRadioChannel(renamedSecond, select: false)
        XCTAssertEqual(settings.internetRadio, first)
        XCTAssertTrue(settings.moveInternetRadioChannel(id: renamedSecond.id, to: 0))
        XCTAssertEqual(settings.internetRadioChannels, [renamedSecond, first])
        XCTAssertEqual(settings.internetRadio, first)
        XCTAssertFalse(settings.selectInternetRadioChannel(id: UUID()))
    }

    func testInternetRadioChannelsAreLimitedToFour() throws {
        let first = try InternetRadioConfiguration(
            displayName: "첫 채널",
            urlString: "https://radio.example.com/first"
        )
        let second = try InternetRadioConfiguration(
            displayName: "둘째 채널",
            urlString: "https://radio.example.com/second"
        )
        let third = try InternetRadioConfiguration(
            displayName: "셋째 채널",
            urlString: "https://radio.example.com/third"
        )
        let fourth = try InternetRadioConfiguration(
            displayName: "넷째 채널",
            urlString: "https://radio.example.com/fourth"
        )
        let overflow = try InternetRadioConfiguration(
            displayName: "초과 채널",
            urlString: "https://radio.example.com/overflow"
        )
        var settings = AppSettings(
            internetRadioChannels: [first, second, third, fourth, overflow],
            selectedInternetRadioID: fourth.id,
            secondaryInternetRadioID: first.id
        )

        XCTAssertEqual(
            settings.internetRadioChannels.map(\.id),
            [first.id, second.id, third.id, fourth.id]
        )
        XCTAssertEqual(settings.homeInternetRadios.map(\.id), [first.id, second.id])
        XCTAssertNil(settings.internetRadioChannel(id: overflow.id))

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )
        XCTAssertEqual(decoded.homeInternetRadios.map(\.id), [first.id, second.id])

        settings.addInternetRadioChannel(overflow)
        XCTAssertEqual(
            settings.internetRadioChannels.map(\.id),
            [first.id, second.id, third.id, fourth.id]
        )

        XCTAssertEqual(settings.removeInternetRadioChannel(id: first.id), first)
        settings.addInternetRadioChannel(overflow, select: false)
        XCTAssertEqual(
            settings.internetRadioChannels.map(\.id),
            [second.id, third.id, fourth.id, overflow.id]
        )
    }

    func testHomeMusicChannelsCanAssignAndSwapRadioAndAppleSources() throws {
        let first = try InternetRadioConfiguration(
            displayName: "첫 채널",
            urlString: "https://radio.example.com/first"
        )
        let second = try InternetRadioConfiguration(
            displayName: "둘째 채널",
            urlString: "https://radio.example.com/second"
        )
        var settings = AppSettings(internetRadioChannels: [first, second])

        XCTAssertEqual(
            settings.homeMusicChannels,
            [
                .appleMusic,
                .appleClassical,
                .internetRadio(first.id, slot: 0),
                .internetRadio(second.id, slot: 1),
                .emptyInternetRadio(slot: 2),
                .emptyInternetRadio(slot: 3)
            ]
        )
        XCTAssertTrue(settings.moveHomeMusicChannel(id: "appleClassical", to: 0))
        XCTAssertEqual(settings.homeMusicChannels.first, .appleClassical)
        XCTAssertEqual(settings.homeMusicChannels.dropFirst().first, .appleMusic)

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(settings)
        )
        XCTAssertEqual(decoded.homeMusicChannels, settings.homeMusicChannels)
        XCTAssertEqual(decoded.homeMusicChannels.count, 6)
    }

    func testAddingAndRemovingRadioFillsStableHomePlaceholder() throws {
        let channel = try InternetRadioConfiguration(
            displayName: "새 채널",
            urlString: "https://radio.example.com/new"
        )
        var settings = AppSettings()

        XCTAssertEqual(
            settings.homeMusicChannels,
            [
                .appleMusic,
                .appleClassical,
                .emptyInternetRadio(slot: 0),
                .emptyInternetRadio(slot: 1),
                .emptyInternetRadio(slot: 2),
                .emptyInternetRadio(slot: 3)
            ]
        )

        settings.addInternetRadioChannel(channel)
        XCTAssertEqual(settings.homeMusicChannels[2], .internetRadio(channel.id, slot: 0))

        XCTAssertEqual(settings.removeInternetRadioChannel(id: channel.id), channel)
        XCTAssertEqual(settings.homeMusicChannels[2], .emptyInternetRadio(slot: 0))
    }

    func testInternetRadioReconnectUsesCappedBackoff() {
        XCTAssertEqual(InternetRadioReconnectPolicy.delay(forAttempt: 1), 2)
        XCTAssertEqual(InternetRadioReconnectPolicy.delay(forAttempt: 2), 4)
        XCTAssertEqual(InternetRadioReconnectPolicy.delay(forAttempt: 3), 8)
        XCTAssertEqual(InternetRadioReconnectPolicy.delay(forAttempt: 4), 15)
        XCTAssertEqual(InternetRadioReconnectPolicy.delay(forAttempt: 5), 30)
        XCTAssertEqual(InternetRadioReconnectPolicy.delay(forAttempt: 20), 30)
        XCTAssertTrue(InternetRadioReconnectPolicy.shouldRetry(attempt: 5))
        XCTAssertFalse(InternetRadioReconnectPolicy.shouldRetry(attempt: 6))
    }

    func testHorizontalDragCoversFullSystemVolumeRangeAndClamps() {
        XCTAssertEqual(VolumeAdjustmentPolicy.horizontalDragTravelRatio, 0.5)
        XCTAssertEqual(
            VolumeAdjustmentPolicy.level(
                startingAt: 0.5,
                horizontalTranslation: 100,
                viewportWidth: 400
            ),
            1
        )
        XCTAssertEqual(
            VolumeAdjustmentPolicy.level(
                startingAt: 0.5,
                horizontalTranslation: -100,
                viewportWidth: 400
            ),
            0
        )
        XCTAssertEqual(
            VolumeAdjustmentPolicy.level(
                startingAt: 0.8,
                horizontalTranslation: 1_000,
                viewportWidth: 400
            ),
            1
        )
        XCTAssertEqual(
            VolumeAdjustmentPolicy.level(
                startingAt: 0.2,
                horizontalTranslation: -1_000,
                viewportWidth: 400
            ),
            0
        )
    }

    func testMusicChannelStripCentersWhenItFitsAndClampsDragWhenItOverflows() {
        let cardWidth = MusicChannelStripLayoutPolicy.cardWidth(viewportWidth: 1_200)
        XCTAssertEqual(cardWidth, 168)
        XCTAssertEqual(
            MusicChannelStripLayoutPolicy.cardWidth(
                viewportWidth: 1_200,
                isPhoneLandscape: true
            ),
            134.4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            MusicChannelStripLayoutPolicy.maximumScroll(
                viewportWidth: 1_200,
                cardCount: 6,
                cardWidth: cardWidth
            ),
            0
        )

        let maximumScroll = MusicChannelStripLayoutPolicy.maximumScroll(
            viewportWidth: 800,
            cardCount: 6,
            cardWidth: 168
        )
        XCTAssertEqual(maximumScroll, 272)
        XCTAssertEqual(
            MusicChannelStripLayoutPolicy.clampedOffset(-120, maximumScroll: maximumScroll),
            -120
        )
        XCTAssertEqual(
            MusicChannelStripLayoutPolicy.clampedOffset(-1_000, maximumScroll: maximumScroll),
            -272
        )
        XCTAssertEqual(
            MusicChannelStripLayoutPolicy.clampedOffset(80, maximumScroll: maximumScroll),
            0
        )
        XCTAssertEqual(
            MusicChannelStripLayoutPolicy.leadingAlignedOffset(
                cardIndex: 0,
                cardWidth: 168,
                maximumScroll: 600
            ),
            0
        )
        XCTAssertEqual(
            MusicChannelStripLayoutPolicy.leadingAlignedOffset(
                cardIndex: 2,
                cardWidth: 168,
                maximumScroll: 600
            ),
            -352
        )
        XCTAssertEqual(
            MusicChannelStripLayoutPolicy.leadingAlignedOffset(
                cardIndex: 5,
                cardWidth: 168,
                maximumScroll: 600
            ),
            -600
        )
    }

    func testPhoneLandscapeSideControlsOnlyEnableForPhoneLandscapeOutsideCatalyst() {
        XCTAssertEqual(PhoneLandscapeSideControlsPolicy.controlWidth, 57.12, accuracy: 0.001)
        XCTAssertTrue(
            PhoneLandscapeSideControlsPolicy.isEnabled(
                isPortrait: false,
                isPhoneIdiom: true,
                isMacCatalyst: false
            )
        )
        XCTAssertFalse(
            PhoneLandscapeSideControlsPolicy.isEnabled(
                isPortrait: true,
                isPhoneIdiom: true,
                isMacCatalyst: false
            )
        )
        XCTAssertFalse(
            PhoneLandscapeSideControlsPolicy.isEnabled(
                isPortrait: false,
                isPhoneIdiom: false,
                isMacCatalyst: false
            )
        )
        XCTAssertFalse(
            PhoneLandscapeSideControlsPolicy.isEnabled(
                isPortrait: false,
                isPhoneIdiom: true,
                isMacCatalyst: true
            )
        )
    }

    func testAudioInterruptionOnlyResumesWhenSystemAllowsIt() {
        let resumable = Notification(
            name: AVAudioSession.interruptionNotification,
            userInfo: [
                AVAudioSessionInterruptionOptionKey:
                    AVAudioSession.InterruptionOptions.shouldResume.rawValue
            ]
        )
        let notResumable = Notification(name: AVAudioSession.interruptionNotification)

        XCTAssertTrue(AudioInterruptionResumePolicy.shouldResume(resumable))
        XCTAssertFalse(AudioInterruptionResumePolicy.shouldResume(notResumable))
    }

    func testRadioPanelsMergeAtFortyPercentOverlapAndPersistGrouping() throws {
        let base = CGRect(x: 0, y: 0, width: 100, height: 60)
        XCTAssertLessThan(
            PanelEditingPolicy.overlapFraction(
                base,
                CGRect(x: 61, y: 0, width: 100, height: 60)
            ),
            PanelEditingPolicy.radioMergeOverlapThreshold
        )
        XCTAssertGreaterThanOrEqual(
            PanelEditingPolicy.overlapFraction(
                base,
                CGRect(x: 60, y: 0, width: 100, height: 60)
            ),
            PanelEditingPolicy.radioMergeOverlapThreshold
        )

        var layout = StandScreenLayout.portrait
        layout.secondaryRadio = layout.radio
        layout.radiosGrouped = true
        let decoded = try JSONDecoder().decode(
            StandScreenLayout.self,
            from: JSONEncoder().encode(layout)
        )
        XCTAssertEqual(decoded.secondaryRadio, layout.secondaryRadio)
        XCTAssertTrue(decoded.radiosGrouped)
    }

    func testRadioPlaybackMutationPolicyStopsOnlyForActiveChannelChanges() throws {
        let active = try InternetRadioConfiguration(
            displayName: "재생 중",
            urlString: "https://active.example.com/live"
        )
        let inactive = try InternetRadioConfiguration(
            displayName: "대기 중",
            urlString: "https://inactive.example.com/live"
        )
        let renamedActive = try active.updated(
            displayName: "이름만 수정",
            urlString: active.urlString
        )
        let changedActive = try active.updated(
            displayName: "주소 수정",
            urlString: "https://active.example.com/new-live"
        )
        let changedInactive = try inactive.updated(
            displayName: "대기 주소 수정",
            urlString: "https://inactive.example.com/new-live"
        )

        XCTAssertFalse(
            InternetRadioPlaybackMutationPolicy.shouldStopForSelection(
                activeChannelID: active.id,
                selectedChannelID: active.id
            )
        )
        XCTAssertTrue(
            InternetRadioPlaybackMutationPolicy.shouldStopForSelection(
                activeChannelID: active.id,
                selectedChannelID: inactive.id
            )
        )
        XCTAssertFalse(
            InternetRadioPlaybackMutationPolicy.shouldStopForUpdate(
                activeChannelID: active.id,
                previous: active,
                updated: renamedActive
            )
        )
        XCTAssertTrue(
            InternetRadioPlaybackMutationPolicy.shouldStopForUpdate(
                activeChannelID: active.id,
                previous: active,
                updated: changedActive
            )
        )
        XCTAssertFalse(
            InternetRadioPlaybackMutationPolicy.shouldStopForUpdate(
                activeChannelID: active.id,
                previous: inactive,
                updated: changedInactive
            )
        )
        XCTAssertTrue(
            InternetRadioPlaybackMutationPolicy.shouldStopForRemoval(
                activeChannelID: active.id,
                removedChannelID: active.id
            )
        )
        XCTAssertFalse(
            InternetRadioPlaybackMutationPolicy.shouldStopForRemoval(
                activeChannelID: active.id,
                removedChannelID: inactive.id
            )
        )
    }

    func testExternalMusicServicesExposeOnlySupportedProviders() {
        XCTAssertEqual(
            ExternalMusicService.allCases,
            [.appleMusic, .appleClassical]
        )
        XCTAssertEqual(ExternalMusicService.appleMusic.displayName, "Apple Music")
        XCTAssertEqual(ExternalMusicService.appleClassical.displayName, "Apple Music Classical")
    }

    func testSharedImportReusesOnlyAnExactExistingStream() throws {
        let existing = try InternetRadioConfiguration(
            displayName: "저장한 이름",
            urlString: "https://radio.example.com/Live"
        )
        let sameStream = try InternetRadioConfiguration(
            displayName: "공유 페이지 제목",
            urlString: "https://radio.example.com/Live"
        )
        let differentCasePath = try InternetRadioConfiguration(
            displayName: "다른 방송",
            urlString: "https://radio.example.com/live"
        )

        let matched = InternetRadioImportPolicy.draft(
            shared: sameStream,
            existingChannels: [existing]
        )
        let unmatched = InternetRadioImportPolicy.draft(
            shared: differentCasePath,
            existingChannels: [existing]
        )

        XCTAssertEqual(matched.id, existing.id)
        XCTAssertEqual(matched.displayName, existing.displayName)
        XCTAssertEqual(unmatched, differentCasePath)
    }

    func testSharedInternetRadioImportIsLocalLatestWinsAndClearsExplicitly() throws {
        let suiteName = "STandTests.radio-share.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SharedInternetRadioImportStore(defaults: defaults)
        let first = try InternetRadioConfiguration(
            displayName: "첫 주소",
            urlString: "https://one.example.com/live"
        )
        let latest = try InternetRadioConfiguration(
            displayName: "새 주소",
            urlString: "https://two.example.com/live"
        )

        XCTAssertNil(store.pendingConfiguration())
        XCTAssertTrue(store.save(first))
        XCTAssertEqual(store.pendingConfiguration(), first)
        XCTAssertTrue(store.save(latest))
        XCTAssertEqual(store.pendingConfiguration(), latest)
        XCTAssertEqual(store.pendingConfiguration(), latest)

        store.clearPendingConfiguration()
        XCTAssertNil(store.pendingConfiguration())
    }

    func testMalformedSharedInternetRadioImportIsDiscarded() throws {
        let suiteName = "STandTests.invalid-radio-share.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SharedInternetRadioImportStore(defaults: defaults)
        defaults.set(Data("not-json".utf8), forKey: SharedInternetRadioImportStore.pendingConfigurationKey)

        XCTAssertNil(store.pendingConfiguration())
        XCTAssertNil(defaults.data(forKey: SharedInternetRadioImportStore.pendingConfigurationKey))
    }

    func testSharedImportDraftPreservesExistingNameUntilConfirmed() throws {
        let existing = try InternetRadioConfiguration(
            displayName: "내 라디오",
            urlString: "https://old.example.com/live"
        )
        let shared = try InternetRadioConfiguration(
            displayName: "공유 페이지 제목",
            urlString: "https://new.example.com/live"
        )

        let draft = InternetRadioImportPolicy.draft(shared: shared, existing: existing)

        XCTAssertEqual(draft.displayName, existing.displayName)
        XCTAssertEqual(draft.urlString, shared.urlString)
        XCTAssertEqual(existing.urlString, "https://old.example.com/live")
    }

    func testNewExperienceModeNamesMatchProductLanguage() {
        XCTAssertEqual(StandExperienceMode.object.title, "오브제 모드")
        XCTAssertEqual(StandExperienceMode.mate.title, "매이트 모드")
        XCTAssertEqual(StandExperienceMode.startled.title, "화들짝 모드")
        XCTAssertEqual(StandModePreference.object.title, "오브제 유지")
        XCTAssertEqual(StandModePreference.mate.title, "매이트 유지")
    }

    func testForcedModesIgnoreBrightnessSignals() {
        XCTAssertEqual(
            AutomaticModeTransitionPolicy.target(
                preference: .object,
                screenBrightness: 1,
                threshold: 0,
                cameraReading: nil
            ),
            .stand
        )
        XCTAssertEqual(
            AutomaticModeTransitionPolicy.target(
                preference: .mate,
                screenBrightness: 0,
                threshold: 1,
                cameraReading: nil
            ),
            .sleeping
        )
    }

    func testFreshCameraReadingOverridesAmbiguousScreenProxy() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let dark = AmbientBrightnessReading(
            value: 0.05,
            measuredAt: now.addingTimeInterval(-10),
            cameraPosition: .front
        )
        XCTAssertEqual(
            AutomaticModeTransitionPolicy.target(
                preference: .automatic,
                screenBrightness: 0.1,
                threshold: 0.9,
                cameraReading: dark,
                now: now
            ),
            .sleeping
        )

        let stale = AmbientBrightnessReading(
            value: 0.05,
            measuredAt: now.addingTimeInterval(-91),
            cameraPosition: .back
        )
        XCTAssertEqual(
            AutomaticModeTransitionPolicy.target(
                preference: .automatic,
                screenBrightness: 0.1,
                threshold: 0.9,
                cameraReading: stale,
                now: now
            ),
            .stand
        )
    }

    func testAutomaticModeAlwaysDecidesWithinOneMinute() {
        XCTAssertLessThanOrEqual(
            AutomaticModeTransitionPolicy.confirmationDelay(
                from: .stand,
                to: .sleeping,
                hasCameraReading: false
            ),
            60
        )
        XCTAssertLessThanOrEqual(
            AutomaticModeTransitionPolicy.confirmationDelay(
                from: .sleeping,
                to: .stand,
                hasCameraReading: false
            ),
            60
        )
        XCTAssertEqual(
            AutomaticModeTransitionPolicy.confirmationDelay(
                from: .stand,
                to: .sleeping,
                hasCameraReading: true
            ),
            4
        )
        XCTAssertEqual(
            AutomaticModeTransitionPolicy.confirmationDelay(
                from: .sleeping,
                to: .stand,
                hasCameraReading: true
            ),
            35
        )
    }

    func testObjectModeNeverTurnsOnRearTorch() {
        XCTAssertEqual(
            LampTorchLightingPolicy.maximumLevel(
                torchEnabled: true,
                isMovementTriggered: false,
                profile: .gentle,
                environmentDisplayMode: .stand,
                roomIsDark: true
            ),
            0
        )
    }

    func testRecommendedAndLegacyClockFontUseFifthTenadaChoice() {
        XCTAssertEqual(ClockFontChoice.allCases[4], .tenada)
        XCTAssertEqual(AppSettings.recommended.clockFont, .tenada)
        XCTAssertTrue(AppSettings.recommended.torchEnabled)
        XCTAssertEqual(AppSettings.recommended.holdDuration, 5)
    }

    func testRecommendedLayoutsMatchCapturedDeviceArrangement() {
        XCTAssertEqual(AppSettings.recommended.clockScale, AppSettings.defaultClockScale)
        let portrait = AppSettings.recommended.portraitLayout
        XCTAssertEqual(
            portrait.clock,
            PanelTransform(x: 0, y: 0, scale: 1.2919049397971205)
        )
        XCTAssertEqual(
            portrait.weatherIcon,
            PanelTransform(x: 0, y: -0.20497429305912612, scale: 0.8692271910752357)
        )
        XCTAssertEqual(portrait.weatherIcon, portrait.weatherTemperature)
        XCTAssertEqual(portrait.weatherIcon, portrait.weatherCondition)
        XCTAssertEqual(portrait.weatherGroupIDs, [1, 1, 1])
        XCTAssertEqual(
            portrait.seconds,
            PanelTransform(x: 0.33550580431177457, y: 0.05785089974293066, scale: 1)
        )
        XCTAssertEqual(portrait.date, PanelTransform(x: 0, y: 0.1179948586118252, scale: 1))
        XCTAssertEqual(portrait.status, PanelTransform(x: 0, y: 0.15, scale: 1))
        XCTAssertEqual(
            portrait.battery,
            PanelTransform(x: 0, y: 0.2069837189374465, scale: 1)
        )
        XCTAssertEqual(
            portrait.radio,
            PanelTransform(x: 0, y: -0.31070694087403605, scale: 1.0476520613791829)
        )
        XCTAssertEqual(
            portrait.controlOrder,
            [.recordings, .boyiso, .settings]
        )
        XCTAssertEqual(
            portrait.secondaryRadio,
            PanelTransform(x: -0.17436152570480928, y: 0.31097257926306765, scale: 0.75)
        )
        XCTAssertTrue(portrait.radiosGrouped)

        let landscape = AppSettings.recommended.landscapeLayout
        XCTAssertEqual(
            landscape.clock,
            PanelTransform(x: 0, y: 0.21553228621291443, scale: 1.112291215059065)
        )
        XCTAssertEqual(
            landscape.weatherIcon,
            PanelTransform(x: 0, y: -0.06745200698080275, scale: 0.55)
        )
        XCTAssertEqual(landscape.weatherIcon, landscape.weatherTemperature)
        XCTAssertEqual(landscape.weatherIcon, landscape.weatherCondition)
        XCTAssertEqual(landscape.weatherGroupIDs, [1, 1, 1])
        XCTAssertEqual(
            landscape.date,
            PanelTransform(x: 0, y: 0.43815008726003507, scale: 0.85)
        )
        XCTAssertEqual(
            landscape.status,
            PanelTransform(x: 0, y: 0.5, scale: 1)
        )
        XCTAssertEqual(
            landscape.battery,
            PanelTransform(x: 0, y: 0.5245898778359511, scale: 1)
        )
        XCTAssertEqual(
            landscape.seconds,
            PanelTransform(
                x: 0.19200000000000014,
                y: 0.2910122164048866,
                scale: 0.8205408216328642
            )
        )
        XCTAssertEqual(
            landscape.radio,
            PanelTransform(x: 0.4, y: -0.3, scale: 0.75)
        )
        XCTAssertEqual(
            landscape.secondaryRadio,
            PanelTransform(x: -0.4, y: -0.3, scale: 0.75)
        )
        XCTAssertFalse(landscape.radiosGrouped)
        XCTAssertEqual(
            landscape.controlOrder,
            [.recordings, .boyiso, .settings]
        )

        XCTAssertEqual(StandScreenLayout.phoneLandscape, landscape)
    }

    func testLandscapeDefaultKeepsRepresentativePhoneLayoutOnEveryDeviceClass() {
        XCTAssertEqual(StandScreenLayout.landscape, StandScreenLayout.phoneLandscape)
        XCTAssertEqual(
            StandScreenLayout.landscape.brightnessRule,
            PanelTransform(x: 0, y: 0.34, scale: 1)
        )
    }

    func testPortraitAndLandscapeControlOrdersRoundTripIndependently() throws {
        var portrait = StandScreenLayout.portrait
        portrait.radio = PanelTransform(x: -0.18, y: 0.24, scale: 0.52)
        portrait.controlOrder = [
            .settings, .recordings, .boyiso
        ]
        var landscape = StandScreenLayout.landscape
        landscape.radio = PanelTransform(x: 0.31, y: -0.12, scale: 1.35)
        landscape.controlOrder = [
            .recordings, .settings, .boyiso
        ]

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(
                AppSettings(portraitLayout: portrait, landscapeLayout: landscape)
            )
        )

        XCTAssertEqual(decoded.portraitLayout.controlOrder, portrait.controlOrder)
        XCTAssertEqual(decoded.landscapeLayout.controlOrder, landscape.controlOrder)
        XCTAssertEqual(decoded.portraitLayout.radio, portrait.radio)
        XCTAssertEqual(decoded.landscapeLayout.radio, landscape.radio)
    }

    func testControlOrderDecodeIgnoresUnknownsAndCompletesMissingKinds() throws {
        let encoded = try JSONEncoder().encode(StandScreenLayout.portrait)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["controlOrder"] = [
            "settings", "radio", "orientation", "aiShot",
            "futureControl", "settings", "flashlight"
        ]

        let decoded = try JSONDecoder().decode(
            StandScreenLayout.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(
            decoded.controlOrder,
            [.settings, .recordings, .boyiso]
        )
    }

    func testInternetRadioIsAStandalonePanelAndNeverABottomControl() throws {
        XCTAssertFalse(StandControlKind.allCases.contains { $0.rawValue == "radio" })

        let configuration = try InternetRadioConfiguration(
            displayName: "패널 라디오",
            urlString: "https://radio.example.com/live"
        )
        let configured = AppSettings(internetRadio: configuration)

        XCTAssertEqual(configured.portraitLayout.controlOrder, StandScreenLayout.portrait.controlOrder)
        XCTAssertEqual(configured.landscapeLayout.controlOrder, StandScreenLayout.landscape.controlOrder)
        XCTAssertEqual(configured.portraitLayout.radio, StandScreenLayout.portrait.radio)
        XCTAssertEqual(configured.landscapeLayout.radio, StandScreenLayout.landscape.radio)
    }

    func testRadioConfigurationDoesNotChangeBottomControlRows() {
        XCTAssertEqual(
            BottomControlLayoutPolicy.rows(
                for: StandControlKind.defaultOrder,
                availableWidth: 381,
                isPortrait: true
            ).count,
            1
        )
        XCTAssertEqual(
            BottomControlLayoutPolicy.rows(
                for: StandControlKind.defaultOrder,
                availableWidth: 840,
                isPortrait: false
            ).count,
            1
        )
    }

    func testIPadPortraitBottomControlsUseACompactSingleRow() {
        let availableWidth: CGFloat = 822

        XCTAssertEqual(
            BottomControlLayoutPolicy.columnCount(
                availableWidth: availableWidth,
                isPortrait: true
            ),
            8
        )
        XCTAssertEqual(
            BottomControlLayoutPolicy.rows(
                for: StandControlKind.defaultOrder,
                availableWidth: availableWidth,
                isPortrait: true
            ).count,
            1
        )
        XCTAssertEqual(
            BottomControlLayoutPolicy.height(
                for: StandControlKind.defaultOrder,
                availableWidth: availableWidth,
                isPortrait: true
            ),
            StandControlLayoutMetrics.itemHeight
        )
    }

    func testPanelEditorResetPreservesBottomButtonOrder() {
        var customized = StandScreenLayout.portrait
        customized.clock = PanelTransform(x: 0.18, y: -0.12, scale: 1.4)
        customized.radio = PanelTransform(x: -0.22, y: 0.31, scale: 0.44)
        customized.controlOrder = [
            .settings, .recordings, .brightness, .flashlight
        ]

        let reset = HomeEditorResetPolicy.panels(in: customized, isPortrait: true)

        XCTAssertEqual(reset.clock, StandScreenLayout.portrait.clock)
        XCTAssertEqual(reset.radio, StandScreenLayout.portrait.radio)
        XCTAssertEqual(reset.weatherGroupIDs, StandScreenLayout.portrait.weatherGroupIDs)
        XCTAssertEqual(reset.controlOrder, customized.controlOrder)
    }

    func testBottomControlWrappingAndEditorBoundaryStayIndependentFromRadioPanel() {
        let availableWidth: CGFloat = 353

        XCTAssertEqual(
            BottomControlLayoutPolicy.rows(
                for: StandControlKind.defaultOrder,
                availableWidth: availableWidth,
                isPortrait: true
            ).count,
            1
        )
        XCTAssertEqual(
            BottomControlLayoutPolicy.rows(
                for: StandControlKind.defaultOrder,
                availableWidth: availableWidth,
                isPortrait: true
            ).count,
            1
        )
        XCTAssertEqual(
            BottomControlLayoutPolicy.height(
                for: StandControlKind.defaultOrder,
                availableWidth: availableWidth,
                isPortrait: true
            ),
            60
        )

        let region = PanelEditingPolicy.editingRegion(
            canvasSize: CGSize(width: 393, height: 852),
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            isPortrait: true,
            controlOrder: StandControlKind.defaultOrder,
            bottomAvailableWidth: availableWidth
        )
        XCTAssertEqual(region.insets.bottom, 130)
        XCTAssertEqual(region.frame.maxY, 722)
    }

    func testLegacyFixedOrientationIsIgnoredAndRemovedWhenEncoding() throws {
        let legacyJSON = """
        {
          "orientationPreference": "portrait",
          "clockHourMode": "twentyFour"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        let encoded = try JSONEncoder().encode(settings)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertNil(object["orientationPreference"])
        XCTAssertNil(object["clockHourMode"])
    }

    func testTorchAndSoundWakeSettingsRoundTrip() throws {
        let settings = AppSettings(
            silhouetteIntensity: 0.08,
            clockScale: 1.25,
            clockFont: .doHyeon,
            automaticDimmingEnabled: false,
            torchEnabled: true,
            torchIntensity: 0.4,
            wakeOnSleepSound: true
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.torchEnabled)
        XCTAssertEqual(decoded.torchIntensity, 0.4)
        XCTAssertTrue(decoded.wakeOnSleepSound)
        XCTAssertEqual(decoded.silhouetteIntensity, 0.08)
        XCTAssertEqual(decoded.clockScale, 1.25)
        XCTAssertEqual(decoded.clockFont, .doHyeon)
        XCTAssertTrue(decoded.preventAutoDimmingWhenScreenBright)
        XCTAssertFalse(decoded.automaticDimmingEnabled)
    }

    @MainActor
    func testTorchDefaultMigrationForcesOnceThenPreservesUserOptOut() throws {
        let suiteName = "STandTests.torch-default-migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var previouslySaved = AppSettings.recommended
        previouslySaved.torchEnabled = false
        defaults.set(try JSONEncoder().encode(previouslySaved), forKey: "appSettings")

        let migrated = SettingsStore(defaults: defaults)
        XCTAssertTrue(migrated.value.torchEnabled)
        XCTAssertTrue(defaults.bool(forKey: SettingsMigration.torchEnabledByDefaultKey))

        migrated.value.torchEnabled = false
        let reopened = SettingsStore(defaults: defaults)
        XCTAssertFalse(reopened.value.torchEnabled)
    }

    @MainActor
    func testFiveSecondHoldDurationMigrationForcesOnceThenPreservesUserChoice() throws {
        let suiteName = "STandTests.hold-duration-migration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var previouslySaved = AppSettings.recommended
        previouslySaved.holdDuration = 120
        defaults.set(try JSONEncoder().encode(previouslySaved), forKey: "appSettings")
        defaults.set(true, forKey: SettingsMigration.torchEnabledByDefaultKey)

        let migrated = SettingsStore(defaults: defaults)
        XCTAssertEqual(migrated.value.holdDuration, 5)
        XCTAssertTrue(defaults.bool(forKey: SettingsMigration.fiveSecondHoldDurationKey))

        migrated.value.holdDuration = 90
        let reopened = SettingsStore(defaults: defaults)
        XCTAssertEqual(reopened.value.holdDuration, 90)
    }

    @MainActor
    func testCurrentExperienceDefaultsMigrationResetsLayoutsOnce() throws {
        let suiteName = "STandTests.current-experience-defaults.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var previouslySaved = AppSettings.recommended
        previouslySaved.clockScale = 1.35
        previouslySaved.portraitLayout.clock = PanelTransform(x: 0.4, y: -0.3, scale: 0.5)
        previouslySaved.landscapeLayout.date = PanelTransform(x: -0.4, y: 0.3, scale: 1.8)
        defaults.set(try JSONEncoder().encode(previouslySaved), forKey: "appSettings")
        defaults.set(true, forKey: SettingsMigration.torchEnabledByDefaultKey)
        defaults.set(true, forKey: SettingsMigration.fiveSecondHoldDurationKey)
        defaults.set(true, forKey: SettingsMigration.internetRadioChannelsKey)
        defaults.set(true, forKey: SettingsMigration.landscapeLayoutDefaultKey)

        let migrated = SettingsStore(defaults: defaults)
        XCTAssertEqual(migrated.value.clockScale, AppSettings.defaultClockScale)
        XCTAssertEqual(migrated.value.portraitLayout, .portrait)
        XCTAssertEqual(migrated.value.landscapeLayout, .landscape)
        XCTAssertTrue(defaults.bool(forKey: SettingsMigration.currentExperienceDefaultsKey))

        migrated.value.portraitLayout.clock = PanelTransform(x: 0.1, y: 0.2, scale: 0.9)
        let reopened = SettingsStore(defaults: defaults)
        XCTAssertEqual(
            reopened.value.portraitLayout.clock,
            PanelTransform(x: 0.1, y: 0.2, scale: 0.9)
        )
    }

    @MainActor
    func testSettingsStoreDoesNotOverwriteUnreadableSavedPayloadOnLaunch() throws {
        let suiteName = "STandTests.unreadable-settings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let futurePayload = try XCTUnwrap(
            #"{"displayTheme":"future-version-theme"}"#.data(using: .utf8)
        )
        defaults.set(futurePayload, forKey: "appSettings")

        _ = SettingsStore(defaults: defaults)

        XCTAssertEqual(defaults.data(forKey: "appSettings"), futurePayload)
        XCTAssertFalse(defaults.bool(forKey: SettingsMigration.torchEnabledByDefaultKey))
        XCTAssertFalse(defaults.bool(forKey: SettingsMigration.currentExperienceDefaultsKey))
        XCTAssertFalse(defaults.bool(forKey: SettingsMigration.landscapeLayoutDefaultKey))
    }

    @MainActor
    func testLandscapeLayoutDefaultMigrationResetsOnlyLandscapeOnceAndPreservesLaterEdits() throws {
        let suiteName = "STandTests.landscape-layout-default.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var previouslySaved = AppSettings.recommended
        previouslySaved.portraitLayout.clock = PanelTransform(x: 0.12, y: -0.08, scale: 0.9)
        previouslySaved.landscapeLayout.clock = PanelTransform(x: -0.3, y: 0.25, scale: 0.6)
        previouslySaved.holdDuration = 45
        previouslySaved.clockFont = .kakaoBigSans
        defaults.set(try JSONEncoder().encode(previouslySaved), forKey: "appSettings")
        defaults.set(true, forKey: SettingsMigration.torchEnabledByDefaultKey)
        defaults.set(true, forKey: SettingsMigration.fiveSecondHoldDurationKey)
        defaults.set(true, forKey: SettingsMigration.internetRadioChannelsKey)
        defaults.set(true, forKey: SettingsMigration.currentExperienceDefaultsKey)
        defaults.set(true, forKey: "settingsMigration.phoneLandscapeLayoutDefault.v3")

        let migrated = SettingsStore(defaults: defaults)

        XCTAssertEqual(migrated.value.landscapeLayout, .landscape)
        XCTAssertEqual(migrated.value.portraitLayout, previouslySaved.portraitLayout)
        XCTAssertEqual(migrated.value.holdDuration, previouslySaved.holdDuration)
        XCTAssertEqual(migrated.value.clockFont, previouslySaved.clockFont)
        XCTAssertTrue(defaults.bool(forKey: SettingsMigration.landscapeLayoutDefaultKey))

        migrated.value.landscapeLayout.clock = PanelTransform(x: 0.05, y: 0.05, scale: 1.1)
        let reopened = SettingsStore(defaults: defaults)
        XCTAssertEqual(
            reopened.value.landscapeLayout.clock,
            PanelTransform(x: 0.05, y: 0.05, scale: 1.1)
        )
        XCTAssertEqual(reopened.value.portraitLayout, previouslySaved.portraitLayout)
    }

    func testLandscapeLayoutMigrationAppliesRegardlessOfDeviceClass() {
        var previouslySaved = AppSettings.recommended
        previouslySaved.landscapeLayout.clock = PanelTransform(x: -0.3, y: 0.25, scale: 0.6)

        let migrated = SettingsMigration.applyingLandscapeLayoutDefault(
            to: previouslySaved,
            hasMigrated: false
        )

        XCTAssertEqual(migrated.landscapeLayout, .landscape)
        XCTAssertEqual(migrated.portraitLayout, previouslySaved.portraitLayout)
    }

    func testScreenEditingSettingsRoundTrip() throws {
        var portrait = StandScreenLayout.portrait
        portrait.clock = PanelTransform(x: 0.08, y: -0.04, scale: 1.15)
        portrait.date = PanelTransform(x: 0.15, y: -0.12, scale: 1.2)
        portrait.radio = PanelTransform(x: -0.24, y: 0.21, scale: 0.48)
        portrait.weatherGroupIDs = [4, 4, 9]

        let settings = AppSettings(
            clockFont: .paperlogyBold,
            portraitLayout: portrait,
            landscapeLayout: .landscape,
            brightnessModeThreshold: 0.18,
            soundSensingEnabled: false,
            weatherLocationEnabled: false
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.clockFont, .paperlogyBold)
        XCTAssertEqual(decoded.portraitLayout, portrait)
        XCTAssertEqual(decoded.landscapeLayout, .landscape)
        XCTAssertEqual(decoded.brightnessModeThreshold, 0.18)
        XCTAssertFalse(decoded.soundSensingEnabled)
        XCTAssertFalse(decoded.weatherLocationEnabled)
    }

    func testLegacyScreenLayoutWithoutClockUsesCenteredClock() throws {
        let encoded = try JSONEncoder().encode(StandScreenLayout.portrait)
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacy.removeValue(forKey: "clock")

        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(StandScreenLayout.self, from: legacyData)

        XCTAssertEqual(decoded.clock, PanelTransform(x: 0, y: 0, scale: 1))
    }

    func testLegacyScreenLayoutWithoutRadioUsesDefaultPanelPlacement() throws {
        let encoded = try JSONEncoder().encode(StandScreenLayout.portrait)
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacy.removeValue(forKey: "radio")

        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try JSONDecoder().decode(StandScreenLayout.self, from: legacyData)

        XCTAssertEqual(decoded.radio, StandScreenLayout.defaultRadioPanelTransform)
    }

    func testDisplayThemeRoundTripsAndLegacySettingsUseColor() throws {
        var settings = AppSettings.recommended
        settings.displayTheme = .grayscale
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: encoded)
        XCTAssertEqual(decoded.displayTheme, .grayscale)

        let legacy = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        var legacyValues = try XCTUnwrap(legacy)
        legacyValues.removeValue(forKey: "displayTheme")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyValues)
        let legacyDecoded = try JSONDecoder().decode(AppSettings.self, from: legacyData)
        XCTAssertEqual(legacyDecoded.displayTheme, .color)
        XCTAssertEqual(Set(StandDisplayTheme.allCases), Set([.color, .grayscale, .midnight, .sage]))
    }

    func testLegacyScreenLayoutWithoutSecondsUsesClockOverlayPlacement() throws {
        let encoded = try JSONEncoder().encode(StandScreenLayout.portrait)
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacy.removeValue(forKey: "seconds")

        let decoded = try JSONDecoder().decode(
            StandScreenLayout.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertEqual(decoded.seconds, PanelTransform(x: 0.27, y: 0.036, scale: 1))
    }

    func testWeatherPanelsMergeAtFortyPercentOverlap() {
        let source = CGRect(x: 0, y: 0, width: 100, height: 100)
        let fortyPercent = CGRect(x: 60, y: 0, width: 100, height: 100)
        let thirtyNinePercent = CGRect(x: 61, y: 0, width: 100, height: 100)

        XCTAssertEqual(PanelEditingPolicy.weatherMergeOverlapThreshold, 0.4)
        XCTAssertEqual(PanelEditingPolicy.overlapFraction(source, fortyPercent), 0.4)
        XCTAssertLessThan(
            PanelEditingPolicy.overlapFraction(source, thirtyNinePercent),
            PanelEditingPolicy.weatherMergeOverlapThreshold
        )
    }

    func testPanelCenterSnapsToEitherGuideInsideItsMiddleTenPercent() {
        XCTAssertTrue(
            PanelEditingPolicy.shouldSnapToCenter(centerOffset: 6, panelLength: 120)
        )
        XCTAssertFalse(
            PanelEditingPolicy.shouldSnapToCenter(centerOffset: 6.1, panelLength: 120)
        )
        XCTAssertTrue(PanelEditingPolicy.shouldSnapToCenter(centerOffset: -2, panelLength: 40))
        XCTAssertFalse(PanelEditingPolicy.shouldSnapToCenter(centerOffset: -2.1, panelLength: 40))
    }

    func testTopLeadingResizeKeepsCenterAndChangesOnlyScale() {
        let original = PanelTransform(x: 0.18, y: -0.22, scale: 1)
        let smallerScale = PanelEditingPolicy.scaleFromTopLeadingDrag(
            startScale: original.scale,
            panelSize: CGSize(width: 100, height: 80),
            translation: CGSize(width: 20, height: 16)
        )
        let largerScale = PanelEditingPolicy.scaleFromTopLeadingDrag(
            startScale: original.scale,
            panelSize: CGSize(width: 100, height: 80),
            translation: CGSize(width: -20, height: -16)
        )

        XCTAssertLessThan(smallerScale, original.scale)
        XCTAssertGreaterThan(largerScale, original.scale)
        XCTAssertEqual(original.x, 0.18)
        XCTAssertEqual(original.y, -0.22)
        XCTAssertEqual(
            PanelEditingPolicy.scaleFromTopLeadingDrag(
                startScale: PanelEditingPolicy.minimumPanelScale,
                panelSize: CGSize(width: 100, height: 80),
                translation: CGSize(width: 500, height: 500)
            ),
            PanelEditingPolicy.minimumPanelScale
        )
        XCTAssertEqual(
            PanelEditingPolicy.scaleFromTopLeadingDrag(
                startScale: 1,
                panelSize: CGSize(width: 100, height: 80),
                translation: CGSize(width: -500, height: -500)
            ),
            PanelEditingPolicy.maximumPanelScale
        )
        XCTAssertEqual(PanelEditingPolicy.minimumPanelScale, 0.30)
        XCTAssertEqual(PanelEditingPolicy.maximumPanelScale, 2.00)
    }

    func testRadioPanelUsesTheSameThirtyToTwoHundredPercentResizeRange() {
        let panelSize = CGSize(
            width: InternetRadioPanelMetrics.width,
            height: InternetRadioPanelMetrics.height
        )
        let minimum = PanelEditingPolicy.scaleFromTopLeadingDrag(
            startScale: StandScreenLayout.defaultRadioPanelTransform.scale,
            panelSize: panelSize,
            translation: CGSize(width: 1_000, height: 1_000)
        )
        let maximum = PanelEditingPolicy.scaleFromTopLeadingDrag(
            startScale: StandScreenLayout.defaultRadioPanelTransform.scale,
            panelSize: panelSize,
            translation: CGSize(width: -1_000, height: -1_000)
        )

        XCTAssertEqual(minimum, PanelEditingPolicy.minimumPanelScale)
        XCTAssertEqual(maximum, PanelEditingPolicy.maximumPanelScale)

        for scale in [0.30, 0.75, 2.00] {
            let interactionSize = InternetRadioPanelMetrics.interactionSize(
                renderedScale: scale
            )
            XCTAssertGreaterThanOrEqual(interactionSize.width * scale, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(interactionSize.height * scale, 44 - 0.001)
        }
    }

    func testEditablePanelCenterIsNotRestrictedByProtectedControls() {
        let center = PanelEditingPolicy.clampedCenter(
            CGPoint(x: 160, y: 20),
            panelSize: CGSize(width: 100, height: 80),
            canvasSize: CGSize(width: 320, height: 700),
            insets: EdgeInsets(top: 100, leading: 20, bottom: 120, trailing: 20)
        )

        XCTAssertEqual(center.x, 160)
        XCTAssertEqual(center.y, 20)

        let bottomRight = PanelEditingPolicy.clampedCenter(
            CGPoint(x: 400, y: 800),
            panelSize: CGSize(width: 100, height: 80),
            canvasSize: CGSize(width: 320, height: 700),
            insets: EdgeInsets(top: 100, leading: 20, bottom: 120, trailing: 20)
        )
        XCTAssertEqual(bottomRight.x, 400)
        XCTAssertEqual(bottomRight.y, 800)
    }

    func testEditorBoundaryGuidesMatchCurrentPortraitControlRows() {
        let region = PanelEditingPolicy.editingRegion(
            canvasSize: CGSize(width: 393, height: 852),
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            isPortrait: true
        )

        // Top: 59 safe + 18 outer + 46 toolbar + 12 clearance.
        XCTAssertEqual(region.frame.minY, 135)
        // Bottom: 34 safe + 18 outer + 12 version + (60 + 6 + 60) rows + 6 clearance.
        XCTAssertEqual(region.frame.maxY, 656)
        XCTAssertEqual(region.insets.bottom, 196)
    }

    func testEditorBoundaryGuidesMatchCurrentLandscapeControlRow() {
        let region = PanelEditingPolicy.editingRegion(
            canvasSize: CGSize(width: 852, height: 393),
            safeAreaInsets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59),
            isPortrait: false
        )

        // Top: 14 outer + 46 toolbar + 2 clearance.
        XCTAssertEqual(region.frame.minY, 62)
        // Bottom: 21 safe + 6 outer + 12 version + 60 row + 2 clearance.
        XCTAssertEqual(region.frame.maxY, 292)
        XCTAssertEqual(region.insets.bottom, 101)
        XCTAssertEqual(region.frame.minX, 83)
        XCTAssertEqual(region.frame.maxX, 769)
    }

    func testLandscapePhoneEditorFreesTheFormerBottomControlRegion() {
        let canvas = CGSize(width: 852, height: 393)
        let safeAreaInsets = EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59)

        let reservedRegion = PanelEditingPolicy.editingRegion(
            canvasSize: canvas,
            safeAreaInsets: safeAreaInsets,
            isPortrait: false
        )
        XCTAssertEqual(reservedRegion.insets.bottom, 101)

        let freedRegion = PanelEditingPolicy.editingRegion(
            canvasSize: canvas,
            safeAreaInsets: safeAreaInsets,
            isPortrait: false,
            controlOrder: nil,
            reservesBottomControlRow: false
        )
        // Bottom: 21 safe + 6 outer + 12 version + 2 clearance, no control row height.
        XCTAssertEqual(freedRegion.insets.bottom, 41)
        XCTAssertLessThan(freedRegion.insets.bottom, reservedRegion.insets.bottom)
        XCTAssertGreaterThan(freedRegion.frame.maxY, reservedRegion.frame.maxY)
    }

    func testLandscapePhoneEditorReservesTheFixedTopMusicRow() {
        let baseRegion = PanelEditingPolicy.editingRegion(
            canvasSize: CGSize(width: 852, height: 393),
            safeAreaInsets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59),
            isPortrait: false,
            controlOrder: nil,
            reservesBottomControlRow: false
        )
        let phoneLandscapeRegion = PanelEditingPolicy.editingRegion(
            canvasSize: CGSize(width: 852, height: 393),
            safeAreaInsets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59),
            isPortrait: false,
            controlOrder: nil,
            reservesBottomControlRow: false,
            reservesPhoneLandscapeTopRow: true
        )

        XCTAssertEqual(
            phoneLandscapeRegion.insets.top - baseRegion.insets.top,
            InternetRadioPanelMetrics.height + 8
        )
        XCTAssertEqual(phoneLandscapeRegion.insets.bottom, baseRegion.insets.bottom)
    }

    func testEditorMovementUsesFullCanvasVerticallyWithoutChromeBoundary() {
        let canvas = CGSize(width: 393, height: 852)
        let region = PanelEditingPolicy.editingRegion(
            canvasSize: canvas,
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            isPortrait: true,
            fontPaletteVisible: true,
            controlOrder: StandControlKind.defaultOrder,
            bottomAvailableWidth: 353,
            reservesEditorChrome: false
        )

        XCTAssertEqual(region.insets.top, 0)
        XCTAssertEqual(region.insets.bottom, 0)
        XCTAssertEqual(region.frame.minY, 0)
        XCTAssertEqual(region.frame.maxY, canvas.height)

        for requestedY in [-1.0, 1.0] {
            let requested = PanelTransform(x: 0, y: requestedY, scale: 1)
            let result = PanelEditingPolicy.clampedTransform(
                requested,
                panelSize: CGSize(width: 260, height: StatusPanelMetrics.height),
                canvasSize: canvas,
                insets: region.insets,
                screenScale: 1
            )
            XCTAssertEqual(result, requested)
        }
    }

    func testLandscapePanelCanCrossFormerEditorGuidesAtScreenScale() {
        let canvas = CGSize(width: 852, height: 393)
        let region = PanelEditingPolicy.editingRegion(
            canvasSize: canvas,
            safeAreaInsets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59),
            isPortrait: false
        )
        let panelSize = CGSize(width: 370 / 3, height: 370 / 3)
        let screenScale = 1.35

        for requestedY in [-0.44, 0.44] {
            let requested = PanelTransform(x: 0, y: requestedY, scale: 1)
            let result = PanelEditingPolicy.clampedTransform(
                requested,
                panelSize: panelSize,
                canvasSize: canvas,
                insets: region.insets,
                screenScale: screenScale
            )
            XCTAssertEqual(result, requested)
        }
    }

    func testFontPaletteRaisesEditorBottomGuideToItsActualTopEdge() {
        let region = PanelEditingPolicy.editingRegion(
            canvasSize: CGSize(width: 393, height: 852),
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            isPortrait: true,
            fontPaletteVisible: true
        )

        // 34 safe + 22 palette padding + 190 palette + 8 clearance.
        XCTAssertEqual(region.insets.bottom, 254)
        XCTAssertEqual(region.frame.maxY, 598)
    }

    func testLandscapeFontPaletteRaisesBottomGuideAbovePalette() {
        let region = PanelEditingPolicy.editingRegion(
            canvasSize: CGSize(width: 852, height: 393),
            safeAreaInsets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59),
            isPortrait: false,
            fontPaletteVisible: true
        )

        // 21 safe + 14 palette padding + 126 palette + 2 clearance.
        XCTAssertEqual(region.insets.bottom, 163)
        XCTAssertEqual(region.frame.maxY, 230)
    }

    func testSavedPanelMayOverlapBottomControlsAfterWholeScreenScaling() {
        let canvasSize = CGSize(width: 393, height: 852)
        let insets = EdgeInsets(top: 123, leading: 14, bottom: 218, trailing: 14)
        let panelSize = CGSize(width: 240, height: 46)
        let screenScale = 1.35
        let result = PanelEditingPolicy.clampedTransform(
            PanelTransform(x: 0, y: 0.44, scale: 1),
            panelSize: panelSize,
            canvasSize: canvasSize,
            insets: insets,
            screenScale: screenScale
        )
        XCTAssertEqual(result, PanelTransform(x: 0, y: 0.44, scale: 1))
    }

    func testEditorPanelMovementIsNotClampedToScreenOrControls() {
        let canvasSize = CGSize(width: 393, height: 852)
        let insets = EdgeInsets(top: 123, leading: 14, bottom: 218, trailing: 14)
        let panelSize = CGSize(width: 240, height: 46)
        let result = PanelEditingPolicy.clampedTransform(
            PanelTransform(x: 0, y: 0.44, scale: 1),
            panelSize: panelSize,
            canvasSize: canvasSize,
            insets: insets,
            screenScale: 0.7
        )
        XCTAssertEqual(result, PanelTransform(x: 0, y: 0.44, scale: 1))
    }

    func testPinchMaximumScaleUsesOnlyTheConfiguredSizeLimit() {
        var layout = StandScreenLayout.portrait
        layout.status = .init(x: 0, y: 0.2)
        let canvas = CGSize(width: 393, height: 852)
        let insets = EdgeInsets(top: 123, leading: 14, bottom: 218, trailing: 14)
        let maximum = PanelEditingPolicy.maximumScreenScale(
            layout: layout,
            isPortrait: true,
            canvasSize: canvas,
            insets: insets,
            hardLimit: 1.35
        )
        XCTAssertEqual(maximum, 1.35)
    }

    func testHiddenRadioPanelDoesNotLimitTheWholeDashboardScale() {
        var layout = StandScreenLayout.portrait
        layout.radio = PanelTransform(x: 0, y: 0.44, scale: 2)
        let canvas = CGSize(width: 393, height: 852)
        let insets = EdgeInsets(top: 123, leading: 14, bottom: 218, trailing: 14)

        let withoutRadio = PanelEditingPolicy.maximumScreenScale(
            layout: layout,
            isPortrait: true,
            canvasSize: canvas,
            insets: insets,
            includesRadio: false,
            hardLimit: 1.35
        )
        let withRadio = PanelEditingPolicy.maximumScreenScale(
            layout: layout,
            isPortrait: true,
            canvasSize: canvas,
            insets: insets,
            includesRadio: true,
            hardLimit: 1.35
        )

        XCTAssertEqual(withoutRadio, 1.35)
        XCTAssertEqual(withRadio, 1.35)
    }

    func testBrightnessThresholdTrackMapsAndClampsDragLocation() {
        XCTAssertEqual(BrightnessThresholdPolicy.value(locationX: 60, width: 240), 0.25)
        XCTAssertEqual(BrightnessThresholdPolicy.value(locationX: -20, width: 240), 0)
        XCTAssertEqual(BrightnessThresholdPolicy.value(locationX: 300, width: 240), 1)
    }

    func testBrightnessRuleTrackOnlyBeginsForDirectHorizontalDrag() {
        XCTAssertFalse(
            BrightnessRuleInteractionPolicy.hasReachedDecisionDistance(
                CGSize(width: 5, height: 1)
            )
        )
        XCTAssertTrue(
            BrightnessRuleInteractionPolicy.isTap(CGSize(width: 5, height: 1))
        )
        XCTAssertFalse(
            BrightnessRuleInteractionPolicy.isTap(CGSize(width: 6, height: 0))
        )
        XCTAssertTrue(
            BrightnessRuleInteractionPolicy.isDirectHorizontalDrag(
                translation: CGSize(width: 7, height: 2)
            )
        )
        XCTAssertFalse(
            BrightnessRuleInteractionPolicy.isDirectHorizontalDrag(
                translation: CGSize(width: 4, height: 1)
            )
        )
        XCTAssertFalse(
            BrightnessRuleInteractionPolicy.isDirectHorizontalDrag(
                translation: CGSize(width: 7, height: 12)
            )
        )
        XCTAssertTrue(
            BrightnessRuleInteractionPolicy.isDirectHorizontalDrag(
                translation: CGSize(width: 1, height: 20),
                alreadyDragging: true
            )
        )
    }

    func testBrightnessThresholdTapAlternatesAtTheNearestQuarterPoints() {
        let brightness = 0.6
        let sleepingThreshold = BrightnessThresholdPolicy.valueAfterTap(
            currentBrightness: brightness,
            threshold: 0.8
        )
        XCTAssertEqual(sleepingThreshold, 0.45, accuracy: 0.000_001)
        XCTAssertEqual(
            EnvironmentDisplayMode.resolve(
                brightness: brightness,
                threshold: sleepingThreshold
            ),
            .sleeping
        )

        let standThreshold = BrightnessThresholdPolicy.valueAfterTap(
            currentBrightness: brightness,
            threshold: sleepingThreshold
        )
        XCTAssertEqual(standThreshold, 0.7, accuracy: 0.000_001)
        XCTAssertEqual(
            EnvironmentDisplayMode.resolve(brightness: brightness, threshold: standThreshold),
            .stand
        )
    }

    func testBrightnessAndActionTilesShareFullContainerOpacity() {
        XCTAssertEqual(StandControlLayoutMetrics.tileOpacity, 1)
    }

    func testHiddenControlRevealTargetIsTwiceTheVisualLabelHeight() {
        XCTAssertEqual(
            StandControlLayoutMetrics.hiddenControlRevealHeight,
            StandControlLayoutMetrics.hiddenControlLabelHeight * 2
        )
        XCTAssertEqual(StandControlLayoutMetrics.hiddenControlRevealHeight, 80)
    }

    func testBottomControlTypographyAndThreeColumnSliderMetrics() {
        XCTAssertEqual(StandControlLayoutMetrics.titleFontSize, 10.5)
        XCTAssertEqual(StandControlLayoutMetrics.statusFontSize, 8.5)
        XCTAssertEqual(StandControlLayoutMetrics.foregroundOpacity, 0.78)

        let screenWidth: CGFloat = 393
        let availableWidth = screenWidth - StandControlLayoutMetrics.rowSpacing * 2
        let buttonWidth = BottomControlLayoutPolicy.itemWidth(
            for: .flashlight,
            availableWidth: availableWidth,
            isPortrait: true
        )
        let sliderWidth = BottomControlLayoutPolicy.itemWidth(
            for: .brightness,
            availableWidth: availableWidth,
            isPortrait: true
        )
        let nightRowWidth = buttonWidth * 2 + sliderWidth
            + StandControlLayoutMetrics.rowSpacing * 2
        let secondaryRowWidth = buttonWidth * 2
            + StandControlLayoutMetrics.rowSpacing

        XCTAssertEqual(buttonWidth, 90.75)
        XCTAssertEqual(sliderWidth, 187.5)
        XCTAssertEqual(nightRowWidth, availableWidth)
        XCTAssertLessThan(secondaryRowWidth, availableWidth)
        XCTAssertEqual(screenWidth - availableWidth, StandControlLayoutMetrics.rowSpacing * 2)

        let landscapeAvailableWidth: CGFloat = 852 - StandControlLayoutMetrics.rowSpacing * 2
        let landscapeRows = BottomControlLayoutPolicy.rows(
            for: StandControlKind.defaultOrder,
            availableWidth: landscapeAvailableWidth,
            isPortrait: false
        )
        XCTAssertEqual(landscapeRows.count, 1)
        let landscapeRowWidth = StandControlKind.defaultOrder.reduce(CGFloat.zero) {
            $0 + BottomControlLayoutPolicy.itemWidth(
                for: $1,
                availableWidth: landscapeAvailableWidth,
                isPortrait: false
            )
        } + StandControlLayoutMetrics.rowSpacing
            * CGFloat(StandControlKind.defaultOrder.count - 1)
        XCTAssertLessThan(landscapeRowWidth, landscapeAvailableWidth)
    }

    func testStatusPanelUsesSingleLineWidthAndMatchingBoundaryHeight() {
        XCTAssertEqual(StatusPanelMetrics.width(isPortrait: true), 260)
        XCTAssertEqual(StatusPanelMetrics.width(isPortrait: false), 320)
        XCTAssertEqual(StatusPanelMetrics.height, 36)
        XCTAssertLessThanOrEqual(260 * 1.35, 393 - 28)
        XCTAssertLessThanOrEqual(320 * 1.35, 852 - 166)
    }

    func testThresholdLeftOfBrightnessIsSleepingAndRightIsStand() {
        XCTAssertEqual(
            EnvironmentDisplayMode.resolve(brightness: 0.2, threshold: 0.5),
            .stand
        )
        XCTAssertEqual(
            EnvironmentDisplayMode.resolve(brightness: 0.8, threshold: 0.5),
            .sleeping
        )
    }

    func testStandModeNeverAllowsAutomaticDimming() {
        XCTAssertFalse(
            StandAutomaticDimmingPolicy.shouldFade(
                automaticDimmingEnabled: true,
                environmentDisplayMode: .stand
            )
        )
        XCTAssertTrue(
            StandAutomaticDimmingPolicy.shouldFade(
                automaticDimmingEnabled: true,
                environmentDisplayMode: .sleeping
            )
        )
        XCTAssertFalse(
            StandAutomaticDimmingPolicy.shouldFade(
                automaticDimmingEnabled: false,
                environmentDisplayMode: .sleeping
            )
        )
    }

    func testStartleActivationWaitsForConfiguredDelayAfterEnteringMateMode() {
        let enteredAt: TimeInterval = 1_000

        XCTAssertFalse(
            StartleActivationPolicy.canActivate(
                mateModeEnteredAt: nil,
                now: enteredAt + 120
            )
        )
        XCTAssertFalse(
            StartleActivationPolicy.canActivate(
                mateModeEnteredAt: enteredAt,
                now: enteredAt + StartleActivationPolicy.delay - 0.001
            )
        )
        XCTAssertTrue(
            StartleActivationPolicy.canActivate(
                mateModeEnteredAt: enteredAt,
                now: enteredAt + StartleActivationPolicy.delay
            )
        )
    }

    func testSleepCareMonitoringRunsOnlyInSleepingMode() {
        XCTAssertTrue(
            SleepCareMonitoringPolicy.shouldMonitor(
                isNightSessionActive: true,
                environmentDisplayMode: .sleeping
            )
        )
        XCTAssertFalse(
            SleepCareMonitoringPolicy.shouldMonitor(
                isNightSessionActive: true,
                environmentDisplayMode: .stand
            )
        )
        XCTAssertFalse(
            SleepCareMonitoringPolicy.shouldMonitor(
                isNightSessionActive: false,
                environmentDisplayMode: .sleeping
            )
        )
        XCTAssertTrue(
            SleepCareMonitoringPolicy.shouldCaptureAudio(
                isNightSessionActive: true,
                environmentDisplayMode: .sleeping,
                isSuspended: false
            )
        )
        XCTAssertFalse(
            SleepCareMonitoringPolicy.shouldCaptureAudio(
                isNightSessionActive: true,
                environmentDisplayMode: .sleeping,
                isSuspended: true
            )
        )
        XCTAssertFalse(
            SleepCareMonitoringPolicy.shouldCaptureAudio(
                isNightSessionActive: true,
                environmentDisplayMode: .sleeping,
                isSuspended: false,
                isEnabled: false
            )
        )
    }

    func testStartleTorchUsesLowGeneralAndMaximumUrgentProfilesOnlyWhenEnabledAndDark() {
        XCTAssertEqual(
            SleepMovementLightingPolicy.torchLevel(
                torchEnabled: true,
                profile: .gentle,
                environmentDisplayMode: .sleeping,
                roomIsDark: true
            ),
            0.1
        )
        XCTAssertEqual(
            SleepMovementLightingPolicy.torchLevel(
                torchEnabled: true,
                profile: .urgent,
                environmentDisplayMode: .sleeping,
                roomIsDark: true
            ),
            1
        )
        XCTAssertEqual(
            SleepMovementLightingPolicy.torchLevel(
                torchEnabled: false,
                profile: .urgent,
                environmentDisplayMode: .sleeping,
                roomIsDark: true
            ),
            0
        )
        XCTAssertEqual(
            SleepMovementLightingPolicy.torchLevel(
                torchEnabled: true,
                profile: .gentle,
                environmentDisplayMode: .stand,
                roomIsDark: true
            ),
            0
        )
        XCTAssertEqual(
            SleepMovementLightingPolicy.torchLevel(
                torchEnabled: true,
                profile: .gentle,
                environmentDisplayMode: .sleeping,
                roomIsDark: false
            ),
            0.1
        )
        XCTAssertEqual(
            SleepMovementLightingPolicy.torchLevel(
                torchEnabled: true,
                profile: .urgent,
                environmentDisplayMode: .sleeping,
                roomIsDark: false
            ),
            0
        )
    }

    func testTorchOnlyRunsForMovementTriggeredStartleMode() {
        XCTAssertEqual(
            LampTorchLightingPolicy.maximumLevel(
                torchEnabled: true,
                isMovementTriggered: false,
                profile: .gentle,
                environmentDisplayMode: .sleeping,
                roomIsDark: true
            ),
            0
        )
        XCTAssertEqual(
            LampTorchLightingPolicy.maximumLevel(
                torchEnabled: false,
                isMovementTriggered: false,
                profile: .urgent,
                environmentDisplayMode: .sleeping,
                roomIsDark: true
            ),
            0
        )
        XCTAssertEqual(
            LampTorchLightingPolicy.maximumLevel(
                torchEnabled: true,
                isMovementTriggered: true,
                profile: .gentle,
                environmentDisplayMode: .sleeping,
                roomIsDark: true
            ),
            0.1
        )
        XCTAssertEqual(
            LampTorchLightingPolicy.maximumLevel(
                torchEnabled: true,
                isMovementTriggered: true,
                profile: .urgent,
                environmentDisplayMode: .sleeping,
                roomIsDark: true
            ),
            1
        )
    }

    func testStartleLightingProfilesReachTheirPeaksAndRestoreBaseWithinTenSeconds() {
        let base = 0.02

        XCTAssertEqual(StartleLightingProfile.totalDuration, 10)
        XCTAssertEqual(StartleLightingProfile.gentle.riseDuration, 2)
        XCTAssertEqual(StartleLightingProfile.gentle.peakDisplayIntensity, 0.4)
        XCTAssertEqual(StartleLightingProfile.gentle.displayIntensity(
            elapsed: 0,
            baseIntensity: base
        ), base, accuracy: 0.0001)
        XCTAssertLessThan(StartleLightingProfile.gentle.displayIntensity(
            elapsed: 1,
            baseIntensity: base
        ), 0.4)
        XCTAssertEqual(StartleLightingProfile.gentle.displayIntensity(
            elapsed: 2,
            baseIntensity: base
        ), 0.4, accuracy: 0.0001)
        XCTAssertEqual(StartleLightingProfile.gentle.displayIntensity(
            elapsed: 10,
            baseIntensity: base
        ), base, accuracy: 0.0001)

        XCTAssertEqual(StartleLightingProfile.urgent.riseDuration, 1)
        XCTAssertEqual(StartleLightingProfile.urgent.displayIntensity(
            elapsed: 1,
            baseIntensity: base
        ), 1, accuracy: 0.0001)
        XCTAssertEqual(StartleLightingProfile.urgent.displayIntensity(
            elapsed: 10,
            baseIntensity: base
        ), base, accuracy: 0.0001)
    }

    func testStartleLightingClassifiesMovementAndFingerSnapAsGentle() {
        let sourceID = UUID()
        let movement = BoyisoEvent(sourceID: sourceID, sourceName: "아이 방", role: .guest,
            kind: .movement, detail: "turning", monitoring: true, batteryPercent: nil)
        let fingerSnap = BoyisoEvent(sourceID: sourceID, sourceName: "아이 방", role: .guest,
            kind: .sound, detail: "finger_snap", monitoring: true, batteryPercent: nil)
        let bigSound = BoyisoEvent(sourceID: sourceID, sourceName: "아이 방", role: .guest,
            kind: .sound, detail: "big_sound", monitoring: true, batteryPercent: nil)
        let continuousSound = BoyisoEvent(sourceID: sourceID, sourceName: "아이 방", role: .guest,
            kind: .sound, detail: "continuous_sound", monitoring: true, batteryPercent: nil)

        let walkiePress = BoyisoEvent(sourceID: sourceID, sourceName: "무전기", role: .walkie,
            kind: .walkie, detail: "press", monitoring: false, batteryPercent: nil)

        XCTAssertEqual(StartleLightingProfile.forEvent(movement), .gentle)
        XCTAssertEqual(StartleLightingProfile.forEvent(fingerSnap), .gentle)
        XCTAssertEqual(StartleLightingProfile.forEvent(bigSound), .urgent)
        XCTAssertEqual(StartleLightingProfile.forEvent(continuousSound), .urgent)
        XCTAssertEqual(StartleLightingProfile.forEvent(walkiePress), .urgent)
    }

    func testStartleTorchRequiresARecentDarkRoomReading() {
        let now = Date()
        XCTAssertTrue(AmbientCameraModePolicy.isRecentlyDark(
            AmbientBrightnessReading(
                value: AmbientCameraModePolicy.darkThreshold,
                measuredAt: now,
                cameraPosition: .front
            ),
            now: now
        ))
        XCTAssertFalse(AmbientCameraModePolicy.isRecentlyDark(
            AmbientBrightnessReading(
                value: AmbientCameraModePolicy.brightThreshold,
                measuredAt: now,
                cameraPosition: .front
            ),
            now: now
        ))
        XCTAssertFalse(AmbientCameraModePolicy.isRecentlyDark(
            AmbientBrightnessReading(
                value: 0,
                measuredAt: now.addingTimeInterval(-AmbientCameraModePolicy.maximumReadingAge - 1),
                cameraPosition: .front
            ),
            now: now
        ))
        XCTAssertFalse(AmbientCameraModePolicy.isRecentlyDark(nil, now: now))
    }

    func testSimplifiedBrightnessModeBoundariesAndTapTargets() {
        XCTAssertEqual(
            SimplifiedBrightnessModePolicy.mode(for: 0.4, preference: .automatic),
            .sleeping
        )
        XCTAssertEqual(
            SimplifiedBrightnessModePolicy.mode(for: 0.401, preference: .automatic),
            .stand
        )
        XCTAssertEqual(SimplifiedBrightnessModePolicy.preference(for: 0), .mate)
        XCTAssertEqual(SimplifiedBrightnessModePolicy.preference(for: 0.1), .automatic)
        XCTAssertEqual(SimplifiedBrightnessModePolicy.preference(for: 0.9), .automatic)
        XCTAssertEqual(SimplifiedBrightnessModePolicy.preference(for: 1), .object)
        XCTAssertEqual(SimplifiedBrightnessModePolicy.tapLevel(from: .stand), 0.35)
        XCTAssertEqual(SimplifiedBrightnessModePolicy.tapLevel(from: .sleeping), 0.8)
        XCTAssertEqual(
            SimplifiedBrightnessModePolicy.preferenceDuringAdjustment(for: 1),
            .automatic
        )
        XCTAssertEqual(
            SimplifiedBrightnessModePolicy.preferenceDuringAdjustment(for: 0),
            .automatic
        )
        XCTAssertEqual(SimplifiedBrightnessModePolicy.objectLockDelay, .seconds(1))
        XCTAssertEqual(SimplifiedBrightnessModePolicy.mateLockDelay, .seconds(1))

        let tinyReleaseMovement = SimplifiedBrightnessModePolicy.stabilizedAdjustment(
            requestedLevel: 0.98,
            currentPreference: .object
        )
        XCTAssertEqual(tinyReleaseMovement.level, 1)
        XCTAssertEqual(tinyReleaseMovement.preference, .object)

        let intentionalRelease = SimplifiedBrightnessModePolicy.stabilizedAdjustment(
            requestedLevel: 0.94,
            currentPreference: .object
        )
        XCTAssertEqual(intentionalRelease.level, 0.94)
        XCTAssertEqual(intentionalRelease.preference, .automatic)
    }

    func testCameraBrightnessUsesSustainedBrightReadingWithoutReactingToAmbiguousLight() {
        let now = Date()
        XCTAssertEqual(AmbientCameraModePolicy.minimumObservationDuration, 1)
        XCTAssertEqual(AmbientCameraModePolicy.maximumReadingAge, 60)
        XCTAssertEqual(AmbientCameraModePolicy.samplingInterval, .seconds(45))
        XCTAssertEqual(
            AmbientCameraModePolicy.target(
                current: .sleeping,
                fallback: .sleeping,
                reading: AmbientBrightnessReading(
                    value: AmbientCameraModePolicy.brightThreshold,
                    measuredAt: now,
                    cameraPosition: .front
                ),
                now: now
            ),
            .stand
        )
        XCTAssertEqual(
            AmbientCameraModePolicy.target(
                current: .sleeping,
                fallback: .sleeping,
                reading: AmbientBrightnessReading(
                    value: 0.22,
                    measuredAt: now,
                    cameraPosition: .front
                ),
                now: now
            ),
            .sleeping
        )
        XCTAssertEqual(
            AmbientCameraModePolicy.target(
                current: .stand,
                fallback: .stand,
                reading: AmbientBrightnessReading(
                    value: AmbientCameraModePolicy.darkThreshold,
                    measuredAt: now,
                    cameraPosition: .front
                ),
                now: now
            ),
            .sleeping
        )
    }

    func testAmbientCameraSamplesOnlyDuringAutomaticMateMode() {
        XCTAssertTrue(AmbientCameraSamplingPolicy.shouldSample(
            isSessionActive: true,
            displayMode: .sleeping,
            modePreference: .automatic,
            isEnabled: true
        ))
        XCTAssertFalse(AmbientCameraSamplingPolicy.shouldSample(
            isSessionActive: true,
            displayMode: .stand,
            modePreference: .automatic,
            isEnabled: true
        ))
        XCTAssertFalse(AmbientCameraSamplingPolicy.shouldSample(
            isSessionActive: true,
            displayMode: .sleeping,
            modePreference: .mate,
            isEnabled: true
        ))
        XCTAssertFalse(AmbientCameraSamplingPolicy.shouldSample(
            isSessionActive: false,
            displayMode: .sleeping,
            modePreference: .automatic,
            isEnabled: true
        ))
    }

    func testHalfScreenVerticalDragCoversTheFullSystemBrightnessRange() {
        XCTAssertEqual(SimplifiedBrightnessModePolicy.verticalDragTravelRatio, 0.5)
        XCTAssertEqual(
            SimplifiedBrightnessModePolicy.level(
                startingAt: 0.5,
                verticalTranslation: -400,
                viewportHeight: 800
            ),
            1
        )
        XCTAssertEqual(
            SimplifiedBrightnessModePolicy.level(
                startingAt: 0.5,
                verticalTranslation: 400,
                viewportHeight: 800
            ),
            0
        )
        XCTAssertEqual(
            SimplifiedBrightnessModePolicy.level(
                startingAt: 1,
                verticalTranslation: 100,
                viewportHeight: 800
            ),
            0.75
        )
        XCTAssertEqual(SimplifiedBrightnessModePolicy.preference(for: 1), .object)
        XCTAssertEqual(SimplifiedBrightnessModePolicy.preference(for: 0), .mate)
    }

    func testSystemBrightnessCannotOverwriteAnActiveOrFixedAppAdjustment() {
        XCTAssertFalse(AppBrightnessSystemSyncPolicy.shouldAdoptSystemBrightness(
            isAdjustingBrightness: true,
            modePreference: .automatic
        ))
        XCTAssertFalse(AppBrightnessSystemSyncPolicy.shouldAdoptSystemBrightness(
            isAdjustingBrightness: false,
            modePreference: .object
        ))
        XCTAssertFalse(AppBrightnessSystemSyncPolicy.shouldAdoptSystemBrightness(
            isAdjustingBrightness: false,
            modePreference: .mate
        ))
        XCTAssertTrue(AppBrightnessSystemSyncPolicy.shouldAdoptSystemBrightness(
            isAdjustingBrightness: false,
            modePreference: .automatic
        ))
    }

    func testMateLockIsOnlyVisibleWhileFixedInMateOutsideStartle() {
        XCTAssertTrue(MateLockPresentationPolicy.isVisible(
            modePreference: .mate,
            experienceMode: .mate
        ))
        XCTAssertFalse(MateLockPresentationPolicy.isVisible(
            modePreference: .mate,
            experienceMode: .startled
        ))
        XCTAssertFalse(MateLockPresentationPolicy.isVisible(
            modePreference: .automatic,
            experienceMode: .mate
        ))
        XCTAssertFalse(MateLockPresentationPolicy.isVisible(
            modePreference: .object,
            experienceMode: .object
        ))
    }

    func testMateLockMatchesAndroidSurfaceBrightness() {
        XCTAssertEqual(MateLockPresentationPolicy.backgroundOpacity, 0.68)
        XCTAssertEqual(MateLockPresentationPolicy.borderOpacity, 0.12)
        XCTAssertEqual(MateLockPresentationPolicy.foregroundOpacity, 0.35)
    }

    func testSecondsPanelLosesItsBackgroundWhenPlacedOnClock() {
        var layout = StandScreenLayout.portrait
        XCTAssertTrue(
            ClockSecondsPlacement.isOverlappingClock(
                layout: layout,
                canvasSize: CGSize(width: 393, height: 852),
                isPortrait: true
            )
        )
        layout.seconds = PanelTransform(x: -0.4, y: -0.35, scale: 1)
        XCTAssertFalse(
            ClockSecondsPlacement.isOverlappingClock(
                layout: layout,
                canvasSize: CGSize(width: 393, height: 852),
                isPortrait: true
            )
        )
    }

    func testSimplifiedControlOrderDropsLegacyBrightnessAndFlashTiles() {
        XCTAssertEqual(
            StandControlKind.normalizedOrder([
                .flashlight, .settings, .brightness, .recordings, .stopDetection
            ]),
            [.settings, .recordings, .boyiso]
        )
    }

    func testAdaptiveNoiseFloorRequiresTenToFourteenDecibelsOfRelativeRise() {
        var quietTracker = AdaptiveNoiseFloorTracker()
        var quietState = quietTracker.state
        for _ in 0..<60 {
            quietState = quietTracker.observe(rmsDB: -62, duration: 1)
        }

        var noisyTracker = AdaptiveNoiseFloorTracker()
        var noisyState = noisyTracker.state
        for _ in 0..<60 {
            noisyState = noisyTracker.observe(rmsDB: -30, duration: 1)
        }

        XCTAssertTrue(quietState.isCalibrated)
        XCTAssertEqual(quietState.noiseFloorDB, -62)
        XCTAssertEqual(quietState.effectiveSoundThresholdDB, -52)
        XCTAssertEqual(noisyState.noiseFloorDB, -30)
        XCTAssertEqual(noisyState.effectiveSoundThresholdDB, -18)
        XCTAssertGreaterThan(noisyState.effectiveSoundThresholdDB, quietState.effectiveSoundThresholdDB)
    }

    func testAdaptiveNoiseFloorIgnoresSmallRelativeRiseAndAcceptsTenDecibels() {
        var tracker = AdaptiveNoiseFloorTracker()
        for _ in 0..<59 { _ = tracker.observe(rmsDB: -60, duration: 1) }
        let state = tracker.observe(rmsDB: -10, duration: 1)

        XCTAssertEqual(state.noiseFloorDB, -60)
        var detector = AudioEventDetector(
            configuration: AudioDetectorConfiguration(
                soundThresholdDB: state.effectiveSoundThresholdDB
            )
        )
        _ = detector.analyze(rmsDB: -60, peakDB: -54, bufferDuration: 0.02, now: 1)
        _ = detector.analyze(rmsDB: -54, peakDB: -45, bufferDuration: 0.02, now: 1.02)
        _ = detector.analyze(rmsDB: -54, peakDB: -45, bufferDuration: 0.02, now: 1.04)
        let smallRise = detector.analyze(
            rmsDB: -54,
            peakDB: -45,
            bufferDuration: 0.02,
            now: 1.06
        )
        XCTAssertFalse(smallRise.soundBegan)

        detector.reset()
        _ = detector.analyze(rmsDB: -49, peakDB: -30, bufferDuration: 0.02, now: 2)
        _ = detector.analyze(rmsDB: -49, peakDB: -30, bufferDuration: 0.02, now: 2.02)
        let clearRise = detector.analyze(
            rmsDB: -49,
            peakDB: -30,
            bufferDuration: 0.02,
            now: 2.04
        )
        XCTAssertTrue(clearRise.soundBegan)
    }

    func testUserThresholdLimitsAutomaticSensitivityAndCalibrationSuppressesReactions() {
        var tracker = AdaptiveNoiseFloorTracker()
        var state = tracker.state
        for _ in 0..<59 { state = tracker.observe(rmsDB: -55, duration: 1) }

        XCTAssertFalse(AudioCalibrationPolicy.canReact(state))
        state = tracker.observe(rmsDB: -55, duration: 1)
        XCTAssertTrue(AudioCalibrationPolicy.canReact(state))
        XCTAssertEqual(
            AdaptiveSoundThresholdPolicy.soundThreshold(
                noiseFloorDB: state.noiseFloorDB,
                userThresholdDB: -36
            ),
            -36
        )
        XCTAssertEqual(
            AdaptiveSoundThresholdPolicy.clapPeakThreshold(
                noiseFloorDB: state.noiseFloorDB,
                userThresholdDB: -36,
                configuredPeakThresholdDB: -18
            ),
            -18
        )
    }

    func testReportedQuietClipCannotOpenRecordingOrClapGateAtRecommendedSettings() {
        var detector = AudioEventDetector(
            configuration: AudioDetectorConfiguration(soundThresholdDB: -36)
        )
        for index in 0..<10 {
            let detection = detector.analyze(
                rmsDB: -46.69,
                peakDB: -36.92,
                bufferDuration: 0.02,
                now: Double(index) * 0.02
            )
            XCTAssertFalse(detection.soundBegan)
            XCTAssertFalse(detection.isAboveSoundThreshold)
            XCTAssertFalse(detection.clapDetected)
        }
    }

    func testWeatherResponseDecodesAndMapsKoreanCondition() throws {
        let data = """
        {
          "current": {
            "temperature_2m": 24.6,
            "apparent_temperature": 26.1,
            "precipitation": 0.4,
            "weather_code": 61,
            "is_day": 1
          }
        }
        """.data(using: .utf8)!

        let weather = try WeatherService.decodeWeather(from: data)

        XCTAssertEqual(weather.temperature, 24.6)
        XCTAssertEqual(weather.apparentTemperature, 26.1)
        XCTAssertEqual(weather.precipitation, 0.4)
        XCTAssertEqual(weather.summary, "비")
        XCTAssertEqual(weather.systemImage, "cloud.rain.fill")
    }

    func testWeatherLocationNameKeepsUniqueRegionalComponents() {
        XCTAssertEqual(
            WeatherService.locationName(
                administrativeArea: "서울특별시",
                locality: "서울특별시",
                subAdministrativeArea: "강남구",
                subLocality: "삼성동",
                country: "대한민국"
            ),
            "서울특별시 강남구 삼성동"
        )
        XCTAssertEqual(
            WeatherService.locationName(
                administrativeArea: nil,
                locality: nil,
                subAdministrativeArea: nil,
                subLocality: nil,
                country: "대한민국"
            ),
            "대한민국"
        )
    }

    @MainActor
    func testDisablingWeatherLocationClearsCachedLocationData() {
        let cachedWeather = CurrentWeather(
            temperature: 20,
            apparentTemperature: 19,
            precipitation: 0,
            weatherCode: 0,
            isDay: true
        )
        let service = WeatherService(
            initialWeather: cachedWeather,
            initialLocationName: "이전 위치",
            initialLastUpdated: Date()
        )

        service.setLocationEnabled(false)

        XCTAssertNil(service.weather)
        XCTAssertNil(service.locationName)
        XCTAssertNil(service.lastUpdated)
        XCTAssertEqual(service.availability, .idle)
    }

    func testWeatherLocationMarqueePausesTravelsAndReturns() {
        let overflow: CGFloat = 36
        let speed: CGFloat = 18
        let pause = 1.2

        XCTAssertEqual(
            WeatherLocationMarquee.offset(
                elapsed: 0.6,
                overflow: overflow,
                speed: speed,
                pause: pause
            ),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WeatherLocationMarquee.offset(
                elapsed: 2.2,
                overflow: overflow,
                speed: speed,
                pause: pause
            ),
            -18,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WeatherLocationMarquee.offset(
                elapsed: 3.7,
                overflow: overflow,
                speed: speed,
                pause: pause
            ),
            -36,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WeatherLocationMarquee.offset(
                elapsed: 5.4,
                overflow: overflow,
                speed: speed,
                pause: pause
            ),
            -18,
            accuracy: 0.001
        )
        XCTAssertEqual(
            WeatherLocationMarquee.offset(elapsed: 2, overflow: 0),
            0,
            accuracy: 0.001
        )
    }

    func testWeatherPanelMetadataIsBalancedAroundTransparentSplit() {
        for isPortrait in [true, false] {
            let geometry = WeatherPanelGeometry(isPortrait: isPortrait)
            let locationDistance = geometry.panelCenterY - geometry.locationCenterY
            let apparentDistance = geometry.apparentTemperatureCenterY - geometry.panelCenterY

            XCTAssertEqual(locationDistance, apparentDistance, accuracy: 0.001)
            XCTAssertEqual(geometry.splitGap, isPortrait ? 4 : 3)
            XCTAssertEqual(geometry.temperatureOpticalOffset, isPortrait ? 2 : 2.5)
        }
    }

    func testBatteryProtectionOnlyStopsWhenLowAndUnplugged() {
        XCTAssertTrue(
            DeviceBatteryStatus(level: 0.2, powerState: .unplugged).shouldProtectBattery
        )
        XCTAssertFalse(
            DeviceBatteryStatus(level: 0.2, powerState: .charging).shouldProtectBattery
        )
        XCTAssertFalse(
            DeviceBatteryStatus(level: 0.21, powerState: .unplugged).shouldProtectBattery
        )
        XCTAssertFalse(
            DeviceBatteryStatus(level: nil, powerState: .unknown).shouldProtectBattery
        )
    }

    func testAmbientDimmingPolicyOnlyPausesForBrightScreenWhenEnabled() {
        XCTAssertTrue(
            AmbientDimmingPolicy.shouldPause(screenBrightness: 0.65, enabled: true)
        )
        XCTAssertFalse(
            AmbientDimmingPolicy.shouldPause(screenBrightness: 0.64, enabled: true)
        )
        XCTAssertFalse(
            AmbientDimmingPolicy.shouldPause(screenBrightness: 1, enabled: false)
        )
    }

    func testHorizontalDragAdjustsHoldDurationBetweenFiveSecondsAndFiveMinutes() {
        XCTAssertEqual(HoldDurationAdjustment.value(startingAt: 60, translation: 300), 300)
        XCTAssertEqual(HoldDurationAdjustment.value(startingAt: 60, translation: -300), 5)
        XCTAssertEqual(HoldDurationAdjustment.value(startingAt: 60, translation: 30), 90)
    }

    func testWakeMotionPolicyDetectsBedMovementButIgnoresMinorSensorNoise() {
        XCTAssertTrue(
            WakeMotionPolicy.detectsMovement(
                accelerationMagnitude: 0.18,
                rotationMagnitude: 0.1
            )
        )
        XCTAssertTrue(
            WakeMotionPolicy.detectsMovement(
                accelerationMagnitude: 0.02,
                rotationMagnitude: 1.6
            )
        )
        XCTAssertFalse(
            WakeMotionPolicy.detectsMovement(
                accelerationMagnitude: 0.03,
                rotationMagnitude: 0.2
            )
        )
    }

    func testFaceDownPostureUsesHysteresisToAvoidFlicker() {
        XCTAssertFalse(DevicePosturePolicy.isFaceDown(gravityZ: 0.81, currentlyFaceDown: false))
        XCTAssertTrue(DevicePosturePolicy.isFaceDown(gravityZ: 0.82, currentlyFaceDown: false))
        XCTAssertTrue(DevicePosturePolicy.isFaceDown(gravityZ: 0.7, currentlyFaceDown: true))
        XCTAssertFalse(DevicePosturePolicy.isFaceDown(gravityZ: 0.62, currentlyFaceDown: true))
        XCTAssertFalse(DevicePosturePolicy.isFaceDown(gravityZ: -1, currentlyFaceDown: false))
    }

    func testStoppedDeviceMotionGenerationRejectsQueuedUpdates() {
        let activeGeneration = UUID()
        XCTAssertTrue(DeviceMotionUpdatePolicy.shouldDeliver(
            capturedGeneration: activeGeneration,
            currentGeneration: activeGeneration,
            isActive: true
        ))
        XCTAssertFalse(DeviceMotionUpdatePolicy.shouldDeliver(
            capturedGeneration: UUID(),
            currentGeneration: activeGeneration,
            isActive: true
        ))
        XCTAssertFalse(DeviceMotionUpdatePolicy.shouldDeliver(
            capturedGeneration: activeGeneration,
            currentGeneration: activeGeneration,
            isActive: false
        ))
    }

    func testScreenTapBrightensWhileFadingAndDimsWhileHolding() {
        XCTAssertEqual(ScreenTapPolicy.action(for: .fading), .brighten)
        XCTAssertEqual(ScreenTapPolicy.action(for: .off), .brighten)
        XCTAssertEqual(ScreenTapPolicy.action(for: .holding), .dim)
    }

    func testLampEnvelopeHoldsThenFadesSmoothly() {
        let envelope = LampEnvelope(
            activatedAt: 10,
            holdDuration: 5,
            fadeDuration: 10,
            maximumIntensity: 0.8
        )

        XCTAssertEqual(envelope.intensity(at: 10), 0.8, accuracy: 0.0001)
        XCTAssertEqual(envelope.intensity(at: 15), 0.8, accuracy: 0.0001)
        XCTAssertEqual(envelope.intensity(at: 20), 0.4, accuracy: 0.0001)
        XCTAssertEqual(envelope.intensity(at: 25), 0, accuracy: 0.0001)
        XCTAssertTrue(envelope.isFinished(at: 25))
    }

    func testClapRequiresSharpRiseAndHonorsRefractoryWindow() {
        var detector = AudioEventDetector(
            configuration: AudioDetectorConfiguration(soundThresholdDB: -36)
        )

        _ = detector.analyze(rmsDB: -52, peakDB: -30, bufferDuration: 0.02, now: 1)
        let clap = detector.analyze(rmsDB: -12, peakDB: -2, bufferDuration: 0.02, now: 1.02)
        _ = detector.analyze(rmsDB: -52, peakDB: -30, bufferDuration: 0.02, now: 1.1)
        let repeatedClap = detector.analyze(rmsDB: -10, peakDB: -1, bufferDuration: 0.02, now: 1.12)
        _ = detector.analyze(rmsDB: -52, peakDB: -30, bufferDuration: 0.02, now: 3)
        let laterClap = detector.analyze(rmsDB: -10, peakDB: -1, bufferDuration: 0.02, now: 3.02)

        XCTAssertTrue(clap.clapDetected)
        XCTAssertFalse(repeatedClap.clapDetected)
        XCTAssertTrue(laterClap.clapDetected)
    }

    func testQuietFingerSnapUsesPeakRiseToWakeScreen() {
        var snapDetector = AudioEventDetector(
            configuration: AudioDetectorConfiguration(soundThresholdDB: -36)
        )
        _ = snapDetector.analyze(rmsDB: -58, peakDB: -42, bufferDuration: 0.02, now: 1)
        let fingerSnap = snapDetector.analyze(
            rmsDB: -53,
            peakDB: -17,
            bufferDuration: 0.02,
            now: 1.02
        )
        XCTAssertTrue(fingerSnap.clapDetected)
        XCTAssertFalse(fingerSnap.isAboveSoundThreshold)
    }

    func testSustainedSoundStartsOnlyAfterAttackDuration() {
        var detector = AudioEventDetector(
            configuration: AudioDetectorConfiguration(
                soundThresholdDB: -36,
                soundAttackDuration: 0.1
            )
        )

        var detections: [AudioDetection] = []
        for index in 0..<5 {
            detections.append(
                detector.analyze(
                    rmsDB: -25,
                    peakDB: -12,
                    bufferDuration: 0.02,
                    now: Double(index) * 0.02
                )
            )
        }

        XCTAssertFalse(detections[3].soundBegan)
        XCTAssertTrue(detections[4].soundBegan)
        XCTAssertTrue(detections[4].isAboveSoundThreshold)
    }

    func testBriefSoundDoesNotOpenRecordingGate() {
        var detector = AudioEventDetector(
            configuration: AudioDetectorConfiguration(
                soundThresholdDB: -36,
                soundAttackDuration: 0.1
            )
        )

        for index in 0..<3 {
            let detection = detector.analyze(
                rmsDB: -24,
                peakDB: -10,
                bufferDuration: 0.02,
                now: Double(index) * 0.02
            )
            XCTAssertFalse(detection.soundBegan)
        }

        let silence = detector.analyze(rmsDB: -60, peakDB: -55, bufferDuration: 0.02, now: 0.08)
        XCTAssertFalse(silence.soundBegan)
        XCTAssertFalse(silence.isAboveSoundThreshold)
    }

    func testSleepSoundClassifierRecognizesSnoreLikeSound() {
        var classifier = SleepSoundClassifier(releaseDuration: 0.2)
        var result: SleepSoundClassification?

        for index in 0..<10 {
            result = classifier.analyze(
                features: SleepSoundFeatures(
                    rmsDB: -24,
                    peakDB: -17,
                    zeroCrossingRate: 0.05,
                    lowFrequencyRatio: 0.75,
                    duration: 0.1
                ),
                detection: AudioDetection(
                    clapDetected: false,
                    soundBegan: index == 0,
                    isAboveSoundThreshold: true
                )
            )
        }
        for _ in 0..<2 {
            result = classifier.analyze(
                features: silentSleepSoundFeatures,
                detection: silentAudioDetection
            ) ?? result
        }

        XCTAssertEqual(result?.kind, .snore)
        XCTAssertGreaterThan(result?.confidence ?? 0, 0.58)
    }

    func testSleepSoundClassifierRecognizesMovementLikeSound() {
        var classifier = SleepSoundClassifier(releaseDuration: 0.2)
        var result: SleepSoundClassification?

        for index in 0..<3 {
            result = classifier.analyze(
                features: SleepSoundFeatures(
                    rmsDB: -28,
                    peakDB: -10,
                    zeroCrossingRate: 0.3,
                    lowFrequencyRatio: 0.15,
                    duration: 0.1
                ),
                detection: AudioDetection(
                    clapDetected: false,
                    soundBegan: index == 0,
                    isAboveSoundThreshold: true
                )
            )
        }
        for _ in 0..<2 {
            result = classifier.analyze(
                features: silentSleepSoundFeatures,
                detection: silentAudioDetection
            ) ?? result
        }

        XCTAssertEqual(result?.kind, .movement)
        XCTAssertGreaterThan(result?.confidence ?? 0, 0.55)
    }

    func testSleepSoundClassifierRecognizesSpeechLikeVariationAsSleepTalk() {
        var classifier = SleepSoundClassifier(releaseDuration: 0.2)
        var result: SleepSoundClassification?

        for index in 0..<12 {
            let rmsDB: Float = index.isMultiple(of: 2) ? -30 : -24
            result = classifier.analyze(
                features: SleepSoundFeatures(
                    rmsDB: rmsDB,
                    peakDB: rmsDB + 9,
                    zeroCrossingRate: 0.11,
                    lowFrequencyRatio: 0.42,
                    duration: 0.1
                ),
                detection: AudioDetection(
                    clapDetected: false,
                    soundBegan: index == 0,
                    isAboveSoundThreshold: true
                )
            )
        }
        for _ in 0..<2 {
            result = classifier.analyze(
                features: silentSleepSoundFeatures,
                detection: silentAudioDetection
            ) ?? result
        }

        XCTAssertEqual(result?.kind, .sleepTalk)
        XCTAssertGreaterThanOrEqual(result?.confidence ?? 0, 0.60)
        XCTAssertTrue(result.map(SleepSoundRecordingPolicy.shouldKeep) ?? false)
        XCTAssertFalse(result.map(SleepSoundWakePolicy.shouldWake) ?? true)
    }

    func testSteadyBackgroundSoundIsNotSavedAsSleepTalk() {
        var classifier = SleepSoundClassifier(releaseDuration: 0.2)
        var result: SleepSoundClassification?

        for index in 0..<12 {
            result = classifier.analyze(
                features: SleepSoundFeatures(
                    rmsDB: -27,
                    peakDB: -18,
                    zeroCrossingRate: 0.11,
                    lowFrequencyRatio: 0.42,
                    duration: 0.1
                ),
                detection: AudioDetection(
                    clapDetected: false,
                    soundBegan: index == 0,
                    isAboveSoundThreshold: true
                )
            )
        }
        for _ in 0..<2 {
            result = classifier.analyze(
                features: silentSleepSoundFeatures,
                detection: silentAudioDetection
            ) ?? result
        }

        XCTAssertEqual(result?.kind, .other)
        XCTAssertFalse(result.map(SleepSoundRecordingPolicy.shouldKeep) ?? true)
    }

    func testOnlySnoreAndSleepTalkCandidatesAreKeptWhileMovementWakes() {
        let snore = SleepSoundClassification(kind: .snore, confidence: 0.7, duration: 1)
        let sleepTalk = SleepSoundClassification(kind: .sleepTalk, confidence: 0.7, duration: 1)
        let movement = SleepSoundClassification(kind: .movement, confidence: 0.7, duration: 0.4)
        let other = SleepSoundClassification(kind: .other, confidence: 0.99, duration: 2)

        XCTAssertTrue(SleepSoundRecordingPolicy.shouldKeep(snore))
        XCTAssertTrue(SleepSoundRecordingPolicy.shouldKeep(sleepTalk))
        XCTAssertFalse(SleepSoundRecordingPolicy.shouldKeep(movement))
        XCTAssertFalse(SleepSoundRecordingPolicy.shouldKeep(other))
        XCTAssertFalse(SleepSoundWakePolicy.shouldWake(snore))
        XCTAssertFalse(SleepSoundWakePolicy.shouldWake(sleepTalk))
        XCTAssertTrue(SleepSoundWakePolicy.shouldWake(movement))
        XCTAssertFalse(SleepSoundWakePolicy.shouldWake(other))
    }

    func testClipRecorderCreatesReadableM4AWithBoundaryPadding() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let saved = expectation(description: "clip saved")
        var savedURL: URL?
        let recorder = ClipSegmentRecorder(
            directory: directory,
            onRecordingChanged: { _ in },
            onSaved: { url in
                savedURL = url
                saved.fulfill()
            }
        )
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )

        recorder.process(
            buffer: try makeBuffer(format: format),
            detection: AudioDetection(
                clapDetected: false,
                soundBegan: true,
                isAboveSoundThreshold: true
            ),
            now: 1
        )
        recorder.process(
            buffer: try makeBuffer(format: format),
            detection: AudioDetection(
                clapDetected: false,
                soundBegan: false,
                isAboveSoundThreshold: true
            ),
            now: 1.1
        )
        recorder.approveCurrentClip()
        XCTAssertNil(savedURL, "승인 뒤에도 1.4초 후행 여백이 끝나기 전에는 파일을 닫지 않습니다.")
        let bufferDuration = 1_024.0 / format.sampleRate
        var now = 1.1
        while now + bufferDuration < 2.5 {
            now += bufferDuration
            recorder.process(
                buffer: try makeBuffer(format: format),
                detection: silentAudioDetection,
                now: now
            )
            XCTAssertNil(savedURL)
        }
        recorder.process(
            buffer: try makeBuffer(format: format),
            detection: silentAudioDetection,
            now: 2.5 + bufferDuration
        )

        wait(for: [saved], timeout: 1)
        let url = try XCTUnwrap(savedURL)
        XCTAssertEqual(url.pathExtension, "m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let file = try AVAudioFile(forReading: url)
        let recordedDuration = Double(file.length) / file.processingFormat.sampleRate
        XCTAssertGreaterThanOrEqual(recordedDuration, 1.35)
    }

    func testClipRecorderRollsContinuousSoundIntoANewFileAtMaximumDuration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let savedTwice = expectation(description: "two clips saved")
        savedTwice.expectedFulfillmentCount = 2
        var savedURLs: [URL] = []
        let recorder = ClipSegmentRecorder(
            directory: directory,
            onRecordingChanged: { _ in },
            onSaved: { url in
                savedURLs.append(url)
                savedTwice.fulfill()
            },
            postRollDuration: 0.1,
            maximumClipDuration: 0.05
        )
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let began = AudioDetection(
            clapDetected: false,
            soundBegan: true,
            isAboveSoundThreshold: true
        )
        let continuing = AudioDetection(
            clapDetected: false,
            soundBegan: false,
            isAboveSoundThreshold: true
        )
        let silence = AudioDetection(
            clapDetected: false,
            soundBegan: false,
            isAboveSoundThreshold: false
        )

        recorder.process(buffer: try makeBuffer(format: format), detection: began, now: 1)
        recorder.process(buffer: try makeBuffer(format: format), detection: continuing, now: 1.1)
        recorder.process(buffer: try makeBuffer(format: format), detection: continuing, now: 1.12)
        XCTAssertTrue(savedURLs.isEmpty, "분류 전 90초 분할 파일은 목록에 공개하지 않아야 합니다.")
        recorder.approveCurrentClip()
        recorder.process(buffer: try makeBuffer(format: format), detection: silence, now: 1.3)

        wait(for: [savedTwice], timeout: 1)
        XCTAssertEqual(Set(savedURLs).count, 2)
        for url in savedURLs {
            XCTAssertEqual(url.deletingLastPathComponent(), directory)
            let file = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(file.length, 0)
        }
    }

    func testClipRecorderBoundsPendingSegmentsForContinuousLoudSound() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var savedURLs: [URL] = []
        let recorder = ClipSegmentRecorder(
            directory: directory,
            onRecordingChanged: { _ in },
            onSaved: { savedURLs.append($0) },
            maximumClipDuration: 0.05,
            maximumPendingSegmentCount: 2
        )
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let began = AudioDetection(
            clapDetected: false,
            soundBegan: true,
            isAboveSoundThreshold: true
        )
        let continuing = AudioDetection(
            clapDetected: false,
            soundBegan: false,
            isAboveSoundThreshold: true
        )

        recorder.process(buffer: try makeBuffer(format: format), detection: began, now: 1)
        recorder.process(buffer: try makeBuffer(format: format), detection: continuing, now: 1.1)
        recorder.process(buffer: try makeBuffer(format: format), detection: continuing, now: 1.2)

        XCTAssertTrue(savedURLs.isEmpty)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    func testClipRecorderDiscardsNonSnoreCandidate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var savedURLs: [URL] = []
        let recorder = ClipSegmentRecorder(
            directory: directory,
            onRecordingChanged: { _ in },
            onSaved: { savedURLs.append($0) }
        )
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )

        recorder.process(
            buffer: try makeBuffer(format: format),
            detection: AudioDetection(
                clapDetected: false,
                soundBegan: true,
                isAboveSoundThreshold: true
            ),
            now: 1
        )
        recorder.discardCurrentClip()

        XCTAssertTrue(savedURLs.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.isEmpty)
    }

    func testClipRecorderDiscardsEveryPendingRolloverBeforeClassification() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var savedURLs: [URL] = []
        let recorder = ClipSegmentRecorder(
            directory: directory,
            onRecordingChanged: { _ in },
            onSaved: { savedURLs.append($0) },
            postRollDuration: 10,
            maximumClipDuration: 0.05
        )
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let began = AudioDetection(
            clapDetected: false,
            soundBegan: true,
            isAboveSoundThreshold: true
        )
        let continuing = AudioDetection(
            clapDetected: false,
            soundBegan: false,
            isAboveSoundThreshold: true
        )

        recorder.process(buffer: try makeBuffer(format: format), detection: began, now: 1)
        recorder.process(buffer: try makeBuffer(format: format), detection: continuing, now: 1.1)
        recorder.process(buffer: try makeBuffer(format: format), detection: continuing, now: 1.2)

        XCTAssertTrue(savedURLs.isEmpty)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).isEmpty
        )

        recorder.discardCurrentClip()

        XCTAssertTrue(savedURLs.isEmpty)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    @MainActor
    func testClipRecorderNeverExposesOrRecoversUnapprovedStagingAudio() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let stagingDirectory = directory.appendingPathComponent(".Pending", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )
        let staleURL = stagingDirectory.appendingPathComponent("stale.m4a")
        try writeAudioFile(at: staleURL, format: format, bufferCount: 1)

        XCTAssertTrue(FileManager.default.fileExists(atPath: staleURL.path))
        let initialLibrary = RecordingLibrary(directory: directory)
        XCTAssertTrue(initialLibrary.clips.isEmpty)

        _ = ClipSegmentRecorder(
            directory: directory,
            onRecordingChanged: { _ in },
            onSaved: { _ in }
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory.path))
        let recoveredLibrary = RecordingLibrary(directory: directory)
        XCTAssertTrue(recoveredLibrary.clips.isEmpty)
    }

    func testApprovedClipRemainsApprovedWhenARejectedEventFollows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var savedURLs: [URL] = []
        let recorder = ClipSegmentRecorder(
            directory: directory,
            onRecordingChanged: { _ in },
            onSaved: { savedURLs.append($0) }
        )
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        recorder.process(
            buffer: try makeBuffer(format: format),
            detection: AudioDetection(
                clapDetected: false,
                soundBegan: true,
                isAboveSoundThreshold: true
            ),
            now: 1
        )
        recorder.approveCurrentClip()
        recorder.rejectCurrentClip()
        recorder.process(
            buffer: try makeBuffer(format: format),
            detection: silentAudioDetection,
            now: 3
        )

        XCTAssertEqual(savedURLs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURLs[0].path))
    }

    func testLegacySleepGroupingUsesSeparateNinetyMinuteEstimateFromPreviousClipEnd() {
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        let first = RecordingClip(
            url: URL(fileURLWithPath: "/tmp/legacy-first.m4a"),
            createdAt: start,
            duration: 120
        )
        let exactBoundary = RecordingClip(
            url: URL(fileURLWithPath: "/tmp/legacy-boundary.m4a"),
            createdAt: start.addingTimeInterval(120 + 90 * 60),
            duration: 60
        )
        let justOutsideBoundary = RecordingClip(
            url: URL(fileURLWithPath: "/tmp/legacy-new-sleep.m4a"),
            createdAt: exactBoundary.createdAt.addingTimeInterval(60 + 90 * 60 + 0.001),
            duration: 30
        )

        let groups = SleepSessionGroupingPolicy.inferredGroups(
            from: [justOutsideBoundary, first, exactBoundary]
        )

        XCTAssertEqual(SleepSessionGroupingPolicy.legacyRecordingGap, 90 * 60)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].clips.map(\.url), [first.url, exactBoundary.url])
        XCTAssertEqual(groups[1].clips.map(\.url), [justOutsideBoundary.url])
        XCTAssertTrue(groups.allSatisfy(\.isInferred))
    }

    @MainActor
    func testSleepModeSessionsResumeThroughThirtyMinutesButSplitAfterward() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstStart = Date(timeIntervalSinceReferenceDate: 20_000)
        let firstEnd = firstStart.addingTimeInterval(2 * 60 * 60)
        let firstLibrary = RecordingLibrary(directory: directory)
        let firstSessionID = firstLibrary.beginSleepSession(at: firstStart)
        firstLibrary.endSleepSession(id: firstSessionID, at: firstEnd)

        // Manifest를 다시 읽어도 실제 잠자기 모드 종료 시각을 기준으로 이어야 한다.
        let reloadedLibrary = RecordingLibrary(directory: directory)
        let exactBoundaryID = reloadedLibrary.beginSleepSession(
            at: firstEnd.addingTimeInterval(30 * 60)
        )
        XCTAssertEqual(SleepSessionGroupingPolicy.sleepModeResumeGap, 30 * 60)
        XCTAssertEqual(exactBoundaryID, firstSessionID)

        let resumedEnd = firstEnd.addingTimeInterval(45 * 60)
        reloadedLibrary.endSleepSession(id: exactBoundaryID, at: resumedEnd)
        let nextSessionID = reloadedLibrary.beginSleepSession(
            at: resumedEnd.addingTimeInterval(30 * 60 + 0.001)
        )
        XCTAssertNotEqual(nextSessionID, firstSessionID)
    }

    @MainActor
    func testDeletingAllRecordingsKeepsTheCurrentSleepModeSessionOpen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let library = RecordingLibrary(directory: directory)
        let sessionStart = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 8, day: 8, hour: 1)
            )
        )
        let sessionID = library.beginSleepSession(at: sessionStart)
        let firstURL = directory.appendingPathComponent("sleep-sound-20260808-010100-000.m4a")
        try writeAudioFile(at: firstURL, format: format, bufferCount: 1)
        library.add(firstURL, sessionID: sessionID)
        XCTAssertEqual(library.recordingSessions.first?.isInferred, false)

        try library.deleteAll()
        XCTAssertTrue(library.clips.isEmpty)

        let laterURL = directory.appendingPathComponent("sleep-sound-20260808-010500-000.m4a")
        try writeAudioFile(at: laterURL, format: format, bufferCount: 1)
        library.add(laterURL)

        let session = try XCTUnwrap(library.recordingSessions.first)
        XCTAssertEqual(session.id, "session-\(sessionID.uuidString)")
        XCTAssertFalse(session.isInferred)
        XCTAssertEqual(session.clips.map(\.url), [laterURL])
    }

    @MainActor
    func testDeletingRecordingsDoesNotBreakThirtyMinuteSleepModeResumeWindow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = RecordingLibrary(directory: directory)
        let firstEnd = Date(timeIntervalSinceReferenceDate: 40_000)
        let firstID = library.beginSleepSession(at: firstEnd.addingTimeInterval(-2 * 60 * 60))
        library.endSleepSession(id: firstID, at: firstEnd)

        try library.deleteAll(at: firstEnd.addingTimeInterval(60))
        let resumedID = library.beginSleepSession(
            at: firstEnd.addingTimeInterval(SleepSessionGroupingPolicy.sleepModeResumeGap)
        )
        XCTAssertEqual(resumedID, firstID)

        let resumedEnd = firstEnd.addingTimeInterval(45 * 60)
        library.endSleepSession(id: resumedID, at: resumedEnd)
        try library.deleteAll(at: resumedEnd)
        let nextID = library.beginSleepSession(
            at: resumedEnd.addingTimeInterval(
                SleepSessionGroupingPolicy.sleepModeResumeGap + 0.001
            )
        )
        XCTAssertNotEqual(nextID, firstID)
    }

    @MainActor
    func testDeletingAllAlsoRemovesAudioNotYetIndexedByTheLibrary() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let library = RecordingLibrary(directory: directory)
        let lateCallbackURL = directory.appendingPathComponent(
            "sleep-sound-20260808-021500-000.m4a"
        )
        try writeAudioFile(at: lateCallbackURL, format: format, bufferCount: 1)
        let pendingDirectory = directory.appendingPathComponent(".Pending", isDirectory: true)
        try FileManager.default.createDirectory(at: pendingDirectory, withIntermediateDirectories: true)
        let pendingURL = pendingDirectory.appendingPathComponent("pending.m4a")
        try writeAudioFile(at: pendingURL, format: format, bufferCount: 1)

        XCTAssertTrue(library.clips.isEmpty)
        try library.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: lateCallbackURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pendingURL.path))

        library.add(lateCallbackURL)
        XCTAssertTrue(library.clips.isEmpty)
    }

    @MainActor
    func testAbnormalRecoveryNeverUsesTheLastRecordingTimeAsModeExit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let sessionStart = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 8, day: 8, hour: 1)
            )
        )
        let firstLibrary = RecordingLibrary(directory: directory)
        let firstSessionID = firstLibrary.beginSleepSession(at: sessionStart)
        let muchLaterClipURL = directory.appendingPathComponent(
            "sleep-sound-20260808-060000-000.m4a"
        )
        try writeAudioFile(at: muchLaterClipURL, format: format, bufferCount: 1)
        firstLibrary.add(muchLaterClipURL, sessionID: firstSessionID)

        let recoveredLibrary = RecordingLibrary(directory: directory)
        let nextSessionID = recoveredLibrary.beginSleepSession(
            at: sessionStart.addingTimeInterval(30 * 60 + 0.001)
        )

        XCTAssertNotEqual(nextSessionID, firstSessionID)
    }

    @MainActor
    func testReloadBeforeSavedCallbackStillAssociatesClipWithExactModeSession() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let library = RecordingLibrary(directory: directory)
        let sessionStart = try XCTUnwrap(
            Calendar.current.date(
                from: DateComponents(year: 2026, month: 8, day: 8, hour: 1)
            )
        )
        let sessionID = library.beginSleepSession(at: sessionStart)
        let movedBeforeCallbackURL = directory.appendingPathComponent(
            "sleep-sound-20260808-011500-000.m4a"
        )
        try writeAudioFile(at: movedBeforeCallbackURL, format: format, bufferCount: 1)

        library.reload()
        library.add(movedBeforeCallbackURL)

        let session = try XCTUnwrap(library.recordingSessions.first)
        XCTAssertEqual(session.id, "session-\(sessionID.uuidString)")
        XCTAssertFalse(session.isInferred)
        XCTAssertEqual(session.clips.map(\.url), [movedBeforeCallbackURL])
    }

    func testSleepSessionTimelineMarkerClampsToSessionBounds() {
        let start = Date(timeIntervalSinceReferenceDate: 30_000)
        let end = start.addingTimeInterval(100)
        let before = RecordingClip(
            url: URL(fileURLWithPath: "/tmp/before.m4a"),
            createdAt: start.addingTimeInterval(-10),
            duration: 1
        )
        let middle = RecordingClip(
            url: URL(fileURLWithPath: "/tmp/middle.m4a"),
            createdAt: start.addingTimeInterval(50),
            duration: 1
        )
        let after = RecordingClip(
            url: URL(fileURLWithPath: "/tmp/after.m4a"),
            createdAt: end.addingTimeInterval(10),
            duration: 1
        )

        XCTAssertEqual(
            SleepSessionGroupingPolicy.markerFraction(
                for: before,
                sessionStart: start,
                sessionEnd: end
            ),
            0
        )
        XCTAssertEqual(
            SleepSessionGroupingPolicy.markerFraction(
                for: middle,
                sessionStart: start,
                sessionEnd: end
            ),
            0.5,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            SleepSessionGroupingPolicy.markerFraction(
                for: after,
                sessionStart: start,
                sessionEnd: end
            ),
            1
        )
    }

    @MainActor
    func testStartleEventsPersistWithoutARecordingAndKeepTheirDuration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let start = Date(timeIntervalSinceReferenceDate: 90_000)
        let library = RecordingLibrary(directory: directory)
        let sessionID = library.beginSleepSession(at: start)
        let eventID = try XCTUnwrap(
            library.beginStartleEvent(sessionID: sessionID, at: start.addingTimeInterval(20))
        )
        library.endStartleEvent(id: eventID, at: start.addingTimeInterval(32))
        library.endSleepSession(id: sessionID, at: start.addingTimeInterval(120))

        let reloaded = RecordingLibrary(directory: directory)
        let session = try XCTUnwrap(reloaded.recordingSessions.first)
        XCTAssertTrue(session.clips.isEmpty)
        XCTAssertEqual(session.startleEvents.count, 1)
        XCTAssertEqual(session.startleEvents[0].startedAt, start.addingTimeInterval(20))
        XCTAssertEqual(session.startleEvents[0].endedAt, start.addingTimeInterval(32))
    }

    @MainActor
    func testRecordingPlaybackBoostDefaultsToTwoTimes() {
        XCTAssertTrue(RecordingPlayer().boostEnabled)
    }

    @MainActor
    func testPartialBatchDeletionReloadsAndCleansSuccessfullyDeletedReferences() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let start = Date(timeIntervalSinceReferenceDate: 80_000)
        let library = RecordingLibrary(directory: directory)
        let sessionID = library.beginSleepSession(at: start)
        let url = directory.appendingPathComponent("sleep-sound-20010102-061320-000.m4a")
        try writeAudioFile(at: url, format: format, bufferCount: 1)
        library.add(url, sessionID: sessionID)
        let clip = try XCTUnwrap(library.clips.first)

        XCTAssertThrowsError(try library.delete([clip, clip]))
        XCTAssertTrue(library.clips.isEmpty)
        XCTAssertTrue(library.recordingSessions.allSatisfy(\.clips.isEmpty))
    }

    @MainActor
    func testRecordingLibraryMergesSelectedAndTodayClipsChronologically() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let olderURL = directory.appendingPathComponent("sleep-sound-20260807-010000-000.m4a")
        let newerURL = directory.appendingPathComponent("sleep-sound-20260807-020000-000.m4a")
        let previousDayURL = directory.appendingPathComponent("sleep-sound-20260806-230000-000.m4a")
        try writeAudioFile(at: newerURL, format: format, bufferCount: 3)
        try writeAudioFile(at: olderURL, format: format, bufferCount: 2)
        try writeAudioFile(at: previousDayURL, format: format, bufferCount: 4)

        let library = RecordingLibrary(directory: directory)
        let older = try XCTUnwrap(library.clips.first { $0.url == olderURL })
        let newer = try XCTUnwrap(library.clips.first { $0.url == newerURL })
        let previousDay = try XCTUnwrap(library.clips.first { $0.url == previousDayURL })
        let selectedDuration = older.duration + previousDay.duration
        let selectedMerge = try await library.merge([older, previousDay], kind: .selected)

        XCTAssertEqual(
            selectedMerge.mergedTitle,
            previousDay.createdAt.formatted(.dateTime.hour().minute().second())
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: selectedMerge.url.path))
        XCTAssertEqual(selectedMerge.createdAt, previousDay.createdAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: olderURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previousDayURL.path))
        XCTAssertEqual(library.clips.count, 4)
        XCTAssertEqual(selectedMerge.duration, selectedDuration + 0.5, accuracy: 0.12)

        let mergeDate = try XCTUnwrap(
            Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 7, hour: 12))
        )
        let todayDuration = library.mergeableClips(on: mergeDate).reduce(0) { $0 + $1.duration }
        let todayMerge = try await library.mergeToday(on: mergeDate)

        XCTAssertEqual(todayMerge.mergedTitle, "오늘 녹음 합본")
        XCTAssertEqual(todayMerge.createdAt, older.createdAt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: todayMerge.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: selectedMerge.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newerURL.path))
        XCTAssertEqual(library.clips.count, 5)
        XCTAssertEqual(todayMerge.duration, todayDuration + 0.5, accuracy: 0.12)

        XCTAssertEqual(
            RecordingSelectionPolicy.all(in: library.mergeableClips),
            Set([olderURL, newerURL, previousDayURL])
        )
        XCTAssertEqual(
            RecordingSelectionPolicy.today(
                in: library.mergeableClips,
                date: mergeDate
            ),
            Set([olderURL, newerURL])
        )

        let destructiveMerge = try await library.merge(
            [older, newer],
            kind: .selected,
            deleteSources: true
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: destructiveMerge.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: olderURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newerURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previousDayURL.path))
        XCTAssertEqual(library.clips.count, 4)
    }

    private func writeAudioFile(
        at url: URL,
        format: AVAudioFormat,
        bufferCount: Int
    ) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: 48_000
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        for _ in 0..<bufferCount {
            try file.write(from: makeBuffer(format: format))
        }
    }

    private var silentSleepSoundFeatures: SleepSoundFeatures {
        SleepSoundFeatures(
            rmsDB: -70,
            peakDB: -65,
            zeroCrossingRate: 0,
            lowFrequencyRatio: 0,
            duration: 0.1
        )
    }

    private var silentAudioDetection: AudioDetection {
        AudioDetection(
            clapDetected: false,
            soundBegan: false,
            isAboveSoundThreshold: false
        )
    }

    private func makeBuffer(format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_024)
        )
        buffer.frameLength = 1_024
        guard let samples = buffer.floatChannelData?[0] else {
            XCTFail("Expected Float32 PCM")
            return buffer
        }
        for index in 0..<Int(buffer.frameLength) {
            samples[index] = sin(Float(index) * 0.05) * 0.12
        }
        return buffer
    }
}

final class BoyisoProtocolTests: XCTestCase {
    func testKoreanFirstBrandingKeepsAppAndProtocolIdentitiesSeparate() {
        XCTAssertEqual(BoyisoBranding.primaryName, "보이소")
        XCTAssertEqual(BoyisoBranding.descriptor, "BOISO · 보이는 소리")
        XCTAssertEqual(BoyisoBranding.representativeIconAccessibilityLabel, "보이소")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "S.tand")
        XCTAssertEqual(BoyisoInvitation.scheme, "stand")
        XCTAssertEqual(BoyisoInvitation.host, "boyiso")
    }

    func testConnectedDisplayNameUpdateTrimsPersistsAndRejectsEmptyName() {
        let suite = "BoyisoProtocolTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = BoyisoConnectivityService(defaults: defaults)

        XCTAssertTrue(service.updateDisplayName("  아이 방  "))
        XCTAssertEqual(service.deviceName, "아이 방")
        XCTAssertEqual(service.currentParticipant.name, "아이 방")
        XCTAssertFalse(service.updateDisplayName("   \n"))
        XCTAssertEqual(service.deviceName, "아이 방")
    }

    func testEveryParticipantCanReuseTheSameInvitationAfterLeavingAndRejoining() throws {
        let invitation = BoyisoInvitation.make()
        let sharedURL = invitation.url

        XCTAssertEqual(try BoyisoInvitation(url: sharedURL), invitation)
        XCTAssertEqual(try BoyisoInvitation(url: sharedURL), invitation)
    }

    func testDisconnectedRoomShowsReconnectStatusAfterItPreviouslyHadAPeer() {
        XCTAssertEqual(
            BoyisoConnectionStatusCopy.summary(hasPeers: false, hadConnectedPeer: true, hasIssue: false),
            "다시 연결 중"
        )
        XCTAssertEqual(
            BoyisoConnectionStatusCopy.summary(hasPeers: false, hadConnectedPeer: false, hasIssue: false),
            "함께할 사람이 연결되기를 기다리고 있습니다."
        )
        XCTAssertEqual(
            BoyisoConnectionStatusCopy.summary(hasPeers: true, hadConnectedPeer: true, hasIssue: false),
            "함께 연결되어 있습니다."
        )
        XCTAssertNil(BoyisoConnectionStatusCopy.detail(
            hasPeers: true,
            hadConnectedPeer: true,
            hasIssue: false
        ))
        XCTAssertEqual(BoyisoConnectionStatusCopy.detail(
            hasPeers: false,
            hadConnectedPeer: true,
            hasIssue: false
        ), "다시 연결 중")
        XCTAssertEqual(BoyisoConnectionStatusCopy.detail(
            hasPeers: false,
            hadConnectedPeer: false,
            hasIssue: false
        ), "함께할 사람이 연결되기를 기다리고 있습니다.")
    }

    func testBoyisoBackgroundModesDeclareAudioAndBothBluetoothRoles() {
        let modes = Set(Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? [])
        XCTAssertTrue(modes.isSuperset(of: ["audio", "bluetooth-central", "bluetooth-peripheral"]))
    }

    func testBoyisoInAppBannerExpiresAndOldTimerCannotDismissNewEvent() {
        let oldEventID = UUID()
        let newEventID = UUID()

        XCTAssertEqual(BoyisoEventBannerPolicy.displayDurationSeconds, 5)
        XCTAssertTrue(BoyisoEventBannerPolicy.shouldDismiss(
            displayedEventID: oldEventID,
            timerEventID: oldEventID
        ))
        XCTAssertFalse(BoyisoEventBannerPolicy.shouldDismiss(
            displayedEventID: newEventID,
            timerEventID: oldEventID
        ))
        XCTAssertFalse(BoyisoEventBannerPolicy.shouldDismiss(
            displayedEventID: nil,
            timerEventID: oldEventID
        ))
    }

    func testSoundDetectionOverlayUsesExactProductCopy() {
        XCTAssertEqual(BoyisoOverlayKind.soundDetected.primaryMessage, "말할 사람의 소리가 감지되었습니다.")
        XCTAssertEqual(
            BoyisoOverlayKind.soundDetected.accessibilityLabel(sender: "아이 방"),
            "말할 사람의 소리가 감지되었습니다. 보낸 기기, 아이 방"
        )
        XCTAssertEqual(BoyisoOverlayKind.soundDetected.imageName, "BoyisoCryingChild")
    }

    func testParticipantSectionsIncludeCurrentDeviceFirstAndKeepEmptyGroup() {
        let currentID = UUID()
        let current = BoyisoPeerStatus(
            id: currentID,
            name: "엄마",
            role: .host,
            lastSeen: Date(),
            monitoring: false,
            batteryPercent: 82,
            displayMode: .mate,
            sessionActive: true,
            transports: []
        )

        let sections = BoyisoParticipantSections(current: current, peers: [])

        XCTAssertEqual(sections.totalCount, 1)
        XCTAssertEqual(sections.hosts.map(\.id), [currentID])
        XCTAssertTrue(sections.hosts[0].isCurrentDevice)
        XCTAssertEqual(sections.hosts[0].state, "연결됨")
        XCTAssertEqual(sections.hosts[0].connectionLabels, ["이 기기"])
        XCTAssertFalse(sections.hasDuplicateNames)
        XCTAssertEqual(
            sections.hosts[0].accessibilityLabel,
            "엄마, 나, 볼 사람, 연결됨, 배터리 82퍼센트, 연결 경로, 이 기기"
        )
        XCTAssertTrue(sections.guests.isEmpty)
    }

    func testParticipantSectionsUseFixedRoleOrderAndGuestSensingState() {
        let currentID = UUID()
        let current = BoyisoPeerStatus(
            id: currentID,
            name: "아이",
            role: .guest,
            lastSeen: Date(),
            monitoring: true,
            batteryPercent: nil,
            displayMode: .mate,
            sessionActive: true,
            transports: []
        )
        let host = BoyisoPeerStatus(
            id: UUID(), name: "아빠", role: .host, lastSeen: Date(), monitoring: false,
            batteryPercent: 44, displayMode: .object, sessionActive: false, transports: [.localNetwork]
        )
        let waitingGuest = BoyisoPeerStatus(
            id: UUID(), name: "동생", role: .guest, lastSeen: Date(), monitoring: false,
            batteryPercent: nil, displayMode: .mate, sessionActive: true, transports: [.bluetooth]
        )

        let sections = BoyisoParticipantSections(current: current, peers: [waitingGuest, host])

        XCTAssertEqual(sections.totalCount, 3)
        XCTAssertEqual(sections.hosts.map(\.name), ["아빠"])
        XCTAssertEqual(sections.guests.map(\.name), ["아이", "동생"])
        XCTAssertEqual(sections.guests.map(\.state), ["감지 중", "대기 중"])
        XCTAssertTrue(sections.guests[0].isCurrentDevice)
    }

    func testParticipantSectionsMergeOnlyMatchingSourceIDsAndShowOnlyReportedTransports() {
        let current = BoyisoPeerStatus(
            id: UUID(), name: "나", role: .host, lastSeen: Date(), monitoring: false,
            batteryPercent: 90, displayMode: .mate, sessionActive: true, transports: []
        )
        let sharedID = UUID()
        let wifiCopy = BoyisoPeerStatus(
            id: sharedID, name: "SM-T500", role: .host, lastSeen: Date(timeIntervalSince1970: 10),
            monitoring: false, batteryPercent: 70, displayMode: .mate, sessionActive: true,
            transports: [.localNetwork]
        )
        let bluetoothCopy = BoyisoPeerStatus(
            id: sharedID, name: "SM-T500", role: .host, lastSeen: Date(timeIntervalSince1970: 20),
            monitoring: false, batteryPercent: 71, displayMode: .mate, sessionActive: true,
            transports: [.bluetooth]
        )
        let sameNameDifferentID = BoyisoPeerStatus(
            id: UUID(), name: "SM-T500", role: .host, lastSeen: Date(timeIntervalSince1970: 30),
            monitoring: false, batteryPercent: 72, displayMode: .mate, sessionActive: true,
            transports: [.localNetwork]
        )

        let sections = BoyisoParticipantSections(
            current: current,
            peers: [wifiCopy, bluetoothCopy, sameNameDifferentID]
        )

        XCTAssertEqual(sections.totalCount, 3)
        XCTAssertEqual(sections.hosts.filter { $0.name == "SM-T500" }.count, 2)
        XCTAssertTrue(sections.hasDuplicateNames)
        XCTAssertEqual(sections.hosts.first { $0.id == sharedID }?.batteryPercent, 71)
        XCTAssertEqual(
            sections.hosts.first { $0.id == sharedID }?.connectionLabels,
            ["Wi-Fi", "Bluetooth"]
        )
        XCTAssertFalse(
            sections.hosts.first { $0.id == sharedID }?.connectionLabels.contains("인터넷") ?? true
        )
        XCTAssertEqual(
            sections.hosts.first { $0.id == sameNameDifferentID.id }?.connectionLabels,
            ["Wi-Fi"]
        )
    }

    func testDuplicateFingerSnapMeshEventDoesNotRefreshPeerOrRepeatReaction() {
        let suite = "BoyisoProtocolTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = BoyisoConnectivityService(defaults: defaults)
        let event = BoyisoEvent(
            sourceID: UUID(), sourceName: "아이 방", role: .guest, kind: .sound,
            detail: "finger_snap", monitoring: true, batteryPercent: 81,
            displayMode: .mate, sessionActive: true
        )
        var reactions: [BoyisoEvent] = []
        service.onRemoteEvent = { reactions.append($0) }

        service.accept(event, through: .localNetwork)
        let firstUpdate = expectation(description: "first peer update")
        DispatchQueue.main.async { firstUpdate.fulfill() }
        wait(for: [firstUpdate], timeout: 1)
        let first = service.activePeers.first
        XCTAssertEqual(reactions, [event])
        XCTAssertEqual(BoyisoReactionPolicy.chimeCount(for: event), 2)

        service.accept(event, through: .bluetooth)
        let duplicateDelivery = expectation(description: "duplicate delivery ignored")
        DispatchQueue.main.async { duplicateDelivery.fulfill() }
        wait(for: [duplicateDelivery], timeout: 1)
        let second = service.activePeers.first

        XCTAssertEqual(service.activePeers.count, 1)
        XCTAssertEqual(first?.lastSeen, second?.lastSeen)
        XCTAssertEqual(second?.transports, [.localNetwork])
        XCTAssertEqual(reactions, [event])
        XCTAssertEqual(service.lastRemoteEvent, event)
    }

    func testEncryptedLANFrameRoundTripsWithoutSendingRawAudio() throws {
        let invitation = BoyisoInvitation.make()
        let event = BoyisoEvent(
            sourceID: UUID(),
            sourceName: "말할 사람",
            role: .guest,
            kind: .sound,
            intensity: 0.82,
            detail: "big_sound",
            monitoring: true,
            batteryPercent: 78,
            displayMode: .mate,
            sessionActive: true
        )

        let frame = try BoyisoCodec.lanFrame(for: event, invitation: invitation)

        XCTAssertFalse(String(decoding: frame, as: UTF8.self).contains("말할 사람"))
        XCTAssertEqual(
            try BoyisoCodec.openLANFrame(frame, invitation: invitation),
            event
        )
    }

    func testBoyisoWireCanonicalizesUUIDCaseAndDecodesLegacyUppercase() throws {
        let event = BoyisoEvent(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            sourceID: UUID(uuidString: "BA65AAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            sourceName: "말할 사람",
            role: .guest,
            kind: .sound,
            monitoring: true,
            batteryPercent: 80
        )
        let wire = try BoyisoCodec.encodeWire(event)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: wire) as? [String: Any])

        XCTAssertEqual(object["id"] as? String, event.id.uuidString.lowercased())
        XCTAssertEqual(object["sourceID"] as? String, event.sourceID.uuidString.lowercased())

        object["id"] = event.id.uuidString.uppercased()
        object["sourceID"] = event.sourceID.uuidString.uppercased()
        let legacyUppercaseWire = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(BoyisoEvent.self, from: legacyUppercaseWire), event)
    }

    func testBluetoothFragmentsReassembleOutOfOrder() throws {
        let invitation = BoyisoInvitation.make()
        let event = BoyisoEvent(
            sourceID: UUID(),
            sourceName: "참여자",
            role: .host,
            kind: .movement,
            intensity: 1,
            monitoring: true,
            batteryPercent: 55
        )
        let fragments = try BoyisoCodec.bluetoothFragments(
            for: event,
            invitation: invitation,
            maximumPayloadLength: 32
        )
        var reassembler = BoyisoBluetoothReassembler()
        var combined: Data?

        for fragment in fragments.reversed() {
            combined = reassembler.append(fragment, peerID: "peer") ?? combined
        }

        XCTAssertNotNil(combined)
        XCTAssertEqual(
            try BoyisoCodec.open(XCTUnwrap(combined), invitation: invitation),
            event
        )
    }

    func testDuplicateEventFromWiFiAndBluetoothIsAcceptedOnce() {
        let event = BoyisoEvent(
            sourceID: UUID(),
            sourceName: "볼 사람",
            role: .host,
            kind: .toktok,
            monitoring: true,
            batteryPercent: nil
        )
        var deduplicator = BoyisoEventDeduplicator()

        XCTAssertTrue(deduplicator.accepts(event))
        XCTAssertFalse(deduplicator.accepts(event))
    }

    func testV2InvitationRoundTripsAndRejectsV1() throws {
        let invitation = BoyisoInvitation.make()
        XCTAssertEqual(try BoyisoInvitation(url: invitation.url), invitation)
        XCTAssertThrowsError(try BoyisoInvitation(url: URL(string: "stand://boyiso?v=1&room=ABCD2345&key=ABCD2345")!))
        XCTAssertEqual(Data(base64Encoded: invitation.roomKey.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - invitation.roomKey.count % 4) % 4))?.count, 32)
    }

    func testRolesUseProductNamesWhileKeepingWireValues() {
        XCTAssertEqual(BoyisoRole.allCases, [.host, .guest, .walkie])
        XCTAssertEqual(BoyisoRole.host.rawValue, "host")
        XCTAssertEqual(BoyisoRole.guest.rawValue, "guest")
        XCTAssertEqual(BoyisoRole.walkie.rawValue, "walkie")
        XCTAssertEqual(BoyisoRole.host.title, "볼 사람")
        XCTAssertEqual(BoyisoRole.guest.title, "말할 사람")
        XCTAssertEqual(BoyisoRole.walkie.title, "무전기")
        XCTAssertEqual(
            BoyisoRole.walkie.description,
            "주변 소리는 보내지 않고, 버튼을 눌러야만 연결된 화면을 부릅니다."
        )
        XCTAssertEqual(BoyisoEventKind.walkie.rawValue, "walkie")
        XCTAssertEqual(BoyisoEventKind.walkie.title, "무전기 호출")
    }

    func testSoundDetailsDriveCryingChildOnlyForSpecifiedKinds() {
        for detail in ["big_sound", "continuous_sound", "finger_snap"] {
            XCTAssertTrue(BoyisoEvent(sourceID: UUID(), sourceName: "말할 사람", role: .guest,
                kind: .sound, detail: detail, monitoring: true, batteryPercent: nil).isCryingSound)
        }
        XCTAssertFalse(BoyisoEvent(sourceID: UUID(), sourceName: "말할 사람", role: .guest,
            kind: .movement, detail: "turning", monitoring: true, batteryPercent: nil).isCryingSound)
        XCTAssertFalse(BoyisoEvent(sourceID: UUID(), sourceName: "무전기", role: .walkie,
            kind: .walkie, detail: "press", monitoring: false, batteryPercent: nil).isCryingSound)
    }

    func testWalkiePressPolicyOnlySendsForConnectedWalkieRoleAfterCooldown() {
        let start = Date()

        XCTAssertEqual(BoyisoWalkiePressPolicy.cooldownSeconds, 3)
        XCTAssertEqual(BoyisoWalkiePressPolicy.detail, "press")
        XCTAssertTrue(BoyisoWalkiePressPolicy.canSend(
            isEnabled: true, role: .walkie, lastSentAt: .distantPast, now: start
        ))
        XCTAssertFalse(BoyisoWalkiePressPolicy.canSend(
            isEnabled: false, role: .walkie, lastSentAt: .distantPast, now: start
        ))
        XCTAssertFalse(BoyisoWalkiePressPolicy.canSend(
            isEnabled: true, role: .host, lastSentAt: .distantPast, now: start
        ))
        XCTAssertFalse(BoyisoWalkiePressPolicy.canSend(
            isEnabled: true, role: .guest, lastSentAt: .distantPast, now: start
        ))
        XCTAssertFalse(BoyisoWalkiePressPolicy.canSend(
            isEnabled: true, role: .walkie, lastSentAt: start, now: start.addingTimeInterval(2.9)
        ))
        XCTAssertTrue(BoyisoWalkiePressPolicy.canSend(
            isEnabled: true, role: .walkie, lastSentAt: start, now: start.addingTimeInterval(3)
        ))
    }

    func testWalkiePressEventRoundTripsOverEncryptedLANFrame() throws {
        let invitation = BoyisoInvitation.make()
        let event = BoyisoEvent(
            sourceID: UUID(),
            sourceName: "무전기",
            role: .walkie,
            kind: .walkie,
            intensity: 1,
            detail: "press",
            monitoring: false,
            batteryPercent: 64
        )

        let frame = try BoyisoCodec.lanFrame(for: event, invitation: invitation)
        let decoded = try BoyisoCodec.openLANFrame(frame, invitation: invitation)

        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.role, .walkie)
        XCTAssertEqual(decoded.kind, .walkie)
        XCTAssertEqual(decoded.version, BoyisoEvent.protocolVersion)
    }

    func testWalkieCallOverlayUsesDedicatedCopyAndHighSalienceStyle() {
        XCTAssertEqual(BoyisoOverlayKind.walkieCall.primaryMessage, "무전기 호출이 왔어요")
        XCTAssertEqual(
            BoyisoOverlayKind.walkieCall.accessibilityLabel(sender: "거실"),
            "거실님의 무전기 호출"
        )
        XCTAssertEqual(BoyisoOverlayKind.walkieCall.imageName, "BoyisoGreeting")
        XCTAssertTrue(BoyisoOverlayKind.walkieCall.isHighSalience)
        XCTAssertTrue(BoyisoOverlayKind.soundDetected.isHighSalience)
        XCTAssertFalse(BoyisoOverlayKind.greeting.isHighSalience)
    }

    func testWalkieCallEventRepeatsChimesLikeADetectedSound() {
        let walkiePress = BoyisoEvent(sourceID: UUID(), sourceName: "무전기", role: .walkie,
            kind: .walkie, detail: "press", monitoring: false, batteryPercent: nil)
        let heartbeat = BoyisoEvent(sourceID: UUID(), sourceName: "무전기", role: .walkie,
            kind: .heartbeat, monitoring: false, batteryPercent: nil)

        XCTAssertEqual(BoyisoReactionPolicy.chimeCount(for: walkiePress), 2)
        XCTAssertEqual(BoyisoReactionPolicy.chimeCount(for: heartbeat), 0)
    }

    func testRemoteWakePolicyAcceptsWalkieOnlyDuringActiveMateCare() {
        let walkiePress = BoyisoEvent(sourceID: UUID(), sourceName: "무전기", role: .walkie,
            kind: .walkie, detail: "press", monitoring: false, batteryPercent: nil)
        let invalidRole = BoyisoEvent(sourceID: UUID(), sourceName: "볼 사람", role: .host,
            kind: .walkie, detail: "press", monitoring: false, batteryPercent: nil)

        XCTAssertTrue(BoyisoRemoteWakePolicy.shouldWake(
            for: walkiePress, environmentDisplayMode: .sleeping,
            isNightSessionActive: true, multiStimulusWakeEnabled: true
        ))
        XCTAssertFalse(BoyisoRemoteWakePolicy.shouldWake(
            for: walkiePress, environmentDisplayMode: .stand,
            isNightSessionActive: true, multiStimulusWakeEnabled: true
        ))
        XCTAssertFalse(BoyisoRemoteWakePolicy.shouldWake(
            for: walkiePress, environmentDisplayMode: .sleeping,
            isNightSessionActive: false, multiStimulusWakeEnabled: true
        ))
        XCTAssertFalse(BoyisoRemoteWakePolicy.shouldWake(
            for: walkiePress, environmentDisplayMode: .sleeping,
            isNightSessionActive: true, multiStimulusWakeEnabled: false
        ))
        XCTAssertFalse(BoyisoRemoteWakePolicy.shouldWake(
            for: invalidRole, environmentDisplayMode: .sleeping,
            isNightSessionActive: true, multiStimulusWakeEnabled: true
        ))
    }

    func testParticipantSectionsKeepDedicatedWalkieGroupWithConnectedState() {
        let current = BoyisoPeerStatus(
            id: UUID(), name: "거실", role: .walkie, lastSeen: Date(), monitoring: false,
            batteryPercent: 58, displayMode: .object, sessionActive: false, transports: []
        )
        let host = BoyisoPeerStatus(
            id: UUID(), name: "안방", role: .host, lastSeen: Date(), monitoring: false,
            batteryPercent: nil, displayMode: .mate, sessionActive: true, transports: [.localNetwork]
        )

        let sections = BoyisoParticipantSections(current: current, peers: [host])

        XCTAssertEqual(sections.totalCount, 2)
        XCTAssertEqual(sections.hosts.map(\.name), ["안방"])
        XCTAssertTrue(sections.guests.isEmpty)
        XCTAssertEqual(sections.walkies.map(\.name), ["거실"])
        XCTAssertTrue(sections.walkies[0].isCurrentDevice)
        XCTAssertEqual(sections.walkies[0].state, "연결됨")
    }
}
