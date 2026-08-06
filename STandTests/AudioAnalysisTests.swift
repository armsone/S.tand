import AVFoundation
import XCTest
@testable import STand

final class AudioAnalysisTests: XCTestCase {
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
