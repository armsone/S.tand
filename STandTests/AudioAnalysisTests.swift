import AVFoundation
import XCTest
@testable import STand

final class AudioAnalysisTests: XCTestCase {
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
    }

    func testOrientationPreferenceRoundTripsThroughSettingsEncoding() throws {
        let settings = AppSettings(orientationPreference: .portrait)

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.orientationPreference, .portrait)
    }

    func testTorchAndSoundWakeSettingsRoundTrip() throws {
        let settings = AppSettings(
            torchEnabled: true,
            torchIntensity: 0.4,
            wakeOnSleepSound: true
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertTrue(decoded.torchEnabled)
        XCTAssertEqual(decoded.torchIntensity, 0.4)
        XCTAssertTrue(decoded.wakeOnSleepSound)
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
    func testRecordingLibraryMergesClipsChronologically() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let format = try XCTUnwrap(
            AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        )
        let olderURL = directory.appendingPathComponent("sleep-sound-20260807-010000-000.m4a")
        let newerURL = directory.appendingPathComponent("sleep-sound-20260807-020000-000.m4a")
        try writeAudioFile(at: newerURL, format: format, bufferCount: 3)
        try writeAudioFile(at: olderURL, format: format, bufferCount: 2)

        let library = RecordingLibrary(directory: directory)
        let originalDuration = library.totalDuration
        let merged = try await library.mergeAll()

        XCTAssertTrue(merged.isMerged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: merged.url.path))
        XCTAssertEqual(library.clips.count, 3)
        XCTAssertEqual(merged.duration, originalDuration, accuracy: 0.08)

        let replacement = try await library.mergeAll()
        XCTAssertNotEqual(replacement.url, merged.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: merged.url.path))
        XCTAssertEqual(library.clips.count, 3)
        XCTAssertEqual(replacement.duration, originalDuration, accuracy: 0.08)
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
