import AVFoundation
import Combine
import Foundation

struct RecordingClip: Identifiable, Hashable {
    let url: URL
    let createdAt: Date
    let duration: TimeInterval

    var id: URL { url }

    var isMerged: Bool {
        url.deletingPathExtension().lastPathComponent.hasSuffix("-merged")
    }

    var isEmbeddedSample: Bool {
        url.deletingPathExtension().lastPathComponent.contains("-embedded-snore")
    }

    var mergedTitle: String? {
        guard isMerged else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        if name.contains("-today-merged") { return "오늘 녹음 합본" }
        if name.contains("-selected-merged") {
            return createdAt.formatted(.dateTime.hour().minute().second())
        }
        return "합친 녹음"
    }
}

struct SleepRecordingSession: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var clipFileNames: [String]
}

struct RecordingSessionGroup: Identifiable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    let clips: [RecordingClip]
    let isInferred: Bool

    var totalDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }
}

enum SleepSessionGroupingPolicy {
    /// 잠자기 모드가 끝난 뒤 이 시간 안에 다시 잠자기 모드로 들어오면
    /// 잠깐 깬 것으로 보고 기존 잠자리를 이어서 기록한다.
    static let sleepModeResumeGap: TimeInterval = 30 * 60

    /// 이전 버전의 녹음에는 잠자기 모드 진입·종료 시각이 없다.
    /// 이 값은 새 기록의 30분 모드 재진입 규칙과 무관한 과거 파일 전용 추정값이다.
    static let legacyRecordingGap: TimeInterval = 90 * 60
    static let legacyTimelinePadding: TimeInterval = 15 * 60

    static func inferredGroups(
        from clips: [RecordingClip],
        maximumGap: TimeInterval = legacyRecordingGap
    ) -> [RecordingSessionGroup] {
        let sorted = clips
            .filter { !$0.isMerged }
            .sorted { $0.createdAt < $1.createdAt }
        guard let first = sorted.first else { return [] }

        var clusters: [[RecordingClip]] = [[first]]
        for clip in sorted.dropFirst() {
            let previous = clusters[clusters.count - 1].last!
            let previousEnd = previous.createdAt.addingTimeInterval(previous.duration)
            if clip.createdAt.timeIntervalSince(previousEnd) > maximumGap {
                clusters.append([clip])
            } else {
                clusters[clusters.count - 1].append(clip)
            }
        }

        return clusters.map { cluster in
            let firstClip = cluster[0]
            let lastClip = cluster[cluster.count - 1]
            let startedAt = firstClip.createdAt.addingTimeInterval(-legacyTimelinePadding)
            let endedAt = max(
                startedAt.addingTimeInterval(1),
                lastClip.createdAt
                    .addingTimeInterval(lastClip.duration)
                    .addingTimeInterval(legacyTimelinePadding)
            )
            return RecordingSessionGroup(
                id: "legacy-\(firstClip.url.lastPathComponent)",
                startedAt: startedAt,
                endedAt: endedAt,
                clips: cluster,
                isInferred: true
            )
        }
    }

    static func markerFraction(
        for clip: RecordingClip,
        sessionStart: Date,
        sessionEnd: Date
    ) -> Double {
        let duration = max(1, sessionEnd.timeIntervalSince(sessionStart))
        return min(1, max(0, clip.createdAt.timeIntervalSince(sessionStart) / duration))
    }
}

enum RecordingMergeKind: String {
    case selected
    case today
}

enum RecordingMergeError: LocalizedError {
    case notEnoughRecordings
    case missingAudioTrack
    case cannotCreateExporter
    case cannotDeleteSources(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .notEnoughRecordings:
            "합치려면 녹음이 두 개 이상 필요합니다."
        case .missingAudioTrack:
            "오디오가 없는 녹음이 포함되어 있습니다."
        case .cannotCreateExporter:
            "합친 녹음 파일을 만들 수 없습니다."
        case .cannotDeleteSources(let message):
            "합본은 만들었지만 원본 일부를 삭제하지 못했습니다. \(message)"
        case .exportFailed(let message):
            "녹음을 합치지 못했습니다. \(message)"
        }
    }
}

@MainActor
final class RecordingLibrary: ObservableObject {
    @Published private(set) var clips: [RecordingClip] = []

    nonisolated static let defaultDirectory: URL = {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("S.tand", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }()

    let directory: URL
    private var sleepSessions: [SleepRecordingSession] = []

    private var sessionManifestURL: URL {
        directory.appendingPathComponent(".sleep-sessions-v1.json")
    }

    init(directory: URL = RecordingLibrary.defaultDirectory) {
        self.directory = directory
        if directory.standardizedFileURL == Self.defaultDirectory.standardizedFileURL {
            installEmbeddedSamplesIfNeeded()
        }
        reload()
        closeOpenSessionsForRecovery()
    }

    var totalDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }

    var mergeableClips: [RecordingClip] {
        clips.filter { !$0.isMerged }
    }

    var recordingSessions: [RecordingSessionGroup] {
        let originals = mergeableClips
        let clipsByName = Dictionary(
            uniqueKeysWithValues: originals.map { ($0.url.lastPathComponent, $0) }
        )
        var assignedNames = Set<String>()
        var groups: [RecordingSessionGroup] = []

        for session in sleepSessions {
            let sessionClips = session.clipFileNames
                .compactMap { clipsByName[$0] }
                .sorted { $0.createdAt < $1.createdAt }
            guard !sessionClips.isEmpty else { continue }
            assignedNames.formUnion(sessionClips.map { $0.url.lastPathComponent })
            let lastClipEnd = sessionClips
                .map { $0.createdAt.addingTimeInterval($0.duration) }
                .max() ?? session.startedAt
            let endedAt = max(
                session.startedAt.addingTimeInterval(1),
                session.endedAt ?? max(Date(), lastClipEnd)
            )
            groups.append(
                RecordingSessionGroup(
                    id: "session-\(session.id.uuidString)",
                    startedAt: session.startedAt,
                    endedAt: endedAt,
                    clips: sessionClips,
                    isInferred: false
                )
            )
        }

        let legacyClips = originals.filter {
            !assignedNames.contains($0.url.lastPathComponent)
        }
        groups.append(contentsOf: SleepSessionGroupingPolicy.inferredGroups(from: legacyClips))
        return groups.sorted { $0.startedAt > $1.startedAt }
    }

    func mergeableClips(on date: Date, calendar: Calendar = .current) -> [RecordingClip] {
        mergeableClips.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
    }

    func reload() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            loadSleepSessions()
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            clips = urls
                .filter { $0.pathExtension.lowercased() == "m4a" }
                .compactMap(makeClip)
                .sorted { $0.createdAt > $1.createdAt }
            associateUnassignedClipsWithRecordedSessions()
        } catch {
            clips = []
        }
    }

    @discardableResult
    func beginSleepSession(at date: Date = Date()) -> UUID {
        let removedExpiredSessions = removeExpiredEmptySessions(at: date)
        if let openSession = sleepSessions.last(where: { $0.endedAt == nil }) {
            if removedExpiredSessions { persistSleepSessions() }
            return openSession.id
        }
        if let index = sleepSessions.indices
            .filter({ sleepSessions[$0].endedAt != nil })
            .max(by: { sleepSessions[$0].endedAt! < sleepSessions[$1].endedAt! }),
           let endedAt = sleepSessions[index].endedAt {
            let gap = date.timeIntervalSince(endedAt)
            if gap >= 0, gap <= SleepSessionGroupingPolicy.sleepModeResumeGap {
                sleepSessions[index].endedAt = nil
                persistSleepSessions()
                return sleepSessions[index].id
            }
        }
        let session = SleepRecordingSession(
            id: UUID(),
            startedAt: date,
            endedAt: nil,
            clipFileNames: []
        )
        sleepSessions.append(session)
        persistSleepSessions()
        return session.id
    }

    func endSleepSession(id: UUID?, at date: Date = Date()) {
        guard let id,
              let index = sleepSessions.firstIndex(where: { $0.id == id })
        else { return }
        sleepSessions[index].endedAt = max(sleepSessions[index].startedAt, date)
        persistSleepSessions()
        objectWillChange.send()
    }

    func add(_ url: URL, sessionID: UUID? = nil) {
        if let existingClip = clips.first(where: { $0.url == url }) {
            associate(existingClip, with: sessionID)
            return
        }
        guard let clip = makeClip(url) else { return }
        associate(clip, with: sessionID)
        clips.append(clip)
        clips.sort { $0.createdAt > $1.createdAt }
    }

    func delete(_ clip: RecordingClip) {
        try? FileManager.default.removeItem(at: clip.url)
        removeSessionReferences(to: [clip.url])
        reload()
    }

    func delete(_ selectedClips: [RecordingClip]) throws {
        let availableURLs = Set(clips.map(\.url))
        for clip in selectedClips where availableURLs.contains(clip.url) {
            try FileManager.default.removeItem(at: clip.url)
        }
        removeSessionReferences(to: selectedClips.map(\.url))
        reload()
    }

    func deleteAll(at date: Date = Date()) {
        // clips 배열에 아직 반영되지 않은 저장 완료 콜백도 빠짐없이 지운다.
        let storedAudioURLs = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension.lowercased() == "m4a" } ?? []
        for url in storedAudioURLs {
            try? FileManager.default.removeItem(at: url)
        }
        let pendingDirectory = directory.appendingPathComponent(".Pending", isDirectory: true)
        try? FileManager.default.removeItem(at: pendingDirectory)
        // 파일 삭제가 잠자기 모드 이력을 바꾸면 안 된다. 열린 세션과 30분 안에
        // 재개할 수 있는 최근 종료 세션은 비어 있어도 남기고, 오래된 빈 이력만 정리한다.
        for index in sleepSessions.indices {
            sleepSessions[index].clipFileNames.removeAll()
        }
        _ = removeExpiredEmptySessions(at: date)
        persistSleepSessions()
        reload()
    }

    func merge(
        _ selectedClips: [RecordingClip],
        kind: RecordingMergeKind,
        deleteSources: Bool = false
    ) async throws -> RecordingClip {
        let availableURLs = Set(mergeableClips.map(\.url))
        let sourceClips = selectedClips
            .filter { availableURLs.contains($0.url) }
            .sorted { $0.createdAt < $1.createdAt }
        guard sourceClips.count >= 2 else {
            throw RecordingMergeError.notEnoughRecordings
        }

        let outputURL = directory.appendingPathComponent(
            Self.mergedFileName(kind: kind, date: sourceClips[0].createdAt)
        )
        try await RecordingMerger.merge(
            sourceURLs: sourceClips.map(\.url),
            outputURL: outputURL,
            gapDuration: 0.5
        )
        reload()

        guard clips.contains(where: { $0.url == outputURL }) else {
            throw RecordingMergeError.cannotCreateExporter
        }

        if deleteSources {
            do {
                try delete(sourceClips)
            } catch {
                throw RecordingMergeError.cannotDeleteSources(error.localizedDescription)
            }
        }

        guard let mergedClip = clips.first(where: { $0.url == outputURL }) else {
            throw RecordingMergeError.cannotCreateExporter
        }
        return mergedClip
    }

    func mergeToday(on date: Date = Date(), calendar: Calendar = .current) async throws -> RecordingClip {
        try await merge(mergeableClips(on: date, calendar: calendar), kind: .today)
    }

    private func installEmbeddedSamplesIfNeeded() {
        let markerURL = directory.appendingPathComponent(".embedded-snore-samples-v1")
        guard !FileManager.default.fileExists(atPath: markerURL.path) else { return }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let calendar = Calendar.current
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()),
                  let firstTime = calendar.date(
                    bySettingHour: 1,
                    minute: 0,
                    second: 0,
                    of: yesterday
                  )
            else { return }

            let samples = [
                (resource: "sample-snore-5s", minuteOffset: 0),
                (resource: "sample-snore-10s", minuteOffset: 20),
                (resource: "sample-snore-15s", minuteOffset: 40)
            ]
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"

            for sample in samples {
                guard let sourceURL = Bundle.main.url(
                    forResource: sample.resource,
                    withExtension: "m4a"
                ), let recordingDate = calendar.date(
                    byAdding: .minute,
                    value: sample.minuteOffset,
                    to: firstTime
                ) else { continue }

                let filename = "sleep-sound-\(formatter.string(from: recordingDate))-embedded-snore.m4a"
                let destinationURL = directory.appendingPathComponent(filename)
                if !FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                }
            }

            try Data().write(to: markerURL, options: .atomic)
        } catch {
            // 샘플은 테스트 편의 기능이므로 실패해도 실제 녹음 보관함은 정상 동작해야 합니다.
        }
    }

    private func makeClip(_ url: URL) -> RecordingClip? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let duration = Double(file.length) / file.processingFormat.sampleRate
        let resourceValues = try? url.resourceValues(
            forKeys: [.creationDateKey, .contentModificationDateKey]
        )
        return RecordingClip(
            url: url,
            createdAt: Self.dateFromFileName(url)
                ?? resourceValues?.creationDate
                ?? resourceValues?.contentModificationDate
                ?? .distantPast,
            duration: duration
        )
    }

    private func loadSleepSessions() {
        guard let data = try? Data(contentsOf: sessionManifestURL),
              let decoded = try? JSONDecoder().decode([SleepRecordingSession].self, from: data)
        else {
            sleepSessions = []
            return
        }
        sleepSessions = decoded
    }

    private func persistSleepSessions() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(sleepSessions)
            try data.write(to: sessionManifestURL, options: .atomic)
        } catch {
            // 녹음 파일 자체는 보존하고, 세션 메타데이터는 다음 저장 때 다시 시도합니다.
        }
    }

    private func closeOpenSessionsForRecovery() {
        var changed = false
        for index in sleepSessions.indices where sleepSessions[index].endedAt == nil {
            // 비정상 종료에는 실제 모드 이탈 시각이 존재하지 않는다. 녹음 시각을
            // 대신 쓰면 사용자가 정한 모드 기준이 무너지므로 마지막 확정 상태 변경
            // 시각인 startedAt에서 보수적으로 닫는다. 정상 종료/백그라운드는
            // StandViewModel이 실제 이탈 시각으로 endSleepSession을 먼저 기록한다.
            sleepSessions[index].endedAt = sleepSessions[index].startedAt
            changed = true
        }
        if changed { persistSleepSessions() }
    }

    private func associate(_ clip: RecordingClip, with requestedSessionID: UUID?) {
        guard !clip.isMerged else { return }
        let fallbackSessionID = sleepSessions
            .reversed()
            .first { session in
                let lowerBound = session.startedAt.addingTimeInterval(-5)
                let upperBound = (session.endedAt ?? .distantFuture).addingTimeInterval(5)
                return clip.createdAt >= lowerBound && clip.createdAt <= upperBound
            }?
            .id
        guard let sessionID = requestedSessionID ?? fallbackSessionID,
              let index = sleepSessions.firstIndex(where: { $0.id == sessionID })
        else { return }
        let name = clip.url.lastPathComponent
        guard !sleepSessions[index].clipFileNames.contains(name) else { return }
        sleepSessions[index].clipFileNames.append(name)
        persistSleepSessions()
    }

    private func associateUnassignedClipsWithRecordedSessions() {
        guard !sleepSessions.isEmpty else { return }
        var assignedNames = Set(sleepSessions.flatMap(\.clipFileNames))
        var changed = false

        for clip in clips where !clip.isMerged {
            let name = clip.url.lastPathComponent
            guard !assignedNames.contains(name) else { continue }
            guard let index = sleepSessions.indices.reversed().first(where: { index in
                let session = sleepSessions[index]
                let lowerBound = session.startedAt.addingTimeInterval(-5)
                let upperBound = (session.endedAt ?? .distantFuture).addingTimeInterval(5)
                return clip.createdAt >= lowerBound && clip.createdAt <= upperBound
            }) else { continue }

            sleepSessions[index].clipFileNames.append(name)
            assignedNames.insert(name)
            changed = true
        }

        if changed { persistSleepSessions() }
    }

    private func removeSessionReferences(to urls: [URL]) {
        let names = Set(urls.map(\.lastPathComponent))
        guard !names.isEmpty else { return }
        for index in sleepSessions.indices {
            sleepSessions[index].clipFileNames.removeAll { names.contains($0) }
        }
        _ = removeExpiredEmptySessions(at: Date())
        persistSleepSessions()
    }

    @discardableResult
    private func removeExpiredEmptySessions(at referenceDate: Date) -> Bool {
        let previousCount = sleepSessions.count
        sleepSessions.removeAll { session in
            guard session.clipFileNames.isEmpty, let endedAt = session.endedAt else {
                return false
            }
            return referenceDate.timeIntervalSince(endedAt)
                > SleepSessionGroupingPolicy.sleepModeResumeGap
        }
        return sleepSessions.count != previousCount
    }

    private static func dateFromFileName(_ url: URL) -> Date? {
        let prefix = "sleep-sound-"
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix(prefix) else { return nil }

        let timestamp = String(name.dropFirst(prefix.count).prefix(19))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.date(from: timestamp)
    }

    private static func mergedFileName(kind: RecordingMergeKind, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let nonce = UUID().uuidString.prefix(8).lowercased()
        return "sleep-sound-\(formatter.string(from: date))-\(nonce)-\(kind.rawValue)-merged.m4a"
    }
}

private enum RecordingMerger {
    static func merge(
        sourceURLs: [URL],
        outputURL: URL,
        gapDuration: TimeInterval
    ) async throws {
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RecordingMergeError.cannotCreateExporter
        }

        var insertionTime = CMTime.zero
        for (index, sourceURL) in sourceURLs.enumerated() {
            let asset = AVURLAsset(url: sourceURL)
            let duration = try await asset.load(.duration)
            guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                throw RecordingMergeError.missingAudioTrack
            }
            try compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: sourceTrack,
                at: insertionTime
            )
            insertionTime = CMTimeAdd(insertionTime, duration)
            if index < sourceURLs.count - 1 {
                insertionTime = CMTimeAdd(
                    insertionTime,
                    CMTime(seconds: gapDuration, preferredTimescale: 600)
                )
            }
        }

        guard let exporter = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw RecordingMergeError.cannotCreateExporter
        }

        try? FileManager.default.removeItem(at: outputURL)
        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }

        guard exporter.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw RecordingMergeError.exportFailed(
                exporter.error?.localizedDescription ?? "알 수 없는 오류"
            )
        }
    }
}

@MainActor
final class RecordingPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingURL: URL?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    func toggle(_ clip: RecordingClip) {
        if playingURL == clip.url {
            if player?.isPlaying == true {
                pause()
            } else {
                resume()
            }
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: clip.url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            playingURL = clip.url
            duration = player.duration
            currentTime = 0
            isPlaying = true
            startProgressTimer()
        } catch {
            stop()
        }
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clampedTime = min(max(0, time), player.duration)
        player.currentTime = clampedTime
        currentTime = clampedTime
    }

    func pause() {
        player?.pause()
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func resume() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startProgressTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
        currentTime = 0
        duration = 0
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                self.duration = player.duration
                self.isPlaying = player.isPlaying
            }
        }
        if let progressTimer {
            RunLoop.main.add(progressTimer, forMode: .common)
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in stop() }
    }
}
