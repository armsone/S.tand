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

    var mergedTitle: String? {
        guard isMerged else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        if name.contains("-today-merged") { return "오늘 녹음 합본" }
        if name.contains("-selected-merged") { return "선택 녹음 합본" }
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
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .notEnoughRecordings:
            "합치려면 녹음이 두 개 이상 필요합니다."
        case .missingAudioTrack:
            "오디오가 없는 녹음이 포함되어 있습니다."
        case .cannotCreateExporter:
            "합친 녹음 파일을 만들 수 없습니다."
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

    func deleteAll() {
        for clip in clips {
            try? FileManager.default.removeItem(at: clip.url)
        }
        reload()
    }

    func merge(_ selectedClips: [RecordingClip], kind: RecordingMergeKind) async throws -> RecordingClip {
        let availableURLs = Set(mergeableClips.map(\.url))
        let sourceClips = selectedClips
            .filter { availableURLs.contains($0.url) }
            .sorted { $0.createdAt < $1.createdAt }
        guard sourceClips.count >= 2 else {
            throw RecordingMergeError.notEnoughRecordings
        }

        let outputURL = directory.appendingPathComponent(Self.mergedFileName(kind: kind))
        try await RecordingMerger.merge(
            sourceURLs: sourceClips.map(\.url),
            outputURL: outputURL
        )
        reload()

        guard let mergedClip = clips.first(where: { $0.url == outputURL }) else {
            throw RecordingMergeError.cannotCreateExporter
        }
        return mergedClip
    }

    func mergeToday(on date: Date = Date(), calendar: Calendar = .current) async throws -> RecordingClip {
        try await merge(mergeableClips(on: date, calendar: calendar), kind: .today)
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
    static func merge(sourceURLs: [URL], outputURL: URL) async throws {
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw RecordingMergeError.cannotCreateExporter
        }

        var insertionTime = CMTime.zero
        for sourceURL in sourceURLs {
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
