import SwiftUI

struct RecordingsView: View {
    @ObservedObject var library: RecordingLibrary
    let playbackDisabled: Bool
    @StateObject private var player = RecordingPlayer()
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeleteAll = false

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

                        Section {
                            ForEach(library.clips) { clip in
                                RecordingRow(
                                    clip: clip,
                                    isPlaying: player.playingURL == clip.url,
                                    playbackDisabled: playbackDisabled,
                                    play: { player.toggle(clip) },
                                    delete: { library.delete(clip) }
                                )
                            }
                        } header: {
                            Text("\(library.clips.count)개 · 총 \(library.totalDuration.durationText)")
                        }
                    }
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
            .onAppear { library.reload() }
            .onDisappear { player.stop() }
        }
    }
}

private struct RecordingRow: View {
    let clip: RecordingClip
    let isPlaying: Bool
    let playbackDisabled: Bool
    let play: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: play) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .frame(width: 40, height: 40)
                    .background(Color.orange.opacity(0.14), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(playbackDisabled)
            .accessibilityLabel(isPlaying ? "재생 중지" : "녹음 재생")

            VStack(alignment: .leading, spacing: 3) {
                Text(clip.createdAt, format: .dateTime.month().day().hour().minute().second())
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

private extension TimeInterval {
    var durationText: String {
        let totalSeconds = max(0, Int(self.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
