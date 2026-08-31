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

struct SleepStartleEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
}

struct SleepRecordingSession: Identifiable, Codable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var clipFileNames: [String]
    var startleEvents: [SleepStartleEvent]
    /// 오디오 캡처가 실제로 `.monitoring` 상태에 도달했는지를 기록한다. 소리
    /// 후보가 없는 밤과, 감시 자체가 시작되지 못한 실패를 구분하는 최소한의
    /// 근거로 쓰인다.
    var monitoringConfirmed: Bool

    init(
        id: UUID,
        startedAt: Date,
        endedAt: Date?,
        clipFileNames: [String],
        startleEvents: [SleepStartleEvent] = [],
        monitoringConfirmed: Bool = false
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.clipFileNames = clipFileNames
        self.startleEvents = startleEvents
        self.monitoringConfirmed = monitoringConfirmed
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, clipFileNames, startleEvents, monitoringConfirmed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        clipFileNames = try container.decodeIfPresent(
            [String].self,
            forKey: .clipFileNames
        ) ?? []
        startleEvents = try container.decodeIfPresent(
            [SleepStartleEvent].self,
            forKey: .startleEvents
        ) ?? []
        // 이전 버전 기록에는 이 값이 없다. 이미 저장된 소리 후보나 화들짝 반응이
        // 있다면 감시가 실제로 진행됐다는 뜻이므로 그 사실로 값을 보수적으로 채운다.
        monitoringConfirmed = try container.decodeIfPresent(
            Bool.self,
            forKey: .monitoringConfirmed
        ) ?? !(clipFileNames.isEmpty && startleEvents.isEmpty)
    }
}

struct RecordingSessionGroup: Identifiable {
    let id: String
    let startedAt: Date
    let endedAt: Date
    let clips: [RecordingClip]
    let startleEvents: [SleepStartleEvent]
    let isInferred: Bool
    /// 소리 후보 없이 끝난 구간이 실제로 감시된 조용한 밤인지, 감시 자체가
    /// 실패한 구간인지 구분한다. 추정 구간(`isInferred`)에는 근거가 없어 항상
    /// `true`로 취급해 과거 기록의 문구를 바꾸지 않는다.
    let monitoringConfirmed: Bool

    init(
        id: String,
        startedAt: Date,
        endedAt: Date,
        clips: [RecordingClip],
        startleEvents: [SleepStartleEvent],
        isInferred: Bool,
        monitoringConfirmed: Bool = true
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.clips = clips
        self.startleEvents = startleEvents
        self.isInferred = isInferred
        self.monitoringConfirmed = monitoringConfirmed
    }

    var totalDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }

    var insight: SleepSessionInsight {
        SleepSessionInsight(session: self)
    }
}

struct SleepSessionInsight: Equatable {
    static let bucketCount = 12

    let sessionDuration: TimeInterval
    let soundCount: Int
    let soundDuration: TimeInterval
    let movementCount: Int
    let activityBuckets: [Int]
    let busiestBucketIndex: Int?

    init(session: RecordingSessionGroup) {
        sessionDuration = max(0, session.endedAt.timeIntervalSince(session.startedAt))
        soundCount = session.clips.count
        soundDuration = session.totalDuration
        movementCount = session.startleEvents.count

        var buckets = Array(repeating: 0, count: Self.bucketCount)
        let dates = session.clips.map(\.createdAt) + session.startleEvents.map(\.startedAt)
        for date in dates {
            let fraction = SleepSessionGroupingPolicy.markerFraction(
                for: date,
                sessionStart: session.startedAt,
                sessionEnd: session.endedAt
            )
            let index = min(Self.bucketCount - 1, Int(fraction * Double(Self.bucketCount)))
            buckets[index] += 1
        }
        activityBuckets = buckets
        busiestBucketIndex = buckets.max().flatMap { maximum in
            maximum > 0 ? buckets.firstIndex(of: maximum) : nil
        }
    }

    var eventsPerHour: Double {
        guard sessionDuration > 0 else { return 0 }
        return Double(soundCount + movementCount) / (sessionDuration / 3_600)
    }

    func busiestRange(sessionStart: Date) -> Range<Date>? {
        guard let busiestBucketIndex, sessionDuration > 0 else { return nil }
        let bucketDuration = sessionDuration / Double(Self.bucketCount)
        let start = sessionStart.addingTimeInterval(Double(busiestBucketIndex) * bucketDuration)
        return start..<start.addingTimeInterval(bucketDuration)
    }
}

/// 소리 후보와 화들짝 반응이 전혀 없는 구간에 보여줄 문구를 결정한다.
/// 실제로 감시가 확인된 조용한 밤과, 감시 자체가 실패한 구간을 구분해
/// 실패한 구간을 "조용한 밤"으로 오인하지 않도록 한다.
enum SleepSessionQuietNightPolicy {
    static func description(for session: RecordingSessionGroup) -> String? {
        let insight = session.insight
        guard insight.soundCount == 0, insight.movementCount == 0 else { return nil }
        return session.monitoringConfirmed
            ? "감시는 정상적으로 진행됐고 저장할 소리가 없었어요"
            : "감시가 정상적으로 진행되지 못해 저장된 소리가 없어요"
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
                startleEvents: [],
                isInferred: true
            )
        }
    }

    static func markerFraction(
        for clip: RecordingClip,
        sessionStart: Date,
        sessionEnd: Date
    ) -> Double {
        markerFraction(
            for: clip.createdAt,
            sessionStart: sessionStart,
            sessionEnd: sessionEnd
        )
    }

    static func markerFraction(
        for date: Date,
        sessionStart: Date,
        sessionEnd: Date
    ) -> Double {
        let duration = max(1, sessionEnd.timeIntervalSince(sessionStart))
        return min(1, max(0, date.timeIntervalSince(sessionStart) / duration))
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
            removeEmbeddedSamplesIfPresent()
        }
        reload()
        closeOpenSessionsForRecovery()
    }

    var totalDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }

    var storedAudioByteCount: Int64 {
        clips.reduce(0) { result, clip in
            let size = (try? clip.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return result + Int64(size)
        }
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
            // 소리 후보가 없어도 세션 자체는 보여준다. 그래야 조용히 잘 감시된
            // 밤과 감시가 아예 실패한 밤을 사용자가 구분할 수 있다.
            assignedNames.formUnion(sessionClips.map { $0.url.lastPathComponent })
            let lastClipEnd = sessionClips
                .map { $0.createdAt.addingTimeInterval($0.duration) }
                .max() ?? session.startedAt
            let lastStartleEnd = session.startleEvents
                .map { $0.endedAt ?? Date() }
                .max() ?? session.startedAt
            let endedAt = max(
                session.startedAt.addingTimeInterval(1),
                session.endedAt ?? max(Date(), lastClipEnd, lastStartleEnd)
            )
            groups.append(
                RecordingSessionGroup(
                    id: "session-\(session.id.uuidString)",
                    startedAt: session.startedAt,
                    endedAt: endedAt,
                    clips: sessionClips,
                    startleEvents: session.startleEvents,
                    isInferred: false,
                    monitoringConfirmed: session.monitoringConfirmed
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
            clipFileNames: [],
            startleEvents: []
        )
        sleepSessions.append(session)
        persistSleepSessions()
        return session.id
    }

    func endSleepSession(id: UUID?, at date: Date = Date()) {
        guard let id,
              let index = sleepSessions.firstIndex(where: { $0.id == id })
        else { return }
        let end = max(sleepSessions[index].startedAt, date)
        sleepSessions[index].endedAt = end
        for eventIndex in sleepSessions[index].startleEvents.indices
            where sleepSessions[index].startleEvents[eventIndex].endedAt == nil {
            sleepSessions[index].startleEvents[eventIndex].endedAt = max(
                sleepSessions[index].startleEvents[eventIndex].startedAt,
                end
            )
        }
        persistSleepSessions()
        objectWillChange.send()
    }

    /// 오디오 캡처가 실제로 감시 상태에 도달했을 때 한 번 표시한다. 이후
    /// 소리가 없어도 이 값으로 조용한 밤과 감시 실패를 구분한다.
    func confirmMonitoring(sessionID: UUID?) {
        guard let sessionID,
              let index = sleepSessions.firstIndex(where: { $0.id == sessionID }),
              !sleepSessions[index].monitoringConfirmed
        else { return }
        sleepSessions[index].monitoringConfirmed = true
        persistSleepSessions()
        objectWillChange.send()
    }

    @discardableResult
    func beginStartleEvent(sessionID: UUID?, at date: Date = Date()) -> UUID? {
        guard let sessionID,
              let index = sleepSessions.firstIndex(where: { $0.id == sessionID })
        else { return nil }
        if let openEvent = sleepSessions[index].startleEvents.last(where: { $0.endedAt == nil }) {
            return openEvent.id
        }
        let event = SleepStartleEvent(id: UUID(), startedAt: date, endedAt: nil)
        objectWillChange.send()
        sleepSessions[index].startleEvents.append(event)
        persistSleepSessions()
        return event.id
    }

    func endStartleEvent(id: UUID?, at date: Date = Date()) {
        guard let id else { return }
        for sessionIndex in sleepSessions.indices {
            guard let eventIndex = sleepSessions[sessionIndex].startleEvents.firstIndex(
                where: { $0.id == id }
            ) else { continue }
            let startedAt = sleepSessions[sessionIndex].startleEvents[eventIndex].startedAt
            objectWillChange.send()
            sleepSessions[sessionIndex].startleEvents[eventIndex].endedAt = max(startedAt, date)
            persistSleepSessions()
            return
        }
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

    func delete(_ clip: RecordingClip) throws {
        do {
            try FileManager.default.removeItem(at: clip.url)
            removeSessionReferences(to: [clip.url])
        } catch {
            // Keep the session association if the audio itself remains on disk.
            reload()
            throw error
        }
        reload()
    }

    func delete(_ selectedClips: [RecordingClip]) throws {
        let availableURLs = Set(clips.map(\.url))
        var deletedURLs: [URL] = []
        var firstError: Error?
        for clip in selectedClips where availableURLs.contains(clip.url) {
            do {
                try FileManager.default.removeItem(at: clip.url)
                deletedURLs.append(clip.url)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        removeSessionReferences(to: deletedURLs)
        reload()
        if let firstError { throw firstError }
    }

    /// 잠자리 패널 하나를 통째로 지운다. 그 안의 모든 녹음 파일과, 영속된
    /// 세션 메타데이터를 함께 제거해 빈 패널이 남지 않도록 한다.
    func deleteSession(_ session: RecordingSessionGroup) throws {
        var firstError: Error?
        for clip in session.clips {
            do {
                try FileManager.default.removeItem(at: clip.url)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        removeSessionReferences(to: session.clips.map(\.url))
        if let sessionID = Self.sessionID(fromGroupID: session.id),
           let index = sleepSessions.firstIndex(where: { $0.id == sessionID }) {
            sleepSessions.remove(at: index)
            persistSleepSessions()
        }
        reload()
        if let firstError { throw firstError }
    }

    /// 화면의 "전체 삭제"는 녹음뿐 아니라 잠자리 패널 이력까지 모두 지우는
    /// 명시적인 초기화 동작이다. `deleteAll(at:)`은 진행 중이거나 방금 끝난
    /// 잠자기 모드를 재개 판정용으로 보존해야 하므로 그 규칙은 그대로 두고,
    /// 이 메서드에서만 남은 세션 메타데이터를 추가로 비운다.
    func deleteAllIncludingSessions(at date: Date = Date()) throws {
        var deleteAllError: Error?
        do {
            try deleteAll(at: date)
        } catch {
            deleteAllError = error
        }
        if !sleepSessions.isEmpty {
            sleepSessions.removeAll()
            persistSleepSessions()
            reload()
        }
        if let deleteAllError { throw deleteAllError }
    }

    func deleteAll(at date: Date = Date()) throws {
        // clips 배열에 아직 반영되지 않은 저장 완료 콜백도 빠짐없이 지운다.
        let storedAudioURLs = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension.lowercased() == "m4a" } ?? []
        var deletedNames = Set<String>()
        var firstError: Error?
        for url in storedAudioURLs {
            do {
                try FileManager.default.removeItem(at: url)
                deletedNames.insert(url.lastPathComponent)
            } catch {
                // Failed files and their session associations remain visible after reload.
                if firstError == nil { firstError = error }
            }
        }
        let pendingDirectory = directory.appendingPathComponent(".Pending", isDirectory: true)
        if FileManager.default.fileExists(atPath: pendingDirectory.path) {
            do {
                try FileManager.default.removeItem(at: pendingDirectory)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        // 파일 삭제가 잠자기 모드 이력을 바꾸면 안 된다. 열린 세션과 30분 안에
        // 재개할 수 있는 최근 종료 세션은 비어 있어도 남기고, 오래된 빈 이력만 정리한다.
        for index in sleepSessions.indices {
            sleepSessions[index].clipFileNames.removeAll { deletedNames.contains($0) }
        }
        _ = removeExpiredEmptySessions(at: date)
        persistSleepSessions()
        reload()
        if let firstError { throw firstError }
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

    private func removeEmbeddedSamplesIfPresent() {
        let markerURL = directory.appendingPathComponent(".embedded-snore-samples-v1")
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        urls.filter {
            $0.deletingPathExtension().lastPathComponent.contains("-embedded-snore")
        }.forEach { try? FileManager.default.removeItem(at: $0) }
        try? FileManager.default.removeItem(at: markerURL)
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
            for eventIndex in sleepSessions[index].startleEvents.indices
                where sleepSessions[index].startleEvents[eventIndex].endedAt == nil {
                sleepSessions[index].startleEvents[eventIndex].endedAt = max(
                    sleepSessions[index].startleEvents[eventIndex].startedAt,
                    sleepSessions[index].startedAt
                )
            }
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
            // 감시가 실제로 확인된 세션은 소리 후보가 없어도 조용한 밤의 근거로
            // 남긴다. 정리 대상은 감시가 시작조차 못 한 순간적인 진입뿐이다.
            guard !session.monitoringConfirmed,
                  session.clipFileNames.isEmpty,
                  session.startleEvents.isEmpty,
                  let endedAt = session.endedAt else {
                return false
            }
            return referenceDate.timeIntervalSince(endedAt)
                > SleepSessionGroupingPolicy.sleepModeResumeGap
        }
        return sleepSessions.count != previousCount
    }

    private static func sessionID(fromGroupID groupID: String) -> UUID? {
        let prefix = "session-"
        guard groupID.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(groupID.dropFirst(prefix.count)))
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
final class RecordingPlayer: NSObject, ObservableObject {
    @Published private(set) var playingURL: URL?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var boostEnabled = true

    var onPlaybackFinished: (() -> Void)?

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let gainUnit = AVAudioUnitEQ(numberOfBands: 0)
    private var audioFile: AVAudioFile?
    private var scheduledStartFrame: AVAudioFramePosition = 0
    private var playbackToken: UUID?
    private var progressTimer: Timer?

    override init() {
        super.init()
        engine.attach(playerNode)
        engine.attach(gainUnit)
        gainUnit.globalGain = 6
    }

    func toggle(_ clip: RecordingClip) {
        if playingURL == clip.url {
            if playerNode.isPlaying {
                pause()
            } else {
                resume()
            }
            return
        }

        play(clip)
    }

    func play(_ clip: RecordingClip) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let file = try AVAudioFile(forReading: clip.url)
            try prepareEngine(for: file)
            audioFile = file
            playingURL = clip.url
            duration = Double(file.length) / file.processingFormat.sampleRate
            currentTime = 0
            schedule(from: 0, shouldPlay: true)
        } catch {
            stop()
        }
    }

    func seek(to time: TimeInterval) {
        guard audioFile != nil else { return }
        let clampedTime = min(max(0, time), duration)
        currentTime = clampedTime
        schedule(from: clampedTime, shouldPlay: isPlaying)
    }

    func pause() {
        updateProgress()
        playerNode.pause()
        isPlaying = false
        progressTimer?.invalidate()
        progressTimer = nil
    }

    func resume() {
        guard audioFile != nil else { return }
        playerNode.play()
        isPlaying = true
        startProgressTimer()
    }

    func toggleBoost() {
        boostEnabled.toggle()
        gainUnit.globalGain = boostEnabled ? 6 : 0
    }

    func stop() {
        playbackToken = nil
        playerNode.stop()
        engine.stop()
        audioFile = nil
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
                guard let self else { return }
                self.updateProgress()
                self.isPlaying = self.playerNode.isPlaying
            }
        }
        if let progressTimer {
            RunLoop.main.add(progressTimer, forMode: .common)
        }
    }

    private func prepareEngine(for file: AVAudioFile) throws {
        playerNode.stop()
        engine.stop()
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(gainUnit)
        let format = file.processingFormat
        engine.connect(playerNode, to: gainUnit, format: format)
        engine.connect(gainUnit, to: engine.mainMixerNode, format: format)
        gainUnit.globalGain = boostEnabled ? 6 : 0
        engine.prepare()
        try engine.start()
    }

    private func schedule(from time: TimeInterval, shouldPlay: Bool) {
        guard let audioFile else { return }
        playerNode.stop()
        let sampleRate = audioFile.processingFormat.sampleRate
        let startFrame = min(
            audioFile.length,
            max(0, AVAudioFramePosition(time * sampleRate))
        )
        let remainingFrames = audioFile.length - startFrame
        guard remainingFrames > 0 else {
            stop()
            return
        }
        let token = UUID()
        playbackToken = token
        scheduledStartFrame = startFrame
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: startFrame,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: nil
        ) { [weak self] in
            Task { @MainActor in
                guard let self, self.playbackToken == token else { return }
                self.stop()
                self.onPlaybackFinished?()
            }
        }
        if shouldPlay {
            playerNode.play()
            isPlaying = true
            startProgressTimer()
        } else {
            isPlaying = false
        }
    }

    private func updateProgress() {
        guard let audioFile,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else { return }
        let absoluteFrame = scheduledStartFrame + playerTime.sampleTime
        currentTime = min(
            duration,
            max(0, Double(absoluteFrame) / audioFile.processingFormat.sampleRate)
        )
    }
}
