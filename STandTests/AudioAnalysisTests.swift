import AVFoundation
import SwiftUI
import UIKit
import XCTest
@testable import STand

final class AudioAnalysisTests: XCTestCase {
    func testBurnInProtectionMovesWithinAQuietFivePointRange() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let offsets = (0..<8).map {
            BurnInProtection.offset(at: start.addingTimeInterval(Double($0) * 60))
        }

        XCTAssertGreaterThan(Set(offsets.map { "\($0.width),\($0.height)" }).count, 1)
        XCTAssertTrue(offsets.allSatisfy { abs($0.width) <= 5 && abs($0.height) <= 3 })
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

    func testEmbeddedSnoreSamplesAreIncluded() {
        for name in ["sample-snore-5s", "sample-snore-10s", "sample-snore-15s"] {
            XCTAssertNotNil(
                Bundle.main.url(forResource: name, withExtension: "m4a"),
                "내장 테스트 코골이 파일이 앱 번들에 포함되지 않았습니다: \(name).m4a"
            )
        }
    }

    func testLegacySettingsDefaultToAutomaticOrientation() throws {
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

        XCTAssertEqual(settings.orientationPreference, .automatic)
        XCTAssertTrue(settings.torchEnabled)
        XCTAssertEqual(settings.torchIntensity, 0.25)
        XCTAssertFalse(settings.wakeOnSleepSound)
        XCTAssertEqual(settings.silhouetteIntensity, 0.05)
        XCTAssertEqual(settings.clockScale, 1)
        XCTAssertEqual(settings.clockFont, .tenada)
        XCTAssertTrue(settings.preventAutoDimmingWhenScreenBright)
        XCTAssertTrue(settings.automaticDimmingEnabled)
        XCTAssertTrue(settings.multiStimulusWakeEnabled)
        XCTAssertEqual(settings.clockHourMode, .twelve)
        XCTAssertEqual(settings.portraitLayout, .portrait)
        XCTAssertEqual(settings.landscapeLayout, .landscape)
        XCTAssertEqual(settings.brightnessModeThreshold, 0.35)
        XCTAssertEqual(settings.modePreference, .automatic)
        XCTAssertFalse(settings.cameraAmbientSensingEnabled)
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
    }

    func testObjectModeNeverTurnsOnRearTorch() {
        XCTAssertEqual(
            LampTorchLightingPolicy.maximumLevel(
                torchEnabled: true,
                isMovementTriggered: false,
                environmentDisplayMode: .stand
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

    func testRecommendedLayoutsMatchCapturedSimulatorArrangement() {
        let portrait = AppSettings.recommended.portraitLayout
        XCTAssertEqual(portrait.clock, PanelTransform(x: 0, y: 0, scale: 1))
        XCTAssertEqual(
            portrait.weatherIcon,
            PanelTransform(x: 0, y: -0.22811053984575841, scale: 0.86922719107523572)
        )
        XCTAssertEqual(portrait.weatherIcon, portrait.weatherTemperature)
        XCTAssertEqual(portrait.weatherIcon, portrait.weatherCondition)
        XCTAssertEqual(portrait.weatherGroupIDs, [1, 1, 1])
        XCTAssertEqual(portrait.date, PanelTransform(x: 0, y: 0.10, scale: 1))
        XCTAssertEqual(portrait.status, PanelTransform(x: 0, y: 0.15, scale: 1))
        XCTAssertEqual(
            portrait.battery,
            PanelTransform(x: 0, y: 0.20698371893744649, scale: 1)
        )
        XCTAssertEqual(
            portrait.controlOrder,
            [.flashlight, .brightness, .stopDetection, .orientation, .recordings, .aiShot, .settings]
        )

        let landscape = AppSettings.recommended.landscapeLayout
        XCTAssertEqual(
            landscape.clock,
            PanelTransform(x: 0, y: 0.07155322862129146, scale: 1.2810187063251741)
        )
        XCTAssertEqual(
            landscape.weatherIcon,
            PanelTransform(x: 0, y: -0.25582024432809763, scale: 0.68640335461830571)
        )
        XCTAssertEqual(landscape.weatherIcon, landscape.weatherTemperature)
        XCTAssertEqual(landscape.weatherIcon, landscape.weatherCondition)
        XCTAssertEqual(landscape.weatherGroupIDs, [1, 1, 1])
        XCTAssertEqual(
            landscape.date,
            PanelTransform(x: -0.17600000000000007, y: -0.08265270506108202, scale: 1)
        )
        XCTAssertEqual(
            landscape.status,
            PanelTransform(x: 0, y: 0.4646596858638743, scale: 1)
        )
        XCTAssertEqual(
            landscape.battery,
            PanelTransform(x: 0, y: 0.27773123909249542, scale: 1)
        )
        XCTAssertEqual(
            landscape.controlOrder,
            [.flashlight, .stopDetection, .orientation, .brightness, .recordings, .aiShot, .settings]
        )
    }

    func testPortraitAndLandscapeControlOrdersRoundTripIndependently() throws {
        var portrait = StandScreenLayout.portrait
        portrait.controlOrder = [.settings, .recordings, .orientation, .aiShot, .flashlight, .brightness, .stopDetection]
        var landscape = StandScreenLayout.landscape
        landscape.controlOrder = [.brightness, .flashlight, .stopDetection, .aiShot, .settings, .recordings, .orientation]

        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: JSONEncoder().encode(
                AppSettings(portraitLayout: portrait, landscapeLayout: landscape)
            )
        )

        XCTAssertEqual(decoded.portraitLayout.controlOrder, portrait.controlOrder)
        XCTAssertEqual(decoded.landscapeLayout.controlOrder, landscape.controlOrder)
    }

    func testControlOrderDecodeIgnoresUnknownsAndCompletesMissingKinds() throws {
        let encoded = try JSONEncoder().encode(StandScreenLayout.portrait)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["controlOrder"] = ["settings", "futureControl", "settings", "flashlight"]

        let decoded = try JSONDecoder().decode(
            StandScreenLayout.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(
            decoded.controlOrder,
            [.settings, .flashlight, .brightness, .stopDetection, .orientation, .recordings, .aiShot]
        )
    }

    func testPanelEditorResetPreservesBottomButtonOrder() {
        var customized = StandScreenLayout.portrait
        customized.clock = PanelTransform(x: 0.18, y: -0.12, scale: 1.4)
        customized.controlOrder = [
            .settings, .aiShot, .recordings, .orientation,
            .stopDetection, .brightness, .flashlight
        ]

        let reset = HomeEditorResetPolicy.panels(in: customized, isPortrait: true)

        XCTAssertEqual(reset.clock, StandScreenLayout.portrait.clock)
        XCTAssertEqual(reset.weatherGroupIDs, StandScreenLayout.portrait.weatherGroupIDs)
        XCTAssertEqual(reset.controlOrder, customized.controlOrder)
    }

    func testButtonEditorResetPreservesScreenPanels() {
        var customized = StandScreenLayout.landscape
        customized.clock = PanelTransform(x: -0.16, y: 0.08, scale: 1.25)
        customized.date = PanelTransform(x: 0.22, y: 0.18, scale: 0.8)
        customized.controlOrder = Array(StandControlKind.defaultOrder.reversed())

        let reset = HomeEditorResetPolicy.controls(in: customized)

        XCTAssertEqual(reset.clock, customized.clock)
        XCTAssertEqual(reset.date, customized.date)
        XCTAssertEqual(reset.weatherGroupIDs, customized.weatherGroupIDs)
        XCTAssertEqual(reset.controlOrder, StandControlKind.defaultOrder)
    }

    func testBottomControlWrappingAndEditorBoundaryUseSameThreeRowPlan() {
        let availableWidth: CGFloat = 353
        let threeRowOrder: [StandControlKind] = [
            .flashlight, .orientation, .recordings,
            .brightness, .stopDetection, .aiShot, .settings
        ]

        XCTAssertEqual(
            BottomControlLayoutPolicy.rows(
                for: StandControlKind.defaultOrder,
                availableWidth: availableWidth,
                isPortrait: true
            ).count,
            2
        )
        XCTAssertEqual(
            BottomControlLayoutPolicy.rows(
                for: threeRowOrder,
                availableWidth: availableWidth,
                isPortrait: true
            ).count,
            3
        )
        XCTAssertEqual(
            BottomControlLayoutPolicy.height(
                for: threeRowOrder,
                availableWidth: availableWidth,
                isPortrait: true
            ),
            192
        )

        let region = PanelEditingPolicy.editingRegion(
            canvasSize: CGSize(width: 393, height: 852),
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            isPortrait: true,
            controlOrder: threeRowOrder,
            bottomAvailableWidth: availableWidth
        )
        XCTAssertEqual(region.insets.bottom, 250)
        XCTAssertEqual(region.frame.maxY, 602)
    }

    func testOrientationPreferenceRoundTripsThroughSettingsEncoding() throws {
        let settings = AppSettings(orientationPreference: .portrait)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.orientationPreference, .portrait)
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

    func testScreenEditingSettingsRoundTrip() throws {
        var portrait = StandScreenLayout.portrait
        portrait.clock = PanelTransform(x: 0.08, y: -0.04, scale: 1.15)
        portrait.date = PanelTransform(x: 0.15, y: -0.12, scale: 1.2)
        portrait.weatherGroupIDs = [4, 4, 9]

        let settings = AppSettings(
            clockFont: .paperlogyBold,
            clockHourMode: .twentyFour,
            portraitLayout: portrait,
            landscapeLayout: .landscape,
            brightnessModeThreshold: 0.18
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.clockFont, .paperlogyBold)
        XCTAssertEqual(decoded.clockHourMode, .twentyFour)
        XCTAssertEqual(decoded.portraitLayout, portrait)
        XCTAssertEqual(decoded.landscapeLayout, .landscape)
        XCTAssertEqual(decoded.brightnessModeThreshold, 0.18)
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

    func testEditablePanelCenterStaysInsideProtectedControls() {
        let center = PanelEditingPolicy.clampedCenter(
            CGPoint(x: 160, y: 20),
            panelSize: CGSize(width: 100, height: 80),
            canvasSize: CGSize(width: 320, height: 700),
            insets: EdgeInsets(top: 100, leading: 20, bottom: 120, trailing: 20)
        )

        XCTAssertEqual(center.x, 160)
        XCTAssertEqual(center.y, 140)

        let bottomRight = PanelEditingPolicy.clampedCenter(
            CGPoint(x: 400, y: 800),
            panelSize: CGSize(width: 100, height: 80),
            canvasSize: CGSize(width: 320, height: 700),
            insets: EdgeInsets(top: 100, leading: 20, bottom: 120, trailing: 20)
        )
        XCTAssertEqual(bottomRight.x, 250)
        XCTAssertEqual(bottomRight.y, 540)
    }

    func testEditorBoundaryGuidesMatchCurrentPortraitControlRows() {
        let region = PanelEditingPolicy.editingRegion(
            canvasSize: CGSize(width: 393, height: 852),
            safeAreaInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            isPortrait: true
        )

        // Top: 59 safe + 18 outer + 46 toolbar + 12 clearance.
        XCTAssertEqual(region.frame.minY, 135)
        // Bottom: 34 safe + 18 outer + (60 + 6 + 60) rows + 6 clearance.
        XCTAssertEqual(region.frame.maxY, 668)
        XCTAssertEqual(region.insets.bottom, 184)
    }

    func testEditorBoundaryGuidesMatchCurrentLandscapeControlRow() {
        let region = PanelEditingPolicy.editingRegion(
            canvasSize: CGSize(width: 852, height: 393),
            safeAreaInsets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59),
            isPortrait: false
        )

        // Top: 14 outer + 46 toolbar + 2 clearance.
        XCTAssertEqual(region.frame.minY, 62)
        // Bottom: 21 safe + 6 outer + 60 row + 2 clearance.
        XCTAssertEqual(region.frame.maxY, 304)
        XCTAssertEqual(region.insets.bottom, 89)
        XCTAssertEqual(region.frame.minX, 83)
        XCTAssertEqual(region.frame.maxX, 769)
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

        let panelSize = CGSize(width: 260, height: StatusPanelMetrics.height)
        for requestedY in [-1.0, 1.0] {
            let result = PanelEditingPolicy.clampedTransform(
                PanelTransform(x: 0, y: requestedY, scale: 1),
                panelSize: panelSize,
                canvasSize: canvas,
                insets: region.insets,
                screenScale: 1
            )
            let centerY = canvas.height / 2 + CGFloat(result.y) * canvas.height
            XCTAssertGreaterThanOrEqual(centerY - panelSize.height / 2, 0)
            XCTAssertLessThanOrEqual(centerY + panelSize.height / 2, canvas.height)
        }
    }

    func testLandscapePanelBoundingBoxCannotCrossVisibleEditorGuidesAtScreenScale() {
        let canvas = CGSize(width: 852, height: 393)
        let region = PanelEditingPolicy.editingRegion(
            canvasSize: canvas,
            safeAreaInsets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59),
            isPortrait: false
        )
        let panelSize = CGSize(width: 370 / 3, height: 370 / 3)
        let screenScale = 1.35

        for requestedY in [-0.44, 0.44] {
            let result = PanelEditingPolicy.clampedTransform(
                PanelTransform(x: 0, y: requestedY, scale: 1),
                panelSize: panelSize,
                canvasSize: canvas,
                insets: region.insets,
                screenScale: screenScale
            )
            let centerY = canvas.height / 2
                + CGFloat(result.y) * canvas.height * screenScale
            let halfHeight = panelSize.height * result.scale * screenScale / 2

            XCTAssertGreaterThanOrEqual(centerY - halfHeight, region.frame.minY - 0.001)
            XCTAssertLessThanOrEqual(centerY + halfHeight, region.frame.maxY + 0.001)
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

    func testSavedPanelStaysAboveBottomControlsAfterWholeScreenScaling() {
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
        let renderedCenterY = canvasSize.height / 2 + result.y * canvasSize.height * screenScale
        let renderedHalfHeight = panelSize.height * result.scale * screenScale / 2

        XCTAssertLessThanOrEqual(
            renderedCenterY + renderedHalfHeight,
            canvasSize.height - insets.bottom + 0.001
        )
    }

    func testShrunkScreenStillUsesEditorButtonBoundaryForPanelMovement() {
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
        let editorCenterY = canvasSize.height / 2 + result.y * canvasSize.height

        XCTAssertLessThanOrEqual(
            editorCenterY + panelSize.height / 2,
            canvasSize.height - insets.bottom + 0.001
        )
    }

    func testPinchMaximumScaleStopsBeforePanelsCrossVerticalControls() {
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
        let bottomEdge = canvas.height / 2
            + (CGFloat(layout.status.y) * canvas.height
                + 36 * layout.status.scale / 2) * maximum

        XCTAssertLessThanOrEqual(bottomEdge, canvas.height - insets.bottom + 0.001)
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
        let secondaryRowWidth = buttonWidth * 4
            + StandControlLayoutMetrics.rowSpacing * 3

        XCTAssertEqual(buttonWidth, 90.75)
        XCTAssertEqual(sliderWidth, 187.5)
        XCTAssertEqual(nightRowWidth, availableWidth)
        XCTAssertEqual(secondaryRowWidth, availableWidth)
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
        } + StandControlLayoutMetrics.rowSpacing * 6
        XCTAssertEqual(landscapeRowWidth, landscapeAvailableWidth)
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
    }

    func testSleepMovementUsesFullOrTenPercentTorchOnlyInSleepingMode() {
        XCTAssertEqual(
            SleepMovementLightingPolicy.torchLevel(
                torchEnabled: true,
                environmentDisplayMode: .sleeping
            ),
            1
        )
        XCTAssertEqual(
            SleepMovementLightingPolicy.torchLevel(
                torchEnabled: false,
                environmentDisplayMode: .sleeping
            ),
            0.1
        )
        XCTAssertEqual(
            SleepMovementLightingPolicy.torchLevel(
                torchEnabled: true,
                environmentDisplayMode: .stand
            ),
            0
        )
    }

    func testTouchWakeUsesFullTorchWhenLinkedAndNoTorchWhenUnlinked() {
        XCTAssertEqual(
            LampTorchLightingPolicy.maximumLevel(
                torchEnabled: true,
                isMovementTriggered: false,
                environmentDisplayMode: .sleeping
            ),
            1
        )
        XCTAssertEqual(
            LampTorchLightingPolicy.maximumLevel(
                torchEnabled: false,
                isMovementTriggered: false,
                environmentDisplayMode: .sleeping
            ),
            0
        )
        XCTAssertEqual(
            LampTorchLightingPolicy.maximumLevel(
                torchEnabled: false,
                isMovementTriggered: true,
                environmentDisplayMode: .sleeping
            ),
            0.1
        )
    }

    @MainActor
    func testBrightnessThresholdChangeUsesTheNewPublishedValueImmediately() {
        let model = StandViewModel()
        let originalThreshold = model.settings.value.brightnessModeThreshold
        defer { model.settings.value.brightnessModeThreshold = originalThreshold }

        let brightness = model.displayBrightness
        model.settings.value.brightnessModeThreshold = brightness - 0.1
        XCTAssertEqual(model.environmentDisplayMode, .sleeping)

        model.settings.value.brightnessModeThreshold = brightness + 0.1
        XCTAssertEqual(model.environmentDisplayMode, .stand)
    }

    func testSoundSensitivityUsesAnIntuitiveLowToHighScale() {
        XCTAssertEqual(SoundSensitivityPolicy.level(for: -20), 0, accuracy: 0.000_001)
        XCTAssertEqual(SoundSensitivityPolicy.level(for: -35), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(SoundSensitivityPolicy.level(for: -50), 1, accuracy: 0.000_001)
        XCTAssertEqual(SoundSensitivityPolicy.threshold(for: 0), -20, accuracy: 0.000_001)
        XCTAssertEqual(SoundSensitivityPolicy.threshold(for: 0.5), -35, accuracy: 0.000_001)
        XCTAssertEqual(SoundSensitivityPolicy.threshold(for: 1), -50, accuracy: 0.000_001)
        XCTAssertEqual(SoundSensitivityPolicy.label(for: -45), "높음")
        XCTAssertEqual(SoundSensitivityPolicy.label(for: -36), "보통")
        XCTAssertEqual(SoundSensitivityPolicy.label(for: -25), "낮음")
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

        library.deleteAll()
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

        library.deleteAll(at: firstEnd.addingTimeInterval(60))
        let resumedID = library.beginSleepSession(
            at: firstEnd.addingTimeInterval(SleepSessionGroupingPolicy.sleepModeResumeGap)
        )
        XCTAssertEqual(resumedID, firstID)

        let resumedEnd = firstEnd.addingTimeInterval(45 * 60)
        library.endSleepSession(id: resumedID, at: resumedEnd)
        library.deleteAll(at: resumedEnd)
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
        library.deleteAll()
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
