import SwiftUI

private enum RecordingsPage: String, CaseIterable, Identifiable {
    case lastNight
    case sounds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lastNight: "수면 리포트"
        case .sounds: "잠소리 관리"
        }
    }
}

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
    @State private var showsSelectionTools = false
    @State private var showsMergedRecordings = false
    @State private var isMerging = false
    @State private var mergeErrorMessage: String?
    @State private var mergeStatusMessage: String?
    @State private var pendingClipDeletion: RecordingClip?
    @State private var playbackQueue: [RecordingClip] = []
    @State private var playbackQueueIndex = 0
    @State private var selectedPage: RecordingsPage = .lastNight

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

                ScrollView {
                    LazyVStack(spacing: 12) {
                        pagePicker

                        switch selectedPage {
                        case .lastNight:
                            lastNightContent
                        case .sounds:
                            soundListContent
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if selectedPage == .sounds, !selectedClipURLs.isEmpty {
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
            .navigationTitle("잠소리")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(accent)
                }
                if selectedPage == .sounds, !library.clips.isEmpty {
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
                "저장된 잠소리를 모두 삭제할까요?",
                isPresented: $confirmsDeleteAll,
                titleVisibility: .visible
            ) {
                Button("모두 삭제", role: .destructive) {
                    guard !isMerging else { return }
                    player.stop()
                    do {
                        try library.deleteAll()
                        selectedClipURLs.removeAll()
                        expandedSessionIDs.removeAll()
                    } catch {
                        mergeErrorMessage = error.localizedDescription
                    }
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
            .confirmationDialog(
                "이 녹음을 삭제할까요?",
                isPresented: Binding(
                    get: { pendingClipDeletion != nil },
                    set: { if !$0 { pendingClipDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let clip = pendingClipDeletion {
                    Button("녹음 삭제", role: .destructive) {
                        deleteClip(clip)
                    }
                }
                Button("취소", role: .cancel) { pendingClipDeletion = nil }
            } message: {
                Text("삭제한 녹음은 복구할 수 없습니다.")
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
            .onAppear {
                library.reload()
                player.onPlaybackFinished = { playNextQueuedClip() }
                if expandedSessionIDs.isEmpty, let firstSession = library.recordingSessions.first {
                    expandedSessionIDs.insert(firstSession.id)
                }
            }
            .onDisappear {
                playbackQueue.removeAll()
                player.onPlaybackFinished = nil
                player.stop()
            }
        }
        .preferredColorScheme(.dark)
        .tint(accent)
        .grayscale(theme == .grayscale ? 1 : 0)
    }

    private var accent: Color { theme.accentColor }

    private var pagePicker: some View {
        Picker("잠소리 보기", selection: $selectedPage) {
            ForEach(RecordingsPage.allCases) { page in
                Text(page.title).tag(page)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityHint("수면 리포트와 잠소리 관리 화면을 전환합니다")
    }

    @ViewBuilder
    private var lastNightContent: some View {
        if let session = library.recordingSessions.first {
            VStack(spacing: 0) {
                SleepSessionTimelineHeader(
                    session: session,
                    isExpanded: true,
                    selectedCount: 0,
                    accent: accent,
                    showsDisclosure: false
                )

                Rectangle()
                    .fill(.white.opacity(0.07))
                    .frame(height: 1)
                    .padding(.horizontal, 14)

                SleepSessionInsightCard(
                    session: session,
                    accent: accent,
                    playbackDisabled: playbackDisabled,
                    isPlayingQueue: isPlayingQueue(session),
                    playHighlights: { playHighlights(in: session) }
                )
                .padding(12)
            }
            .background { RecordingPanelSurface(accent: accent, cornerRadius: 22) }
        } else {
            ContentUnavailableView(
                "분석할 수면 기록이 없습니다",
                systemImage: "moon.zzz",
                description: Text("매이트 모드에서 소리와 움직임이 기록되면 수면 리포트로 정리합니다.")
            )
            .foregroundStyle(.white.opacity(0.82))
        }
    }

    @ViewBuilder
    private var soundListContent: some View {
        if library.clips.isEmpty, library.recordingSessions.isEmpty {
            ContentUnavailableView(
                "저장된 잠소리가 없습니다",
                systemImage: "waveform.badge.mic",
                description: Text("매이트 모드에서 코골이와 잠꼬대 후보가 감지되면 필요한 구간만 저장합니다.")
            )
            .foregroundStyle(.white.opacity(0.82))
        } else {
            summaryCard
            if !library.mergeableClips.isEmpty {
                todayMergeCard
            }

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
    }

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
                Text("보관 현황")
                    .font(.title3.weight(.bold))
                Text("잠자리 \(library.recordingSessions.count)회 · 원본 \(library.mergeableClips.count)개 · \(library.storedAudioByteCount.storageText)")
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                todaySummary
                Spacer(minLength: 8)
                todayMergeButton
            }
            VStack(alignment: .leading, spacing: 12) {
                todaySummary
                todayMergeButton
            }
        }
        .padding(16)
        .background { RecordingPanelSurface(accent: accent, cornerRadius: 22) }
    }

    private var todaySummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("오늘", systemImage: "calendar")
                .font(.headline)
            Text("\(todayClips.count)개 · \(todayClips.reduce(0) { $0 + $1.duration }.durationText)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.68))
        }
    }

    private var todayMergeButton: some View {
        Button(action: mergeTodayRecordings) {
            Group {
                if isMerging {
                    ProgressView()
                } else {
                    Label("오늘 소리 합치기", systemImage: "waveform.path.badge.plus")
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, minHeight: 46)
            .padding(.horizontal, 14)
            .background(accent.opacity(todayClips.count >= 2 ? 0.24 : 0.09), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(playbackDisabled || isMerging || todayClips.count < 2)
        .opacity(playbackDisabled || isMerging || todayClips.count < 2 ? 0.46 : 1)
        .accessibilityHint("오늘 원본을 시간순으로 합치며 원본은 그대로 둡니다")
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { showsSelectionTools.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.square.fill")
                        .font(.title3)
                        .foregroundStyle(accent)
                        .frame(width: 42, height: 42)
                        .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("녹음 고르기")
                            .font(.headline)
                        Text(selectedClipURLs.isEmpty ? "합치거나 지울 소리를 선택합니다" : "\(selectedClipURLs.count)개 선택됨")
                            .font(.caption)
                            .foregroundStyle(selectedClipURLs.isEmpty ? .white.opacity(0.66) : accent)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(showsSelectionTools ? 180 : 0))
                        .foregroundStyle(.white.opacity(0.64))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsSelectionTools {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 140 : 108), spacing: 8)],
                    spacing: 8
                ) {
                    RecordingActionTile(title: "모두 고르기", systemImage: "checkmark.square.fill", accent: accent) {
                        selectedClipURLs = RecordingSelectionPolicy.all(in: library.mergeableClips)
                    }
                    .disabled(isMerging)
                    RecordingActionTile(title: "오늘만 고르기", systemImage: "calendar.badge.checkmark", accent: accent) {
                        selectedClipURLs = RecordingSelectionPolicy.today(in: library.mergeableClips)
                    }
                    .disabled(isMerging || todayClips.isEmpty)
                    RecordingActionTile(title: "선택 풀기", systemImage: "xmark.square", accent: accent) {
                        selectedClipURLs.removeAll()
                    }
                    .disabled(isMerging || selectedClipURLs.isEmpty)
                }

                Text("소리를 고르면 화면 아래에서 합치거나 삭제할 수 있습니다.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.68))

                Button {
                    confirmsMergeAndDelete = true
                } label: {
                    Label("합친 뒤 원본 지우기", systemImage: "waveform.path.badge.minus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red.opacity(0.86))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .disabled(playbackDisabled || isMerging || selectedClips.count < 2)
                .opacity(playbackDisabled || isMerging || selectedClips.count < 2 ? 0.4 : 1)
            }
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

                VStack(spacing: 10) {
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
            play: { toggleManualPlayback(clip) },
            delete: {
                pendingClipDeletion = clip
            }
        )
    }

    private func deleteClip(_ clip: RecordingClip) {
        if player.playingURL == clip.url { player.stop() }
        pendingClipDeletion = nil
        do {
            try library.delete(clip)
            selectedClipURLs.remove(clip.url)
        } catch {
            mergeErrorMessage = error.localizedDescription
        }
    }

    private func toggleManualPlayback(_ clip: RecordingClip) {
        playbackQueue.removeAll()
        playbackQueueIndex = 0
        player.toggle(clip)
    }

    private func playHighlights(in session: RecordingSessionGroup) {
        guard !playbackDisabled, !session.clips.isEmpty else { return }
        playbackQueue = session.clips.sorted { $0.createdAt < $1.createdAt }
        playbackQueueIndex = 0
        player.play(playbackQueue[0])
    }

    private func playNextQueuedClip() {
        guard !playbackQueue.isEmpty else { return }
        let nextIndex = playbackQueueIndex + 1
        guard playbackQueue.indices.contains(nextIndex) else {
            playbackQueue.removeAll()
            playbackQueueIndex = 0
            return
        }
        playbackQueueIndex = nextIndex
        player.play(playbackQueue[nextIndex])
    }

    private func isPlayingQueue(_ session: RecordingSessionGroup) -> Bool {
        guard let playingURL = player.playingURL else { return false }
        return !playbackQueue.isEmpty && session.clips.contains { $0.url == playingURL }
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
            Color(red: 0.115, green: 0.085, blue: 0.078)
            LinearGradient(
                colors: [
                    accent.opacity(0.18),
                    Color(red: 0.16, green: 0.115, blue: 0.10),
                    Color(red: 0.085, green: 0.075, blue: 0.075)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [accent.opacity(0.22), accent.opacity(0.045), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 640
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
                    colors: [.white.opacity(0.18), .white.opacity(0.09)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.34), .white.opacity(0.15)],
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
            .foregroundStyle(.white.opacity(0.74))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 16))
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                clearButton
                selectionCount
                Spacer(minLength: 4)
                mergeButton
                deleteButton
            }
            VStack(spacing: 8) {
                HStack {
                    clearButton
                    selectionCount
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    mergeButton
                    deleteButton
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
    }

    private var clearButton: some View {
        Button(action: clear) {
            Image(systemName: "xmark")
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.07), in: Circle())
        }
        .disabled(isBusy)
        .accessibilityLabel("선택 해제")
    }

    private var selectionCount: some View {
        Text("\(count)개 선택")
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white.opacity(0.76))
    }

    private var mergeButton: some View {
        Button(action: merge) {
            Label("한데 묶기", systemImage: "waveform.path.badge.plus")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(accent.opacity(0.16), in: Capsule())
        }
        .disabled(!canMerge)
        .opacity(canMerge ? 1 : 0.38)
    }

    private var deleteButton: some View {
        Button(action: delete) {
            Image(systemName: "trash")
                .foregroundStyle(.red.opacity(0.82))
                .frame(width: 48, height: 48)
                .background(.red.opacity(0.09), in: Circle())
        }
        .disabled(isBusy)
        .opacity(isBusy ? 0.34 : 1)
        .accessibilityLabel("선택 삭제")
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
            .foregroundStyle(isDestructive ? Color.red.opacity(0.92) : Color.white.opacity(0.90))
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
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
    var showsDisclosure = true

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
                                .foregroundStyle(.white.opacity(0.65))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.white.opacity(0.07), in: Capsule())
                        }
                    }
                    Text(activitySummary)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.68))
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

                if showsDisclosure {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .foregroundStyle(.white.opacity(0.64))
                }
            }

            SessionTimelineBar(session: session, accent: accent)
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(
            showsDisclosure
                ? (isExpanded ? "잠소리 목록 펼쳐짐" : "잠소리 목록 접힘")
                : "수면 리포트"
        )
        .accessibilityHint(
            showsDisclosure
                ? "두 번 탭하여 잠소리 목록을 \(isExpanded ? "접습니다" : "펼칩니다")"
                : ""
        )
    }

    private var sessionTitle: String {
        let startTime = session.startedAt.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(session.startedAt) { return "오늘 \(startTime) 잠자리" }
        if Calendar.current.isDateInYesterday(session.startedAt) { return "어제 \(startTime) 잠자리" }
        let date = session.startedAt.formatted(.dateTime.month().day().weekday(.short))
        return "\(date) \(startTime) 잠자리"
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
        return "\(estimate)\(sessionTitle), \(timeRangeText), 녹음 \(session.clips.count)개, 화들짝 \(session.startleEvents.count)회, 총 \(session.totalDuration.durationText)"
    }

    private var activitySummary: String {
        var parts = [timeRangeText]
        if !session.clips.isEmpty {
            parts.append("소리 \(session.clips.count)개")
            parts.append(session.totalDuration.durationText)
        }
        if !session.startleEvents.isEmpty {
            parts.append("화들짝 \(session.startleEvents.count)회")
        }
        return parts.joined(separator: " · ")
    }
}

private struct SleepSessionInsightCard: View {
    let session: RecordingSessionGroup
    let accent: Color
    let playbackDisabled: Bool
    let isPlayingQueue: Bool
    let playHighlights: () -> Void

    private var insight: SleepSessionInsight { session.insight }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("분석 요약", systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.bold))
                Spacer()
                ShareLink(item: shareText) {
                    Label("리포트 공유", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(minHeight: 44)
                }
            }

            HStack(spacing: 8) {
                insightMetric("기록 구간", value: insight.sessionDuration.compactDurationText)
                insightMetric("소리 후보", value: "\(insight.soundCount)회")
                insightMetric("화들짝 반응", value: "\(insight.movementCount)회")
            }

            ActivityDistributionBar(buckets: insight.activityBuckets, accent: accent)

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(accent)
                Text(activityDescription)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 4)
            }

            if !session.clips.isEmpty {
                Button(action: playHighlights) {
                    Label(
                        isPlayingQueue ? "핵심 소리 이어 듣는 중" : "핵심 소리 \(session.clips.count)개 이어 듣기",
                        systemImage: isPlayingQueue ? "waveform.circle.fill" : "play.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .disabled(playbackDisabled)
                .opacity(playbackDisabled ? 0.4 : 1)
            }

            Text("소리와 움직임의 발생 기록을 요약한 참고 정보이며, 수면 단계나 질병을 진단하지 않습니다.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.48))
        }
        .padding(13)
        .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
    }

    private func insightMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(.white.opacity(0.94))
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.54))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
    }

    private var activityDescription: String {
        guard let range = insight.busiestRange(sessionStart: session.startedAt) else {
            return "기록된 소리나 뒤척임이 없습니다."
        }
        let start = range.lowerBound.formatted(date: .omitted, time: .shortened)
        let end = range.upperBound.formatted(date: .omitted, time: .shortened)
        return "가장 기록이 몰린 시간은 \(start)–\(end)입니다 · 시간당 \(insight.eventsPerHour.formatted(.number.precision(.fractionLength(1))))회"
    }

    private var shareText: String {
        let date = session.startedAt.formatted(.dateTime.year().month().day())
        return "S.tand 수면 리포트 · \(date)\n기록 구간 \(insight.sessionDuration.compactDurationText)\n소리 후보 \(insight.soundCount)회 · 화들짝 반응 \(insight.movementCount)회\n\(activityDescription)\n※ 감지 기록을 분석한 참고 정보이며 의료 진단이 아닙니다."
    }
}

private struct ActivityDistributionBar: View {
    let buckets: [Int]
    let accent: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(buckets.enumerated()), id: \.offset) { _, count in
                Capsule()
                    .fill(count == 0 ? .white.opacity(0.08) : accent.opacity(0.42 + 0.12 * Double(min(count, 4))))
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(5 + min(count, 4) * 5))
            }
        }
        .frame(height: 26, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("수면 중 활동 분포")
        .accessibilityValue(buckets.map(String.init).joined(separator: ", "))
    }
}

private struct SessionTimelineBar: View {
    let session: RecordingSessionGroup
    let accent: Color

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                VStack(spacing: 4) {
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
                    .frame(height: 10)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.035))
                            .frame(height: 2)

                        ForEach(session.startleEvents) { event in
                            StartleTimelineMarker(
                                event: event,
                                sessionStart: session.startedAt,
                                sessionEnd: session.endedAt,
                                totalWidth: width,
                                accent: accent
                            )
                        }
                    }
                    .frame(height: 2)
                }
            }
            .frame(height: 16)

            HStack {
                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                Spacer()
                Text("잠소리 · 얇은 선은 화들짝")
                Spacer()
                Text(session.endedAt.formatted(date: .omitted, time: .shortened))
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.56))
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

private struct StartleTimelineMarker: View {
    let event: SleepStartleEvent
    let sessionStart: Date
    let sessionEnd: Date
    let totalWidth: CGFloat
    let accent: Color

    var body: some View {
        let startFraction = SleepSessionGroupingPolicy.markerFraction(
            for: event.startedAt,
            sessionStart: sessionStart,
            sessionEnd: sessionEnd
        )
        let endFraction = SleepSessionGroupingPolicy.markerFraction(
            for: event.endedAt ?? sessionEnd,
            sessionStart: sessionStart,
            sessionEnd: sessionEnd
        )
        let fractionWidth = CGFloat(max(0, endFraction - startFraction))
        let markerWidth = max(CGFloat(2), totalWidth * fractionWidth)
        let proposedCenter = totalWidth * CGFloat(startFraction) + markerWidth / 2
        let center = min(
            totalWidth - markerWidth / 2,
            max(markerWidth / 2, proposedCenter)
        )

        Capsule()
            .fill(.white.opacity(0.88))
            .frame(width: markerWidth, height: 2)
            .shadow(color: accent.opacity(0.75), radius: 2)
            .position(x: center, y: 1)
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
                    .frame(width: 48, height: 48)
                    .accessibilityLabel("합친 녹음")
            } else {
                Button(action: toggleSelection) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.title3)
                    .foregroundStyle(isSelected ? accent : .white.opacity(0.58))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .disabled(mutationDisabled)
                .accessibilityLabel(isSelected ? "녹음 선택 해제" : "녹음 선택")
            }

            Button(action: play) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent)
                        .frame(width: 48, height: 48)
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
            .accessibilityLabel("\(clip.mergedTitle ?? "잠소리") 재생")

            Menu {
                ShareLink(item: clip.url) {
                    Label("공유", systemImage: "square.and.arrow.up")
                }
                Button("삭제", systemImage: "trash", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.70))
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("녹음 작업")
            .disabled(mutationDisabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isActive ? accent.opacity(0.18) : .white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 15)
        )
    }

    private var clipDescription: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rowTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(clip.duration.durationText)
                if clip.isMerged { Text("합본") }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.64))
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                playbackButton
                boostButton
                progressControl
                closeButton
            }
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    playbackButton
                    boostButton
                    Spacer(minLength: 0)
                    closeButton
                }
                progressControl
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
    }

    private var playbackButton: some View {
        Button {
            player.toggle(clip)
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .foregroundStyle(accent)
                .frame(width: 48, height: 48)
                .background(accent.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.isPlaying ? "재생 일시 정지" : "재생 계속")
    }

    private var boostButton: some View {
        Button {
            player.toggleBoost()
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.caption.weight(.bold))
                Text("2×")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(player.boostEnabled ? accent : .white.opacity(0.64))
            .frame(width: 48, height: 48)
            .background(
                (player.boostEnabled ? accent.opacity(0.14) : .white.opacity(0.06)),
                in: Circle()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(player.boostEnabled ? "작은 소리 두 배 증폭 끄기" : "작은 소리 두 배 증폭 켜기")
    }

    private var progressControl: some View {
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
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.62))
        }
        .frame(minWidth: 120)
    }

    private var closeButton: some View {
        Button {
            player.stop()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.white.opacity(0.64))
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("재생 닫기")
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

    var compactDurationText: String {
        let totalMinutes = max(0, Int((self / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)시간 \(minutes)분" }
        return "\(minutes)분"
    }
}

private extension Int64 {
    var storageText: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
