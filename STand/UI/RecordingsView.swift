import SwiftUI

struct RecordingsView: View {
    @ObservedObject var library: RecordingLibrary
    let playbackDisabled: Bool
    @StateObject private var player = RecordingPlayer()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeleteAll = false
    @State private var confirmsDeleteSelected = false
    @State private var confirmsMergeAndDelete = false
    @State private var selectedClipURLs: Set<URL> = []
    @State private var isMerging = false
    @State private var mergeErrorMessage: String?
    @State private var mergeStatusMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if library.clips.isEmpty {
                    ContentUnavailableView(
                        "저장된 수면 소리가 없습니다",
                        systemImage: "waveform",
                        description: Text("취침 세션 중 지속되는 소리가 감지되면 필요한 구간만 여기에 저장합니다.")
                    )
                } else {
                    List {
                        if playbackDisabled {
                            Label(
                                "재생은 취침 세션을 종료한 뒤 사용할 수 있습니다.",
                                systemImage: "info.circle"
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }

                        if !library.mergeableClips.isEmpty {
                            selectionActions
                        }

                        if !mergedClips.isEmpty {
                            Section("합친 녹음 · \(mergedClips.count)개") {
                                ForEach(mergedClips) { clip in
                                    recordingRow(clip)
                                }
                            }
                        }

                        ForEach(originalGroups) { group in
                            Section {
                                ForEach(group.clips) { clip in
                                    recordingRow(clip)
                                }
                            } header: {
                                DailySleepTimelineHeader(date: group.date, clips: group.clips)
                                    .textCase(nil)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let playingURL = player.playingURL,
                   let clip = library.clips.first(where: { $0.url == playingURL }) {
                    PlaybackProgressBar(clip: clip, player: player)
                }
            }
            .navigationTitle("수면 소리")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
                if !library.clips.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("선택 모두 해제", systemImage: "checkmark.circle.badge.xmark") {
                                selectedClipURLs.removeAll()
                            }
                            .disabled(selectedClipURLs.isEmpty)

                            Divider()

                            Button("전체 삭제", systemImage: "trash", role: .destructive) {
                                confirmsDeleteAll = true
                            }
                        } label: {
                            Label("목록 작업", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog(
                "저장된 수면 소리를 모두 삭제할까요?",
                isPresented: $confirmsDeleteAll,
                titleVisibility: .visible
            ) {
                Button("모두 삭제", role: .destructive) {
                    player.stop()
                    selectedClipURLs.removeAll()
                    library.deleteAll()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("삭제한 녹음은 복구할 수 없습니다.")
            }
            .confirmationDialog(
                "선택한 녹음 \(selectedClips.count)개를 삭제할까요?",
                isPresented: $confirmsDeleteSelected,
                titleVisibility: .visible
            ) {
                Button("선택 항목 삭제", role: .destructive) {
                    deleteSelectedRecordings()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("삭제한 원본 녹음은 복구할 수 없습니다.")
            }
            .confirmationDialog(
                "합친 뒤 원본 \(selectedClips.count)개를 삭제할까요?",
                isPresented: $confirmsMergeAndDelete,
                titleVisibility: .visible
            ) {
                Button("합치고 지우기", role: .destructive) {
                    mergeSelectedRecordings(deleteSources: true)
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("합본은 남지만 선택한 원본 녹음은 복구할 수 없습니다.")
            }
            .alert(
                "작업을 완료하지 못했습니다",
                isPresented: Binding(
                    get: { mergeErrorMessage != nil },
                    set: { if !$0 { mergeErrorMessage = nil } }
                )
            ) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(mergeErrorMessage ?? "알 수 없는 오류가 발생했습니다.")
            }
            .onAppear { library.reload() }
            .onDisappear { player.stop() }
        }
    }

    private var selectionActions: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    selectedClipURLs = RecordingSelectionPolicy.all(in: library.mergeableClips)
                } label: {
                    Label("전체 선택", systemImage: "checkmark.square.fill")
                }

                Button {
                    selectedClipURLs = RecordingSelectionPolicy.today(in: library.mergeableClips)
                } label: {
                    Label("오늘 선택", systemImage: "calendar.badge.checkmark")
                }
                .disabled(todayClips.isEmpty)

                Spacer(minLength: 0)

                if isMerging {
                    ProgressView()
                } else {
                    Text("\(selectedClipURLs.count)개")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)

            Button {
                confirmsMergeAndDelete = true
            } label: {
                Label("합치고 지우기", systemImage: "waveform.path.badge.minus")
            }
            .disabled(playbackDisabled || isMerging || selectedClips.count < 2)

            Button {
                mergeSelectedRecordings(deleteSources: false)
            } label: {
                Label("합치기", systemImage: "waveform.path.badge.plus")
            }
            .disabled(playbackDisabled || isMerging || selectedClips.count < 2)

            Button(role: .destructive) {
                confirmsDeleteSelected = true
            } label: {
                Label("삭제하기", systemImage: "trash")
            }
            .disabled(isMerging || selectedClips.isEmpty)
        } footer: {
            Text(mergeStatusMessage ?? "전체 또는 오늘 녹음을 선택한 뒤 합치거나 삭제할 수 있습니다. 합치기는 시간순으로 0.5초 간격을 둡니다.")
        }
    }

    @ViewBuilder
    private func recordingRow(_ clip: RecordingClip) -> some View {
        RecordingRow(
            clip: clip,
            isActive: player.playingURL == clip.url,
            isPlaying: player.playingURL == clip.url && player.isPlaying,
            playbackDisabled: playbackDisabled,
            isSelected: selectedClipURLs.contains(clip.url),
            toggleSelection: { toggleSelection(of: clip) },
            play: { player.toggle(clip) },
            delete: {
                if player.playingURL == clip.url { player.stop() }
                selectedClipURLs.remove(clip.url)
                library.delete(clip)
            }
        )
    }

    private var mergedClips: [RecordingClip] {
        library.clips.filter(\.isMerged)
    }

    private var originalGroups: [RecordingDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: library.mergeableClips) {
            calendar.startOfDay(for: $0.createdAt)
        }
        return grouped
            .map { RecordingDayGroup(date: $0.key, clips: $0.value.sorted { $0.createdAt < $1.createdAt }) }
            .sorted { $0.date > $1.date }
    }

    private var todayClips: [RecordingClip] {
        library.mergeableClips(on: Date())
    }

    private var selectedClips: [RecordingClip] {
        library.mergeableClips.filter { selectedClipURLs.contains($0.url) }
    }

    private func toggleSelection(of clip: RecordingClip) {
        guard !clip.isMerged else { return }
        if selectedClipURLs.contains(clip.url) {
            selectedClipURLs.remove(clip.url)
        } else {
            selectedClipURLs.insert(clip.url)
        }
    }

    private func mergeSelectedRecordings(deleteSources: Bool) {
        let clips = selectedClips
        isMerging = true
        player.stop()
        Task {
            defer { isMerging = false }
            do {
                let merged = try await library.merge(
                    clips,
                    kind: .selected,
                    deleteSources: deleteSources
                )
                selectedClipURLs.removeAll()
                let sourceResult = deleteSources ? "원본 삭제됨" : "원본 보관됨"
                mergeStatusMessage = "\(clips.count)개를 합쳤습니다 · \(merged.createdAt.formatted(date: .omitted, time: .shortened)) 시작 · \(sourceResult)"
            } catch {
                mergeErrorMessage = error.localizedDescription
            }
        }
    }

    private func deleteSelectedRecordings() {
        let clips = selectedClips
        player.stop()
        do {
            try library.delete(clips)
            selectedClipURLs.removeAll()
            mergeStatusMessage = "선택한 원본 \(clips.count)개를 삭제했습니다."
        } catch {
            mergeErrorMessage = error.localizedDescription
        }
    }
}

enum RecordingSelectionPolicy {
    static func all(in clips: [RecordingClip]) -> Set<URL> {
        Set(clips.filter { !$0.isMerged }.map(\.url))
    }

    static func today(
        in clips: [RecordingClip],
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> Set<URL> {
        Set(
            clips
                .filter { !$0.isMerged && calendar.isDate($0.createdAt, inSameDayAs: date) }
                .map(\.url)
        )
    }
}

private struct RecordingDayGroup: Identifiable {
    let date: Date
    let clips: [RecordingClip]
    var id: Date { date }
}

private struct DailySleepTimelineHeader: View {
    let date: Date
    let clips: [RecordingClip]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(date, format: .dateTime.year().month().day().weekday(.short))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(clips.count)개 · \(clips.reduce(0) { $0 + $1.duration }.durationText)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(height: 8)

                    ForEach(clips) { clip in
                        Capsule()
                            .fill(Color.orange)
                            .frame(width: markerWidth(for: clip, totalWidth: proxy.size.width), height: 8)
                            .position(
                                x: markerX(for: clip, totalWidth: proxy.size.width),
                                y: 4
                            )
                    }
                }
            }
            .frame(height: 8)

            HStack {
                Text("0시")
                Spacer()
                Text("6시")
                Spacer()
                Text("12시")
                Spacer()
                Text("18시")
                Spacer()
                Text("24시")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(date.formatted(date: .long, time: .omitted)), 녹음 \(clips.count)개")
    }

    private func markerX(for clip: RecordingClip, totalWidth: CGFloat) -> CGFloat {
        let dayStart = Calendar.current.startOfDay(for: date)
        let seconds = max(0, min(86_400, clip.createdAt.timeIntervalSince(dayStart)))
        let x = totalWidth * seconds / 86_400
        return min(max(2, x), max(2, totalWidth - 2))
    }

    private func markerWidth(for clip: RecordingClip, totalWidth: CGFloat) -> CGFloat {
        max(4, min(12, totalWidth * clip.duration / 86_400))
    }
}

private struct RecordingRow: View {
    let clip: RecordingClip
    let isActive: Bool
    let isPlaying: Bool
    let playbackDisabled: Bool
    let isSelected: Bool
    let toggleSelection: () -> Void
    let play: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if clip.isMerged {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(.orange)
                    .frame(width: 28, height: 40)
                    .accessibilityLabel("합친 녹음")
            } else {
                Button(action: toggleSelection) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.orange : Color.secondary)
                        .frame(width: 28, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSelected ? "녹음 선택 해제" : "녹음 선택")
            }

            Button(action: play) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 38, height: 38)
                    .background(Color.orange.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(playbackDisabled)
            .accessibilityLabel(isPlaying ? "재생 일시 정지" : isActive ? "재생 계속" : "녹음 재생")

            Button(action: play) {
                clipDescription
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(playbackDisabled)
            .accessibilityLabel("\(clip.mergedTitle ?? "수면 소리") 재생")

            ShareLink(item: clip.url) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 32, height: 40)
            }
            .accessibilityLabel("녹음 공유")

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
                    .frame(width: 32, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("녹음 삭제")
        }
    }

    private var clipDescription: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rowTitle)
                .font(.body.weight(.medium))
            HStack(spacing: 6) {
                Text(clip.duration.durationText)
                if clip.isMerged {
                    Text("합본")
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var rowTitle: String {
        if let mergedTitle = clip.mergedTitle { return mergedTitle }
        if clip.isEmbeddedSample {
            return "테스트 코골이 · \(Int(clip.duration.rounded()))초"
        }
        return clip.createdAt.formatted(.dateTime.hour().minute().second())
    }
}

private struct PlaybackProgressBar: View {
    let clip: RecordingClip
    @ObservedObject var player: RecordingPlayer

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    player.toggle(clip)
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "재생 일시 정지" : "재생 계속")

                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 0.01)
                )
                .tint(.orange)

                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("재생 닫기")
            }

            HStack {
                Text(player.currentTime.durationText)
                Spacer()
                Text(player.duration.durationText)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private extension TimeInterval {
    var durationText: String {
        let totalSeconds = max(0, Int(self.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
