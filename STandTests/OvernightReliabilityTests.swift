import Foundation
import XCTest
@testable import STand

final class OvernightReliabilityTests: XCTestCase {
    // MARK: - Background mode default and migration

    func testNewAppSettingsDefaultsToBackgroundModeEnabled() {
        XCTAssertTrue(AppSettings().backgroundModeEnabled)
        XCTAssertTrue(AppSettings.recommended.backgroundModeEnabled)
    }

    @MainActor
    func testSettingsStoreEnablesBackgroundModeOnceForExistingUsers() {
        let suiteName = "OvernightReliabilityTests.migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var legacySettings = AppSettings()
        legacySettings.backgroundModeEnabled = false
        let data = try! JSONEncoder().encode(legacySettings)
        defaults.set(data, forKey: "appSettings")

        let firstLaunch = SettingsStore(defaults: defaults)
        XCTAssertTrue(
            firstLaunch.value.backgroundModeEnabled,
            "기존 설치는 업데이트 후 한 번 백그라운드 감시가 켜져야 한다"
        )

        firstLaunch.value.backgroundModeEnabled = false

        let secondLaunch = SettingsStore(defaults: defaults)
        XCTAssertFalse(
            secondLaunch.value.backgroundModeEnabled,
            "마이그레이션 이후 사용자가 직접 끈 선택은 유지되어야 한다"
        )
    }

    func testSettingsMigrationSkipsAlreadyMigratedSettings() {
        var settings = AppSettings()
        settings.backgroundModeEnabled = false
        let migrated = SettingsMigration.applyingBackgroundModeDefaultOn(
            to: settings,
            hasMigrated: true
        )
        XCTAssertFalse(migrated.backgroundModeEnabled)
    }

    // MARK: - Automatic-to-Mate lifecycle policy

    func testBackgroundMonitoringRequiresSettingAndSleepingMode() {
        XCTAssertFalse(BackgroundMonitoringPolicy.shouldKeepMotionMonitoring(
            backgroundModeEnabled: false,
            isNightSessionActive: true,
            environmentDisplayMode: .sleeping
        ))
        XCTAssertFalse(BackgroundMonitoringPolicy.shouldKeepMotionMonitoring(
            backgroundModeEnabled: true,
            isNightSessionActive: true,
            environmentDisplayMode: .stand
        ))
        XCTAssertFalse(BackgroundMonitoringPolicy.shouldKeepMotionMonitoring(
            backgroundModeEnabled: true,
            isNightSessionActive: false,
            environmentDisplayMode: .sleeping
        ))
        XCTAssertTrue(BackgroundMonitoringPolicy.shouldKeepMotionMonitoring(
            backgroundModeEnabled: true,
            isNightSessionActive: true,
            environmentDisplayMode: .sleeping
        ))
    }

    func testBackgroundAudioMonitoringRequiresGrantedMicAndNoSuspension() {
        XCTAssertTrue(BackgroundMonitoringPolicy.shouldKeepAudioMonitoring(
            environmentDisplayMode: .sleeping,
            soundSensingEnabled: true,
            isSuspended: false,
            microphoneAccess: .granted
        ))
        XCTAssertFalse(BackgroundMonitoringPolicy.shouldKeepAudioMonitoring(
            environmentDisplayMode: .sleeping,
            soundSensingEnabled: true,
            isSuspended: false,
            microphoneAccess: .denied
        ))
        XCTAssertFalse(BackgroundMonitoringPolicy.shouldKeepAudioMonitoring(
            environmentDisplayMode: .sleeping,
            soundSensingEnabled: true,
            isSuspended: true,
            microphoneAccess: .granted
        ))
        XCTAssertFalse(BackgroundMonitoringPolicy.shouldKeepAudioMonitoring(
            environmentDisplayMode: .sleeping,
            soundSensingEnabled: false,
            isSuspended: false,
            microphoneAccess: .granted
        ))
        XCTAssertFalse(BackgroundMonitoringPolicy.shouldKeepAudioMonitoring(
            environmentDisplayMode: .stand,
            soundSensingEnabled: true,
            isSuspended: false,
            microphoneAccess: .granted
        ))
    }

    // MARK: - Sound monitoring status mapping

    func testSoundMonitoringStatusIsInactiveOutsideMateSession() {
        XCTAssertEqual(
            SoundMonitoringStatusPolicy.status(
                isNightSessionActive: false,
                environmentDisplayMode: .sleeping,
                soundSensingEnabled: true,
                isSuspended: false,
                audioState: .monitoring,
                microphoneAccess: .granted,
                isWritingClip: false,
                noiseCalibrationProgress: 1
            ),
            .inactive
        )
        XCTAssertEqual(
            SoundMonitoringStatusPolicy.status(
                isNightSessionActive: true,
                environmentDisplayMode: .stand,
                soundSensingEnabled: true,
                isSuspended: false,
                audioState: .monitoring,
                microphoneAccess: .granted,
                isWritingClip: false,
                noiseCalibrationProgress: 1
            ),
            .inactive
        )
    }

    func testSoundMonitoringStatusReflectsCalibrationAndClipWriting() {
        XCTAssertEqual(
            SoundMonitoringStatusPolicy.status(
                isNightSessionActive: true,
                environmentDisplayMode: .sleeping,
                soundSensingEnabled: true,
                isSuspended: false,
                audioState: .monitoring,
                microphoneAccess: .granted,
                isWritingClip: false,
                noiseCalibrationProgress: 0.4
            ),
            .learningRoomSound
        )
        XCTAssertEqual(
            SoundMonitoringStatusPolicy.status(
                isNightSessionActive: true,
                environmentDisplayMode: .sleeping,
                soundSensingEnabled: true,
                isSuspended: false,
                audioState: .monitoring,
                microphoneAccess: .granted,
                isWritingClip: true,
                noiseCalibrationProgress: 1
            ),
            .savingSound
        )
        XCTAssertEqual(
            SoundMonitoringStatusPolicy.status(
                isNightSessionActive: true,
                environmentDisplayMode: .sleeping,
                soundSensingEnabled: true,
                isSuspended: false,
                audioState: .monitoring,
                microphoneAccess: .granted,
                isWritingClip: false,
                noiseCalibrationProgress: 1
            ),
            .monitoring
        )
    }

    func testSoundMonitoringStatusSurfacesPermissionSuspensionAndFailure() {
        XCTAssertEqual(
            SoundMonitoringStatusPolicy.status(
                isNightSessionActive: true,
                environmentDisplayMode: .sleeping,
                soundSensingEnabled: true,
                isSuspended: false,
                audioState: .stopped,
                microphoneAccess: .denied,
                isWritingClip: false,
                noiseCalibrationProgress: 0
            ),
            .microphonePermissionNeeded
        )
        XCTAssertEqual(
            SoundMonitoringStatusPolicy.status(
                isNightSessionActive: true,
                environmentDisplayMode: .sleeping,
                soundSensingEnabled: true,
                isSuspended: true,
                audioState: .stopped,
                microphoneAccess: .granted,
                isWritingClip: false,
                noiseCalibrationProgress: 0
            ),
            .suspended
        )
        XCTAssertEqual(
            SoundMonitoringStatusPolicy.status(
                isNightSessionActive: true,
                environmentDisplayMode: .sleeping,
                soundSensingEnabled: true,
                isSuspended: false,
                audioState: .failed("마이크 입력을 사용할 수 없습니다."),
                microphoneAccess: .granted,
                isWritingClip: false,
                noiseCalibrationProgress: 0
            ),
            .failedToStart("마이크 입력을 사용할 수 없습니다.")
        )
    }

    // MARK: - Session continuity and quiet-night vs failed presentation

    @MainActor
    func testRecordingLibraryKeepsConfirmedQuietSessionsVisible() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = RecordingLibrary(directory: directory)

        let sessionID = library.beginSleepSession(at: Date(timeIntervalSinceReferenceDate: 0))
        library.confirmMonitoring(sessionID: sessionID)
        library.endSleepSession(id: sessionID, at: Date(timeIntervalSinceReferenceDate: 3_600))

        let sessions = library.recordingSessions
        XCTAssertEqual(sessions.count, 1)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertTrue(session.clips.isEmpty)
        XCTAssertTrue(session.monitoringConfirmed)
        XCTAssertEqual(
            SleepSessionQuietNightPolicy.description(for: session),
            "감시는 정상적으로 진행됐고 저장할 소리가 없었어요"
        )
    }

    @MainActor
    func testRecordingLibraryShowsUnconfirmedSessionAsFailedNotQuiet() throws {
        let directory = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = RecordingLibrary(directory: directory)

        let sessionID = library.beginSleepSession(at: Date(timeIntervalSinceReferenceDate: 0))
        // 마이크 감시가 한 번도 확인되지 않은 채로 세션이 끝난다.
        library.endSleepSession(id: sessionID, at: Date(timeIntervalSinceReferenceDate: 3_600))

        let sessions = library.recordingSessions
        XCTAssertEqual(sessions.count, 1)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertFalse(session.monitoringConfirmed)
        XCTAssertEqual(
            SleepSessionQuietNightPolicy.description(for: session),
            "감시가 정상적으로 진행되지 못해 저장된 소리가 없어요"
        )
    }

    func testSleepSessionQuietNightPolicyReturnsNilWhenSoundsOrMovementExist() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let session = RecordingSessionGroup(
            id: "with-sound",
            startedAt: start,
            endedAt: start.addingTimeInterval(3_600),
            clips: [
                RecordingClip(
                    url: URL(fileURLWithPath: "/tmp/clip.m4a"),
                    createdAt: start.addingTimeInterval(60),
                    duration: 5
                )
            ],
            startleEvents: [],
            isInferred: false,
            monitoringConfirmed: true
        )
        XCTAssertNil(SleepSessionQuietNightPolicy.description(for: session))
    }

    private func makeTemporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OvernightReliabilityTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
