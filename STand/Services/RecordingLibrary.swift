import AVFoundation
import Combine
import Foundation

struct RecordingClip: Identifiable, Hashable {
    let url: URL
    let createdAt: Date
    let duration: TimeInterval

    var id: URL { url }
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
}

@MainActor
final class RecordingPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingURL: URL?

    private var player: AVAudioPlayer?

    func toggle(_ clip: RecordingClip) {
        if playingURL == clip.url {
            stop()
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
        } catch {
            stop()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in stop() }
    }
}
