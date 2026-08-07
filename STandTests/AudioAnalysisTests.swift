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
        XCTAssertFalse(settings.torchEnabled)
        XCTAssertEqual(settings.torchIntensity, 0.25)
        XCTAssertFalse(settings.wakeOnSleepSound)
        XCTAssertEqual(settings.silhouetteIntensity, 0.05)
        XCTAssertEqual(settings.clockScale, 1)
        XCTAssertEqual(settings.clockFont, .systemRounded)
        XCTAssertTrue(settings.preventAutoDimmingWhenScreenBright)
        XCTAssertTrue(settings.automaticDimmingEnabled)
        XCTAssertTrue(settings.multiStimulusWakeEnabled)
        XCTAssertEqual(settings.clockHourMode, .twelve)
        XCTAssertEqual(settings.portraitLayout, .portrait)
        XCTAssertEqual(settings.landscapeLayout, .landscape)
        XCTAssertEqual(settings.brightnessModeThreshold, 0.35)
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

    func testScreenEditingSettingsRoundTrip() throws {
        var portrait = StandScreenLayout.portrait
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

    func testWeatherPanelsMergeAtTenPercentOverlap() {
        let source = CGRect(x: 0, y: 0, width: 100, height: 100)
        let tenPercent = CGRect(x: 90, y: 0, width: 100, height: 100)
        let lessThanTenPercent = CGRect(x: 91, y: 0, width: 100, height: 100)

        XCTAssertEqual(PanelEditingPolicy.overlapFraction(source, tenPercent), 0.1)
        XCTAssertLessThan(PanelEditingPolicy.overlapFraction(source, lessThanTenPercent), 0.1)
    }

    func testPanelSnapsWhenGuideEntersItsMiddleTenPercent() {
        XCTAssertTrue(
            PanelEditingPolicy.shouldSnapToVerticalCenter(centerOffset: 6, panelWidth: 120)
        )
        XCTAssertFalse(
            PanelEditingPolicy.shouldSnapToVerticalCenter(centerOffset: 6.1, panelWidth: 120)
        )
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

    func testSavedPanelStaysAboveBottomControlsAfterWholeScreenScaling() {
        let canvasSize = CGSize(width: 393, height: 852)
        let insets = EdgeInsets(top: 123, leading: 14, bottom: 218, trailing: 14)
        let panelSize = CGSize(width: 240, height: 38)
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
        let panelSize = CGSize(width: 240, height: 38)
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
        layout.brightnessRule = .init(x: 0, y: 0.2)
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
            + (CGFloat(layout.brightnessRule.y) * canvas.height
                + 38 * layout.brightnessRule.scale / 2) * maximum

        XCTAssertLessThanOrEqual(bottomEdge, canvas.height - insets.bottom + 0.001)
    }

    func testBrightnessLeftOfThresholdIsSleepingAndRightIsStand() {
        XCTAssertEqual(
            EnvironmentDisplayMode.resolve(brightness: 0.2, threshold: 0.5),
            .sleeping
        )
        XCTAssertEqual(
            EnvironmentDisplayMode.resolve(brightness: 0.8, threshold: 0.5),
            .stand
        )
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

    func testHorizontalDragAdjustsHoldDurationBetweenTenSecondsAndFiveMinutes() {
        XCTAssertEqual(HoldDurationAdjustment.value(startingAt: 60, translation: 300), 300)
        XCTAssertEqual(HoldDurationAdjustment.value(startingAt: 60, translation: -300), 10)
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
        recorder.process(
            buffer: try makeBuffer(format: format),
            detection: AudioDetection(
                clapDetected: false,
                soundBegan: false,
                isAboveSoundThreshold: false
            ),
            now: 3
        )

        wait(for: [saved], timeout: 1)
        let url = try XCTUnwrap(savedURL)
        XCTAssertEqual(url.pathExtension, "m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let file = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(file.length, 0)
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
        recorder.process(buffer: try makeBuffer(format: format), detection: silence, now: 1.3)

        wait(for: [savedTwice], timeout: 1)
        XCTAssertEqual(Set(savedURLs).count, 2)
        for url in savedURLs {
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
        let previousDay = try XCTUnwrap(library.clips.first { $0.url == previousDayURL })
        let selectedDuration = older.duration + previousDay.duration
        let selectedMerge = try await library.merge([older, previousDay], kind: .selected)

        XCTAssertEqual(selectedMerge.mergedTitle, "선택 녹음 합본")
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
