import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct HoldDurationAdjustment {
    static func value(startingAt startingValue: Double, translation: CGFloat) -> Double {
        let rawValue = startingValue + Double(translation / 300) * 290
        let steppedValue = (rawValue / 5).rounded() * 5
        return min(300, max(10, steppedValue))
    }
}

enum ScreenTapLampAction: Equatable {
    case brighten
    case dim
}

struct ScreenTapPolicy {
    static func action(for phase: LampPhase) -> ScreenTapLampAction {
        phase == .holding ? .dim : .brighten
    }
}

struct BurnInProtection {
    private static let path: [CGSize] = [
        .init(width: 0, height: 0),
        .init(width: 3, height: -2),
        .init(width: 5, height: 1),
        .init(width: 2, height: 3),
        .init(width: -2, height: 3),
        .init(width: -5, height: 1),
        .init(width: -3, height: -2),
        .init(width: 0, height: -3)
    ]

    static func offset(at date: Date) -> CGSize {
        let step = Int(date.timeIntervalSinceReferenceDate / 60)
        return path[((step % path.count) + path.count) % path.count]
    }
}

private enum PresentedSheet: String, Identifiable {
    case recordings
    case settings

    var id: String { rawValue }
}

private enum BrightnessTarget: Equatable {
    case lamp
    case silhouette
}

private struct BrightnessDragState {
    let target: BrightnessTarget
    let startingValue: Double
}

private struct BrightnessFeedback: Equatable {
    let target: BrightnessTarget
    let value: Double
}

private enum ScreenAdjustmentAxis {
    case vertical
    case horizontal
}

enum StandControlLayoutMetrics {
    static let itemHeight: CGFloat = 60
    static let rowSpacing: CGFloat = 6
    static let editorToolbarHeight: CGFloat = 46
    static let tileOpacity = 1.0
    static let foregroundOpacity = 0.78
    static let titleFontSize: CGFloat = 10.5
    static let statusFontSize: CGFloat = 8.5

    static func bottomPadding(isPortrait: Bool) -> CGFloat {
        isPortrait ? 18 : 6
    }
}

enum BottomControlLayoutPolicy {
    static func columnCount(isPortrait: Bool) -> Int {
        isPortrait ? 4 : 8
    }

    static func columnWidth(availableWidth: CGFloat, isPortrait: Bool) -> CGFloat {
        let count = CGFloat(columnCount(isPortrait: isPortrait))
        let spacingWidth = CGFloat(max(0, Int(count) - 1)) * StandControlLayoutMetrics.rowSpacing
        return max(0, (availableWidth - spacingWidth) / count)
    }

    static func itemWidth(
        for kind: StandControlKind,
        availableWidth: CGFloat,
        isPortrait: Bool
    ) -> CGFloat {
        let column = columnWidth(availableWidth: availableWidth, isPortrait: isPortrait)
        return kind == .brightness
            ? column * 2 + StandControlLayoutMetrics.rowSpacing
            : column
    }

    static func rows(
        for order: [StandControlKind],
        availableWidth: CGFloat,
        isPortrait: Bool
    ) -> [[StandControlKind]] {
        guard availableWidth > 0 else { return order.map { [$0] } }
        var rows: [[StandControlKind]] = []
        var current: [StandControlKind] = []
        var usedWidth: CGFloat = 0

        for kind in order {
            let width = itemWidth(
                for: kind,
                availableWidth: availableWidth,
                isPortrait: isPortrait
            )
            let proposedWidth = current.isEmpty
                ? width
                : usedWidth + StandControlLayoutMetrics.rowSpacing + width
            if !current.isEmpty, proposedWidth > availableWidth {
                rows.append(current)
                current = [kind]
                usedWidth = width
            } else {
                current.append(kind)
                usedWidth = proposedWidth
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    static func height(
        for order: [StandControlKind],
        availableWidth: CGFloat,
        isPortrait: Bool
    ) -> CGFloat {
        let count = rows(
            for: order,
            availableWidth: availableWidth,
            isPortrait: isPortrait
        ).count
        guard count > 0 else { return 0 }
        return CGFloat(count) * StandControlLayoutMetrics.itemHeight
            + CGFloat(count - 1) * StandControlLayoutMetrics.rowSpacing
    }
}

enum StatusPanelMetrics {
    static let height: CGFloat = 36

    static func width(isPortrait: Bool) -> CGFloat {
        isPortrait ? 260 : 320
    }
}

private struct WrappingControlLayout: Layout {
    var spacing = StandControlLayoutMetrics.rowSpacing

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let availableWidth = proposal.width ?? sizes.reduce(0) { $0 + $1.width }
        return layout(sizes: sizes, availableWidth: availableWidth).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let result = layout(sizes: sizes, availableWidth: bounds.width)
        let horizontalInset = max(0, (bounds.width - result.size.width) / 2)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + horizontalInset + position.x,
                    y: bounds.minY + position.y
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(sizes[index])
            )
        }
    }

    private func layout(
        sizes: [CGSize],
        availableWidth: CGFloat
    ) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var rowStartIndex = 0
        var rowRangesAndWidths: [(Range<Int>, CGFloat)] = []

        for size in sizes {
            if x > 0, x + size.width > availableWidth {
                rowRangesAndWidths.append((rowStartIndex..<positions.count, x - spacing))
                rowStartIndex = positions.count
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        if !sizes.isEmpty {
            rowRangesAndWidths.append((rowStartIndex..<positions.count, max(0, x - spacing)))
        }
        let maximumLineWidth = rowRangesAndWidths.map { $0.1 }.max() ?? 0
        for (indices, rowWidth) in rowRangesAndWidths {
            let inset = max(0, (maximumLineWidth - rowWidth) / 2)
            for index in indices { positions[index].x += inset }
        }
        return (
            positions,
            CGSize(
                width: min(availableWidth, maximumLineWidth),
                height: sizes.isEmpty ? 0 : y + lineHeight
            )
        )
    }
}

struct RootView: View {
    @ObservedObject private var model: StandViewModel
    @ObservedObject private var audio: AudioCaptureService
    @ObservedObject private var library: RecordingLibrary
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var weather: WeatherService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var presentedSheet: PresentedSheet?
    @State private var beginsScreenEditingAfterSheetDismiss = false
    @State private var didInitialize = false
    @State private var brightnessDragState: BrightnessDragState?
    @State private var brightnessFeedback: BrightnessFeedback?
    @State private var brightnessFeedbackTask: Task<Void, Never>?
    @State private var screenAdjustmentAxis: ScreenAdjustmentAxis?
    @State private var holdDurationGestureStart: Double?
    @State private var holdDurationFeedback: Double?
    @State private var holdDurationFeedbackTask: Task<Void, Never>?
    @State private var clockScaleGestureStart: Double?
    @State private var clockScaleFeedback: Double?
    @State private var clockScaleFeedbackTask: Task<Void, Never>?
    @State private var isEditingScreen = false
    @State private var editingLayout = StandScreenLayout.portrait
    @State private var editingIsPortrait = true
    @State private var currentIsPortrait = true
    @State private var currentCanvasSize = CGSize.zero
    @State private var currentProtectedInsets = EdgeInsets()

    init(model: StandViewModel) {
        _model = ObservedObject(wrappedValue: model)
        _audio = ObservedObject(wrappedValue: model.audio)
        _library = ObservedObject(wrappedValue: model.library)
        _settings = ObservedObject(wrappedValue: model.settings)
        _weather = ObservedObject(wrappedValue: model.weather)
    }

    var body: some View {
        GeometryReader { proxy in
            let isPortrait = proxy.size.height > proxy.size.width

            ZStack {
                LampBackground(intensity: model.lampIntensity)

                if !isEditingScreen {
                    if model.isDisplayDark, didInitialize {
                        silhouetteInfo(isPortrait: isPortrait, canvasSize: proxy.size)
                            .transition(.opacity)
                    }

                    VStack(spacing: 0) {
                        topBar(isPortrait: isPortrait)
                            .padding(.horizontal, isPortrait ? 20 : 32)
                        Spacer(minLength: 0)
                        bottomControls(
                            isPortrait: isPortrait,
                            availableWidth: max(
                                0,
                                proxy.size.width - StandControlLayoutMetrics.rowSpacing * 2
                            )
                        )
                        .padding(.horizontal, StandControlLayoutMetrics.rowSpacing)
                    }
                    .padding(.top, isPortrait ? 18 : 20)
                    .padding(.bottom, StandControlLayoutMetrics.bottomPadding(isPortrait: isPortrait))
                    .opacity(model.isDisplayDark || !didInitialize ? 0 : 1)

                    centerContent(isPortrait: isPortrait, canvasSize: proxy.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, isPortrait ? 20 : 32)
                        .opacity(model.isDisplayDark || !didInitialize ? 0 : 1)

                    statusBanners
                        .opacity(model.isDisplayDark || !didInitialize ? 0 : 1)

                    if let brightnessFeedback {
                        BrightnessFeedbackView(feedback: brightnessFeedback)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    if let clockScaleFeedback {
                        ClockScaleFeedbackView(scale: clockScaleFeedback)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                    if let holdDurationFeedback {
                        HoldDurationFeedbackView(duration: holdDurationFeedback)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }

                if isEditingScreen {
                    ScreenEditorView(
                        layout: $editingLayout,
                        isPortrait: editingIsPortrait,
                        weather: weather,
                        clockFont: Binding(
                            get: { settings.value.clockFont },
                            set: { settings.value.clockFont = $0 }
                        ),
                        hourMode: Binding(
                            get: { settings.value.clockHourMode },
                            set: { settings.value.clockHourMode = $0 }
                        ),
                        batteryText: silhouetteBatteryText,
                        onReset: {
                            editingLayout = editingIsPortrait ? .portrait : .landscape
                        },
                        onSave: saveScreenLayout
                    )
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
            .onAppear {
                currentIsPortrait = isPortrait
                updateCanvasMetrics(proxy: proxy, isPortrait: isPortrait)
            }
            .onChange(of: proxy.size) { _, _ in
                updateCanvasMetrics(proxy: proxy, isPortrait: isPortrait)
            }
            .onChange(of: settings.value.portraitLayout.controlOrder) { _, _ in
                updateCanvasMetrics(proxy: proxy, isPortrait: isPortrait)
            }
            .onChange(of: settings.value.landscapeLayout.controlOrder) { _, _ in
                updateCanvasMetrics(proxy: proxy, isPortrait: isPortrait)
            }
            .onChange(of: isPortrait) { _, value in
                currentIsPortrait = value
                updateCanvasMetrics(proxy: proxy, isPortrait: value)
            }
        }
        .grayscale(settings.value.displayTheme == .grayscale ? 1 : 0)
        .animation(.easeInOut(duration: 0.28), value: settings.value.displayTheme)
        .contentShape(Rectangle())
        .gesture(screenAdjustmentGesture.exclusively(before: screenPressGesture))
        .simultaneousGesture(clockMagnificationGesture)
        .persistentSystemOverlays(.hidden)
        .sheet(item: $presentedSheet, onDismiss: {
            model.resumeMonitoringAfterPlayback()
            if beginsScreenEditingAfterSheetDismiss {
                beginsScreenEditingAfterSheetDismiss = false
                enterScreenEditing(isPortrait: currentIsPortrait)
            }
        }) { sheet in
            switch sheet {
            case .recordings:
                RecordingsView(
                    library: library,
                    playbackDisabled: false,
                    theme: settings.value.displayTheme
                )
            case .settings:
                SettingsView(
                    model: model,
                    onEditScreen: transitionFromSettingsToScreenEditor
                )
            }
        }
        .onAppear {
            resetTransientInterface()
            model.appDidBecomeActive()
            model.startNightSession()
            didInitialize = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                resetTransientInterface()
                model.appDidBecomeActive()
                didInitialize = true
            case .inactive, .background:
                resetTransientInterface()
                didInitialize = false
                model.appWillResignActive()
            @unknown default:
                break
            }
        }
    }

    private func resetTransientInterface() {
        brightnessFeedbackTask?.cancel()
        clockScaleFeedbackTask?.cancel()
        holdDurationFeedbackTask?.cancel()

        brightnessFeedbackTask = nil
        clockScaleFeedbackTask = nil
        holdDurationFeedbackTask = nil

        brightnessDragState = nil
        brightnessFeedback = nil
        screenAdjustmentAxis = nil
        holdDurationGestureStart = nil
        holdDurationFeedback = nil
        clockScaleGestureStart = nil
        clockScaleFeedback = nil
    }

    private func topBar(isPortrait: Bool) -> some View {
        HStack(spacing: 16) {
            Text("S.tand")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .tracking(0.8)

            if model.isNightSessionActive {
                AudioStatusPill(
                    audio: audio,
                    compact: isPortrait,
                    monitoringSuspended: model.environmentDisplayMode == .stand
                )
            }

            Spacer()

            if model.isNightSessionActive, !isPortrait {
                Label(
                    model.environmentDisplayMode == .stand
                        ? "스탠드 모드 · 감시 멈춤"
                        : (audio.isWritingClip ? "수면 소리 저장 중" : "기기에서 소리 분석 중"),
                    systemImage: model.environmentDisplayMode == .stand
                        ? "sun.max.fill"
                        : (audio.isWritingClip ? "waveform.badge.mic" : "ear")
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(audio.isWritingClip ? Color.red.opacity(0.9) : Color.white.opacity(0.55))
            } else if !model.isNightSessionActive {
                Text("버전 \(AppVersion.display)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.42))
            }

            BatteryStatusPill(status: model.batteryStatus)
        }
        .foregroundStyle(.white.opacity(0.82))
        .opacity(model.controlsVisible || !model.isNightSessionActive ? 1 : 0.18)
        .animation(.easeOut(duration: 0.3), value: model.controlsVisible)
    }

    @ViewBuilder
    private func centerContent(isPortrait: Bool, canvasSize: CGSize) -> some View {
        if model.isNightSessionActive {
            clockAndWeather(isPortrait: isPortrait, isDimmed: false, canvasSize: canvasSize)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.orange.opacity(0.8))

                Text("오늘 밤도 편안하게")
                    .font(.system(.title2, design: .rounded, weight: .semibold))

                Text("취침을 시작하면 자동 잠금을 막고 박수와 수면 소리를 감지합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))

                Button {
                    model.startNightSession()
                } label: {
                    Label("취침 시작", systemImage: "bed.double.fill")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityHint("자동 잠금을 막고 소리 감지를 시작합니다")
            }
            .padding(.horizontal, isPortrait ? 8 : 0)
        }
    }

    private func silhouetteInfo(isPortrait: Bool, canvasSize: CGSize) -> some View {
        clockAndWeather(isPortrait: isPortrait, isDimmed: true, canvasSize: canvasSize)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var silhouetteBatteryText: String {
        guard let level = model.batteryStatus.level else { return "배터리 --%" }
        return "배터리 \(Int((level * 100).rounded()))%"
    }

    private func clockAndWeather(
        isPortrait: Bool,
        isDimmed: Bool,
        canvasSize: CGSize
    ) -> some View {
        DashboardCanvas(
            service: weather,
            layout: isPortrait ? settings.value.portraitLayout : settings.value.landscapeLayout,
            canvasSize: canvasSize,
            isPortrait: isPortrait,
            isDimmed: isDimmed,
            dimmedIntensity: settings.value.silhouetteIntensity,
            intensity: isDimmed ? 0 : model.lampIntensity,
            clockScale: settings.value.clockScale,
            clockFont: settings.value.clockFont,
            hourMode: settings.value.clockHourMode,
            statusText: dashboardStatusText,
            batteryText: silhouetteBatteryText,
            batterySystemImage: model.batteryStatus.isCharging
                ? "battery.100percent.bolt"
                : "battery.50percent"
        )
    }

    private var dashboardStatusText: String {
        if EnvironmentDisplayMode.resolve(
            brightness: model.displayBrightness,
            threshold: settings.value.brightnessModeThreshold
        ) == .sleeping {
            return switch model.lampPhase {
            case .off: "현재 상태 · 잠자기 모드"
            case .holding: "현재 상태 · 잠자기 전환 대기"
            case .fading: "현재 상태 · 잠자기 감광 중"
            }
        }
        return switch model.lampPhase {
        case .off: "현재 상태 · 잠자기 모드"
        case .holding: "현재 상태 · 스탠드 모드"
        case .fading: "현재 상태 · 스탠드 감광 중"
        }
    }

    private func enterScreenEditing(isPortrait: Bool) {
        editingIsPortrait = isPortrait
        editingLayout = isPortrait ? settings.value.portraitLayout : settings.value.landscapeLayout
        model.revealControls()
        withAnimation(.easeOut(duration: 0.25)) { isEditingScreen = true }
    }

    private func transitionFromSettingsToScreenEditor() {
        beginsScreenEditingAfterSheetDismiss = true
        presentedSheet = nil
    }

    private func saveScreenLayout() {
        if editingIsPortrait {
            settings.value.portraitLayout = editingLayout
        } else {
            settings.value.landscapeLayout = editingLayout
        }
        withAnimation(.easeOut(duration: 0.25)) { isEditingScreen = false }
    }

    private var screenAdjustmentGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isEditingScreen else { return }
                if screenAdjustmentAxis == nil {
                    screenAdjustmentAxis = abs(value.translation.height) > abs(value.translation.width)
                        ? .vertical
                        : .horizontal
                }

                guard screenAdjustmentAxis == .vertical else {
                    updateHoldDuration(with: value.translation.width)
                    return
                }

                let state: BrightnessDragState
                if let brightnessDragState {
                    state = brightnessDragState
                } else {
                    let target: BrightnessTarget = model.isDisplayDark ? .silhouette : .lamp
                    let startingValue = target == .silhouette
                        ? settings.value.silhouetteIntensity
                        : settings.value.lampIntensity
                    state = BrightnessDragState(target: target, startingValue: startingValue)
                    brightnessDragState = state
                    if target == .lamp {
                        model.beginManualLampAdjustment()
                    }
                }

                let change = -value.translation.height / 280
                let adjustedValue: Double
                switch state.target {
                case .lamp:
                    adjustedValue = min(1, max(0.15, state.startingValue + change))
                    model.updateManualLampBrightness(adjustedValue)
                case .silhouette:
                    adjustedValue = min(0.2, max(0.005, state.startingValue + change * 0.2))
                    settings.value.silhouetteIntensity = adjustedValue
                }

                brightnessFeedbackTask?.cancel()
                withAnimation(.easeOut(duration: 0.12)) {
                    brightnessFeedback = BrightnessFeedback(
                        target: state.target,
                        value: adjustedValue
                    )
                }
            }
            .onEnded { _ in
                guard !isEditingScreen else { return }
                switch screenAdjustmentAxis {
                case .vertical:
                    if brightnessDragState?.target == .lamp {
                        model.endManualLampAdjustment()
                    }
                    brightnessDragState = nil
                    scheduleBrightnessFeedbackHide()
                case .horizontal:
                    holdDurationGestureStart = nil
                    model.activateLamp()
                    scheduleHoldDurationFeedbackHide()
                case nil:
                    break
                }
                screenAdjustmentAxis = nil
            }
    }

    private var screenPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.8, maximumDistance: 12)
            .exclusively(
                before: TapGesture(count: 2)
                    .exclusively(before: TapGesture())
            )
            .onEnded { result in
                switch result {
                case .first(true):
                    guard !isEditingScreen else { return }
                    enterScreenEditing(isPortrait: currentIsPortrait)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                case .second(let tapResult):
                    switch tapResult {
                    case .first:
                        toggleDisplayTheme()
                    case .second:
                        handleScreenTap()
                    }
                default:
                    break
                }
            }
    }

    private func toggleDisplayTheme() {
        guard !isEditingScreen else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            settings.value.displayTheme.toggle()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func handleScreenTap() {
                guard !isEditingScreen else { return }
                if model.isNightSessionActive {
                    if ScreenTapPolicy.action(for: model.lampPhase) == .brighten {
                        model.activateLamp()
                        model.revealControls()
                    } else {
                        model.dimLampNow()
                    }
                }
    }

    private func updateHoldDuration(with horizontalTranslation: CGFloat) {
        let startingValue: Double
        if let holdDurationGestureStart {
            startingValue = holdDurationGestureStart
        } else {
            startingValue = settings.value.holdDuration
            holdDurationGestureStart = startingValue
        }

        let duration = HoldDurationAdjustment.value(
            startingAt: startingValue,
            translation: horizontalTranslation
        )
        settings.value.holdDuration = duration
        holdDurationFeedbackTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            holdDurationFeedback = duration
        }
    }

    private var clockMagnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { magnification in
                guard !isEditingScreen else { return }
                let startingScale: Double
                if let clockScaleGestureStart {
                    startingScale = clockScaleGestureStart
                } else {
                    startingScale = settings.value.clockScale
                    clockScaleGestureStart = startingScale
                }

                let requestedScale = max(0.7, startingScale * Double(magnification))
                let layout = currentIsPortrait
                    ? settings.value.portraitLayout
                    : settings.value.landscapeLayout
                let maximumScale = PanelEditingPolicy.maximumScreenScale(
                    layout: layout,
                    isPortrait: currentIsPortrait,
                    canvasSize: currentCanvasSize,
                    insets: currentProtectedInsets,
                    hardLimit: 1.35
                )
                let scale = min(max(maximumScale, startingScale), requestedScale)
                settings.value.clockScale = scale
                clockScaleFeedbackTask?.cancel()
                withAnimation(.easeOut(duration: 0.12)) {
                    clockScaleFeedback = scale
                }
            }
            .onEnded { _ in
                guard !isEditingScreen else { return }
                clockScaleGestureStart = nil
                scheduleClockScaleFeedbackHide()
            }
    }

    private func updateCanvasMetrics(proxy: GeometryProxy, isPortrait: Bool) {
        currentCanvasSize = proxy.size
        let layout = isPortrait
            ? settings.value.portraitLayout
            : settings.value.landscapeLayout
        currentProtectedInsets = PanelEditingPolicy.editingRegion(
            canvasSize: proxy.size,
            safeAreaInsets: proxy.safeAreaInsets,
            isPortrait: isPortrait,
            controlOrder: layout.controlOrder,
            bottomAvailableWidth: max(
                0,
                proxy.size.width - StandControlLayoutMetrics.rowSpacing * 2
            )
        ).insets
    }

    private func scheduleBrightnessFeedbackHide() {
        brightnessFeedbackTask?.cancel()
        brightnessFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    brightnessFeedback = nil
                }
            }
        }
    }

    private func scheduleClockScaleFeedbackHide() {
        clockScaleFeedbackTask?.cancel()
        clockScaleFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    clockScaleFeedback = nil
                }
            }
        }
    }

    private func scheduleHoldDurationFeedbackHide() {
        holdDurationFeedbackTask?.cancel()
        holdDurationFeedbackTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    holdDurationFeedback = nil
                }
            }
        }
    }

    @ViewBuilder
    private func bottomControls(isPortrait: Bool, availableWidth: CGFloat) -> some View {
        if model.isNightSessionActive, !model.controlsVisible {
            tapToControlText
        } else {
            WrappingControlLayout {
                ForEach(visibleControlOrder(isPortrait: isPortrait)) { kind in
                    bottomControl(
                        for: kind,
                        width: BottomControlLayoutPolicy.itemWidth(
                            for: kind,
                            availableWidth: availableWidth,
                            isPortrait: isPortrait
                        )
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.3), value: model.controlsVisible)
        }
    }

    private func visibleControlOrder(isPortrait: Bool) -> [StandControlKind] {
        let order = isPortrait
            ? settings.value.portraitLayout.controlOrder
            : settings.value.landscapeLayout.controlOrder
        guard !model.isNightSessionActive else { return order }
        return order.filter { ![.flashlight, .brightness, .stopDetection].contains($0) }
    }

    @ViewBuilder
    private func bottomControl(for kind: StandControlKind, width: CGFloat) -> some View {
        switch kind {
        case .flashlight:
            ControlButton(
                title: "플래시 연동",
                systemImage: settings.value.torchEnabled ? "flashlight.on.fill" : "flashlight.off.fill",
                status: settings.value.torchEnabled ? "점등 시 연동" : "연동 안 함",
                hint: "화면이 켜질 때 후면 플래시를 함께 켤지 바꿉니다",
                width: width
            ) {
                settings.value.torchEnabled.toggle()
                if settings.value.torchEnabled { model.activateLamp() }
            }
        case .brightness:
            CompactBrightnessRuleControl(
                currentBrightness: model.displayBrightness,
                width: width,
                threshold: Binding(
                    get: { settings.value.brightnessModeThreshold },
                    set: { settings.value.brightnessModeThreshold = $0 }
                )
            )
        case .stopDetection:
            ControlButton(
                title: "감지 종료",
                systemImage: "stop.circle.fill",
                hint: "소리 감지와 자동 녹음을 종료합니다",
                width: width
            ) {
                model.stopNightSession()
            }
        case .orientation:
            ControlButton(
                title: model.orientationControlTitle,
                systemImage: model.orientationControlImage,
                hint: model.orientationPreference == .automatic
                    ? "현재 화면 방향으로 고정합니다"
                    : "화면 방향이 iPhone 회전을 따르도록 바꿉니다",
                width: width
            ) {
                model.toggleOrientationLock()
            }
        case .recordings:
            ControlButton(
                title: "녹음 목록 보기",
                systemImage: "waveform",
                status: library.clips.isEmpty ? "녹음 없음" : "\(library.clips.count)개 녹음",
                hint: "저장된 수면 소리 녹음 목록을 엽니다",
                width: width
            ) {
                model.pauseMonitoringForPlayback()
                presentedSheet = .recordings
            }
        case .aiShot:
            ControlButton(
                title: "AiShot 실행",
                systemImage: "camera.aperture",
                hint: "HanClip의 AiShot 촬영 화면을 엽니다",
                width: width
            ) {
                if let url = URL(string: "hanclip://aishot") { openURL(url) }
            }
        case .settings:
            ControlButton(
                title: "설정 열기",
                systemImage: "slider.horizontal.3",
                hint: "밝기, 감지, 녹음 설정을 엽니다",
                width: width
            ) {
                presentedSheet = .settings
            }
        }
    }

    private var tapToControlText: some View {
        Label(
            model.lampPhase == .holding ? "탭하면 자연스럽게 어두워짐" : "탭하면 조명 켜짐",
            systemImage: model.lampPhase == .holding ? "moon.fill" : "lightbulb.fill"
        )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.24))
            .padding(.vertical, 12)
    }

    private var statusBanners: some View {
        VStack {
            if model.batteryProtectionActive {
                batteryProtectionBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let message = audio.recordingErrorMessage, model.isNightSessionActive {
                Label(message, systemImage: "externaldrive.badge.exclamationmark")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, 12)
    }

    private var batteryProtectionBanner: some View {
        Label(
            model.batteryStatus.isCharging
                ? "충전이 연결되었습니다. 취침 시작을 눌러 다시 시작하세요."
                : "배터리가 20% 이하라 보호를 위해 감지와 불빛을 중지했습니다.",
            systemImage: model.batteryStatus.isCharging ? "battery.100percent.bolt" : "battery.25percent"
        )
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
    }

}

private struct LampBackground: View {
    let intensity: Double

    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [
                    Color(red: 1.0, green: 0.62, blue: 0.28).opacity(intensity),
                    Color(red: 0.95, green: 0.27, blue: 0.06).opacity(intensity * 0.72),
                    Color.black.opacity(1 - intensity * 0.22)
                ],
                center: .center,
                startRadius: 20,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
        .animation(.linear(duration: 0.08), value: intensity)
    }
}

private struct BrightnessFeedbackView: View {
    let feedback: BrightnessFeedback

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: feedback.target == .lamp ? "sun.max.fill" : "moon.stars.fill")
                .font(.title2)

            Text(feedback.target == .lamp ? "화면 조명 밝기" : "슬리핑 모드 밝기")
                .font(.caption.weight(.semibold))

            ProgressView(value: normalizedValue)
                .tint(.white.opacity(0.82))
                .frame(width: 120)

            Text("\(displayPercent)%")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.white.opacity(feedback.target == .lamp ? 0.86 : 0.34))
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private var normalizedValue: Double {
        switch feedback.target {
        case .lamp: (feedback.value - 0.15) / 0.85
        case .silhouette: (feedback.value - 0.005) / 0.195
        }
    }

    private var displayPercent: Int {
        Int((normalizedValue * 100).rounded())
    }
}

private struct ClockScaleFeedbackView: View {
    let scale: Double

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.title2)
            Text("시계 크기")
                .font(.caption.weight(.semibold))
            Text("\(Int((scale * 100).rounded()))%")
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.white.opacity(0.72))
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

private struct HoldDurationFeedbackView: View {
    let duration: Double

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.title2)
            Text("어두워지기까지")
                .font(.caption.weight(.semibold))
            ProgressView(value: (duration - 10) / 290)
                .tint(.white.opacity(0.82))
                .frame(width: 140)
            Text(durationText)
                .font(.caption2.monospacedDigit())
        }
        .foregroundStyle(.white.opacity(0.78))
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private var durationText: String {
        let seconds = Int(duration.rounded())
        if seconds < 60 { return "\(seconds)초" }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return remainder == 0 ? "\(minutes)분" : "\(minutes)분 \(remainder)초"
    }
}

private struct WeatherBadge: View {
    @ObservedObject var service: WeatherService
    let isPortrait: Bool
    let isDimmed: Bool
    let dimmedIntensity: Double
    var clockScale = 1.0

    var body: some View {
        Group {
            if isPortrait {
                HStack(spacing: 16) {
                    weatherIcon
                    weatherInformation
                }
                .padding(.horizontal, 24)
                .frame(width: 282, height: 92)
                .background(
                    FlipPanelSurface(isDimmed: isDimmed, cornerRadius: 18, splitGap: 4)
                )
            } else {
                HStack(spacing: 12) {
                    weatherIcon
                        .frame(width: 88, height: 72)
                        .background(
                            FlipPanelSurface(isDimmed: isDimmed, cornerRadius: 18, splitGap: 3)
                        )

                    weatherInformation
                        .padding(.leading, 20)
                        .frame(width: 270, height: 72, alignment: .leading)
                        .background(
                            FlipPanelSurface(isDimmed: isDimmed, cornerRadius: 18, splitGap: 3)
                        )
                }
                .frame(width: 370, height: 72)
            }
        }
        .foregroundStyle(.white.opacity(isDimmed ? dimmedIntensity : 0.62))
        .scaleEffect(clockScale)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var weatherIcon: some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: isPortrait ? 34 : 30, weight: .medium))
    }

    private var weatherInformation: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(primaryText)
                .font(.title3.weight(.semibold))
            if let secondaryText {
                Text(secondaryText)
                    .font(.caption)
                    .opacity(0.72)
            }
        }
    }

    private var systemImage: String {
        if let weather = service.weather { return weather.systemImage }
        return switch service.availability {
        case .locationDenied: "location.slash.fill"
        case .failed: "exclamationmark.icloud.fill"
        default: "location.fill"
        }
    }

    private var primaryText: String {
        if let weather = service.weather {
            return "\(Int(weather.temperature.rounded()))°  \(weather.summary)"
        }
        return switch service.availability {
        case .idle, .requestingLocation: "현재 위치 확인 중"
        case .loading: "날씨 불러오는 중"
        case .locationDenied: "위치 권한 필요"
        case .failed: "날씨 확인 필요"
        case .available: "날씨 정보"
        }
    }

    private var secondaryText: String? {
        guard let weather = service.weather else {
            return service.availability == .locationDenied ? "설정에서 위치 접근을 허용해 주세요" : nil
        }
        var parts = ["체감 \(Int(weather.apparentTemperature.rounded()))°"]
        if weather.precipitation > 0 {
            parts.append("강수 \(weather.precipitation.formatted(.number.precision(.fractionLength(1))))mm")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        [primaryText, secondaryText].compactMap { $0 }.joined(separator: ", ")
    }
}

private enum WeatherPiece: Int, CaseIterable, Identifiable {
    case icon
    case temperature
    case condition

    var id: Int { rawValue }
}

private extension StandScreenLayout {
    func weatherTransform(at index: Int) -> PanelTransform {
        switch index {
        case 0: weatherIcon
        case 1: weatherTemperature
        default: weatherCondition
        }
    }

    mutating func setWeatherTransform(_ transform: PanelTransform, at index: Int) {
        switch index {
        case 0: weatherIcon = transform
        case 1: weatherTemperature = transform
        default: weatherCondition = transform
        }
    }
}

private struct DashboardCanvas: View {
    @ObservedObject var service: WeatherService
    let layout: StandScreenLayout
    let canvasSize: CGSize
    let isPortrait: Bool
    let isDimmed: Bool
    let dimmedIntensity: Double
    let intensity: Double
    let clockScale: Double
    let clockFont: ClockFontChoice
    let hourMode: ClockHourMode
    let statusText: String
    let batteryText: String
    let batterySystemImage: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let drift = BurnInProtection.offset(at: context.date)
            ZStack {
                FlipClockFace(
                    date: context.date,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    clockScale: 1,
                    clockFont: clockFont,
                    hourMode: hourMode
                )
                .panelTransform(layout.clock, canvasSize: canvasSize)

                Text(context.date, format: .dateTime.month().day().weekday(.wide))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .panelTransform(layout.date, canvasSize: canvasSize)

                Text(statusText)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .frame(
                        width: StatusPanelMetrics.width(isPortrait: isPortrait),
                        height: StatusPanelMetrics.height
                    )
                    .panelTransform(layout.status, canvasSize: canvasSize)

                if isDimmed {
                    Label(batteryText, systemImage: batterySystemImage)
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.04), in: Capsule())
                        .panelTransform(layout.battery, canvasSize: canvasSize)
                }

                WeatherPanelCollection(
                    service: service,
                    layout: layout,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    globalScale: 1,
                    canvasSize: canvasSize
                )
            }
            .scaleEffect(clockScale, anchor: .center)
            .foregroundStyle(
                .white.opacity(isDimmed ? dimmedIntensity : max(0.12, min(0.88, 0.22 + intensity)))
            )
            .offset(drift)
            .animation(.easeInOut(duration: 4), value: drift)
        }
    }
}

private extension View {
    func panelTransform(
        _ transform: PanelTransform,
        canvasSize: CGSize,
        globalScale: Double = 1
    ) -> some View {
        scaleEffect(transform.scale * globalScale)
            .offset(
                x: transform.x * canvasSize.width,
                y: transform.y * canvasSize.height
            )
    }
}

private struct WeatherPanelCollection: View {
    @ObservedObject var service: WeatherService
    let layout: StandScreenLayout
    let isPortrait: Bool
    let isDimmed: Bool
    let globalScale: Double
    let canvasSize: CGSize

    var body: some View {
        let groupIDs = Array(Set(layout.weatherGroupIDs)).sorted()
        ForEach(groupIDs, id: \.self) { groupID in
            let pieces = WeatherPiece.allCases.filter {
                layout.weatherGroupIDs[$0.rawValue] == groupID
            }
            if let first = pieces.first {
                WeatherGroupPanel(
                    service: service,
                    pieces: pieces,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed
                )
                .panelTransform(
                    layout.weatherTransform(at: first.rawValue),
                    canvasSize: canvasSize,
                    globalScale: globalScale
                )
            }
        }
    }
}

private struct WeatherGroupPanel: View {
    @ObservedObject var service: WeatherService
    let pieces: [WeatherPiece]
    let isPortrait: Bool
    let isDimmed: Bool

    var body: some View {
        let geometry = WeatherPanelGeometry(isPortrait: isPortrait)
        let cell = geometry.cellSide
        let panelWidth = cell * CGFloat(pieces.count)
        HStack(spacing: 0) {
            ForEach(pieces) { piece in
                WeatherPieceContent(
                    service: service,
                    piece: piece,
                    geometry: geometry
                )
                    .frame(width: cell, height: cell)
            }
        }
        .frame(width: panelWidth, height: cell)
        .background(
            FlipPanelSurface(
                isDimmed: isDimmed,
                cornerRadius: isPortrait ? 18 : 20,
                splitGap: geometry.splitGap
            )
        )
        .overlay(alignment: .top) {
            if pieces.contains(.temperature) {
                WeatherLocationLabel(
                    locationName: locationText,
                    isPortrait: isPortrait
                )
                .frame(width: panelWidth, height: geometry.metadataHeight)
                .padding(.top, geometry.metadataEdgeInset)
            }
        }
    }

    private var locationText: String {
        if let locationName = service.locationName {
            return locationName
        }

        return switch service.availability {
        case .locationDenied: "위치 권한 필요"
        case .failed: "위치 확인 필요"
        default: "현재 위치"
        }
    }
}

struct WeatherPanelGeometry: Equatable {
    let cellSide: CGFloat
    let splitGap: CGFloat
    let metadataHeight: CGFloat
    let metadataEdgeInset: CGFloat
    let temperatureOpticalOffset: CGFloat

    init(isPortrait: Bool) {
        cellSide = (isPortrait ? 282 : 370) / 3
        splitGap = isPortrait ? 4 : 3
        metadataHeight = 18
        metadataEdgeInset = isPortrait ? 7 : 8
        // The raised degree mark makes the temperature's ink look high even when
        // SwiftUI's line box is mathematically centered.
        temperatureOpticalOffset = isPortrait ? 2 : 2.5
    }

    var panelCenterY: CGFloat { cellSide / 2 }
    var locationCenterY: CGFloat { metadataEdgeInset + metadataHeight / 2 }
    var apparentTemperatureCenterY: CGFloat {
        cellSide - metadataEdgeInset - metadataHeight / 2
    }
}

enum WeatherLocationMarquee {
    static func offset(
        elapsed: TimeInterval,
        overflow: CGFloat,
        speed: CGFloat = 18,
        pause: TimeInterval = 1.2
    ) -> CGFloat {
        guard overflow > 0, speed > 0 else { return 0 }

        let travelDuration = TimeInterval(overflow / speed)
        let cycleDuration = (travelDuration * 2) + (pause * 2)
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: cycleDuration)

        if phase < pause { return 0 }
        if phase < pause + travelDuration {
            return -CGFloat(phase - pause) * speed
        }
        if phase < (pause * 2) + travelDuration {
            return -overflow
        }

        let returnElapsed = phase - ((pause * 2) + travelDuration)
        return min(0, -overflow + CGFloat(returnElapsed) * speed)
    }
}

private struct WeatherLocationLabel: View {
    let locationName: String
    let isPortrait: Bool

    private var font: Font {
        .system(size: isPortrait ? 11 : 13, weight: .medium, design: .rounded)
    }

    var body: some View {
        WeatherLocationMarqueeText(
            text: locationName,
            font: font,
            iconSize: isPortrait ? 9 : 11
        )
        .opacity(0.72)
        .padding(.horizontal, isPortrait ? 8 : 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("현재 위치, \(locationName)")
    }
}

private struct WeatherLocationMarqueeText: View {
    let text: String
    let font: Font
    let iconSize: CGFloat

    @State private var textWidth: CGFloat = 0
    @State private var startedAt = Date.now

    var body: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 5
            let iconWidth = iconSize
            let availableTextWidth = max(0, proxy.size.width - iconWidth - spacing)
            let textViewportWidth = min(textWidth, availableTextWidth)
            let overflow = max(0, textWidth - textViewportWidth)

            HStack(spacing: spacing) {
                Image(systemName: "location.fill")
                    .font(.system(size: iconSize, weight: .semibold))
                    .frame(width: iconWidth)

                TimelineView(.animation(minimumInterval: 1 / 30, paused: overflow <= 0)) { context in
                    Text(text)
                        .font(font)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .background {
                            GeometryReader { textProxy in
                                Color.clear.preference(
                                    key: WeatherLocationTextWidthKey.self,
                                    value: textProxy.size.width
                                )
                            }
                        }
                        .offset(
                            x: WeatherLocationMarquee.offset(
                                elapsed: context.date.timeIntervalSince(startedAt),
                                overflow: overflow
                            )
                        )
                }
                .frame(width: textViewportWidth, alignment: .leading)
                .clipped()
            }
            .frame(
                width: iconWidth + spacing + textViewportWidth,
                alignment: .leading
            )
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: isFiniteHeight)
        .clipped()
        .onPreferenceChange(WeatherLocationTextWidthKey.self) { textWidth = $0 }
    }

    private var isFiniteHeight: CGFloat { 18 }
}

private struct WeatherLocationTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct WeatherPieceContent: View {
    @ObservedObject var service: WeatherService
    let piece: WeatherPiece
    let geometry: WeatherPanelGeometry

    private var isPortrait: Bool { geometry.cellSide < 100 }

    var body: some View {
        Group {
            switch piece {
            case .icon:
                Image(systemName: service.weather?.systemImage ?? "location.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: isPortrait ? 34 : 40, weight: .medium))
            case .temperature:
                ZStack {
                    Text(service.weather.map { "\(Int($0.temperature.rounded()))°" } ?? "--°")
                        .font(.system(size: isPortrait ? 28 : 34, weight: .semibold, design: .rounded))
                        .offset(y: geometry.temperatureOpticalOffset)

                    Text(service.weather.map { "체감 \(Int($0.apparentTemperature.rounded()))°" } ?? "체감 --°")
                        .font(.system(size: isPortrait ? 11 : 13, weight: .medium, design: .rounded))
                        .opacity(0.72)
                        .frame(height: geometry.metadataHeight)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, geometry.metadataEdgeInset)
                }
            case .condition:
                Text(service.weather?.summary ?? "날씨")
                    .font(.system(size: isPortrait ? 17 : 20, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .multilineTextAlignment(.center)
    }
}

private struct CompactBrightnessRuleControl: View {
    let currentBrightness: Double
    let width: CGFloat
    @Binding var threshold: Double
    @State private var trackFrame = CGRect.zero
    @State private var interactionPhase: BrightnessRuleGesturePhase = .undecided

    private let coordinateSpaceName = "compactBrightnessRule"

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Label("잠자기", systemImage: "moon.fill")
                    .foregroundStyle(threshold < currentBrightness ? Color.orange : Color.white.opacity(0.42))
                Spacer()
                Label("스탠드", systemImage: "sun.max.fill")
                    .foregroundStyle(threshold >= currentBrightness ? Color.orange : Color.white.opacity(0.42))
            }
            .font(.system(size: StandControlLayoutMetrics.titleFontSize, weight: .semibold))
            .labelStyle(.titleAndIcon)

            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                let gap: CGFloat = 2
                let availableWidth = max(0, width - gap)
                let splitX = availableWidth * threshold

                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        Capsule()
                            .fill(.white.opacity(0.24))
                            .frame(width: splitX, height: 4)
                        Capsule()
                            .fill(.white.opacity(0.10))
                            .frame(width: availableWidth - splitX, height: 4)
                    }

                    Rectangle()
                        .fill(.white.opacity(0.48))
                        .frame(width: 1, height: 12)
                        .offset(x: max(0, width - 1) * threshold)

                    Circle()
                        .fill(Color.orange.opacity(0.9))
                        .frame(width: 5, height: 5)
                        .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 0.5))
                        .offset(x: max(0, width - 5) * currentBrightness)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .background {
                    GeometryReader { trackProxy in
                        Color.clear.preference(
                            key: BrightnessRuleTrackFramePreferenceKey.self,
                            value: trackProxy.frame(in: .named(coordinateSpaceName))
                        )
                    }
                }
            }
            .frame(height: 20)

            Text("현재 \(Int((currentBrightness * 100).rounded())) · 기준 \(Int((threshold * 100).rounded()))")
                .font(
                    .system(
                        size: StandControlLayoutMetrics.statusFontSize,
                        weight: .medium,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.52))
        }
        .padding(.horizontal, 8)
        .frame(
            width: width,
            height: StandControlLayoutMetrics.itemHeight
        )
        .background {
            FlipPanelSurface(isDimmed: false, cornerRadius: 13, splitGap: 2)
        }
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .coordinateSpace(name: coordinateSpaceName)
        .onPreferenceChange(BrightnessRuleTrackFramePreferenceKey.self) { trackFrame = $0 }
        .highPriorityGesture(interactionGesture)
        .opacity(StandControlLayoutMetrics.tileOpacity)
        .accessibilityLabel("밝기 기준, 현재 \(Int(currentBrightness * 100))퍼센트, 기준 \(Int(threshold * 100))퍼센트")
        .accessibilityHint("좌우로 밀어 기준을 조절하거나 탭하여 잠자기와 스탠드 모드를 전환합니다")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: threshold = min(1, threshold + 0.05)
            case .decrement: threshold = max(0, threshold - 0.05)
            @unknown default: break
            }
        }
    }

    private var interactionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                updateInteraction(
                    translation: value.translation,
                    startLocation: value.startLocation,
                    currentLocation: value.location
                )
            }
            .onEnded { value in
                finishInteraction(
                    translation: value.translation,
                    currentLocation: value.location
                )
            }
    }

    private func updateInteraction(
        translation: CGSize,
        startLocation: CGPoint,
        currentLocation: CGPoint
    ) {
        if interactionPhase == .undecided {
            guard BrightnessRuleInteractionPolicy.hasReachedDecisionDistance(translation) else {
                return
            }
            interactionPhase = BrightnessRuleInteractionPolicy.isDirectHorizontalDrag(
                translation: translation
            ) && trackFrame.contains(startLocation)
                ? .draggingTrack
                : .ignored
        }

        guard interactionPhase == .draggingTrack else { return }
        threshold = BrightnessThresholdPolicy.value(
            locationX: currentLocation.x - trackFrame.minX,
            width: trackFrame.width
        )
    }

    private func finishInteraction(translation: CGSize, currentLocation: CGPoint) {
        if interactionPhase == .draggingTrack {
            threshold = BrightnessThresholdPolicy.value(
                locationX: currentLocation.x - trackFrame.minX,
                width: trackFrame.width
            )
        } else if interactionPhase == .undecided,
                  BrightnessRuleInteractionPolicy.isTap(translation) {
            toggleMode()
        }
        interactionPhase = .undecided
    }

    private func toggleMode() {
        withAnimation(.easeInOut(duration: 0.24)) {
            threshold = BrightnessThresholdPolicy.valueAfterTap(
                currentBrightness: currentBrightness,
                threshold: threshold
            )
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

enum BrightnessRuleGesturePhase {
    case undecided
    case draggingTrack
    case ignored
}

struct BrightnessRuleTrackFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

enum BrightnessRuleInteractionPolicy {
    static let minimumDragDistance: CGFloat = 6

    static func hasReachedDecisionDistance(_ translation: CGSize) -> Bool {
        max(abs(translation.width), abs(translation.height)) >= minimumDragDistance
    }

    static func isTap(_ translation: CGSize) -> Bool {
        !hasReachedDecisionDistance(translation)
    }

    static func isDirectHorizontalDrag(
        translation: CGSize,
        alreadyDragging: Bool = false
    ) -> Bool {
        if alreadyDragging { return true }
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)
        return horizontalDistance >= minimumDragDistance
            && horizontalDistance >= verticalDistance
    }
}

enum BrightnessThresholdPolicy {
    static func value(locationX: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, Double(locationX / width)))
    }

    static func valueAfterTap(currentBrightness: Double, threshold: Double) -> Double {
        let brightness = min(1, max(0, currentBrightness))
        if threshold < brightness {
            return brightness + (1 - brightness) / 4
        }
        return brightness - brightness / 4
    }
}

private struct ScreenEditorView: View {
    @Binding var layout: StandScreenLayout
    let isPortrait: Bool
    @ObservedObject var weather: WeatherService
    @Binding var clockFont: ClockFontChoice
    @Binding var hourMode: ClockHourMode
    let batteryText: String
    let onReset: () -> Void
    let onSave: () -> Void
    @State private var showFontPalette = false

    var body: some View {
        GeometryReader { proxy in
            let bottomHorizontalPadding = StandControlLayoutMetrics.rowSpacing
            let bottomAvailableWidth = max(0, proxy.size.width - bottomHorizontalPadding * 2)

            ZStack {
                Color.black.opacity(0.32).ignoresSafeArea()

                Rectangle().fill(.white.opacity(0.16)).frame(width: 0.5)
                Rectangle().fill(.white.opacity(0.16)).frame(height: 0.5)

                EditablePanel(
                    transform: $layout.clock,
                    canvasSize: proxy.size
                ) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        FlipClockFace(
                            date: context.date,
                            isPortrait: isPortrait,
                            isDimmed: false,
                            clockScale: 1,
                            clockFont: clockFont,
                            hourMode: hourMode
                        )
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            TapGesture(count: 2).onEnded {
                                hourMode.toggle()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        )
                        .onTapGesture { showFontPalette.toggle() }
                    }
                }

                editableWeatherPanels(
                    canvasSize: proxy.size
                )

                EditablePanel(
                    transform: $layout.date,
                    canvasSize: proxy.size
                ) {
                    Text(Date.now, format: .dateTime.month().day().weekday(.wide))
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                }

                EditablePanel(
                    transform: $layout.status,
                    canvasSize: proxy.size
                ) {
                    Text("현재 상태 · 스탠드 모드")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .padding(.horizontal, 12)
                        .frame(
                            width: StatusPanelMetrics.width(isPortrait: isPortrait),
                            height: StatusPanelMetrics.height
                        )
                        .background(.white.opacity(0.08), in: Capsule())
                }

                EditablePanel(
                    transform: $layout.battery,
                    canvasSize: proxy.size
                ) {
                    Label(batteryText, systemImage: "battery.100percent.bolt")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                }

                if showFontPalette {
                    VStack {
                        Spacer()
                        fontPalette
                    }
                    .padding(.horizontal, isPortrait ? 14 : 28)
                    .padding(.bottom, isPortrait ? 22 : 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
                } else {
                    VStack {
                        Spacer()
                        EditorControlOrderView(
                            order: $layout.controlOrder,
                            availableWidth: bottomAvailableWidth,
                            isPortrait: isPortrait
                        )
                    }
                    .padding(.horizontal, bottomHorizontalPadding)
                    .padding(
                        .bottom,
                        StandControlLayoutMetrics.bottomPadding(isPortrait: isPortrait)
                    )
                    .zIndex(5)
                }

                VStack {
                    HStack {
                        Button("초기화", action: onReset)
                        Spacer()
                        Text(isPortrait ? "세로 화면 편집" : "가로 화면 편집")
                            .font(.headline)
                        Spacer()
                        Button("저장", action: onSave)
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 20)
                    .frame(height: StandControlLayoutMetrics.editorToolbarHeight)
                    .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                }
                .padding(isPortrait ? 18 : 14)
                .zIndex(10)
            }
            .foregroundStyle(.white.opacity(0.86))
        }
    }

    @ViewBuilder
    private func editableWeatherPanels(
        canvasSize: CGSize
    ) -> some View {
        let groupIDs = Array(Set(layout.weatherGroupIDs)).sorted()
        ForEach(groupIDs, id: \.self) { groupID in
            let pieces = WeatherPiece.allCases.filter {
                layout.weatherGroupIDs[$0.rawValue] == groupID
            }
            EditablePanel(
                transform: weatherBinding(for: groupID),
                canvasSize: canvasSize,
                onEnded: { mergeWeatherGroup(groupID, canvasSize: canvasSize) }
            ) {
                WeatherGroupPanel(
                    service: weather,
                    pieces: pieces,
                    isPortrait: isPortrait,
                    isDimmed: false
                )
            }
            .onTapGesture(count: 2) {
                if pieces.count > 1 { splitWeatherGroup(groupID) }
            }
        }
    }

    private func weatherBinding(for groupID: Int) -> Binding<PanelTransform> {
        Binding(
            get: {
                let index = layout.weatherGroupIDs.firstIndex(of: groupID) ?? 0
                return layout.weatherTransform(at: index)
            },
            set: { newValue in
                for index in layout.weatherGroupIDs.indices where layout.weatherGroupIDs[index] == groupID {
                    layout.setWeatherTransform(newValue, at: index)
                }
            }
        )
    }

    private func mergeWeatherGroup(_ groupID: Int, canvasSize: CGSize) {
        let sourceIndices = layout.weatherGroupIDs.indices.filter { layout.weatherGroupIDs[$0] == groupID }
        guard let sourceIndex = sourceIndices.first else { return }
        let source = layout.weatherTransform(at: sourceIndex)
        let candidates = Array(Set(layout.weatherGroupIDs)).filter { $0 != groupID }
        let sourceBounds = weatherBounds(for: groupID, canvasSize: canvasSize)
        guard let targetID = candidates.max(by: {
            PanelEditingPolicy.overlapFraction(
                sourceBounds,
                weatherBounds(for: $0, canvasSize: canvasSize)
            ) < PanelEditingPolicy.overlapFraction(
                sourceBounds,
                weatherBounds(for: $1, canvasSize: canvasSize)
            )
        }) else { return }
        let target = weatherBinding(for: targetID).wrappedValue
        let overlap = PanelEditingPolicy.overlapFraction(
            sourceBounds,
            weatherBounds(for: targetID, canvasSize: canvasSize)
        )
        guard overlap >= PanelEditingPolicy.weatherMergeOverlapThreshold else { return }

        let targetIndices = layout.weatherGroupIDs.indices.filter { layout.weatherGroupIDs[$0] == targetID }
        let leftIndex = (sourceIndices + targetIndices).min {
            layout.weatherTransform(at: $0).x < layout.weatherTransform(at: $1).x
        } ?? sourceIndex
        var merged = layout.weatherTransform(at: leftIndex)
        merged.x = (source.x + target.x) / 2
        merged.y = (source.y + target.y) / 2
        for index in sourceIndices + targetIndices {
            layout.weatherGroupIDs[index] = targetID
            layout.setWeatherTransform(merged, at: index)
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func splitWeatherGroup(_ groupID: Int) {
        let indices = layout.weatherGroupIDs.indices.filter { layout.weatherGroupIDs[$0] == groupID }
        guard indices.count > 1, let first = indices.first else { return }
        let center = layout.weatherTransform(at: first)
        for (position, index) in indices.enumerated() {
            layout.weatherGroupIDs[index] = index
            var transform = center
            transform.x += Double(position) * 0.16 - Double(indices.count - 1) * 0.08
            layout.setWeatherTransform(transform, at: index)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func weatherBounds(for groupID: Int, canvasSize: CGSize) -> CGRect {
        let piecesCount = layout.weatherGroupIDs.filter { $0 == groupID }.count
        let transform = weatherBinding(for: groupID).wrappedValue
        let totalWidth: CGFloat = isPortrait ? 282 : 370
        let cell = totalWidth / 3
        let width = cell * CGFloat(piecesCount) * transform.scale
        let height = cell * transform.scale
        let center = CGPoint(
            x: canvasSize.width / 2 + transform.x * canvasSize.width,
            y: canvasSize.height / 2 + transform.y * canvasSize.height
        )
        return CGRect(
            x: center.x - width / 2,
            y: center.y - height / 2,
            width: width,
            height: height
        )
    }

    private var fontPalette: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                spacing: 8
            ) {
                ForEach(ClockFontChoice.allCases) { choice in
                    Button {
                        clockFont = choice
                    } label: {
                        FontMiniClock(choice: choice, selected: choice == clockFont)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .frame(maxWidth: isPortrait ? 390 : 650, maxHeight: isPortrait ? 190 : 126)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

extension StandControlKind {
    var editorTitle: String {
        switch self {
        case .flashlight: "플래시"
        case .brightness: "밝기 기준"
        case .stopDetection: "감지 종료"
        case .orientation: "화면 방향"
        case .recordings: "수면 소리"
        case .aiShot: "AiShot"
        case .settings: "설정"
        }
    }

    var editorSystemImage: String {
        switch self {
        case .flashlight: "flashlight.on.fill"
        case .brightness: "slider.horizontal.3"
        case .stopDetection: "stop.circle.fill"
        case .orientation: "rectangle.portrait.rotate"
        case .recordings: "waveform"
        case .aiShot: "camera.aperture"
        case .settings: "gearshape.fill"
        }
    }
}

private struct EditorControlOrderView: View {
    @Binding var order: [StandControlKind]
    let availableWidth: CGFloat
    let isPortrait: Bool
    @State private var draggedKind: StandControlKind?

    var body: some View {
        WrappingControlLayout {
            ForEach(order) { kind in
                EditorControlOrderTile(
                    kind: kind,
                    width: BottomControlLayoutPolicy.itemWidth(
                        for: kind,
                        availableWidth: availableWidth,
                        isPortrait: isPortrait
                    )
                )
                    .onDrag {
                        draggedKind = kind
                        return NSItemProvider(object: kind.rawValue as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: ControlOrderDropDelegate(
                            target: kind,
                            order: $order,
                            draggedKind: $draggedKind
                        )
                    )
            }
        }
        .frame(
            width: availableWidth,
            height: BottomControlLayoutPolicy.height(
                for: order,
                availableWidth: availableWidth,
                isPortrait: isPortrait
            )
        )
        .accessibilityLabel("하단 버튼 순서 편집")
        .accessibilityHint("버튼을 끌어 순서를 변경합니다")
    }
}

private struct EditorControlOrderTile: View {
    let kind: StandControlKind
    let width: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: kind.editorSystemImage)
                .font(.system(size: 15, weight: .semibold))
            Text(kind.editorTitle)
                .font(.system(size: StandControlLayoutMetrics.titleFontSize, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(StandControlLayoutMetrics.foregroundOpacity))
        .frame(
            width: width,
            height: StandControlLayoutMetrics.itemHeight
        )
        .background {
            FlipPanelSurface(isDimmed: false, cornerRadius: 13, splitGap: 2)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.orange.opacity(0.72))
                .padding(7)
        }
        .contentShape(Rectangle())
        .accessibilityLabel("\(kind.editorTitle), 순서 변경")
    }
}

private struct ControlOrderDropDelegate: DropDelegate {
    let target: StandControlKind
    @Binding var order: [StandControlKind]
    @Binding var draggedKind: StandControlKind?

    func dropEntered(info: DropInfo) {
        guard let draggedKind,
              draggedKind != target,
              let sourceIndex = order.firstIndex(of: draggedKind),
              let targetIndex = order.firstIndex(of: target)
        else { return }

        withAnimation(.snappy(duration: 0.2)) {
            order.move(
                fromOffsets: IndexSet(integer: sourceIndex),
                toOffset: targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
            )
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedKind = nil
        return true
    }
}

struct PanelEditingRegion: Equatable {
    let frame: CGRect
    let insets: EdgeInsets
}

enum PanelEditingPolicy {
    static let weatherMergeOverlapThreshold: CGFloat = 0.40
    static let minimumPanelScale = 0.30
    static let maximumPanelScale = 2.00

    static func protectedInsets(
        safeAreaInsets: EdgeInsets,
        isPortrait: Bool,
        fontPaletteVisible: Bool = false,
        bottomControlAreaHeight: CGFloat? = nil
    ) -> EdgeInsets {
        let topOuterPadding: CGFloat = isPortrait ? 18 : 14
        let topGuideClearance: CGFloat = isPortrait ? 12 : 2
        let bottomOuterPadding = StandControlLayoutMetrics.bottomPadding(isPortrait: isPortrait)
        let bottomGuideClearance: CGFloat = isPortrait ? 6 : 2
        let bottomRowCount: CGFloat = isPortrait ? 2 : 1
        let defaultBottomRowsHeight = StandControlLayoutMetrics.itemHeight * bottomRowCount
            + StandControlLayoutMetrics.rowSpacing * max(0, bottomRowCount - 1)
        let controlBoundary = safeAreaInsets.bottom
            + bottomOuterPadding
            + (bottomControlAreaHeight ?? defaultBottomRowsHeight)
            + bottomGuideClearance

        let paletteHeight: CGFloat = isPortrait ? 190 : 126
        let paletteBottomPadding: CGFloat = isPortrait ? 22 : 14
        let paletteGuideClearance: CGFloat = isPortrait ? 8 : 2
        let fontPaletteBoundary = safeAreaInsets.bottom
            + paletteBottomPadding
            + paletteHeight
            + paletteGuideClearance

        return EdgeInsets(
            top: safeAreaInsets.top
                + topOuterPadding
                + StandControlLayoutMetrics.editorToolbarHeight
                + topGuideClearance,
            leading: safeAreaInsets.leading + (isPortrait ? 14 : 24),
            bottom: fontPaletteVisible
                ? max(controlBoundary, fontPaletteBoundary)
                : controlBoundary,
            trailing: safeAreaInsets.trailing + (isPortrait ? 14 : 24)
        )
    }

    static func editingRegion(
        canvasSize: CGSize,
        safeAreaInsets: EdgeInsets,
        isPortrait: Bool,
        fontPaletteVisible: Bool = false,
        controlOrder: [StandControlKind]? = nil,
        bottomAvailableWidth: CGFloat? = nil,
        reservesEditorChrome: Bool = true
    ) -> PanelEditingRegion {
        let controlAreaHeight: CGFloat? = controlOrder.map {
            BottomControlLayoutPolicy.height(
                for: $0,
                availableWidth: bottomAvailableWidth
                    ?? max(0, canvasSize.width - StandControlLayoutMetrics.rowSpacing * 2),
                isPortrait: isPortrait
            )
        }
        var insets = protectedInsets(
            safeAreaInsets: safeAreaInsets,
            isPortrait: isPortrait,
            fontPaletteVisible: fontPaletteVisible,
            bottomControlAreaHeight: controlAreaHeight
        )
        if !reservesEditorChrome {
            insets.top = 0
            insets.bottom = 0
        }
        let minimumX = min(canvasSize.width, insets.leading)
        let maximumX = max(minimumX, canvasSize.width - insets.trailing)
        let minimumY = min(canvasSize.height, insets.top)
        let maximumY = max(minimumY, canvasSize.height - insets.bottom)
        return PanelEditingRegion(
            frame: CGRect(
                x: minimumX,
                y: minimumY,
                width: maximumX - minimumX,
                height: maximumY - minimumY
            ),
            insets: insets
        )
    }

    static func shouldSnapToCenter(centerOffset: CGFloat, panelLength: CGFloat) -> Bool {
        panelLength > 0 && abs(centerOffset) <= panelLength * 0.05
    }

    static func scaleFromTopLeadingDrag(
        startScale: Double,
        panelSize: CGSize,
        translation: CGSize
    ) -> Double {
        guard panelSize.width > 0, panelSize.height > 0 else { return startScale }
        let halfWidth = panelSize.width * startScale / 2
        let halfHeight = panelSize.height * startScale / 2
        let denominator = halfWidth * halfWidth + halfHeight * halfHeight
        guard denominator > 0 else { return startScale }
        let resizedX = -halfWidth + translation.width
        let resizedY = -halfHeight + translation.height
        let projectedRatio = max(
            0,
            (resizedX * -halfWidth + resizedY * -halfHeight) / denominator
        )
        return min(
            maximumPanelScale,
            max(minimumPanelScale, startScale * projectedRatio)
        )
    }

    static func overlapFraction(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
        guard smallerArea > 0 else { return 0 }
        return intersection.width * intersection.height / smallerArea
    }

    static func clampedCenter(
        _ proposed: CGPoint,
        panelSize: CGSize,
        canvasSize: CGSize,
        insets: EdgeInsets
    ) -> CGPoint {
        let halfWidth = panelSize.width / 2
        let halfHeight = panelSize.height / 2
        let minimumX = insets.leading + halfWidth
        let maximumX = max(minimumX, canvasSize.width - insets.trailing - halfWidth)
        let minimumY = insets.top + halfHeight
        let maximumY = max(minimumY, canvasSize.height - insets.bottom - halfHeight)
        return CGPoint(
            x: min(maximumX, max(minimumX, proposed.x)),
            y: min(maximumY, max(minimumY, proposed.y))
        )
    }

    static func clampedTransform(
        _ transform: PanelTransform,
        panelSize: CGSize,
        canvasSize: CGSize,
        insets: EdgeInsets,
        screenScale: Double
    ) -> PanelTransform {
        guard canvasSize.width > 0, canvasSize.height > 0, panelSize != .zero else {
            return transform
        }

        // 편집 화면 자체와 저장 후 전체 확대 화면 중 더 큰 쪽을 기준으로 제한한다.
        // 전체 화면이 축소된 상태에서도 편집 패널이 버튼 경계를 넘어가지 않는다.
        let groupScale = max(1, screenScale)
        let renderedSize = CGSize(
            width: panelSize.width * transform.scale * groupScale,
            height: panelSize.height * transform.scale * groupScale
        )
        let proposedCenter = CGPoint(
            x: canvasSize.width / 2 + transform.x * canvasSize.width * groupScale,
            y: canvasSize.height / 2 + transform.y * canvasSize.height * groupScale
        )
        let center = clampedCenter(
            proposedCenter,
            panelSize: renderedSize,
            canvasSize: canvasSize,
            insets: insets
        )
        var result = transform
        result.x = (center.x - canvasSize.width / 2) / (canvasSize.width * groupScale)
        result.y = (center.y - canvasSize.height / 2) / (canvasSize.height * groupScale)
        return result
    }

    static func maximumScreenScale(
        layout: StandScreenLayout,
        isPortrait: Bool,
        canvasSize: CGSize,
        insets: EdgeInsets,
        hardLimit: Double
    ) -> Double {
        guard canvasSize.height > 0 else { return hardLimit }
        let canvasCenterY = canvasSize.height / 2
        let topRoom = max(0, canvasCenterY - insets.top)
        let bottomRoom = max(0, canvasSize.height - insets.bottom - canvasCenterY)
        let weatherHeight: CGFloat = (isPortrait ? 282 : 370) / 3
        let panels: [(PanelTransform, CGFloat)] = [
            (layout.weatherIcon, weatherHeight),
            (layout.weatherTemperature, weatherHeight),
            (layout.weatherCondition, weatherHeight),
            (layout.date, 36),
            (layout.status, StatusPanelMetrics.height),
            (layout.battery, 36),
            (layout.clock, isPortrait ? 92 : 116)
        ]

        var maximum = hardLimit
        for (transform, baseHeight) in panels {
            let centerOffset = CGFloat(transform.y) * canvasSize.height
            let halfHeight = baseHeight * transform.scale / 2
            let topReach = halfHeight - centerOffset
            let bottomReach = halfHeight + centerOffset
            if topReach > 0 { maximum = min(maximum, Double(topRoom / topReach)) }
            if bottomReach > 0 { maximum = min(maximum, Double(bottomRoom / bottomReach)) }
        }
        return max(0.7, maximum)
    }
}

private struct EditablePanelSizeKey: PreferenceKey {
    static var defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

private struct EditablePanel<Content: View>: View {
    @Binding var transform: PanelTransform
    let canvasSize: CGSize
    var onEnded: () -> Void = {}
    @ViewBuilder let content: () -> Content
    @State private var dragStart: PanelTransform?
    @State private var scaleStart: Double?
    @State private var cornerResizeStart: Double?
    @State private var panelSize = CGSize.zero
    @State private var snappedToVerticalGuide = false
    @State private var snappedToHorizontalGuide = false

    var body: some View {
        content()
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: EditablePanelSizeKey.self, value: proxy.size)
                }
            }
            .onPreferenceChange(EditablePanelSizeKey.self) { measuredSize in
                panelSize = measuredSize
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.orange.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4]))
            }
            .overlay(alignment: .topLeading) {
                ZStack {
                    Circle()
                        .fill(.orange.opacity(0.9))
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.black.opacity(0.72))
                }
                .frame(width: 26, height: 26)
                .contentShape(Circle())
                .offset(x: -10, y: -10)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let start = cornerResizeStart ?? transform.scale
                            cornerResizeStart = start
                            transform.scale = PanelEditingPolicy.scaleFromTopLeadingDrag(
                                startScale: start,
                                panelSize: panelSize,
                                translation: value.translation
                            )
                        }
                        .onEnded { _ in
                            cornerResizeStart = nil
                            UISelectionFeedbackGenerator().selectionChanged()
                            onEnded()
                        }
                )
                .accessibilityLabel("패널 크기 조절")
                .accessibilityHint("왼쪽 위 조절점을 끌어 패널 중심을 유지한 채 크기를 변경합니다")
            }
            .panelTransform(transform, canvasSize: canvasSize)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let start = dragStart ?? transform
                        dragStart = start
                        let proposedX = start.x + value.translation.width / canvasSize.width
                        let proposedY = start.y + value.translation.height / canvasSize.height
                        let snapX = PanelEditingPolicy.shouldSnapToCenter(
                            centerOffset: proposedX * canvasSize.width,
                            panelLength: panelSize.width * transform.scale
                        )
                        let snapY = PanelEditingPolicy.shouldSnapToCenter(
                            centerOffset: proposedY * canvasSize.height,
                            panelLength: panelSize.height * transform.scale
                        )
                        transform.x = snapX ? 0 : proposedX
                        transform.y = snapY ? 0 : proposedY
                        if (snapX && !snappedToVerticalGuide)
                            || (snapY && !snappedToHorizontalGuide) {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        snappedToVerticalGuide = snapX
                        snappedToHorizontalGuide = snapY
                    }
                    .onEnded { _ in
                        dragStart = nil
                        snappedToVerticalGuide = false
                        snappedToHorizontalGuide = false
                        onEnded()
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        let start = scaleStart ?? transform.scale
                        scaleStart = start
                        transform.scale = min(
                            PanelEditingPolicy.maximumPanelScale,
                            max(
                                PanelEditingPolicy.minimumPanelScale,
                                start * Double(value)
                            )
                        )
                    }
                    .onEnded { _ in scaleStart = nil }
            )
    }


}

private struct FontMiniClock: View {
    let choice: ClockFontChoice
    let selected: Bool

    var body: some View {
        HStack(spacing: 3) {
            miniCard("12")
            Text(":").font(choice.font(size: 16))
            miniCard("34")
        }
        .padding(5)
        .background(selected ? Color.orange.opacity(0.24) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func miniCard(_ value: String) -> some View {
        Text(value)
            .font(choice.font(size: 20))
            .offset(y: choice.clockVerticalOffset(size: 20))
            .mask(FlipTextSplitMask(gap: 2))
            .frame(width: 38, height: 30)
            .background(FlipPanelSurface(isDimmed: false, cornerRadius: 7, splitGap: 2))
    }
}

private struct NightClock: View {
    let phase: LampPhase
    let intensity: Double
    let isPortrait: Bool
    let isDimmed: Bool
    let dimmedIntensity: Double
    let clockScale: Double
    let clockFont: ClockFontChoice
    let automaticDimmingEnabled: Bool
    let automaticDimmingPaused: Bool
    let manualDimmingHoldActive: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                FlipClockFace(
                    date: context.date,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    clockScale: clockScale,
                    clockFont: clockFont
                )

                VStack(spacing: 5) {
                Text(context.date, format: .dateTime.month().day().weekday(.wide))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(isDimmed ? dimmedIntensity : 0.48))

                if !isDimmed {
                    Text(statusText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.36))
                        .padding(.top, 6)
                }
                }
                .offset(
                    y: (isPortrait ? 92 : 116) * clockScale / 2
                        + (isDimmed ? 12 : 24)
                )
            }
            .foregroundStyle(
                .white.opacity(isDimmed ? dimmedIntensity : max(0.12, min(0.88, 0.22 + intensity)))
            )
            .accessibilityElement(children: .combine)
        }
    }

    private var statusText: String {
        if manualDimmingHoldActive {
            return "현재 상태 · 롱 터치 밝기 고정 중"
        }
        if !automaticDimmingEnabled {
            return "현재 상태 · 자동 디밍 꺼짐 · 화면 밝기 유지 중"
        }
        if automaticDimmingPaused {
            return "현재 상태 · 밝은 환경으로 판단해 자동 감광 보류 중"
        }
        return switch phase {
        case .off: "잠자기 모드 · 박수 또는 화면 탭을 기다리는 중"
        case .holding: "현재 상태 · 조명 켜짐 · 탭하면 자연스럽게 어두워짐"
        case .fading: "현재 상태 · 화면 조명이 서서히 어두워지는 중"
        }
    }
}

enum FlipClockSecondStyle {
    static func opacity(isDimmed: Bool) -> Double {
        isDimmed ? 0.16 : 0.40
    }
}

private struct FlipClockFace: View {
    let date: Date
    let isPortrait: Bool
    let isDimmed: Bool
    let clockScale: Double
    let clockFont: ClockFontChoice
    var hourMode: ClockHourMode = .twentyFour

    var body: some View {
        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let rawHour = components.hour ?? 0
        let displayHour = hourMode == .twelve ? (rawHour % 12 == 0 ? 12 : rawHour % 12) : rawHour
        HStack(spacing: isPortrait ? 8 : 12) {
                FlipClockCard(
                    value: String(format: "%02d", displayHour),
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    clockFont: clockFont
                )
                Text(":")
                    .font(clockFont.font(size: isPortrait ? 48 : 62))
                    .opacity(isDimmed ? 0.42 : 0.72)
                    .offset(y: clockFont.clockVerticalOffset(size: isPortrait ? 48 : 62))
                ZStack(alignment: .bottomTrailing) {
                    FlipClockCard(
                        value: String(format: "%02d", components.minute ?? 0),
                        isPortrait: isPortrait,
                        isDimmed: isDimmed,
                        clockFont: clockFont
                    )

                    Text(String(format: "%02d", components.second ?? 0))
                        .font(clockFont.font(size: isPortrait ? 13 : 16))
                        .monospacedDigit()
                        .foregroundStyle(
                            .white.opacity(FlipClockSecondStyle.opacity(isDimmed: isDimmed))
                        )
                        .contentTransition(.numericText())
                        .frame(width: isPortrait ? 24 : 30)
                        .padding(.trailing, isPortrait ? 20 : 26)
                        .padding(.bottom, isPortrait ? 7 : 9)
                }
        }
        .scaleEffect(clockScale)
        .frame(height: (isPortrait ? 92 : 116) * clockScale)
        .animation(.snappy(duration: 0.42), value: components.minute)
        .animation(.easeInOut(duration: 0.18), value: components.second)
    }
}

private struct FlipClockCard: View {
    let value: String
    let isPortrait: Bool
    let isDimmed: Bool
    let clockFont: ClockFontChoice

    var body: some View {
        ZStack {
            FlipPanelSurface(
                isDimmed: isDimmed,
                cornerRadius: isPortrait ? 18 : 22
            )

            Text(value)
                .font(clockFont.font(size: isPortrait ? 64 : 82))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.42), value: value)
                .offset(y: clockFont.clockVerticalOffset(size: isPortrait ? 64 : 82))
                .mask(FlipTextSplitMask(gap: isPortrait ? 4 : 3))
        }
        .frame(
            width: isPortrait ? 126 : 164,
            height: isPortrait ? 92 : 116
        )
    }
}

struct FlipTextSplitMask: View {
    let gap: CGFloat

    var body: some View {
        VStack(spacing: gap) {
            Rectangle()
            Rectangle()
        }
    }
}

private struct FlipPanelSurface: View {
    let isDimmed: Bool
    let cornerRadius: CGFloat
    var splitGap: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(isDimmed ? 0.014 : 0.095),
                        .white.opacity(isDimmed ? 0.008 : 0.052)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .mask {
                VStack(spacing: splitGap) {
                    Rectangle()
                    Rectangle()
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.white.opacity(isDimmed ? 0.018 : 0.08), lineWidth: 1)
            }
    }
}

private struct AudioStatusPill: View {
    @ObservedObject var audio: AudioCaptureService
    let compact: Bool
    let monitoringSuspended: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)

            Group {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(statusColor.opacity(0.9))
                                .frame(width: max(3, proxy.size.width * audio.normalizedLevel))
                        }
                }
                .frame(width: compact ? 32 : 44, height: 5)
            }

            Text(statusText)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.07), in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(statusText), 감지 레벨 \(Int((audio.normalizedLevel * 100).rounded()))퍼센트")
    }

    private var statusColor: Color {
        if monitoringSuspended { return .white.opacity(0.42) }
        if audio.isWritingClip { return .red }
        if audio.state == .monitoring { return .green }
        return .orange
    }

    private var statusText: String {
        if monitoringSuspended {
            return compact ? "스탠드" : "감시 멈춤"
        }
        if audio.microphoneAccess == .denied {
            return compact ? "감지 안 됨" : "소리 감지 안 됨"
        }
        if audio.isWritingClip { return compact ? "저장" : "저장 중" }
        switch audio.state {
        case .monitoring: return compact ? "감지" : "감지 중"
        case .starting: return compact ? "준비" : "준비 중"
        case .failed: return compact ? "감지 안 됨" : "소리 감지 안 됨"
        case .stopped: return "정지됨"
        }
    }
}

private struct BatteryStatusPill: View {
    let status: DeviceBatteryStatus

    var body: some View {
        Label(levelText, systemImage: systemImage)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(status.shouldProtectBattery ? Color.orange : Color.white.opacity(0.72))
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(.white.opacity(0.07), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(accessibilityText)
    }

    private var levelText: String {
        guard let level = status.level else { return "--%" }
        return "\(Int((level * 100).rounded()))%"
    }

    private var systemImage: String {
        if status.isCharging { return "battery.100percent.bolt" }
        guard let level = status.level else { return "battery.0percent" }
        return switch level {
        case ...0.2: "battery.25percent"
        case ...0.5: "battery.50percent"
        case ...0.75: "battery.75percent"
        default: "battery.100percent"
        }
    }

    private var accessibilityText: String {
        status.isCharging ? "배터리 \(levelText), 충전 중" : "배터리 \(levelText)"
    }
}

private struct ControlButton: View {
    let title: String
    let systemImage: String
    var status: String? = nil
    var hint: String? = nil
    let width: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 20, height: 16)

                Text(title)
                    .font(.system(size: StandControlLayoutMetrics.titleFontSize, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                if let status {
                    Text(status)
                        .font(.system(size: StandControlLayoutMetrics.statusFontSize, weight: .medium))
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
            .foregroundStyle(.white.opacity(StandControlLayoutMetrics.foregroundOpacity))
            .padding(.horizontal, 4)
            .frame(
                width: width,
                height: StandControlLayoutMetrics.itemHeight
            )
            .background {
                FlipPanelSurface(isDimmed: false, cornerRadius: 13, splitGap: 2)
            }
            .opacity(StandControlLayoutMetrics.tileOpacity)
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint ?? "")
    }
}
