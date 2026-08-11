import SwiftUI
import UIKit

struct STandBrandIcon: View {
    let size: CGFloat

    var body: some View {
        Image("STandBrandIcon")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 0.7)
            }
            .accessibilityHidden(true)
    }
}

enum DatePanelMetrics {
    static func width(isPortrait: Bool) -> CGFloat {
        isPortrait ? 200 : 240
    }
}

private struct StandDatePanel: View {
    let date: Date
    let isPortrait: Bool

    var body: some View {
        Text(date, format: .dateTime.month().day().weekday(.wide))
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: DatePanelMetrics.width(isPortrait: isPortrait))
    }
}

struct HoldDurationAdjustment {
    static func value(startingAt startingValue: Double, translation: CGFloat) -> Double {
        let rawValue = startingValue + Double(translation / 300) * 295
        let steppedValue = (rawValue / 5).rounded() * 5
        return min(300, max(5, steppedValue))
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
    case internetRadio
    case internetRadioChannels
    case settings

    var id: String { rawValue }
}

private struct BrightnessDragState {
    let startingValue: Double
}

enum HomeEditorResetPolicy {
    static func panels(in layout: StandScreenLayout, isPortrait: Bool) -> StandScreenLayout {
        var reset = isPortrait ? StandScreenLayout.portrait : .landscape
        reset.controlOrder = layout.controlOrder
        return reset
    }

}

enum StandControlLayoutMetrics {
    static let itemHeight: CGFloat = 60
    static let hiddenControlLabelHeight: CGFloat = 40
    static let hiddenControlRevealHeight = hiddenControlLabelHeight * 2
    static let rowSpacing: CGFloat = 6
    static let editorToolbarHeight: CGFloat = 46
    static let tileOpacity = 1.0
    static let foregroundOpacity = 0.78
    static let titleFontSize: CGFloat = 10.5
    static let statusFontSize: CGFloat = 8.5
    static let versionFooterHeight: CGFloat = 12

    static func bottomPadding(isPortrait: Bool) -> CGFloat {
        (isPortrait ? 18 : 6) + versionFooterHeight
    }
}

enum BottomControlLayoutPolicy {
    static func columnCount(availableWidth: CGFloat, isPortrait: Bool) -> Int {
        isPortrait && availableWidth < 700 ? 4 : 8
    }

    static func columnWidth(availableWidth: CGFloat, isPortrait: Bool) -> CGFloat {
        let count = CGFloat(
            columnCount(availableWidth: availableWidth, isPortrait: isPortrait)
        )
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
    @ObservedObject private var radio: InternetRadioPlayer
    @ObservedObject private var library: RecordingLibrary
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var weather: WeatherService
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentedSheet: PresentedSheet?
    @State private var didInitialize = false
    @State private var brightnessDragState: BrightnessDragState?
    @State private var clockScaleGestureStart: Double?
    @State private var clockScaleFeedback: Double?
    @State private var clockScaleFeedbackTask: Task<Void, Never>?
    @State private var isEditingScreen = false
    @State private var editingLayout = StandScreenLayout.portrait
    @State private var editingIsPortrait = true
    @State private var currentIsPortrait = true
    @State private var currentCanvasSize = CGSize.zero
    @State private var currentProtectedInsets = EdgeInsets()
    @State private var radioEditorChannelID: UUID?

    init(model: StandViewModel) {
        _model = ObservedObject(wrappedValue: model)
        _audio = ObservedObject(wrappedValue: model.audio)
        _radio = ObservedObject(wrappedValue: model.radio)
        _library = ObservedObject(wrappedValue: model.library)
        _settings = ObservedObject(wrappedValue: model.settings)
        _weather = ObservedObject(wrappedValue: model.weather)
    }

    var body: some View {
        GeometryReader { proxy in
            let isPortrait = proxy.size.height > proxy.size.width

            ZStack {
                LampBackground(
                    intensity: model.lampIntensity,
                    theme: settings.value.displayTheme
                )

                if !isEditingScreen {
                    if model.isDisplayDark, didInitialize {
                        silhouetteInfo(isPortrait: isPortrait, canvasSize: proxy.size)
                            .transition(.opacity)
                    }

                    VStack(spacing: 0) {
                        topBar(isPortrait: isPortrait)
                            .padding(.horizontal, isPortrait ? 20 : 32)
                        statusBanners
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
                    .zIndex(5)

                    centerContent(isPortrait: isPortrait, canvasSize: proxy.size)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, isPortrait ? 20 : 32)
                        .opacity(model.isDisplayDark || !didInitialize ? 0 : 1)

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        HStack(spacing: 7) {
                            Text(AppVersion.build)
                            Text("·")
                            Text("밝기 \(Int((model.displayBrightness * 100).rounded()))%")
                                .monospacedDigit()
                        }
                            .font(.system(
                                size: StandControlLayoutMetrics.statusFontSize,
                                weight: .medium,
                                design: .monospaced
                            ))
                            .foregroundStyle(.white.opacity(0.28))
                            .frame(height: StandControlLayoutMetrics.versionFooterHeight)
                    }
                    .allowsHitTesting(false)
                    .accessibilityLabel(
                        "빌드 번호 \(AppVersion.build), 현재 밝기 \(Int((model.displayBrightness * 100).rounded()))퍼센트"
                    )
                    .opacity(model.isDisplayDark || !didInitialize ? 0 : 1)
                    .zIndex(6)

                    if brightnessDragState != nil {
                        AppBrightnessHUD(level: model.displayBrightness)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .zIndex(90)
                    }

                    if let clockScaleFeedback {
                        ClockScaleFeedbackView(scale: clockScaleFeedback)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }

                }

                if isEditingScreen {
                    ScreenEditorView(
                        layout: $editingLayout,
                        isPortrait: editingIsPortrait,
                        weather: weather,
                        radioConfigurations: settings.value.homeInternetRadios,
                        availableRadioCount: settings.value.internetRadioChannels.count,
                        clockFont: Binding(
                            get: { settings.value.clockFont },
                            set: { settings.value.clockFont = $0 }
                        ),
                        hourMode: .twelve,
                        batteryText: silhouetteBatteryText,
                        onConfigureRadio: { channelID in
                            radioEditorChannelID = channelID
                            presentedSheet = .internetRadio
                        },
                        onManageRadios: {
                            presentedSheet = .internetRadioChannels
                        },
                        onReset: {
                            editingLayout = HomeEditorResetPolicy.panels(
                                in: editingLayout,
                                isPortrait: editingIsPortrait
                            )
                        },
                        onSave: saveScreenLayout
                    )
                    .transition(.opacity)
                    .zIndex(20)
                }

                if model.isFaceDown {
                    Color.black
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(100)
                }

            }
            .grayscale(settings.value.displayTheme == .grayscale ? 1 : 0)
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
        .animation(.easeInOut(duration: 0.28), value: settings.value.displayTheme)
        .contentShape(Rectangle())
        .gesture(screenAdjustmentGesture.exclusively(before: screenPressGesture))
        .simultaneousGesture(clockMagnificationGesture)
        .persistentSystemOverlays(.hidden)
        .sheet(item: $presentedSheet, onDismiss: {
            model.resumeMonitoringAfterPlayback()
        }) { sheet in
            switch sheet {
            case .recordings:
                RecordingsView(
                    library: library,
                    playbackDisabled: false,
                    theme: settings.value.displayTheme
                )
            case .internetRadio:
                InternetRadioConfigurationView(
                    configuration: model.sharedInternetRadioDraft
                        ?? radioConfigurationForEditor,
                    accent: settings.value.displayTheme.accentColor,
                    isSharedImport: model.sharedInternetRadioDraft != nil,
                    allowsDeletion: model.sharedInternetRadioDraft == nil
                        && radioConfigurationForEditor != nil,
                    onSave: { configuration in
                        if radioEditorChannelID != nil {
                            _ = model.updateInternetRadioChannel(configuration)
                        } else {
                            model.saveInternetRadioConfiguration(configuration)
                        }
                    },
                    onDelete: {
                        if let radioEditorChannelID {
                            _ = model.removeInternetRadioChannel(id: radioEditorChannelID)
                        } else {
                            model.removeInternetRadioConfiguration()
                        }
                    },
                    onCancel: model.discardSharedInternetRadioDraft
                )
                .id(internetRadioEditorIdentity)
            case .internetRadioChannels:
                InternetRadioChannelManagementView(model: model)
            case .settings:
                SettingsView(model: model)
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
        .onChange(of: model.sharedInternetRadioDraft) { _, draft in
            guard draft != nil else { return }
            presentedSheet = .internetRadio
        }
    }

    private func resetTransientInterface() {
        clockScaleFeedbackTask?.cancel()

        clockScaleFeedbackTask = nil

        brightnessDragState = nil
        clockScaleGestureStart = nil
        clockScaleFeedback = nil
    }

    private func topBar(isPortrait _: Bool) -> some View {
        let objectModeLocked = model.isNightSessionActive
            && settings.value.modePreference == .object
        let statusTitle = model.isNightSessionActive
            ? (objectModeLocked ? "오브제 모드 잠금" : model.experienceMode.title)
            : "자동 기능 꺼짐"
        let statusImage = model.isNightSessionActive
            ? (objectModeLocked ? "lock.fill" : model.experienceMode.systemImage)
            : "stop.circle.fill"

        return ZStack {
            HStack(spacing: 12) {
                Label(statusTitle, systemImage: statusImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 12)

                BatteryStatusPill(status: model.batteryStatus)
            }

            HStack(spacing: 8) {
                STandBrandIcon(size: 28)

                Text("S.tand")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .tracking(0.8)
            }
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity)
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

                Text("S.tand가 곁에 있을게요")
                    .font(.system(.title2, design: .rounded, weight: .semibold))

                Text("시작하면 오브제와 매이트 모드를 오가며 시간·날씨와 잠자리를 돌봅니다.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.58))

                Button {
                    model.startNightSession()
                } label: {
                    Label("S.tand 시작", systemImage: "lamp.table.fill")
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
            hourMode: .twelve,
            batteryText: silhouetteBatteryText,
            batterySystemImage: model.batteryStatus.isCharging
                ? "battery.100percent.bolt"
                : "battery.50percent",
            radioConfigurations: settings.value.homeInternetRadios,
            radioState: radio.state,
            activeRadioChannelID: radio.activeChannelID,
            onToggleRadio: model.toggleInternetRadioPlayback(channelID:),
            onEditRadio: { channelID in
                radioEditorChannelID = channelID
                presentedSheet = .internetRadio
            }
        )
    }

    private var internetRadioEditorIdentity: String {
        let configuration = model.sharedInternetRadioDraft ?? radioConfigurationForEditor
        let source = model.sharedInternetRadioDraft == nil ? "saved" : "shared"
        return "\(source)|\(configuration?.id.uuidString ?? "new")"
    }

    private var radioConfigurationForEditor: InternetRadioConfiguration? {
        guard let radioEditorChannelID else { return settings.value.internetRadio }
        return settings.value.internetRadioChannels.first { $0.id == radioEditorChannelID }
    }

    private func enterScreenEditing(isPortrait: Bool) {
        editingIsPortrait = isPortrait
        editingLayout = isPortrait ? settings.value.portraitLayout : settings.value.landscapeLayout
        model.revealControls()
        withAnimation(.easeOut(duration: 0.25)) { isEditingScreen = true }
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
                guard !isEditingScreen, presentedSheet == nil else { return }
                guard abs(value.translation.height) > abs(value.translation.width) else { return }

                let state: BrightnessDragState
                if let brightnessDragState {
                    state = brightnessDragState
                } else {
                    state = BrightnessDragState(startingValue: model.displayBrightness)
                    brightnessDragState = state
                    model.beginBrightnessAdjustment()
                }

                let adjustedValue = SimplifiedBrightnessModePolicy.level(
                    startingAt: state.startingValue,
                    verticalTranslation: value.translation.height,
                    viewportHeight: currentCanvasSize.height
                )
                model.updateBrightnessLevel(adjustedValue)
            }
            .onEnded { _ in
                guard !isEditingScreen else { return }
                if brightnessDragState != nil {
                    model.endBrightnessAdjustment()
                    brightnessDragState = nil
                }
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
                    guard !isEditingScreen, presentedSheet == nil else { return }
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
        guard !isEditingScreen, model.isNightSessionActive else { return }
        model.toggleObjectMateMode()
        model.revealControls()
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

                let scale = min(1.35, max(0.7, startingScale * Double(magnification)))
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

    @ViewBuilder
    private func bottomControls(isPortrait: Bool, availableWidth: CGFloat) -> some View {
        if model.isNightSessionActive, !model.controlsVisible {
            Button {
                model.revealControls()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                tapToControlText
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .frame(height: StandControlLayoutMetrics.hiddenControlRevealHeight)
            .contentShape(Rectangle())
            .accessibilityLabel("하단 기능 버튼 열기")
            .accessibilityHint("두 번 누르면 플래시, 밝기 기준, 녹음 및 설정 버튼이 나타납니다")
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
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.3), value: model.controlsVisible)
        }
    }

    private func visibleControlOrder(isPortrait: Bool) -> [StandControlKind] {
        let order = isPortrait
            ? settings.value.portraitLayout.controlOrder
            : settings.value.landscapeLayout.controlOrder
        let simplifiedOrder = order.filter { ![.flashlight, .brightness].contains($0) }
        return simplifiedOrder
    }

    @ViewBuilder
    private func bottomControl(for kind: StandControlKind, width: CGFloat) -> some View {
        switch kind {
        case .flashlight:
            ControlButton(
                title: "플래시 연동",
                systemImage: settings.value.torchEnabled ? "flashlight.on.fill" : "flashlight.off.fill",
                status: settings.value.torchEnabled ? "터치·뒤척임 100%" : "터치 0% · 뒤척임 10%",
                hint: "연동하면 터치와 뒤척임 모두 100퍼센트, 해제하면 터치는 끄고 뒤척임만 10퍼센트로 켭니다",
                width: width
            ) {
                settings.value.torchEnabled.toggle()
                if settings.value.torchEnabled { model.activateLamp() }
            }
        case .brightness:
            CompactBrightnessRuleControl(
                currentBrightness: model.displayBrightness,
                currentMode: model.environmentDisplayMode,
                width: width,
                threshold: Binding(
                    get: { settings.value.brightnessModeThreshold },
                    set: { settings.value.brightnessModeThreshold = $0 }
                ),
                modePreference: Binding(
                    get: { settings.value.modePreference },
                    set: { model.setModePreference($0) }
                )
            )
        case .stopDetection:
            EmptyView()
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
        VStack(spacing: 6) {
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
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .allowsHitTesting(false)
    }

    private var batteryProtectionBanner: some View {
        Label(
            model.batteryStatus.isCharging
                ? "충전이 연결되었습니다. S.tand 시작을 눌러 다시 시작하세요."
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
    let theme: StandDisplayTheme

    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: gradientColors,
                center: .center,
                startRadius: 20,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
        .animation(.linear(duration: 0.08), value: intensity)
        .animation(.easeInOut(duration: 0.28), value: theme)
    }

    private var gradientColors: [Color] {
        switch theme {
        case .color:
            [
                Color(red: 1.0, green: 0.62, blue: 0.28).opacity(intensity),
                Color(red: 0.95, green: 0.27, blue: 0.06).opacity(intensity * 0.72),
                Color.black.opacity(1 - intensity * 0.22)
            ]
        case .grayscale:
            [
                Color(white: 0.72).opacity(intensity * 0.72),
                Color(white: 0.30).opacity(intensity * 0.64),
                Color.black.opacity(1 - intensity * 0.18)
            ]
        case .midnight:
            [
                Color(red: 0.28, green: 0.58, blue: 1.0).opacity(intensity * 0.86),
                Color(red: 0.08, green: 0.20, blue: 0.58).opacity(intensity * 0.78),
                Color(red: 0.01, green: 0.02, blue: 0.09).opacity(1 - intensity * 0.18)
            ]
        case .sage:
            [
                Color(red: 0.60, green: 0.82, blue: 0.64).opacity(intensity * 0.80),
                Color(red: 0.20, green: 0.43, blue: 0.30).opacity(intensity * 0.72),
                Color(red: 0.025, green: 0.075, blue: 0.055).opacity(1 - intensity * 0.18)
            ]
        }
    }
}

private struct AppBrightnessHUD: View {
    let level: Double

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 16, weight: .semibold))

            Text("앱 밝기")
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            Text("\(percent)%")
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 15)
        .frame(height: 46)
        .background(.black.opacity(0.48), in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.14), lineWidth: 1)
        }
    }

    private var percent: Int {
        Int((min(1, max(0, level)) * 100).rounded())
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
    let batteryText: String
    let batterySystemImage: String
    let radioConfigurations: [InternetRadioConfiguration]
    let radioState: InternetRadioPlaybackState
    let activeRadioChannelID: UUID?
    let onToggleRadio: (UUID) -> Void
    let onEditRadio: (UUID) -> Void

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

                ClockSecondsPanel(
                    date: context.date,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    clockFont: clockFont,
                    showsBackground: !ClockSecondsPlacement.isOverlappingClock(
                        layout: layout,
                        canvasSize: canvasSize,
                        isPortrait: isPortrait
                    )
                )
                .panelTransform(layout.seconds, canvasSize: canvasSize)

                StandDatePanel(date: context.date, isPortrait: isPortrait)
                    .panelTransform(layout.date, canvasSize: canvasSize)

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

                radioPanels
            }
            .scaleEffect(clockScale, anchor: .center)
            .foregroundStyle(
                .white.opacity(isDimmed ? dimmedIntensity : max(0.12, min(0.88, 0.22 + intensity)))
            )
            .offset(drift)
            .animation(.easeInOut(duration: 4), value: drift)
        }
    }

    @ViewBuilder
    private var radioPanels: some View {
        if radioConfigurations.count == 2, layout.radiosGrouped {
            InternetRadioGroupedPanel(
                configurations: radioConfigurations,
                state: radioState,
                activeChannelID: activeRadioChannelID,
                isDimmed: isDimmed,
                dimmedIntensity: dimmedIntensity,
                showsEditBadge: false,
                actions: onToggleRadio,
                editActions: onEditRadio
            )
            .panelTransform(layout.radio, canvasSize: canvasSize)
        } else {
            ForEach(Array(radioConfigurations.enumerated()), id: \.element.id) { index, configuration in
                let transform = index == 0 ? layout.radio : layout.secondaryRadio
                InternetRadioPanel(
                    configuration: configuration,
                    state: activeRadioChannelID == configuration.id ? radioState : .idle,
                    isDimmed: isDimmed,
                    dimmedIntensity: dimmedIntensity,
                    showsEditBadge: false,
                    renderedScale: transform.scale * clockScale,
                    action: { onToggleRadio(configuration.id) },
                    editAction: { onEditRadio(configuration.id) }
                )
                .panelTransform(transform, canvasSize: canvasSize)
            }
        }
    }
}

enum InternetRadioPanelMetrics {
    static let width: CGFloat = 144
    static let height: CGFloat = 60
    static let cornerRadius: CGFloat = 13
    static let minimumHitTarget: CGFloat = 44

    static func interactionSize(renderedScale: Double) -> CGSize {
        let scale = max(0.01, CGFloat(renderedScale))
        return CGSize(
            width: max(width, minimumHitTarget / scale),
            height: max(height, minimumHitTarget / scale)
        )
    }
}

private struct InternetRadioPanel: View {
    let configuration: InternetRadioConfiguration?
    let state: InternetRadioPlaybackState
    let isDimmed: Bool
    let dimmedIntensity: Double
    let showsEditBadge: Bool
    let renderedScale: Double
    let action: () -> Void
    let editAction: () -> Void
    let drawsSurface: Bool
    let allowsInteraction: Bool

    init(
        configuration: InternetRadioConfiguration?,
        state: InternetRadioPlaybackState,
        isDimmed: Bool,
        dimmedIntensity: Double,
        showsEditBadge: Bool,
        renderedScale: Double,
        action: @escaping () -> Void,
        editAction: @escaping () -> Void,
        drawsSurface: Bool = true,
        allowsInteraction: Bool = true
    ) {
        self.configuration = configuration
        self.state = state
        self.isDimmed = isDimmed
        self.dimmedIntensity = dimmedIntensity
        self.showsEditBadge = showsEditBadge
        self.renderedScale = renderedScale
        self.action = action
        self.editAction = editAction
        self.drawsSurface = drawsSurface
        self.allowsInteraction = allowsInteraction
    }

    var body: some View {
        Group {
            if showsEditBadge || !allowsInteraction {
                panelContent
            } else {
                panelContent
                    .highPriorityGesture(
                        LongPressGesture(minimumDuration: 0.8, maximumDistance: 12)
                            .exclusively(before: TapGesture())
                            .onEnded { result in
                                switch result {
                                case .first(true):
                                    editAction()
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                case .second:
                                    action()
                                default:
                                    break
                                }
                            }
                    )
            }
        }
        .foregroundStyle(.white.opacity(isDimmed ? 0.46 : 0.78))
        .opacity(isDimmed ? min(1, max(0, dimmedIntensity)) : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAction {
            if showsEditBadge {
                editAction()
            } else {
                action()
            }
        }
        .accessibilityAction(named: Text("채널 편집"), editAction)
    }

    private var panelContent: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(configuration?.displayName ?? "인터넷 라디오")
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(statusText)
                    .font(.system(size: 8.5, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(isDimmed ? 0.40 : 0.52))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .frame(
            width: InternetRadioPanelMetrics.width,
            height: InternetRadioPanelMetrics.height
        )
        .background {
            if drawsSurface {
                FlipPanelSurface(
                    isDimmed: isDimmed,
                    cornerRadius: InternetRadioPanelMetrics.cornerRadius,
                    splitGap: 2
                )
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsEditBadge {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.black.opacity(0.72), .orange)
                    .offset(x: 6, y: -6)
                }
        }
        .frame(
            width: showsEditBadge
                ? InternetRadioPanelMetrics.width
                : InternetRadioPanelMetrics.interactionSize(
                    renderedScale: renderedScale
                ).width,
            height: showsEditBadge
                ? InternetRadioPanelMetrics.height
                : InternetRadioPanelMetrics.interactionSize(
                    renderedScale: renderedScale
                ).height
        )
        .contentShape(Rectangle())
    }

    private var systemImage: String {
        guard configuration != nil else { return "radio.fill" }
        return switch state {
        case .loading: "antenna.radiowaves.left.and.right"
        case .reconnecting: "arrow.clockwise.circle.fill"
        case .playing: "stop.circle.fill"
        case .idle, .failed: "radio.fill"
        }
    }

    private var statusText: String {
        guard configuration != nil else { return "HTTPS 주소 등록" }
        if showsEditBadge { return "채널 편집" }
        return switch state {
        case .idle: "대기 중"
        case .loading: "연결 중"
        case .playing: "재생 중"
        case .reconnecting: "자동 재연결 중"
        case .failed: "연결 실패"
        }
    }

    private var accessibilityLabel: String {
        let name = configuration?.displayName ?? "인터넷 라디오"
        return "\(name), \(statusText)"
    }

    private var accessibilityHint: String {
        guard !showsEditBadge else {
            return configuration == nil
                ? "라디오 채널을 등록합니다"
                : "라디오 채널을 편집합니다"
        }
        return switch state {
        case .idle, .failed: "등록한 인터넷 라디오를 재생합니다"
        case .loading, .reconnecting: "인터넷 라디오 연결을 취소합니다"
        case .playing: "인터넷 라디오를 끄고 소리 감지와 녹음을 다시 시작합니다"
        }
    }
}

private struct InternetRadioGroupedPanel: View {
    let configurations: [InternetRadioConfiguration]
    let state: InternetRadioPlaybackState
    let activeChannelID: UUID?
    let isDimmed: Bool
    let dimmedIntensity: Double
    let showsEditBadge: Bool
    let actions: (UUID) -> Void
    let editActions: (UUID) -> Void
    let allowsChildInteraction: Bool

    init(
        configurations: [InternetRadioConfiguration],
        state: InternetRadioPlaybackState,
        activeChannelID: UUID?,
        isDimmed: Bool,
        dimmedIntensity: Double,
        showsEditBadge: Bool,
        actions: @escaping (UUID) -> Void,
        editActions: @escaping (UUID) -> Void = { _ in },
        allowsChildInteraction: Bool = true
    ) {
        self.configurations = configurations
        self.state = state
        self.activeChannelID = activeChannelID
        self.isDimmed = isDimmed
        self.dimmedIntensity = dimmedIntensity
        self.showsEditBadge = showsEditBadge
        self.actions = actions
        self.editActions = editActions
        self.allowsChildInteraction = allowsChildInteraction
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(configurations.prefix(2)) { configuration in
                InternetRadioPanel(
                    configuration: configuration,
                    state: activeChannelID == configuration.id ? state : .idle,
                    isDimmed: isDimmed,
                    dimmedIntensity: dimmedIntensity,
                    showsEditBadge: false,
                    renderedScale: 1,
                    action: { actions(configuration.id) },
                    editAction: { editActions(configuration.id) },
                    drawsSurface: false,
                    allowsInteraction: allowsChildInteraction
                )
            }
        }
        .background(
            FlipPanelSurface(
                isDimmed: isDimmed,
                cornerRadius: InternetRadioPanelMetrics.cornerRadius,
                splitGap: 2
            )
        )
        .overlay {
            Rectangle()
                .fill(.white.opacity(isDimmed ? 0.025 : 0.08))
                .frame(width: 1)
        }
        .overlay(alignment: .topTrailing) {
            if showsEditBadge {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.black.opacity(0.72), .orange)
                    .offset(x: 6, y: -6)
            }
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
    let currentMode: EnvironmentDisplayMode
    let width: CGFloat
    @Binding var threshold: Double
    @Binding var modePreference: StandModePreference
    @State private var trackFrame = CGRect.zero
    @State private var interactionPhase: BrightnessRuleGesturePhase = .undecided

    private let coordinateSpaceName = "compactBrightnessRule"

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Label("매이트", systemImage: "moon.fill")
                    .foregroundStyle(threshold < currentBrightness ? Color.orange : Color.white.opacity(0.42))
                Spacer()
                Label("오브제", systemImage: "sun.max.fill")
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

            Text("\(preferenceText) · 현재 \(Int((currentBrightness * 100).rounded())) · 기준 \(Int((threshold * 100).rounded()))")
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
        .accessibilityLabel("모드와 밝기 기준, \(preferenceText), 현재 \(Int(currentBrightness * 100))퍼센트, 기준 \(Int(threshold * 100))퍼센트")
        .accessibilityHint("레일을 좌우로 밀면 자동 기준을 조절하고, 타일을 탭하면 매이트와 오브제 모드를 강제로 전환합니다")
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
        if modePreference != .automatic { modePreference = .automatic }
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
            modePreference = currentMode == .stand ? .mate : .object
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private var preferenceText: String {
        switch modePreference {
        case .automatic: "자동"
        case .object: "오브제 고정"
        case .mate: "매이트 고정"
        }
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
    let radioConfigurations: [InternetRadioConfiguration]
    let availableRadioCount: Int
    @Binding var clockFont: ClockFontChoice
    let hourMode: ClockHourMode
    let batteryText: String
    let onConfigureRadio: (UUID?) -> Void
    let onManageRadios: () -> Void
    let onReset: () -> Void
    let onSave: () -> Void
    @State private var showFontPalette = false

    var body: some View {
        GeometryReader { proxy in
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
                        .onTapGesture { showFontPalette.toggle() }
                    }
                }

                EditablePanel(
                    transform: $layout.seconds,
                    canvasSize: proxy.size
                ) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ClockSecondsPanel(
                            date: context.date,
                            isPortrait: isPortrait,
                            isDimmed: false,
                            clockFont: clockFont,
                            showsBackground: !ClockSecondsPlacement.isOverlappingClock(
                                layout: layout,
                                canvasSize: proxy.size,
                                isPortrait: isPortrait
                            )
                        )
                    }
                }

                editableWeatherPanels(
                    canvasSize: proxy.size
                )

                EditablePanel(
                    transform: $layout.date,
                    canvasSize: proxy.size
                ) {
                    StandDatePanel(date: .now, isPortrait: isPortrait)
                        .padding(.horizontal, 12).padding(.vertical, 8)
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

                editableRadioPanels(canvasSize: proxy.size)

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
                        Label(
                            "패널 이동·크기 조절 · 라디오 연필을 눌러 주소 편집",
                            systemImage: "hand.draw.fill"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(.bottom, isPortrait ? 24 : 12)
                    .allowsHitTesting(false)
                    .zIndex(3)
                }

                VStack {
                    HStack {
                        Button("초기화", action: onReset)
                        Spacer()
                        Text(isPortrait ? "세로 패널 편집" : "가로 패널 편집")
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
    private func editableRadioPanels(canvasSize: CGSize) -> some View {
        if radioConfigurations.count == 2, layout.radiosGrouped {
            EditablePanel(
                transform: $layout.radio,
                canvasSize: canvasSize
            ) {
                InternetRadioGroupedPanel(
                    configurations: radioConfigurations,
                    state: .idle,
                    activeChannelID: nil,
                    isDimmed: false,
                    dimmedIntensity: 1,
                    showsEditBadge: true,
                    actions: { _ in },
                    allowsChildInteraction: false
                )
                .onTapGesture(count: 2, perform: splitRadioPanels)
            }
        } else {
            ForEach(Array(radioConfigurations.enumerated()), id: \.element.id) { index, configuration in
                EditablePanel(
                    transform: index == 0 ? $layout.radio : $layout.secondaryRadio,
                    canvasSize: canvasSize,
                    onEnded: { mergeRadioPanelsIfNeeded(canvasSize: canvasSize) },
                    onTap: { onConfigureRadio(configuration.id) }
                ) {
                    InternetRadioPanel(
                        configuration: configuration,
                        state: .idle,
                        isDimmed: false,
                        dimmedIntensity: 1,
                        showsEditBadge: true,
                        renderedScale: index == 0 ? layout.radio.scale : layout.secondaryRadio.scale,
                        action: {},
                        editAction: { onConfigureRadio(configuration.id) }
                    )
                }
            }

            if radioConfigurations.count == 1, availableRadioCount >= 2 {
                EditablePanel(
                    transform: $layout.secondaryRadio,
                    canvasSize: canvasSize,
                    onTap: onManageRadios
                ) {
                    Label("두 번째 라디오 추가", systemImage: "plus.circle.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(
                            width: InternetRadioPanelMetrics.width,
                            height: InternetRadioPanelMetrics.height
                        )
                        .background(
                            FlipPanelSurface(
                                isDimmed: false,
                                cornerRadius: InternetRadioPanelMetrics.cornerRadius,
                                splitGap: 2
                            )
                        )
                }
            }
        }
    }

    private func mergeRadioPanelsIfNeeded(canvasSize: CGSize) {
        guard radioConfigurations.count == 2, !layout.radiosGrouped else { return }
        let first = radioBounds(transform: layout.radio, canvasSize: canvasSize)
        let second = radioBounds(transform: layout.secondaryRadio, canvasSize: canvasSize)
        guard PanelEditingPolicy.overlapFraction(first, second)
            >= PanelEditingPolicy.radioMergeOverlapThreshold else { return }
        var merged = layout.radio
        merged.x = (layout.radio.x + layout.secondaryRadio.x) / 2
        merged.y = (layout.radio.y + layout.secondaryRadio.y) / 2
        merged.scale = min(layout.radio.scale, layout.secondaryRadio.scale)
        layout.radio = merged
        layout.secondaryRadio = merged
        layout.radiosGrouped = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func splitRadioPanels() {
        guard layout.radiosGrouped else { return }
        let center = layout.radio
        layout.radio = PanelTransform(x: center.x - 0.11, y: center.y, scale: center.scale)
        layout.secondaryRadio = PanelTransform(x: center.x + 0.11, y: center.y, scale: center.scale)
        layout.radiosGrouped = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func radioBounds(transform: PanelTransform, canvasSize: CGSize) -> CGRect {
        let size = CGSize(
            width: InternetRadioPanelMetrics.width * transform.scale,
            height: InternetRadioPanelMetrics.height * transform.scale
        )
        let center = CGPoint(
            x: canvasSize.width / 2 + transform.x * canvasSize.width,
            y: canvasSize.height / 2 + transform.y * canvasSize.height
        )
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
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

private struct InternetRadioConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var address: String
    @State private var validationMessage: String?
    @State private var showsBrowser = false

    let configuration: InternetRadioConfiguration?
    let accent: Color
    let isSharedImport: Bool
    let allowsDeletion: Bool
    let onSave: (InternetRadioConfiguration) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    init(
        configuration: InternetRadioConfiguration?,
        accent: Color = .orange,
        isSharedImport: Bool = false,
        allowsDeletion: Bool? = nil,
        onSave: @escaping (InternetRadioConfiguration) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) {
        self.configuration = configuration
        self.accent = accent
        self.isSharedImport = isSharedImport
        self.allowsDeletion = allowsDeletion ?? (configuration != nil)
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _displayName = State(initialValue: configuration?.displayName ?? "")
        _address = State(initialValue: configuration?.urlString ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("이름 (선택)", text: $displayName)
                        .textInputAutocapitalization(.never)
                    TextField("https://…", text: $address)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    PasteButton(payloadType: String.self) { values in
                        guard let pasted = values.first else { return }
                        address = pasted
                        validationMessage = nil
                    }
                    .accessibilityLabel("복사한 주소 붙여넣기")

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("라디오 정보")
                } footer: {
                    Text(radioInformationFooter)
                }

                Section {
                    Button {
                        showsBrowser = true
                    } label: {
                        Label("웹에서 주소 찾기", systemImage: "safari.fill")
                    }
                } footer: {
                    Text("브라우저는 주소를 자동으로 감지하거나 입력하지 않습니다. 이용 권한이 있는 주소를 직접 복사한 뒤 돌아와 붙여넣어 주세요.")
                }

                if isSharedImport {
                    Section {
                        Label(
                            "Safari에서 직접 공유한 주소를 입력했습니다.",
                            systemImage: "safari.fill"
                        )
                        Text("저장을 누르기 전까지 기존 채널 목록은 바뀌지 않습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("재생 중 동작") {
                    Label(
                        "소리 감지와 수면 녹음은 일시 중지됩니다.",
                        systemImage: "waveform.slash"
                    )
                    Label(
                        "기기 움직임 감지는 계속됩니다.",
                        systemImage: "gyroscope"
                    )
                }

                if allowsDeletion {
                    Section {
                        Button("채널 삭제", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("라디오 채널")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: save)
                        .fontWeight(.semibold)
                }
            }
            .fullScreenCover(isPresented: $showsBrowser) {
                InternetRadioBrowserView(accent: accent)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSharedImport)
    }

    private var radioInformationFooter: String {
        "직접 이용 권한을 확인한 합법적인 HTTPS 스트림 주소만 등록해 주세요. 주소는 이 기기에만 저장되며 방송을 저장하거나 중계하지 않습니다."
    }

    private func save() {
        do {
            let configuration = try InternetRadioConfiguration(
                id: configuration?.id ?? UUID(),
                displayName: displayName,
                urlString: address
            )
            validationMessage = nil
            onSave(configuration)
            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

struct PanelEditingRegion: Equatable {
    let frame: CGRect
    let insets: EdgeInsets
}

enum PanelEditingPolicy {
    static let weatherMergeOverlapThreshold: CGFloat = 0.40
    static let radioMergeOverlapThreshold: CGFloat = 0.40
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
        transform
    }

    static func maximumScreenScale(
        layout: StandScreenLayout,
        isPortrait: Bool,
        canvasSize: CGSize,
        insets: EdgeInsets,
        includesRadio: Bool = true,
        hardLimit: Double
    ) -> Double {
        hardLimit
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
    var onTap: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @State private var dragStart: PanelTransform?
    @State private var scaleStart: Double?
    @State private var cornerResizeStart: Double?
    @State private var panelSize = CGSize.zero
    @State private var snappedToVerticalGuide = false
    @State private var snappedToHorizontalGuide = false

    var body: some View {
        let renderedWidth = panelSize.width * transform.scale
        let renderedHeight = panelSize.height * transform.scale

        ZStack {
            Color.clear
                .frame(
                    width: max(44, renderedWidth),
                    height: max(44, renderedHeight)
                )
                .contentShape(Rectangle())

            content()
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: EditablePanelSizeKey.self,
                            value: proxy.size
                        )
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            .orange.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [4])
                        )
                }
                .scaleEffect(transform.scale)

            if let onTap {
                Color.clear
                    .frame(
                        width: max(44, renderedWidth),
                        height: max(44, renderedHeight)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
            }

            ZStack {
                Color.clear
                Circle()
                    .fill(.orange.opacity(0.9))
                    .frame(width: 26, height: 26)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black.opacity(0.72))
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .offset(x: -renderedWidth / 2, y: -renderedHeight / 2)
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
            .onPreferenceChange(EditablePanelSizeKey.self) { measuredSize in
                panelSize = measuredSize
            }
            .offset(
                x: transform.x * canvasSize.width,
                y: transform.y * canvasSize.height
            )
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
            return "밝기 고정 중"
        }
        if !automaticDimmingEnabled {
            return "화면 밝기 유지 중"
        }
        if automaticDimmingPaused {
            return "밝은 환경 · 화면 밝기 유지 중"
        }
        return switch phase {
        case .off: "매이트 모드 · 뒤척임 또는 화면 탭을 기다리는 중"
        case .holding: "오브제 모드"
        case .fading: "화들짝 모드 · 다시 매이트 모드로 돌아가는 중"
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
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
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
                FlipClockCard(
                    value: String(format: "%02d", components.minute ?? 0),
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    clockFont: clockFont
                )
        }
        .scaleEffect(clockScale)
        .frame(height: (isPortrait ? 92 : 116) * clockScale)
        .animation(.snappy(duration: 0.42), value: components.minute)
    }
}

enum ClockSecondsPlacement {
    static func isOverlappingClock(
        layout: StandScreenLayout,
        canvasSize: CGSize,
        isPortrait: Bool
    ) -> Bool {
        let clockWidth: CGFloat = isPortrait ? 288 : 374
        let clockHeight: CGFloat = isPortrait ? 92 : 116
        let clockCenter = CGPoint(
            x: canvasSize.width / 2 + CGFloat(layout.clock.x) * canvasSize.width,
            y: canvasSize.height / 2 + CGFloat(layout.clock.y) * canvasSize.height
        )
        let secondsCenter = CGPoint(
            x: canvasSize.width / 2 + CGFloat(layout.seconds.x) * canvasSize.width,
            y: canvasSize.height / 2 + CGFloat(layout.seconds.y) * canvasSize.height
        )
        let clockBounds = CGRect(
            x: clockCenter.x - clockWidth * CGFloat(layout.clock.scale) / 2,
            y: clockCenter.y - clockHeight * CGFloat(layout.clock.scale) / 2,
            width: clockWidth * CGFloat(layout.clock.scale),
            height: clockHeight * CGFloat(layout.clock.scale)
        )
        return clockBounds.insetBy(dx: -8, dy: -8).contains(secondsCenter)
    }
}

private struct ClockSecondsPanel: View {
    let date: Date
    let isPortrait: Bool
    let isDimmed: Bool
    let clockFont: ClockFontChoice
    let showsBackground: Bool

    var body: some View {
        Text(date, format: .dateTime.second(.twoDigits))
            .font(clockFont.font(size: showsBackground ? (isPortrait ? 18 : 22) : (isPortrait ? 13 : 16)))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(FlipClockSecondStyle.opacity(isDimmed: isDimmed)))
            .contentTransition(.numericText())
            .offset(y: clockFont.clockVerticalOffset(size: showsBackground ? (isPortrait ? 18 : 22) : (isPortrait ? 13 : 16)))
            .frame(width: isPortrait ? 48 : 58, height: isPortrait ? 36 : 42)
            .background {
                if showsBackground {
                    FlipPanelSurface(
                        isDimmed: isDimmed,
                        cornerRadius: isPortrait ? 11 : 13,
                        splitGap: isPortrait ? 2 : 2.5
                    )
                }
            }
            .animation(.easeInOut(duration: 0.18), value: date)
            .accessibilityLabel("초 (date.formatted(.dateTime.second(.twoDigits)))")
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
