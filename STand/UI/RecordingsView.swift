import SwiftUI

struct RecordingsView: View {
    @ObservedObject var library: RecordingLibrary
    let playbackDisabled: Bool
    @StateObject private var player = RecordingPlayer()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeleteAll = false
    @State private var confirmsMergeSelection = false
    @State private var confirmsMergeToday = false
    @State private var isSelecting = false
    @State private var selectedClipURLs: Set<URL> = []
    @State private var isMerging = false
    @State private var mergeErrorMessage: String?

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

                        if library.mergeableClips.count >= 2 {
                            Section {
                                Button {
                                    player.stop()
                                    isSelecting = true
                                } label: {
                                    HStack {
                                        Label("선택한 소리 합치기", systemImage: "checkmark.circle")
                                        Spacer()
                                        Text("2개 이상 선택")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .disabled(playbackDisabled || isMerging || isSelecting)

                                Button {
                                    confirmsMergeToday = true
                                } label: {
                                    HStack {
                                        Label("오늘 녹음 합치기", systemImage: "calendar")
                                        Spacer()
                                        Text("\(todayClips.count)개")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .disabled(playbackDisabled || isMerging || todayClips.count < 2)
                            } footer: {
                                Text("선택한 원본 또는 오늘의 원본을 시간순으로 합칩니다. 원본과 이전 합본은 그대로 보관됩니다.")
                            }
                        }

                        Section {
                            ForEach(library.clips) { clip in
                                RecordingRow(
                                    clip: clip,
                                    isActive: player.playingURL == clip.url,
                                    isPlaying: player.playingURL == clip.url && player.isPlaying,
                                    playbackDisabled: playbackDisabled,
                                    selectionEnabled: isSelecting,
                                    isSelected: selectedClipURLs.contains(clip.url),
                                    toggleSelection: { toggleSelection(of: clip) },
                                    play: { player.toggle(clip) },
                                    delete: {
                                        if player.playingURL == clip.url {
                                            player.stop()
                                        }
                                        selectedClipURLs.remove(clip.url)
                                        library.delete(clip)
                                    }
                                )
                            }
                        } header: {
                            Text("\(library.clips.count)개 · 총 \(library.totalDuration.durationText)")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelecting {
                    SelectionMergeBar(
                        selectionCount: selectedClipURLs.count,
                        isMerging: isMerging,
                        merge: { confirmsMergeSelection = true },
                        cancel: { cancelSelection() }
                    )
                } else if let playingURL = player.playingURL,
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
                        if isSelecting {
                            Button("선택 취소") { cancelSelection() }
                        } else {
                            Menu {
                                Button {
                                    player.stop()
                                    isSelecting = true
                                } label: {
                                    Label("합칠 녹음 선택", systemImage: "checkmark.circle")
                                }
                                .disabled(library.mergeableClips.count < 2)

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
            }
            .confirmationDialog(
                "저장된 수면 소리를 모두 삭제할까요?",
                isPresented: $confirmsDeleteAll,
                titleVisibility: .visible
            ) {
                Button("모두 삭제", role: .destructive) {
                    player.stop()
                    library.deleteAll()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("삭제한 녹음은 복구할 수 없습니다.")
            }
            .confirmationDialog(
                "선택한 \(selectedClipURLs.count)개의 소리를 하나로 합칠까요?",
                isPresented: $confirmsMergeSelection,
                titleVisibility: .visible
            ) {
                Button("선택한 소리 합치기") {
                    mergeSelectedRecordings()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("녹음 시각 순서로 이어 붙입니다. 원본 파일은 삭제하지 않습니다.")
            }
            .confirmationDialog(
                "오늘 녹음 \(todayClips.count)개를 하나로 합칠까요?",
                isPresented: $confirmsMergeToday,
                titleVisibility: .visible
            ) {
                Button("오늘 녹음 합치기") {
                    mergeTodayRecordings()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("오늘 자정 이후 저장된 원본 녹음을 시간순으로 합칩니다. 원본 파일은 삭제하지 않습니다.")
            }
            .alert(
                "녹음을 합치지 못했습니다",
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

    private func cancelSelection() {
        selectedClipURLs.removeAll()
        isSelecting = false
    }

    private func mergeSelectedRecordings() {
        let clips = selectedClips
        isMerging = true
        player.stop()
        Task {
            defer { isMerging = false }
            do {
                _ = try await library.merge(clips, kind: .selected)
                cancelSelection()
            } catch {
                mergeErrorMessage = error.localizedDescription
            }
        }
    }

    private func mergeTodayRecordings() {
        isMerging = true
        player.stop()
        Task {
            defer { isMerging = false }
            do {
                _ = try await library.mergeToday()
            } catch {
                mergeErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct RecordingRow: View {
    let clip: RecordingClip
    let isActive: Bool
    let isPlaying: Bool
    let playbackDisabled: Bool
    let selectionEnabled: Bool
    let isSelected: Bool
    let toggleSelection: () -> Void
    let play: () -> Void
    let delete: () -> Void

    var body: some View {
        Group {
            if selectionEnabled {
                Button(action: toggleSelection) {
                    HStack(spacing: 14) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.orange : Color.secondary)
                            .frame(width: 28, height: 40)

                        clipDescription
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(clip.isMerged)
                .opacity(clip.isMerged ? 0.2 : 1)
                .accessibilityLabel(isSelected ? "병합 선택 해제" : "병합할 녹음 선택")
            } else {
                HStack(spacing: 12) {
                    Button(action: play) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 40, height: 40)
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
                            .frame(width: 36, height: 40)
                    }
                    .accessibilityLabel("녹음 공유")

                    Button(role: .destructive, action: delete) {
                        Image(systemName: "trash")
                            .frame(width: 36, height: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("녹음 삭제")
                }
            }
        }
    }

    private var clipDescription: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(clip.mergedTitle ?? clip.createdAt.formatted(.dateTime.month().day().hour().minute().second()))
                .font(.body.weight(.medium))
            Text(clip.duration.durationText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct SelectionMergeBar: View {
    let selectionCount: Int
    let isMerging: Bool
    let merge: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("취소", action: cancel)

            Spacer()

            Text("\(selectionCount)개 선택")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            Button(action: merge) {
                if isMerging {
                    ProgressView()
                } else {
                    Label("하나로 합치기", systemImage: "waveform.path.badge.plus")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(selectionCount < 2 || isMerging)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
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
