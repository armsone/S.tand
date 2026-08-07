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

    init(directory: URL = RecordingLibrary.defaultDirectory) {
        self.directory = directory
        if directory.standardizedFileURL == Self.defaultDirectory.standardizedFileURL {
            installEmbeddedSamplesIfNeeded()
        }
        reload()
    }

    var totalDuration: TimeInterval {
        clips.reduce(0) { $0 + $1.duration }
    }

    var mergeableClips: [RecordingClip] {
        clips.filter { !$0.isMerged }
    }

    func mergeableClips(on date: Date, calendar: Calendar = .current) -> [RecordingClip] {
        mergeableClips.filter { calendar.isDate($0.createdAt, inSameDayAs: date) }
    }

    func reload() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            clips = urls
                .filter { $0.pathExtension.lowercased() == "m4a" }
                .compactMap(makeClip)
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            clips = []
        }
    }

    func add(_ url: URL) {
        guard !clips.contains(where: { $0.url == url }), let clip = makeClip(url) else { return }
        clips.append(clip)
        clips.sort { $0.createdAt > $1.createdAt }
    }

    func delete(_ clip: RecordingClip) {
        try? FileManager.default.removeItem(at: clip.url)
        reload()
    }

    func delete(_ selectedClips: [RecordingClip]) throws {
        let availableURLs = Set(clips.map(\.url))
        for clip in selectedClips where availableURLs.contains(clip.url) {
            try FileManager.default.removeItem(at: clip.url)
        }
        reload()
    }

    func deleteAll() {
        for clip in clips {
            try? FileManager.default.removeItem(at: clip.url)
        }
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
        return RecordingClip(
            url: url,
            createdAt: Self.dateFromFileName(url) ?? .distantPast,
            duration: duration
        )
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
