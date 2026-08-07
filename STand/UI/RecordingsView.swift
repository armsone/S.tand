import SwiftUI

struct RecordingsView: View {
    @ObservedObject var library: RecordingLibrary
    let playbackDisabled: Bool
    @StateObject private var player = RecordingPlayer()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeleteAll = false
    @State private var confirmsMergeAll = false
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

                        if library.mergeableClipCount >= 2 {
                            Section {
                                Button {
                                    confirmsMergeAll = true
                                } label: {
                                    HStack {
                                        Label("전체 녹음을 하나로 합치기", systemImage: "waveform.path.badge.plus")
                                        Spacer()
                                        if isMerging {
                                            ProgressView()
                                        }
                                    }
                                }
                                .disabled(playbackDisabled || isMerging)
                            } footer: {
                                Text("시간순으로 이어 붙인 새 녹음을 만듭니다. 기존 녹음은 그대로 보관됩니다.")
                            }
                        }

                        Section {
                            ForEach(library.clips) { clip in
                                RecordingRow(
                                    clip: clip,
                                    isActive: player.playingURL == clip.url,
                                    isPlaying: player.playingURL == clip.url && player.isPlaying,
                                    playbackDisabled: playbackDisabled,
                                    play: { player.toggle(clip) },
                                    delete: {
                                        if player.playingURL == clip.url {
                                            player.stop()
                                        }
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
                        Button("전체 삭제", role: .destructive) {
                            confirmsDeleteAll = true
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
                "전체 녹음을 하나로 합칠까요?",
                isPresented: $confirmsMergeAll,
                titleVisibility: .visible
            ) {
                Button("합친 녹음 만들기") {
                    mergeAllRecordings()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("녹음 시각 순서로 이어 붙입니다. 원본 파일은 삭제하지 않습니다.")
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

    private func mergeAllRecordings() {
        isMerging = true
        player.stop()
        Task {
            defer { isMerging = false }
            do {
                _ = try await library.mergeAll()
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
    let play: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: play) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 40, height: 40)
                    .background(Color.orange.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(playbackDisabled)
            .accessibilityLabel(isPlaying ? "재생 일시 정지" : isActive ? "재생 계속" : "녹음 재생")

            VStack(alignment: .leading, spacing: 3) {
                Text(clip.isMerged ? "합친 녹음" : clip.createdAt.formatted(.dateTime.month().day().hour().minute().second()))
                    .font(.body.weight(.medium))
                Text(clip.duration.durationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ShareLink(item: clip.url) {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 40, height: 40)
            }
            .accessibilityLabel("녹음 공유")

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("녹음 삭제")
        }
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
