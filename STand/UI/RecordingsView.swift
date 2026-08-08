import SwiftUI

struct RecordingsView: View {
    @ObservedObject var library: RecordingLibrary
    let playbackDisabled: Bool
    let theme: StandDisplayTheme

    @StateObject private var player = RecordingPlayer()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmsDeleteAll = false
    @State private var confirmsDeleteSelected = false
    @State private var confirmsMergeAndDelete = false
    @State private var selectedClipURLs: Set<URL> = []
    @State private var expandedSessionIDs: Set<String> = []
    @State private var showsMergedRecordings = false
    @State private var isMerging = false
    @State private var mergeErrorMessage: String?
    @State private var mergeStatusMessage: String?

    init(
        library: RecordingLibrary,
        playbackDisabled: Bool,
        theme: StandDisplayTheme = .color
    ) {
        self.library = library
        self.playbackDisabled = playbackDisabled
        self.theme = theme
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RecordingBackground(accent: accent)

                if library.clips.isEmpty {
                    ContentUnavailableView(
                        "저장된 수면 소리가 없습니다",
                        systemImage: "waveform.badge.mic",
                        description: Text("잠자기 모드에서 코골이와 잠꼬대 후보가 감지되면 필요한 구간만 저장합니다.")
                    )
                    .foregroundStyle(.white.opacity(0.82))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            summaryCard
                            todayMergeCard

                            if playbackDisabled {
                                RecordingNoticeCard(
                                    text: "재생은 취침 세션을 종료한 뒤 사용할 수 있습니다."
                                )
                            }

                            ForEach(library.recordingSessions) { session in
                                sessionCard(session)
                            }

                            if !library.mergeableClips.isEmpty {
                                selectionCard
                            }

                            if !mergedClips.isEmpty {
                                mergedRecordingsCard
                            }

                            if let mergeStatusMessage {
                                Label(mergeStatusMessage, systemImage: "checkmark.circle.fill")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.62))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 30)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if !selectedClipURLs.isEmpty {
                        RecordingSelectionDock(
                            count: selectedClipURLs.count,
                            accent: accent,
                            canMerge: !playbackDisabled && !isMerging && selectedClips.count >= 2,
                            clear: { selectedClipURLs.removeAll() },
                            merge: { mergeSelectedRecordings(deleteSources: false) },
                            delete: { confirmsDeleteSelected = true },
                            isBusy: isMerging
                        )
                    }
                    if let playingURL = player.playingURL,
                       let clip = library.clips.first(where: { $0.url == playingURL }) {
                        PlaybackProgressBar(clip: clip, player: player, accent: accent)
                    }
                }
            }
            .navigationTitle("수면 소리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.84), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(accent)
                }
                if !library.clips.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("전체 선택", systemImage: "checkmark.square.fill") {
                                selectedClipURLs = RecordingSelectionPolicy.all(
                                    in: library.mergeableClips
                                )
                            }
                            .disabled(isMerging)
                            Button("오늘 선택", systemImage: "calendar.badge.checkmark") {
                                selectedClipURLs = RecordingSelectionPolicy.today(
                                    in: library.mergeableClips
                                )
                            }
                            .disabled(isMerging || todayClips.isEmpty)
                            Button("선택 모두 해제", systemImage: "checkmark.circle.badge.xmark") {
                                selectedClipURLs.removeAll()
                            }
                            .disabled(isMerging || selectedClipURLs.isEmpty)

                            Divider()

                            Button("전체 삭제", systemImage: "trash", role: .destructive) {
                                confirmsDeleteAll = true
                            }
                            .disabled(isMerging)
                        } label: {
                            Label("목록 작업", systemImage: "ellipsis.circle")
                                .foregroundStyle(accent)
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
                    guard !isMerging else { return }
                    player.stop()
                    selectedClipURLs.removeAll()
                    expandedSessionIDs.removeAll()
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
                    guard !isMerging else { return }
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
        .preferredColorScheme(.dark)
        .tint(accent)
        .grayscale(theme == .grayscale ? 1 : 0)
    }

    private var accent: Color { .orange }

    private var summaryCard: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent.opacity(0.15))
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text("나의 수면 기록")
                    .font(.title3.weight(.bold))
                Text("잠자리 \(library.recordingSessions.count)회 · 원본 \(library.mergeableClips.count)개")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.56))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(originalDuration.durationText)
                    .font(.headline.monospacedDigit())
                Text("원본 소리")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.42))
            }
        }
        .padding(16)
        .background { RecordingPanelSurface(accent: accent, cornerRadius: 22) }
        .accessibilityElement(children: .combine)
    }

    private var todayMergeCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Label("오늘 녹음", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
                Text("\(todayClips.count)개 · \(todayClips.reduce(0) { $0 + $1.duration }.durationText)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.52))
            }

            Spacer(minLength: 8)

            Button(action: mergeTodayRecordings) {
                Group {
                    if isMerging {
                        ProgressView()
                    } else {
                        Label("오늘 소리 한데 묶기", systemImage: "waveform.path.badge.plus")
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 132, minHeight: 46)
                .padding(.horizontal, 8)
                .background(accent.opacity(todayClips.count >= 2 ? 0.18 : 0.07), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(playbackDisabled || isMerging || todayClips.count < 2)
            .accessibilityHint("오늘 녹음된 원본을 시간순으로 합치고 원본은 그대로 보관합니다")
        }
        .padding(16)
        .background { RecordingPanelSurface(accent: accent, cornerRadius: 22) }
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("녹음 선택", systemImage: "checkmark.square")
                    .font(.headline)
                Spacer()
                Text("\(selectedClipURLs.count)개 선택")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(selectedClipURLs.isEmpty ? .white.opacity(0.42) : accent)
            }

            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 132 : 96),
                        spacing: 8
                    )
                ],
                spacing: 8
            ) {
                RecordingActionTile(title: "전체 선택", systemImage: "checkmark.square.fill", accent: accent) {
                    selectedClipURLs = RecordingSelectionPolicy.all(in: library.mergeableClips)
                }
                .disabled(isMerging)
                RecordingActionTile(title: "오늘 선택", systemImage: "calendar.badge.checkmark", accent: accent) {
                    selectedClipURLs = RecordingSelectionPolicy.today(in: library.mergeableClips)
                }
                .disabled(isMerging || todayClips.isEmpty)
                RecordingActionTile(title: "선택 해제", systemImage: "xmark.square", accent: accent) {
                    selectedClipURLs.removeAll()
                }
                .disabled(isMerging || selectedClipURLs.isEmpty)

                RecordingActionTile(title: "합치기", systemImage: "waveform.path.badge.plus", accent: accent) {
                    mergeSelectedRecordings(deleteSources: false)
                }
                .disabled(playbackDisabled || isMerging || selectedClips.count < 2)
                RecordingActionTile(title: "합치고 지우기", systemImage: "waveform.path.badge.minus", accent: accent) {
                    confirmsMergeAndDelete = true
                }
                .disabled(playbackDisabled || isMerging || selectedClips.count < 2)
                RecordingActionTile(
                    title: "선택 삭제",
                    systemImage: "trash",
                    accent: accent,
                    isDestructive: true
                ) {
                    confirmsDeleteSelected = true
                }
                .disabled(isMerging || selectedClips.isEmpty)
            }

            Text("합치기는 시간순으로 0.5초 간격을 두며, 기본적으로 원본을 보관합니다.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(16)
        .background { RecordingPanelSurface(accent: accent, cornerRadius: 22) }
    }

    private func sessionCard(_ session: RecordingSessionGroup) -> some View {
        let isExpanded = expandedSessionIDs.contains(session.id)
        let selectedCount = session.clips.filter { selectedClipURLs.contains($0.url) }.count

        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.24)) {
                    if isExpanded {
                        expandedSessionIDs.remove(session.id)
                    } else {
                        expandedSessionIDs.insert(session.id)
                    }
                }
            } label: {
                SleepSessionTimelineHeader(
                    session: session,
                    isExpanded: isExpanded,
                    selectedCount: selectedCount,
                    accent: accent
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 1)
                    .padding(.horizontal, 14)

                VStack(spacing: 8) {
                    ForEach(session.clips) { clip in
                        recordingRow(clip)
                    }
                }
                .padding(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background { RecordingPanelSurface(accent: accent, cornerRadius: 22) }
    }

    private var mergedRecordingsCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.24)) {
                    showsMergedRecordings.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.title3)
                        .foregroundStyle(accent)
                        .frame(width: 42, height: 42)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("한데 묶은 소리")
                            .font(.headline)
                        Text("\(mergedClips.count)개 · 원본과 별도로 보관")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.48))
                    }

                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(showsMergedRecordings ? 180 : 0))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsMergedRecordings {
                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                VStack(spacing: 8) {
                    ForEach(mergedClips) { clip in recordingRow(clip) }
                }
                .padding(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background { RecordingPanelSurface(accent: accent, cornerRadius: 22) }
    }

    @ViewBuilder
    private func recordingRow(_ clip: RecordingClip) -> some View {
        RecordingRow(
            clip: clip,
            isActive: player.playingURL == clip.url,
            isPlaying: player.playingURL == clip.url && player.isPlaying,
            playbackDisabled: playbackDisabled,
            mutationDisabled: isMerging,
            isSelected: selectedClipURLs.contains(clip.url),
            accent: accent,
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

    private var todayClips: [RecordingClip] {
        library.mergeableClips(on: Date())
    }

    private var originalDuration: TimeInterval {
        library.mergeableClips.reduce(0) { $0 + $1.duration }
    }

    private var selectedClips: [RecordingClip] {
        library.mergeableClips.filter { selectedClipURLs.contains($0.url) }
    }

    private func toggleSelection(of clip: RecordingClip) {
        guard !isMerging, !clip.isMerged else { return }
        if selectedClipURLs.contains(clip.url) {
            selectedClipURLs.remove(clip.url)
        } else {
            selectedClipURLs.insert(clip.url)
        }
    }

    private func mergeTodayRecordings() {
        guard todayClips.count >= 2 else { return }
        isMerging = true
        player.stop()
        Task {
            defer { isMerging = false }
            do {
                let merged = try await library.mergeToday()
                mergeStatusMessage = "오늘 녹음 \(todayClips.count)개를 한데 묶었습니다 · \(merged.createdAt.formatted(date: .omitted, time: .shortened)) 시작 · 원본 보관됨"
            } catch {
                mergeErrorMessage = error.localizedDescription
            }
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
        guard !isMerging else { return }
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

private struct RecordingBackground: View {
    let accent: Color

    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [accent.opacity(0.18), accent.opacity(0.035), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 620
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.36)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct RecordingPanelSurface: View {
    let accent: Color
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.095), .white.opacity(0.045)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.2), .white.opacity(0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
    }
}

private struct RecordingNoticeCard: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.58))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct RecordingSelectionDock: View {
    let count: Int
    let accent: Color
    let canMerge: Bool
    let clear: () -> Void
    let merge: () -> Void
    let delete: () -> Void
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(action: clear) {
                Image(systemName: "xmark")
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.07), in: Circle())
            }
            .disabled(isBusy)
            .accessibilityLabel("선택 해제")

            Text("\(count)개 선택")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.76))

            Spacer(minLength: 4)

            Button(action: merge) {
                Label("한데 묶기", systemImage: "waveform.path.badge.plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(accent.opacity(0.16), in: Capsule())
            }
            .disabled(!canMerge)
            .opacity(canMerge ? 1 : 0.38)

            Button(action: delete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.82))
                    .frame(width: 38, height: 38)
                    .background(.red.opacity(0.09), in: Circle())
            }
            .disabled(isBusy)
            .opacity(isBusy ? 0.34 : 1)
            .accessibilityLabel("선택 삭제")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
    }
}

private struct RecordingActionTile: View {
    let title: String
    let systemImage: String
    let accent: Color
    var isDestructive = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(isDestructive ? Color.red.opacity(0.88) : Color.white.opacity(0.76))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
            .opacity(isEnabled ? 1 : 0.34)
        }
        .buttonStyle(.plain)
    }
}

private struct SleepSessionTimelineHeader: View {
    let session: RecordingSessionGroup
    let isExpanded: Bool
    let selectedCount: Int
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(sessionTitle)
                            .font(.headline)
                        if session.isInferred {
                            Text("시간 추정")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.07), in: Capsule())
                        }
                    }
                    Text("\(timeRangeText) · \(session.clips.count)개 · \(session.totalDuration.durationText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer(minLength: 8)

                if selectedCount > 0 {
                    Text("\(selectedCount) 선택")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(accent.opacity(0.13), in: Capsule())
                }

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .foregroundStyle(.white.opacity(0.48))
            }

            SessionTimelineBar(session: session, accent: accent)
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isExpanded ? "녹음 목록 펼쳐짐" : "녹음 목록 접힘")
        .accessibilityHint("두 번 탭하여 녹음 목록을 \(isExpanded ? "접습니다" : "펼칩니다")")
    }

    private var sessionTitle: String {
        if Calendar.current.isDateInToday(session.startedAt) { return "오늘 잠자리" }
        if Calendar.current.isDateInYesterday(session.startedAt) { return "어제 잠자리" }
        return session.startedAt.formatted(.dateTime.month().day().weekday(.short))
    }

    private var timeRangeText: String {
        let start = session.startedAt.formatted(date: .omitted, time: .shortened)
        let end = session.endedAt.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDate(session.startedAt, inSameDayAs: session.endedAt) {
            return "\(start)–\(end)"
        }
        return "\(start)–다음 날 \(end)"
    }

    private var accessibilityLabel: String {
        let estimate = session.isInferred ? "시간 추정, " : ""
        return "\(estimate)\(sessionTitle), \(timeRangeText), 녹음 \(session.clips.count)개, 총 \(session.totalDuration.durationText)"
    }
}

private struct SessionTimelineBar: View {
    let session: RecordingSessionGroup
    let accent: Color

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.085))
                        .frame(height: 10)

                    LinearGradient(
                        colors: [accent.opacity(0.28), accent.opacity(0.08)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .mask(Capsule().frame(height: 10))

                    ForEach(session.clips) { clip in
                        let fraction = SleepSessionGroupingPolicy.markerFraction(
                            for: clip,
                            sessionStart: session.startedAt,
                            sessionEnd: session.endedAt
                        )
                        let widthForMarker = markerWidth(for: clip, totalWidth: width)
                        Capsule()
                            .fill(accent)
                            .frame(width: widthForMarker, height: 10)
                            .shadow(color: accent.opacity(0.55), radius: 4)
                            .position(
                                x: markerX(
                                    fraction: fraction,
                                    totalWidth: width,
                                    markerWidth: widthForMarker
                                ),
                                y: 5
                            )
                    }
                }
            }
            .frame(height: 10)

            HStack {
                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text("수면 소리 감지 시점")
                Spacer()
                Text(session.endedAt.formatted(date: .omitted, time: .shortened))
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.34))
        }
    }

    private func markerX(
        fraction: Double,
        totalWidth: CGFloat,
        markerWidth: CGFloat
    ) -> CGFloat {
        let halfWidth = markerWidth / 2
        return halfWidth + max(0, totalWidth - markerWidth) * fraction
    }

    private func markerWidth(for clip: RecordingClip, totalWidth: CGFloat) -> CGFloat {
        let sessionDuration = max(1, session.endedAt.timeIntervalSince(session.startedAt))
        return max(7, min(22, totalWidth * clip.duration / sessionDuration))
    }
}

private struct RecordingRow: View {
    let clip: RecordingClip
    let isActive: Bool
    let isPlaying: Bool
    let playbackDisabled: Bool
    let mutationDisabled: Bool
    let isSelected: Bool
    let accent: Color
    let toggleSelection: () -> Void
    let play: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            if clip.isMerged {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(accent)
                    .frame(width: 40, height: 44)
                    .accessibilityLabel("합친 녹음")
            } else {
                Button(action: toggleSelection) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(isSelected ? accent : .white.opacity(0.38))
                        .frame(width: 40, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(mutationDisabled)
                .accessibilityLabel(isSelected ? "녹음 선택 해제" : "녹음 선택")
            }

            Button(action: play) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 42, height: 42)
                    .background(accent.opacity(0.13), in: Circle())
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

            Menu {
                ShareLink(item: clip.url) {
                    Label("공유", systemImage: "square.and.arrow.up")
                }
                Button("삭제", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(width: 42, height: 44)
            }
            .accessibilityLabel("녹음 작업")
            .disabled(mutationDisabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isActive ? accent.opacity(0.105) : .white.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 15)
        )
    }

    private var clipDescription: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rowTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.84))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(clip.duration.durationText)
                if clip.isMerged { Text("합본") }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.42))
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
    let accent: Color

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Button {
                    player.toggle(clip)
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .foregroundStyle(accent)
                        .frame(width: 38, height: 38)
                        .background(accent.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "재생 일시 정지" : "재생 계속")

                VStack(spacing: 3) {
                    Slider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(player.duration, 0.01)
                    )
                    .tint(accent)

                    HStack {
                        Text(player.currentTime.durationText)
                        Spacer()
                        Text(player.duration.durationText)
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.42))
                }

                Button {
                    player.stop()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.42))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("재생 닫기")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }
}

private extension TimeInterval {
    var durationText: String {
        let totalSeconds = max(0, Int(self.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = totalSeconds % 3_600 / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
