import AudioToolbox
import MediaPlayer
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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

enum MusicChannelStripLayoutPolicy {
    static let spacing: CGFloat = 8
    static let sideInset: CGFloat = 12
    static let phoneLandscapeCardWidthScale: CGFloat = 0.8

    static func cardWidth(viewportWidth: CGFloat, isPhoneLandscape: Bool = false) -> CGFloat {
        let baseWidth = viewportWidth < 700 ? max(148, (viewportWidth - 46) / 2) : 168
        return isPhoneLandscape ? baseWidth * phoneLandscapeCardWidthScale : baseWidth
    }

    static func contentWidth(cardCount: Int, cardWidth: CGFloat) -> CGFloat {
        guard cardCount > 0 else { return 0 }
        return CGFloat(cardCount) * cardWidth + CGFloat(cardCount - 1) * spacing
    }

    static func maximumScroll(
        viewportWidth: CGFloat,
        cardCount: Int,
        cardWidth: CGFloat
    ) -> CGFloat {
        max(
            0,
            contentWidth(cardCount: cardCount, cardWidth: cardWidth)
                - max(0, viewportWidth - sideInset * 2)
        )
    }

    static func clampedOffset(_ offset: CGFloat, maximumScroll: CGFloat) -> CGFloat {
        min(0, max(-maximumScroll, offset))
    }

    static func leadingAlignedOffset(
        cardIndex: Int,
        cardWidth: CGFloat,
        maximumScroll: CGFloat
    ) -> CGFloat {
        clampedOffset(
            -CGFloat(max(0, cardIndex)) * (cardWidth + spacing),
            maximumScroll: maximumScroll
        )
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
    case boyiso

    var id: String { rawValue }
}

private struct UpdateAlertItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    var isTestFlightOpenAction: Bool = false

    static func == (lhs: UpdateAlertItem, rhs: UpdateAlertItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.message == rhs.message && lhs.isTestFlightOpenAction == rhs.isTestFlightOpenAction
    }
}

private enum ScreenAdjustmentDragState {
    case brightness(startingValue: Double)
    case volume(startingValue: Double)
    case ignored
}

@MainActor
private final class SystemVolumeController: ObservableObject {
    @Published private(set) var level: Double

    #if !targetEnvironment(macCatalyst)
    fileprivate let volumeView = MPVolumeView(frame: .zero)
    #endif

    init() {
        #if targetEnvironment(macCatalyst)
        // Catalyst는 iOS의 MPVolumeView로 Mac 시스템 볼륨을 안전하게 바꿀 수
        // 없으므로 가짜 시작값을 만들지 않고 전역 가로 볼륨 제스처를 사용하지 않는다.
        level = 0
        #else
        level = Double(AVAudioSession.sharedInstance().outputVolume)
        volumeView.showsRouteButton = false
        volumeView.showsVolumeSlider = true
        #endif
    }

    func refresh() {
        #if targetEnvironment(macCatalyst)
        return
        #else
        level = VolumeAdjustmentPolicy.clamped(
            Double(AVAudioSession.sharedInstance().outputVolume)
        )
        #endif
    }

    func update(_ requestedLevel: Double) {
        let adjustedLevel = VolumeAdjustmentPolicy.clamped(requestedLevel)
        #if targetEnvironment(macCatalyst)
        _ = adjustedLevel
        return
        #else
        level = adjustedLevel
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else {
            return
        }
        slider.setValue(Float(adjustedLevel), animated: false)
        slider.sendActions(for: .valueChanged)
        #endif
    }
}

#if targetEnvironment(macCatalyst)
private struct SystemVolumeBridge: UIViewRepresentable {
    let controller: SystemVolumeController

    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#else
private struct SystemVolumeBridge: UIViewRepresentable {
    let controller: SystemVolumeController

    func makeUIView(context: Context) -> MPVolumeView {
        controller.volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
#endif

private enum RootCoordinateSpace {
    static let name = "stand.root"
}

private struct MusicChannelStripFramePreferenceKey: PreferenceKey {
    static var defaultValue = CGRect(x: 0, y: 0, width: 100_000, height: 160)

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

enum HomeEditorResetPolicy {
    static func panels(in layout: StandScreenLayout, isPortrait: Bool) -> StandScreenLayout {
        let usesPhoneLandscapeLayout = PhoneLandscapeSideControlsPolicy.isEnabled(
            isPortrait: isPortrait
        )
        var reset = isPortrait
            ? StandScreenLayout.portrait
            : (usesPhoneLandscapeLayout ? .phoneLandscape : .landscape)
        reset.controlOrder = layout.controlOrder
        return reset
    }

}

/// 홈 화면 편집 모드 진입 계약. Android `StandPolicies`와 같은 기준을 공유한다.
/// 편집 모드는 정지 상태로 2.0초를 계속 누른 뒤에만 열리고, 허용 이동량을 넘는 움직임
/// (세로 밝기·가로 음량 조절 포함)은 그 제스처의 편집 진입을 영구히 취소한다.
enum HomeEditEntryPolicy {
    /// 편집 진입에 필요한 연속 정지 누름 시간(초). 2000ms.
    static let minimumPressDuration: TimeInterval = 2.0
    /// 기존 `LongPressGesture` 허용 이동량(pt). 이 값을 초과하면 편집 진입을 취소한다.
    static let maximumMovement: CGFloat = 12

    enum Event: Equatable {
        /// 누름 시작점 기준 누적 이동 거리.
        case moved(distance: CGFloat)
        /// 누름 시작 이후 누적 경과 시간(초).
        case held(seconds: TimeInterval)
        case ended
        case cancelled
        case additionalTouch
    }

    /// 한 번의 누름 제스처에 대한 편집 진입 대기 상태. 순수 값 타입이라 결정적으로 검증할 수 있다.
    struct PendingEntry: Equatable {
        private(set) var isCancelled = false
        private(set) var didEnter = false

        /// 이벤트를 적용하고, 이 이벤트로 편집 모드에 진입해야 하면 `true`를 돌려준다.
        @discardableResult
        mutating func apply(_ event: Event) -> Bool {
            guard !isCancelled, !didEnter else { return false }
            switch event {
            case .moved(let distance):
                if distance > HomeEditEntryPolicy.maximumMovement {
                    isCancelled = true
                }
                return false
            case .held(let seconds):
                guard seconds >= HomeEditEntryPolicy.minimumPressDuration else { return false }
                didEnter = true
                return true
            case .ended, .cancelled, .additionalTouch:
                isCancelled = true
                return false
            }
        }
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

/// 홈 음악 스트립 카드(라디오·외부 음악)의 iOS 확정 시안 지표.
/// 첫 줄은 아이콘+제목, 둘째 줄은 상태로 고정된 2행 구조를 유지한다.
enum HomeMusicStripCardMetrics {
    static let height = InternetRadioPanelMetrics.height
    static let cornerRadius = InternetRadioPanelMetrics.cornerRadius
    static let splitGap: CGFloat = 2
    static let iconSize: CGFloat = 24
    static let iconTitleGap: CGFloat = 8
    static let titleFontSize: CGFloat = 11
    static let titleLineHeight: CGFloat = 13
    static let statusFontSize: CGFloat = 8
    static let statusLineHeight: CGFloat = 10
    static let rowGap: CGFloat = 11
    static let contentLift: CGFloat = 2
    static let statusLift: CGFloat = 1
    static let horizontalPadding: CGFloat = 11
    static let verticalPadding: CGFloat = 5
}

/// 잠소리·보이소·설정 공용 카드의 iOS 확정 시안 지표.
/// 아이콘+제목(1행), 상태(2행)의 공통 해부 구조를 세 카드가 함께 쓴다.
enum HomeSharedControlMetrics {
    static let portraitSize = CGSize(width: 98, height: 66)
    static let phoneLandscapeSize = CGSize(width: 68, height: 60)
    static let spacing: CGFloat = 6
    static let cornerRadius: CGFloat = 13
    static let splitGap: CGFloat = 2
    static let iconSize: CGFloat = 17
    static let iconTitleGap: CGFloat = 4
    static let titleFontSize: CGFloat = 9
    static let titleLineHeight: CGFloat = 10.5
    static let statusFontSize: CGFloat = 7.5
    static let statusLineHeight: CGFloat = 9
    static let rowGap: CGFloat = 12
    static let padding: CGFloat = 5
    static let order: [StandControlKind] = [.recordings, .boyiso, .settings]

    static func size(isPhoneLandscape: Bool) -> CGSize {
        isPhoneLandscape ? phoneLandscapeSize : portraitSize
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

enum PhoneLandscapeSideControlsPolicy {
    static let baseControlWidth: CGFloat = 84
    static let controlWidthScale: CGFloat = 0.68
    static let controlWidth = baseControlWidth * controlWidthScale

    static func isEnabled(
        isPortrait: Bool,
        isPhoneIdiom: Bool,
        isMacCatalyst: Bool
    ) -> Bool {
        !isPortrait && isPhoneIdiom && !isMacCatalyst
    }

    static func isEnabled(isPortrait: Bool) -> Bool {
        #if targetEnvironment(macCatalyst)
        let isMacCatalyst = true
        #else
        let isMacCatalyst = false
        #endif
        return isEnabled(
            isPortrait: isPortrait,
            isPhoneIdiom: UIDevice.current.userInterfaceIdiom == .phone,
            isMacCatalyst: isMacCatalyst
        )
    }
}

enum StatusPanelMetrics {
    static let height: CGFloat = 36

    static func width(isPortrait: Bool) -> CGFloat {
        isPortrait ? 260 : 320
    }
}

enum StandPresentationMetrics {
    static let macHomeScale: CGFloat = 1.5

    static var homeScale: CGFloat {
        #if targetEnvironment(macCatalyst)
        macHomeScale
        #else
        1
        #endif
    }

    static func contentSize(for viewport: CGSize, scale: CGFloat) -> CGSize {
        guard scale > 0 else { return viewport }
        return CGSize(width: viewport.width / scale, height: viewport.height / scale)
    }
}

enum ExternalMusicTitleTapAction: Equatable {
    case play
    case next
}

enum ExternalMusicTitleTapPolicy {
    static func action(
        isActive: Bool,
        playbackState: ExternalMusicPlaybackState
    ) -> ExternalMusicTitleTapAction {
        isActive && playbackState == .playing ? .next : .play
    }
}

enum InternetRadioTitleTapPolicy {
    static func targetChannelID(
        tappedChannelID: UUID,
        activeChannelID: UUID?,
        playbackState: InternetRadioPlaybackState,
        orderedChannelIDs: [UUID]
    ) -> UUID? {
        guard !orderedChannelIDs.isEmpty else { return nil }
        guard playbackState == .playing else {
            return orderedChannelIDs.contains(tappedChannelID) ? tappedChannelID : nil
        }

        let currentChannelID = activeChannelID ?? tappedChannelID
        guard let currentIndex = orderedChannelIDs.firstIndex(of: currentChannelID) else {
            return orderedChannelIDs.first
        }
        return orderedChannelIDs[(currentIndex + 1) % orderedChannelIDs.count]
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
    @ObservedObject private var boyiso: BoyisoConnectivityService
    @ObservedObject private var firstLaunchPermissions: FirstLaunchPermissionCoordinator
    @StateObject private var systemVolume = SystemVolumeController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentedSheet: PresentedSheet?
    @State private var showsCatalystSettings = false
    @State private var showsCatalystRecordings = false
    @State private var showsCatalystBoyiso = false
    @State private var didInitialize = false
    @State private var screenAdjustmentDragState: ScreenAdjustmentDragState?
    // 현재 누름 제스처의 편집 진입 대기 상태. 밝기·음량 드래그가 시작되면 취소된다.
    @State private var homeEditEntry = HomeEditEntryPolicy.PendingEntry()
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
    @State private var hasStartedApp = false
    @State private var boyisoGreetingSender: String?
    @State private var boyisoCryingSender: String?
    @State private var boyisoWalkieSender: String?
    @State private var boyisoOverlayTask: Task<Void, Never>?
    @State private var boyisoBannerEvent: BoyisoEvent?
    @State private var boyisoBannerTask: Task<Void, Never>?
    @State private var musicChannelStripOffset: CGFloat = 0
    @State private var musicChannelStripDragStartOffset: CGFloat?
    @State private var musicChannelStripFrame = MusicChannelStripFramePreferenceKey.defaultValue
    // Mac Catalyst 전용 카드 순서 편집 모드. 다른 플랫폼에서는 항상 false로 유지되어 동작에 영향을 주지 않습니다.
    @State private var isMusicStripReorderingCatalyst = false
    @State private var musicStripDraggingChannelID: String?
    #if targetEnvironment(macCatalyst)
    @ObservedObject private var macUpdater = MacUpdaterController.shared
    @State private var isAwaitingMacUpdaterResult = false
    #endif
    @State private var updateAlert: UpdateAlertItem?
    @State private var mobileUpdateTask: Task<Void, Never>?
    @State private var isCheckingMobileUpdate = false

    init(
        model: StandViewModel,
        firstLaunchPermissions: FirstLaunchPermissionCoordinator
    ) {
        _model = ObservedObject(wrappedValue: model)
        _audio = ObservedObject(wrappedValue: model.audio)
        _radio = ObservedObject(wrappedValue: model.radio)
        _library = ObservedObject(wrappedValue: model.library)
        _settings = ObservedObject(wrappedValue: model.settings)
        _weather = ObservedObject(wrappedValue: model.weather)
        _boyiso = ObservedObject(wrappedValue: model.boyiso)
        _firstLaunchPermissions = ObservedObject(wrappedValue: firstLaunchPermissions)
        _isEditingScreen = State(initialValue: UICatalogLaunch.startsInEditor)
    }

    var body: some View {
        GeometryReader { proxy in
            let presentationScale = StandPresentationMetrics.homeScale
            let contentSize = StandPresentationMetrics.contentSize(
                for: proxy.size,
                scale: presentationScale
            )
            let isPortrait = contentSize.height > contentSize.width

            ZStack {
                SystemVolumeBridge(controller: systemVolume)
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                LampBackground(
                    intensity: model.lampIntensity,
                    theme: settings.value.displayTheme
                )

                if !isEditingScreen {
                    if model.isDisplayDark, didInitialize {
                        silhouetteInfo(isPortrait: isPortrait, canvasSize: contentSize)
                            .transition(.opacity)
                    }

                    let usesPhoneLandscapeSideControls = PhoneLandscapeSideControlsPolicy.isEnabled(
                        isPortrait: isPortrait
                    )

                    VStack(spacing: 0) {
                        topBar(isPortrait: isPortrait)
                            .padding(.horizontal, isPortrait ? 20 : 32)
                        if usesPhoneLandscapeSideControls {
                            HStack(spacing: StandControlLayoutMetrics.rowSpacing) {
                                musicChannelStrip(isPortrait: isPortrait)
                                    .frame(maxWidth: .infinity)
                                phoneLandscapeSideControls()
                            }
                            .padding(.trailing, 32)
                            .padding(.top, 8)
                        } else {
                            musicChannelStrip(isPortrait: isPortrait)
                                .padding(.top, 8)
                        }
                        statusBanners
                            .padding(.horizontal, isPortrait ? 20 : 32)
                        Spacer(minLength: 0)
                        if !usesPhoneLandscapeSideControls {
                            bottomControls(
                                isPortrait: isPortrait,
                                availableWidth: max(
                                    0,
                                    contentSize.width - StandControlLayoutMetrics.rowSpacing * 2
                                )
                            )
                            .padding(.horizontal, StandControlLayoutMetrics.rowSpacing)
                        }
                    }
                    .padding(.top, isPortrait ? 18 : 20)
                    .padding(.bottom, StandControlLayoutMetrics.bottomPadding(isPortrait: isPortrait))
                    .opacity(model.isDisplayDark || !didInitialize ? 0 : 1)
                    .zIndex(5)

                    centerContent(isPortrait: isPortrait, canvasSize: contentSize)
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

                    if let screenAdjustmentDragState {
                        adjustmentHUD(for: screenAdjustmentDragState)
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
                        clockFont: Binding(
                            get: { settings.value.clockFont },
                            set: { settings.value.clockFont = $0 }
                        ),
                        hourMode: .twelve,
                        batteryText: silhouetteBatteryText,
                        batterySystemImage: model.batteryStatus.systemImage,
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

                if didInitialize, let sender = boyisoGreetingSender {
                    BoyisoGreetingOverlay(sender: sender, kind: .greeting)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        .zIndex(160)
                } else if didInitialize, let sender = boyisoWalkieSender {
                    BoyisoGreetingOverlay(sender: sender, kind: .walkieCall)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        .zIndex(160)
                } else if didInitialize, let sender = boyisoCryingSender {
                    BoyisoGreetingOverlay(sender: sender, kind: .soundDetected)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        .zIndex(160)
                }

                if !isEditingScreen, model.isNightSessionActive {
                    homeAccessibilityControls
                }

                if firstLaunchPermissions.shouldPresentExplanation {
                    FirstLaunchPermissionView(
                        coordinator: firstLaunchPermissions,
                        accent: settings.value.displayTheme.accentColor,
                        onComplete: {
                            if firstLaunchPermissions.isCameraAuthorized {
                                model.setAmbientCameraSensingEnabled(true)
                            }
                            startAppIfNeeded()
                        }
                    )
                    .zIndex(200)
                }

            }
            .frame(width: contentSize.width, height: contentSize.height)
            .scaleEffect(presentationScale, anchor: .center)
            .frame(width: proxy.size.width, height: proxy.size.height)
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
        .coordinateSpace(name: RootCoordinateSpace.name)
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
                    theme: settings.value.displayTheme,
                    onClose: { presentedSheet = nil }
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
                            return model.updateInternetRadioChannel(configuration)
                        } else {
                            return model.saveInternetRadioConfiguration(configuration)
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
            case .boyiso:
                NavigationStack {
                    BoyisoView(service: boyiso, accent: settings.value.displayTheme.accentColor)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("완료") { presentedSheet = nil }
                                    .fontWeight(.semibold)
                                    .foregroundStyle(settings.value.displayTheme.accentColor)
                            }
                        }
                }
            }
        }
        #if targetEnvironment(macCatalyst)
        .fullScreenCover(
            isPresented: $showsCatalystRecordings,
            onDismiss: { model.resumeMonitoringAfterPlayback() }
        ) {
            RecordingsView(
                library: library,
                playbackDisabled: false,
                theme: settings.value.displayTheme,
                onClose: { showsCatalystRecordings = false }
            )
        }
        .fullScreenCover(isPresented: $showsCatalystBoyiso) {
            NavigationStack {
                BoyisoView(service: boyiso, accent: settings.value.displayTheme.accentColor)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("완료") { showsCatalystBoyiso = false }
                                .fontWeight(.semibold)
                                .foregroundStyle(settings.value.displayTheme.accentColor)
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showsCatalystSettings) {
            SettingsView(model: model)
        }
        #endif
        .onAppear {
            resetTransientInterface()
            if !firstLaunchPermissions.shouldPresentExplanation {
                startAppIfNeeded()
            }
        }
        .onDisappear { resetTransientInterface() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                resetTransientInterface()
                if !firstLaunchPermissions.shouldPresentExplanation {
                    if hasStartedApp {
                        model.appDidBecomeActive()
                        didInitialize = true
                    } else {
                        startAppIfNeeded()
                    }
                }
            case .inactive, .background:
                resetTransientInterface()
                didInitialize = false
                if hasStartedApp { model.appWillResignActive() }
            @unknown default:
                break
            }
        }
        .onChange(of: boyiso.lastRemoteEvent?.id) { _, _ in
            guard let event = boyiso.lastRemoteEvent else { return }
            showBoyisoBanner(event)
            handleBoyisoEvent(event)
        }
        .onChange(of: model.sharedInternetRadioDraft) { _, draft in
            guard draft != nil else { return }
            presentedSheet = .internetRadio
        }
        #if targetEnvironment(macCatalyst)
        .onChange(of: macUpdater.activity) { _, newActivity in
            handleMacUpdaterActivityChange(newActivity)
        }
        #endif
        .alert(
            updateAlert?.title ?? "",
            isPresented: Binding(
                get: { updateAlert != nil },
                set: { if !$0 { updateAlert = nil } }
            ),
            presenting: updateAlert
        ) { item in
            if item.isTestFlightOpenAction {
                Button("TestFlight 열기") {
                    openTestFlightApp()
                }
                Button("취소", role: .cancel) {
                    updateAlert = nil
                }
            } else {
                Button("확인", role: .cancel) {
                    updateAlert = nil
                }
            }
        } message: { item in
            Text(item.message)
        }
    }

    private func resetTransientInterface() {
        clockScaleFeedbackTask?.cancel()
        boyisoOverlayTask?.cancel()
        boyisoBannerTask?.cancel()
        mobileUpdateTask?.cancel()

        clockScaleFeedbackTask = nil
        boyisoOverlayTask = nil
        boyisoBannerTask = nil
        mobileUpdateTask = nil
        isCheckingMobileUpdate = false
        #if targetEnvironment(macCatalyst)
        isAwaitingMacUpdaterResult = false
        #endif

        screenAdjustmentDragState = nil
        clockScaleGestureStart = nil
        clockScaleFeedback = nil
        boyisoGreetingSender = nil
        boyisoCryingSender = nil
        boyisoWalkieSender = nil
        boyisoBannerEvent = nil
    }

    private func startAppIfNeeded() {
        guard scenePhase == .active else { return }
        guard !hasStartedApp else {
            model.appDidBecomeActive()
            didInitialize = true
            return
        }
        hasStartedApp = true
        model.appDidBecomeActive()
        model.startNightSession()
        didInitialize = true
    }

    private func checkForUpdatesFromHome() {
        #if targetEnvironment(macCatalyst)
        checkMacCatalystUpdates()
        #else
        checkMobileTestFlightUpdates()
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private func checkMacCatalystUpdates() {
        macUpdater.startIfNeeded()
        switch macUpdater.availability {
        case .unsupported:
            updateAlert = UpdateAlertItem(
                title: "업데이트 불가",
                message: "이 기기 환경에서는 업데이트를 지원하지 않습니다."
            )
        case .notStarted:
            updateAlert = UpdateAlertItem(
                title: "업데이트 준비 중",
                message: "업데이트 구성 요소를 준비하고 있습니다. 잠시 후 다시 시도해 주세요."
            )
        case .unavailable(let reason):
            updateAlert = UpdateAlertItem(
                title: "업데이트 사용 불가",
                message: reason
            )
        case .ready:
            if macUpdater.activity == .checking {
                updateAlert = UpdateAlertItem(
                    title: "업데이트 확인 중",
                    message: "현재 최신 버전을 확인하고 있습니다."
                )
            } else if macUpdater.canCheckManually {
                isAwaitingMacUpdaterResult = true
                macUpdater.checkForUpdatesManually()
            }
        }
    }

    private func handleMacUpdaterActivityChange(_ activity: MacUpdaterActivity) {
        guard isAwaitingMacUpdaterResult else { return }
        switch activity {
        case .checking:
            break
        case .upToDate:
            isAwaitingMacUpdaterResult = false
            updateAlert = UpdateAlertItem(
                title: "최신 버전",
                message: "현재 최신 버전을 사용하고 있습니다."
            )
        case .updateFound(let version):
            isAwaitingMacUpdaterResult = false
            let versionInfo = version.map { " (\($0))" } ?? ""
            updateAlert = UpdateAlertItem(
                title: "새 버전 발견",
                message: "새로운 버전\(versionInfo)이(가) 있습니다."
            )
        case .failed(let message):
            isAwaitingMacUpdaterResult = false
            updateAlert = UpdateAlertItem(
                title: "업데이트 확인 실패",
                message: message
            )
        case .idle:
            isAwaitingMacUpdaterResult = false
        }
    }
    #else
    private func checkMobileTestFlightUpdates() {
        if isCheckingMobileUpdate {
            updateAlert = UpdateAlertItem(
                title: "업데이트 확인 중",
                message: "현재 최신 버전을 확인하고 있습니다."
            )
            return
        }

        isCheckingMobileUpdate = true
        mobileUpdateTask = Task { @MainActor in
            defer {
                isCheckingMobileUpdate = false
                mobileUpdateTask = nil
            }
            do {
                var request = URLRequest(url: TestFlightUpdateCheck.endpoint)
                request.timeoutInterval = 10
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    updateAlert = UpdateAlertItem(
                        title: "업데이트 확인 실패",
                        message: "서버 연결에 실패했습니다. 네트워크 상태를 확인하고 다시 시도해 주세요."
                    )
                    return
                }

                let currentBuildText = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
                let outcome = TestFlightUpdateCheck.evaluate(
                    responseData: data,
                    currentBuildText: currentBuildText
                )

                guard !Task.isCancelled else { return }

                switch outcome {
                case .upToDate:
                    updateAlert = UpdateAlertItem(
                        title: "최신 버전",
                        message: "현재 최신 버전을 사용하고 있습니다."
                    )
                case .newerAvailable(let latestBuild, let version):
                    let versionInfo = version.map { " (\($0))" } ?? ""
                    updateAlert = UpdateAlertItem(
                        title: "새 버전 사용 가능",
                        message: "새로운 TestFlight 빌드 \(latestBuild)\(versionInfo)이(가) 있습니다.\n외부 TestFlight 앱으로 이동하여 업데이트하시겠습니까?",
                        isTestFlightOpenAction: true
                    )
                case .malformed(let reason):
                    updateAlert = UpdateAlertItem(
                        title: "업데이트 확인 실패",
                        message: reason
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                updateAlert = UpdateAlertItem(
                    title: "업데이트 확인 실패",
                    message: "네트워크 연결 상태를 확인하고 다시 시도해 주세요."
                )
            }
        }
    }
    #endif

    private func openTestFlightApp() {
        guard let url = URL(string: "itms-beta://") else {
            showTestFlightUnavailableAlert()
            return
        }
        UIApplication.shared.open(url, options: [:]) { success in
            if !success {
                showTestFlightUnavailableAlert()
            }
        }
    }

    private func showTestFlightUnavailableAlert() {
        DispatchQueue.main.async {
            updateAlert = UpdateAlertItem(
                title: "TestFlight 열기 실패",
                message: "기기에 TestFlight 앱이 설치되어 있지 않거나 열 수 없습니다. App Store에서 TestFlight 앱을 설치한 후 다시 시도해 주세요."
            )
        }
    }

    private func topBar(isPortrait _: Bool) -> some View {
        let objectModeLocked = model.isNightSessionActive
            && settings.value.modePreference == .object
        let mateModeLocked = model.isNightSessionActive
            && settings.value.modePreference == .mate
        let statusTitle = model.isNightSessionActive
            ? (objectModeLocked ? "오브제 모드 잠금" : (mateModeLocked ? "매이트 모드 잠금" : model.experienceMode.title))
            : "자동 기능 꺼짐"
        let statusImage = model.isNightSessionActive
            ? ((objectModeLocked || mateModeLocked) ? "lock.fill" : model.experienceMode.systemImage)
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

            Button {
                checkForUpdatesFromHome()
            } label: {
                HStack(spacing: 8) {
                    STandBrandIcon(size: 28)

                    Text("S.tand")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .tracking(0.8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("최신 버전 확인")
            .accessibilityHint("현재 버전이 최신인지 확인합니다.")
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white.opacity(0.82))
        .opacity(model.controlsVisible || !model.isNightSessionActive ? 1 : 0.62)
        .animation(.easeOut(duration: 0.3), value: model.controlsVisible)
    }

    private func musicChannelStrip(isPortrait: Bool) -> some View {
        let usesPhoneLandscapeLayout = PhoneLandscapeSideControlsPolicy.isEnabled(
            isPortrait: isPortrait
        )
        return VStack(spacing: 6) {
            #if targetEnvironment(macCatalyst)
            if isMusicStripReorderingCatalyst {
                musicChannelStripEditingBar(isPortrait: isPortrait)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            #endif

            GeometryReader { proxy in
                let channels = homeMusicChannels
                let cardWidth = MusicChannelStripLayoutPolicy.cardWidth(
                    viewportWidth: proxy.size.width,
                    isPhoneLandscape: usesPhoneLandscapeLayout
                )
                let maximumScroll = MusicChannelStripLayoutPolicy.maximumScroll(
                    viewportWidth: proxy.size.width,
                    cardCount: channels.count,
                    cardWidth: cardWidth
                )

                Group {
                    if maximumScroll == 0 {
                        HStack(spacing: MusicChannelStripLayoutPolicy.spacing) {
                            musicChannelCards(
                                channels,
                                cardWidth: cardWidth,
                                maximumScroll: maximumScroll
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Group {
                            #if targetEnvironment(macCatalyst)
                            if isMusicStripReorderingCatalyst {
                                HStack(spacing: MusicChannelStripLayoutPolicy.spacing) {
                                    musicChannelCards(
                                        channels,
                                        cardWidth: cardWidth,
                                        maximumScroll: maximumScroll
                                    )
                                }
                                .offset(x: MusicChannelStripLayoutPolicy.sideInset + musicChannelStripOffset)
                                .frame(width: proxy.size.width, alignment: .leading)
                                .contentShape(Rectangle())
                                .clipped()
                            } else {
                                HStack(spacing: MusicChannelStripLayoutPolicy.spacing) {
                                    musicChannelCards(
                                        channels,
                                        cardWidth: cardWidth,
                                        maximumScroll: maximumScroll
                                    )
                                }
                                .offset(x: MusicChannelStripLayoutPolicy.sideInset + musicChannelStripOffset)
                                .frame(width: proxy.size.width, alignment: .leading)
                                .contentShape(Rectangle())
                                .highPriorityGesture(
                                    musicChannelStripDragGesture(maximumScroll: maximumScroll),
                                    including: .all
                                )
                                .clipped()
                            }
                            #else
                            HStack(spacing: MusicChannelStripLayoutPolicy.spacing) {
                                musicChannelCards(
                                    channels,
                                    cardWidth: cardWidth,
                                    maximumScroll: maximumScroll
                                )
                            }
                            .offset(x: MusicChannelStripLayoutPolicy.sideInset + musicChannelStripOffset)
                            .frame(width: proxy.size.width, alignment: .leading)
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                musicChannelStripDragGesture(maximumScroll: maximumScroll),
                                including: .all
                            )
                            .clipped()
                            #endif
                        }
                        .mask {
                            if usesPhoneLandscapeLayout {
                                MusicChannelStripEdgeMask(
                                    showsLeadingFade: musicChannelStripOffset < -0.5,
                                    showsTrailingFade: musicChannelStripOffset > -maximumScroll + 0.5
                                )
                            } else {
                                Rectangle()
                            }
                        }
                        .onAppear {
                            musicChannelStripOffset = MusicChannelStripLayoutPolicy.clampedOffset(
                                musicChannelStripOffset,
                                maximumScroll: maximumScroll
                            )
                        }
                        .onChange(of: maximumScroll) { _, value in
                            musicChannelStripOffset = MusicChannelStripLayoutPolicy.clampedOffset(
                                musicChannelStripOffset,
                                maximumScroll: value
                            )
                        }
                    }
                }
                .background {
                    GeometryReader { frameProxy in
                        Color.clear.preference(
                            key: MusicChannelStripFramePreferenceKey.self,
                            value: frameProxy.frame(in: .named(RootCoordinateSpace.name))
                        )
                    }
                }
            }
            .frame(height: InternetRadioPanelMetrics.height)
            .onPreferenceChange(MusicChannelStripFramePreferenceKey.self) {
                musicChannelStripFrame = $0
            }
            .accessibilityLabel("음악 채널")
        }
        .animation(.easeOut(duration: 0.2), value: isMusicStripReorderingCatalyst)
    }

    #if targetEnvironment(macCatalyst)
    private func musicChannelStripEditingBar(isPortrait: Bool) -> some View {
        HStack(spacing: 10) {
            Label("카드 순서 편집 중", systemImage: "arrow.left.arrow.right")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            Spacer(minLength: 8)

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isMusicStripReorderingCatalyst = false
                }
                musicStripDraggingChannelID = nil
            } label: {
                Text("완료")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .accessibilityLabel("카드 순서 편집 마치기")
        }
        .padding(.horizontal, isPortrait ? 20 : 32)
    }
    #endif

    @ViewBuilder
    private func musicChannelCards(
        _ channels: [HomeMusicChannel],
        cardWidth: CGFloat,
        maximumScroll: CGFloat
    ) -> some View {
        let selectionIDs = settings.value.homeMusicChannels.map(\.id)
        ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
            HomeMusicStripCard(
                channel: channel,
                width: cardWidth,
                radioState: radio.state,
                activeRadioChannelID: radio.activeChannelID,
                activeExternalMusicService: model.activeExternalMusicService,
                externalMusicPlaybackState: model.externalMusicPlaybackState,
                externalMusicTrackTitle: model.externalMusicTrackTitle,
                orderIndex: index,
                selectionID: selectionIDs.indices.contains(index) ? selectionIDs[index] : channel.id,
                onToggleRadio: model.toggleInternetRadioPlayback(channelID:),
                onSelectRadioTitle: { channelID in
                    guard let targetChannelID = handleInternetRadioTitleTap(channelID),
                          let targetIndex = channels.firstIndex(where: { channel in
                              guard case .radio(let configuration) = channel else { return false }
                              return configuration.id == targetChannelID
                          }) else { return }
                    withAnimation(.snappy(duration: 0.28)) {
                        musicChannelStripOffset = MusicChannelStripLayoutPolicy.leadingAlignedOffset(
                            cardIndex: targetIndex,
                            cardWidth: cardWidth,
                            maximumScroll: maximumScroll
                        )
                    }
                },
                onToggleExternalMusic: model.toggleExternalMusicPlayback,
                onSkipExternalMusic: model.skipToNextExternalMusicTrack,
                onEditRadio: { channelID in
                    radioEditorChannelID = channelID
                    presentedSheet = .internetRadio
                },
                onRegisterRadio: {
                    openSettings()
                },
                onMoveChannel: { selectionID, destinationIndex in
                    model.moveHomeMusicChannel(id: selectionID, to: destinationIndex)
                },
                isReorderingCatalyst: isMusicStripReorderingCatalyst,
                draggingChannelID: $musicStripDraggingChannelID,
                onBeginReordering: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isMusicStripReorderingCatalyst = true
                    }
                }
            )
        }
    }

    @discardableResult
    private func handleInternetRadioTitleTap(_ tappedChannelID: UUID) -> UUID? {
        let orderedChannelIDs = settings.value.internetRadioChannels.map(\.id)
        guard let targetChannelID = InternetRadioTitleTapPolicy.targetChannelID(
            tappedChannelID: tappedChannelID,
            activeChannelID: radio.activeChannelID,
            playbackState: radio.state,
            orderedChannelIDs: orderedChannelIDs
        ) else { return nil }
        model.playInternetRadio(channelID: targetChannelID)
        return targetChannelID
    }

    private func musicChannelStripDragGesture(maximumScroll: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let startOffset = musicChannelStripDragStartOffset
                    ?? musicChannelStripOffset
                musicChannelStripDragStartOffset = startOffset
                musicChannelStripOffset = MusicChannelStripLayoutPolicy.clampedOffset(
                    startOffset + value.translation.width,
                    maximumScroll: maximumScroll
                )
            }
            .onEnded { value in
                let startOffset = musicChannelStripDragStartOffset
                    ?? musicChannelStripOffset
                musicChannelStripDragStartOffset = nil
                withAnimation(.snappy(duration: 0.28)) {
                    musicChannelStripOffset = MusicChannelStripLayoutPolicy.clampedOffset(
                        startOffset + value.predictedEndTranslation.width,
                        maximumScroll: maximumScroll
                    )
                }
            }
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
            batterySystemImage: model.batteryStatus.systemImage,
            musicChannels: homeMusicChannels,
            radioState: radio.state,
            activeRadioChannelID: radio.activeChannelID,
            activeExternalMusicService: model.activeExternalMusicService,
            externalMusicPlaybackState: model.externalMusicPlaybackState,
            externalMusicTrackTitle: model.externalMusicTrackTitle,
            showsMateLock: MateLockPresentationPolicy.isVisible(
                modePreference: settings.value.modePreference,
                experienceMode: model.experienceMode
            ),
            onToggleRadio: model.toggleInternetRadioPlayback(channelID:),
            onToggleExternalMusic: model.toggleExternalMusicPlayback,
            onEndExternalMusic: model.endExternalMusicSession,
            onEditRadio: { channelID in
                radioEditorChannelID = channelID
                presentedSheet = .internetRadio
            }
        )
    }

    private var homeMusicChannels: [HomeMusicChannel] {
        settings.value.homeMusicChannels.compactMap { selection in
            switch selection.kind {
            case .appleMusic:
                .external(.appleMusic)
            case .appleClassical:
                .external(.appleClassical)
            case .internetRadio:
                if let configuration = selection.radioID
                    .flatMap(settings.value.internetRadioChannel(id:)) {
                    .radio(configuration)
                } else {
                    .emptyRadio(slot: selection.radioSlot ?? 0)
                }
            }
        }
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
                // 세로 밝기·가로 음량 조절로 쓰이는 이동은 이 제스처의 편집 진입을 영구히 취소한다.
                homeEditEntry.apply(
                    .moved(distance: hypot(value.translation.width, value.translation.height))
                )
                guard !firstLaunchPermissions.shouldPresentExplanation,
                      !isEditingScreen,
                      presentedSheet == nil,
                      !musicChannelStripFrame.contains(value.startLocation)
                else { return }
                let state = screenAdjustmentDragState ?? initialAdjustmentState(for: value.translation)
                screenAdjustmentDragState = state

                switch state {
                case .brightness(let startingValue):
                    let adjustedValue = SimplifiedBrightnessModePolicy.level(
                        startingAt: startingValue,
                        verticalTranslation: value.translation.height,
                        viewportHeight: currentCanvasSize.height
                    )
                    model.updateBrightnessLevel(adjustedValue)
                case .volume(let startingValue):
                    let adjustedValue = VolumeAdjustmentPolicy.level(
                        startingAt: startingValue,
                        horizontalTranslation: value.translation.width,
                        viewportWidth: currentCanvasSize.width
                    )
                    systemVolume.update(adjustedValue)
                case .ignored:
                    break
                }
            }
            .onEnded { _ in
                // 손가락을 뗀 뒤 다음 누름은 새 제스처이므로 편집 진입 대기 상태를 초기화한다.
                homeEditEntry = HomeEditEntryPolicy.PendingEntry()
                guard !firstLaunchPermissions.shouldPresentExplanation,
                      !isEditingScreen
                else { return }
                if case .brightness = screenAdjustmentDragState {
                    model.endBrightnessAdjustment()
                }
                screenAdjustmentDragState = nil
            }
    }

    private func initialAdjustmentState(for translation: CGSize) -> ScreenAdjustmentDragState {
        if abs(translation.height) > abs(translation.width) {
            model.beginBrightnessAdjustment()
            return .brightness(startingValue: model.displayBrightness)
        }
        #if targetEnvironment(macCatalyst)
        return .ignored
        #else
        systemVolume.refresh()
        return .volume(startingValue: systemVolume.level)
        #endif
    }

    @ViewBuilder
    private func adjustmentHUD(for state: ScreenAdjustmentDragState) -> some View {
        switch state {
        case .brightness:
            AppBrightnessHUD(level: model.displayBrightness)
        case .volume:
            SystemVolumeHUD(level: systemVolume.level)
        case .ignored:
            EmptyView()
        }
    }

    private var screenPressGesture: some Gesture {
        // 편집 진입은 정지 상태 2.0초 누름 뒤에만 열린다(HomeEditEntryPolicy). 허용 이동량을
        // 넘는 움직임은 시스템 인식기가 실패 처리하고, 밝기·음량 드래그가 먼저 시작되면
        // exclusively(before:)와 homeEditEntry 취소 상태가 함께 편집 진입을 막는다.
        LongPressGesture(
            minimumDuration: HomeEditEntryPolicy.minimumPressDuration,
            maximumDistance: HomeEditEntryPolicy.maximumMovement
        )
            .onChanged { _ in
                // 새 누름이 시작될 때마다 새 제스처로 취급해 이전 취소 상태를 지운다.
                homeEditEntry = HomeEditEntryPolicy.PendingEntry()
            }
            .exclusively(
                before: TapGesture(count: 2)
                    .exclusively(before: TapGesture())
            )
            .onEnded { result in
                switch result {
                case .first(true):
                    guard !firstLaunchPermissions.shouldPresentExplanation,
                          !isEditingScreen,
                          presentedSheet == nil,
                          homeEditEntry.apply(.held(seconds: HomeEditEntryPolicy.minimumPressDuration))
                    else { return }
                    homeEditEntry = HomeEditEntryPolicy.PendingEntry()
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
        guard !firstLaunchPermissions.shouldPresentExplanation, !isEditingScreen else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            settings.value.displayTheme.toggle()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func handleScreenTap() {
        guard !firstLaunchPermissions.shouldPresentExplanation,
              !isEditingScreen,
              model.isNightSessionActive
        else { return }
        model.toggleObjectMateMode()
        model.revealControls()
    }

    private var homeAccessibilityControls: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel("홈 화면 제어")
            .accessibilityValue(
                "\(model.experienceMode.title), 앱 밝기 \(Int((model.displayBrightness * 100).rounded()))퍼센트"
            )
            .accessibilityHint("위아래로 쓸어 앱 밝기를 조절하거나 동작 메뉴에서 모드, 테마와 편집을 선택합니다")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjustBrightnessForAccessibility(by: 0.1)
                case .decrement: adjustBrightnessForAccessibility(by: -0.1)
                @unknown default: break
                }
            }
            .accessibilityAction(named: Text("오브제와 매이트 전환"), handleScreenTap)
            .accessibilityAction(named: Text("테마 전환"), toggleDisplayTheme)
            .accessibilityAction(named: Text("화면 편집 열기")) {
                enterScreenEditing(isPortrait: currentIsPortrait)
            }
            .accessibilityAction(named: Text("시계 크게")) {
                adjustClockScaleForAccessibility(by: 0.1)
            }
            .accessibilityAction(named: Text("시계 작게")) {
                adjustClockScaleForAccessibility(by: -0.1)
            }
    }

    private func adjustBrightnessForAccessibility(by amount: Double) {
        let value = min(1, max(0, model.displayBrightness + amount))
        model.beginBrightnessAdjustment()
        model.updateBrightnessLevel(value)
        model.endBrightnessAdjustment()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func adjustClockScaleForAccessibility(by amount: Double) {
        settings.value.clockScale = min(
            AppSettings.maximumClockScale,
            max(AppSettings.minimumClockScale, settings.value.clockScale + amount)
        )
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private var clockMagnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { magnification in
                guard !firstLaunchPermissions.shouldPresentExplanation, !isEditingScreen else { return }
                let startingScale: Double
                if let clockScaleGestureStart {
                    startingScale = clockScaleGestureStart
                } else {
                    startingScale = settings.value.clockScale
                    clockScaleGestureStart = startingScale
                }

                let scale = min(
                    AppSettings.maximumClockScale,
                    max(AppSettings.minimumClockScale, startingScale * Double(magnification))
                )
                settings.value.clockScale = scale
                clockScaleFeedbackTask?.cancel()
                withAnimation(.easeOut(duration: 0.12)) {
                    clockScaleFeedback = scale
                }
            }
            .onEnded { _ in
                guard !firstLaunchPermissions.shouldPresentExplanation, !isEditingScreen else { return }
                clockScaleGestureStart = nil
                scheduleClockScaleFeedbackHide()
            }
    }

    private func updateCanvasMetrics(proxy: GeometryProxy, isPortrait: Bool) {
        currentCanvasSize = proxy.size
        let layout = isPortrait
            ? settings.value.portraitLayout
            : settings.value.landscapeLayout
        let usesPhoneLandscapeSideControls = PhoneLandscapeSideControlsPolicy.isEnabled(
            isPortrait: isPortrait
        )
        currentProtectedInsets = PanelEditingPolicy.editingRegion(
            canvasSize: proxy.size,
            safeAreaInsets: proxy.safeAreaInsets,
            isPortrait: isPortrait,
            controlOrder: usesPhoneLandscapeSideControls ? nil : layout.controlOrder,
            bottomAvailableWidth: max(
                0,
                proxy.size.width - StandControlLayoutMetrics.rowSpacing * 2
            ),
            reservesBottomControlRow: !usesPhoneLandscapeSideControls,
            reservesPhoneLandscapeTopRow: usesPhoneLandscapeSideControls
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
            .accessibilityHint("녹음 및 설정 버튼이 나타납니다")
        } else {
            // 잠소리·보이소·설정 공용 카드는 고정 크기(98x66)를 쓰므로
            // 폭 계산 대신 6pt 간격으로 나열하고 좁은 폭에서만 줄바꿈한다.
            WrappingControlLayout(spacing: HomeSharedControlMetrics.spacing) {
                ForEach(visibleControlOrder(isPortrait: isPortrait)) { kind in
                    bottomControl(
                        for: kind,
                        size: HomeSharedControlMetrics.size(isPhoneLandscape: false)
                    )
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.3), value: model.controlsVisible)
        }
    }

    private func phoneLandscapeSideControls() -> some View {
        HStack(spacing: HomeSharedControlMetrics.spacing) {
            ForEach(visibleControlOrder(isPortrait: false)) { kind in
                bottomControl(
                    for: kind,
                    size: HomeSharedControlMetrics.size(isPhoneLandscape: true)
                )
            }
        }
        .opacity(model.controlsVisible || !model.isNightSessionActive ? 1 : 0.62)
        .animation(.easeOut(duration: 0.3), value: model.controlsVisible)
        .accessibilityElement(children: .contain)
    }

    private func visibleControlOrder(isPortrait: Bool) -> [StandControlKind] {
        let order = isPortrait
            ? settings.value.portraitLayout.controlOrder
            : settings.value.landscapeLayout.controlOrder
        // 홈 공용 카드는 잠소리 -> 보이소 -> 설정 순서로 고정한다.
        // 사용자 순서에서 빠진 항목만 그대로 숨긴다.
        return HomeSharedControlMetrics.order.filter { order.contains($0) }
    }

    @ViewBuilder
    private func bottomControl(for kind: StandControlKind, size: CGSize) -> some View {
        switch kind {
        case .flashlight:
            HomeSharedControlCard(
                title: "플래시 연동",
                status: settings.value.torchEnabled ? "일반 10% · 강한 알림은 어두울 때 최대" : "사용하지 않음",
                size: size,
                hint: "일반 움직임과 핑거스냅은 10퍼센트, 강한 소리 알림은 방이 어두울 때 최대 밝기로 켭니다",
                icon: {
                    HomeSharedControlSymbolIcon(
                        systemImage: settings.value.torchEnabled
                            ? "flashlight.on.fill"
                            : "flashlight.off.fill"
                    )
                }
            ) {
                settings.value.torchEnabled.toggle()
                if settings.value.torchEnabled { model.activateLamp() }
            }
        case .brightness:
            CompactBrightnessRuleControl(
                currentBrightness: model.displayBrightness,
                currentMode: model.environmentDisplayMode,
                width: size.width,
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
            HomeSharedControlCard(
                title: "잠소리",
                status: library.clips.isEmpty ? "잠소리 없음" : "잠소리 \(library.clips.count)개",
                size: size,
                hint: "저장된 잠소리를 확인합니다",
                icon: { HomeSharedControlSymbolIcon(systemImage: "waveform") }
            ) {
                openRecordings()
            }
        case .boyiso:
            BoyisoHomeSharedControlCard(
                title: BoyisoBranding.primaryName,
                status: boyiso.isEnabled ? boyiso.role.title : "연결 안 됨",
                size: size,
                tap: {
                    if !boyiso.isEnabled { openBoyiso() }
                    else if boyiso.role == .walkie { _ = boyiso.sendWalkiePress() }
                    else { _ = boyiso.sendTokTok() }
                },
                longPress: { openBoyiso() }
            )
        case .settings:
            HomeSharedControlCard(
                title: "설정",
                status: "화면·감지",
                size: size,
                hint: "밝기, 감지, 녹음 설정을 엽니다",
                icon: { HomeSharedControlSymbolIcon(systemImage: "slider.horizontal.3") }
            ) {
                openSettings()
            }
        }
    }

    private func openSettings() {
        #if targetEnvironment(macCatalyst)
        showsCatalystSettings = true
        #else
        presentedSheet = .settings
        #endif
    }

    private func openRecordings() {
        model.pauseMonitoringForPlayback()
        #if targetEnvironment(macCatalyst)
        showsCatalystRecordings = true
        #else
        presentedSheet = .recordings
        #endif
    }

    private func openBoyiso() {
        #if targetEnvironment(macCatalyst)
        showsCatalystBoyiso = true
        #else
        presentedSheet = .boyiso
        #endif
    }

    private var tapToControlText: some View {
        Label(
            "탭하여 녹음·설정 열기",
            systemImage: "ellipsis.circle.fill"
        )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.62))
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
            if let event = boyisoBannerEvent {
                Label(
                    "\(event.sourceName) · \(event.kind.title)",
                    systemImage: event.kind == .movement
                        ? "figure.roll"
                        : event.kind == .walkie ? "dot.radiowaves.left.and.right" : "waveform"
                )
                .font(.headline.weight(.bold))
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(.orange.opacity(0.82), in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel("\(BoyisoBranding.primaryName) 알림, \(event.sourceName)에서 \(event.kind.title)")
            }
            if boyiso.isEnabled, !boyiso.peers.isEmpty, boyiso.activePeers.isEmpty {
                Label("\(BoyisoBranding.primaryName) 공간 연결이 끊겼습니다", systemImage: "wifi.exclamationmark")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(.red.opacity(0.78), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .allowsHitTesting(false)
    }

    private func showBoyisoBanner(_ event: BoyisoEvent) {
        boyisoBannerTask?.cancel()
        boyisoBannerEvent = event
        boyisoBannerTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(BoyisoEventBannerPolicy.displayDurationSeconds))
            guard !Task.isCancelled,
                  BoyisoEventBannerPolicy.shouldDismiss(
                    displayedEventID: boyisoBannerEvent?.id,
                    timerEventID: event.id
                  )
            else { return }
            boyisoBannerEvent = nil
            boyisoBannerTask = nil
        }
    }

    private func handleBoyisoEvent(_ event: BoyisoEvent) {
        let chimeCount = BoyisoReactionPolicy.chimeCount(for: event)
        guard chimeCount > 0 else { return }
        boyisoOverlayTask?.cancel()
        if event.kind == .toktok {
            boyisoGreetingSender = event.sourceName
            boyisoCryingSender = nil
            boyisoWalkieSender = nil
            playBoyisoChime()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            if event.kind == .walkie {
                boyisoWalkieSender = event.sourceName
                boyisoCryingSender = nil
            } else {
                boyisoCryingSender = event.sourceName
                boyisoWalkieSender = nil
            }
            boyisoGreetingSender = nil
            Task { @MainActor in
                for index in 0..<chimeCount {
                    if index > 0 { try? await Task.sleep(for: .milliseconds(1_250)) }
                    playBoyisoChime()
                }
            }
        }
        UIAccessibility.post(notification: .announcement, argument: {
            switch event.kind {
            case .toktok: "\(event.sourceName)님의 톡톡"
            case .walkie: "\(event.sourceName)님의 무전기 호출"
            default: "\(event.sourceName)에서 소리를 감지했습니다"
            }
        }())
        boyisoOverlayTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            boyisoGreetingSender = nil
            boyisoCryingSender = nil
            boyisoWalkieSender = nil
        }
    }

    private func playBoyisoChime() {
        guard let url = Bundle.main.url(forResource: "boyiso_toktok", withExtension: "wav") else { return }
        var soundID: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &soundID) == kAudioServicesNoError else { return }
        AudioServicesPlaySystemSoundWithCompletion(soundID) {
            AudioServicesDisposeSystemSoundID(soundID)
        }
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
        GeometryReader { proxy in
            let diagonal = (proxy.size.width * proxy.size.width
                + proxy.size.height * proxy.size.height).squareRoot()

            ZStack {
                Color.black
                RadialGradient(
                    colors: gradientColors,
                    center: .center,
                    startRadius: 20,
                    endRadius: max(700, diagonal * 0.72)
                )
            }
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

private struct SystemVolumeHUD: View {
    let level: Double

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: level == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 16, weight: .semibold))

            Text("시스템 볼륨")
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
        Int((VolumeAdjustmentPolicy.clamped(level) * 100).rounded())
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

private enum HomeMusicChannel: Identifiable {
    case radio(InternetRadioConfiguration)
    case external(ExternalMusicService)
    case emptyRadio(slot: Int)

    var id: String {
        switch self {
        case let .radio(configuration): "radio:\(configuration.id.uuidString)"
        case let .external(service): "external:\(service.id)"
        case let .emptyRadio(slot): "radio:empty:\(slot)"
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
    let musicChannels: [HomeMusicChannel]
    let radioState: InternetRadioPlaybackState
    let activeRadioChannelID: UUID?
    let activeExternalMusicService: ExternalMusicService?
    let externalMusicPlaybackState: ExternalMusicPlaybackState
    let externalMusicTrackTitle: String?
    let showsMateLock: Bool
    let onToggleRadio: (UUID) -> Void
    let onToggleExternalMusic: (ExternalMusicService) -> Void
    let onEndExternalMusic: () -> Void
    let onEditRadio: (UUID) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = UICatalogLaunch.fixedDate ?? context.date
            let drift = BurnInProtection.offset(at: date)
            ZStack {
                FlipClockFace(
                    date: date,
                    isPortrait: isPortrait,
                    isDimmed: isDimmed,
                    clockScale: 1,
                    clockFont: clockFont,
                    hourMode: hourMode
                )
                .panelTransform(layout.clock, canvasSize: canvasSize)

                if showsMateLock {
                    MateModeLockOverlay(isPortrait: isPortrait)
                        .panelTransform(layout.clock, canvasSize: canvasSize)
                }

                ClockSecondsPanel(
                    date: date,
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

                StandDatePanel(date: date, isPortrait: isPortrait)
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
        if musicChannels.count == 2, layout.radiosGrouped {
            HStack(spacing: 0) {
                ForEach(musicChannels) { channel in
                    HomeMusicPanel(
                        channel: channel,
                        radioState: radioState,
                        activeRadioChannelID: activeRadioChannelID,
                        activeExternalMusicService: activeExternalMusicService,
                        externalMusicPlaybackState: externalMusicPlaybackState,
                        externalMusicTrackTitle: externalMusicTrackTitle,
                        isDimmed: isDimmed,
                        dimmedIntensity: dimmedIntensity,
                        renderedScale: 1,
                        drawsSurface: false,
                        onToggleRadio: onToggleRadio,
                        onToggleExternalMusic: onToggleExternalMusic,
                        onEndExternalMusic: onEndExternalMusic,
                        onEditRadio: onEditRadio
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
            .panelTransform(layout.radio, canvasSize: canvasSize)
        } else {
            ForEach(Array(musicChannels.enumerated()), id: \.element.id) { index, channel in
                let transform = index == 0 ? layout.radio : layout.secondaryRadio
                HomeMusicPanel(
                    channel: channel,
                    radioState: radioState,
                    activeRadioChannelID: activeRadioChannelID,
                    activeExternalMusicService: activeExternalMusicService,
                    externalMusicPlaybackState: externalMusicPlaybackState,
                    externalMusicTrackTitle: externalMusicTrackTitle,
                    isDimmed: isDimmed,
                    dimmedIntensity: dimmedIntensity,
                    renderedScale: transform.scale * clockScale,
                    drawsSurface: true,
                    onToggleRadio: onToggleRadio,
                    onToggleExternalMusic: onToggleExternalMusic,
                    onEndExternalMusic: onEndExternalMusic,
                    onEditRadio: onEditRadio
                )
                .panelTransform(transform, canvasSize: canvasSize)
            }
        }
    }
}

private struct HomeMusicPanel: View {
    let channel: HomeMusicChannel
    let radioState: InternetRadioPlaybackState
    let activeRadioChannelID: UUID?
    let activeExternalMusicService: ExternalMusicService?
    let externalMusicPlaybackState: ExternalMusicPlaybackState
    let externalMusicTrackTitle: String?
    let isDimmed: Bool
    let dimmedIntensity: Double
    let renderedScale: Double
    let drawsSurface: Bool
    let onToggleRadio: (UUID) -> Void
    let onToggleExternalMusic: (ExternalMusicService) -> Void
    let onEndExternalMusic: () -> Void
    let onEditRadio: (UUID) -> Void

    @ViewBuilder
    var body: some View {
        switch channel {
        case let .radio(configuration):
            InternetRadioPanel(
                configuration: configuration,
                state: activeRadioChannelID == configuration.id ? radioState : .idle,
                isDimmed: isDimmed,
                dimmedIntensity: dimmedIntensity,
                showsEditBadge: false,
                renderedScale: renderedScale,
                action: { onToggleRadio(configuration.id) },
                editAction: { onEditRadio(configuration.id) },
                drawsSurface: drawsSurface
            )
        case let .external(service):
            ExternalMusicPanel(
                service: service,
                isActive: activeExternalMusicService == service,
                playbackState: externalMusicPlaybackState,
                trackTitle: externalMusicTrackTitle,
                isDimmed: isDimmed,
                dimmedIntensity: dimmedIntensity,
                renderedScale: renderedScale,
                drawsSurface: drawsSurface,
                onToggle: { onToggleExternalMusic(service) },
                onEnd: onEndExternalMusic
            )
        case .emptyRadio:
            InternetRadioPanel(
                configuration: nil,
                state: .idle,
                isDimmed: isDimmed,
                dimmedIntensity: dimmedIntensity,
                showsEditBadge: false,
                renderedScale: renderedScale,
                action: {},
                editAction: {},
                drawsSurface: drawsSurface,
                allowsInteraction: false
            )
        }
    }

}

private struct MusicChannelStripEdgeMask: View {
    let showsLeadingFade: Bool
    let showsTrailingFade: Bool

    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: showsLeadingFade ? [.clear, .black] : [.black, .black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 24)

            Rectangle().fill(.black)

            LinearGradient(
                colors: showsTrailingFade ? [.black, .clear] : [.black, .black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 28)
        }
    }
}

private struct HomeMusicStripCard: View {
    let channel: HomeMusicChannel
    let width: CGFloat
    let radioState: InternetRadioPlaybackState
    let activeRadioChannelID: UUID?
    let activeExternalMusicService: ExternalMusicService?
    let externalMusicPlaybackState: ExternalMusicPlaybackState
    let externalMusicTrackTitle: String?
    let orderIndex: Int
    let selectionID: String
    let onToggleRadio: (UUID) -> Void
    let onSelectRadioTitle: (UUID) -> Void
    let onToggleExternalMusic: (ExternalMusicService) -> Void
    let onSkipExternalMusic: (ExternalMusicService) -> Void
    let onEditRadio: (UUID) -> Void
    let onRegisterRadio: () -> Void
    let onMoveChannel: (String, Int) -> Void
    let isReorderingCatalyst: Bool
    @Binding var draggingChannelID: String?
    let onBeginReordering: () -> Void

    var body: some View {
        #if targetEnvironment(macCatalyst)
        if isReorderingCatalyst {
            reorderingCardBody
        } else {
            normalCardBody
                .contextMenu {
                    Button {
                        onBeginReordering()
                    } label: {
                        Label("카드 순서 편집", systemImage: "arrow.left.arrow.right")
                    }
                    .onAppear {
                        // Catalyst의 오른쪽 클릭만으로 편집 모드를 활성화한다.
                        // 메뉴 항목을 한 번 더 누르지 않아도 다음 실행 루프에
                        // 카드가 드래그·수정 가능한 모습으로 전환된다.
                        DispatchQueue.main.async {
                            onBeginReordering()
                        }
                    }
                }
        }
        #else
        normalCardBody
        #endif
    }

    private var normalCardBody: some View {
        ZStack {
            FlipPanelSurface(
                isDimmed: false,
                cornerRadius: HomeMusicStripCardMetrics.cornerRadius,
                splitGap: HomeMusicStripCardMetrics.splitGap
            )

            switch channel {
            case let .external(service):
                externalContent(service)
            case let .radio(configuration):
                radioContent(configuration)
            case .emptyRadio:
                emptyRadioContent
            }
        }
        .frame(width: width, height: HomeMusicStripCardMetrics.height)
        .foregroundStyle(.white.opacity(0.80))
    }

    #if targetEnvironment(macCatalyst)
    private var reorderingCardBody: some View {
        ZStack {
            FlipPanelSurface(isDimmed: false, cornerRadius: 13, splitGap: 2)
            reorderingContent
        }
        .frame(width: width, height: InternetRadioPanelMetrics.height)
        .foregroundStyle(.white.opacity(0.80))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(
                    Color.orange.opacity(0.85),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
        }
        .contentShape(Rectangle())
        .onDrag {
            draggingChannelID = selectionID
            return NSItemProvider(object: NSString(string: selectionID))
        }
        .onDrop(
            of: [.text],
            delegate: MusicChannelReorderDropDelegate(
                destinationIndex: orderIndex,
                draggingChannelID: $draggingChannelID,
                onMove: onMoveChannel
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(reorderingTitle), 카드 순서 편집")
        .accessibilityHint("드래그해 순서를 바꿉니다")
    }

    private var reorderingContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            VStack(alignment: .leading, spacing: 2) {
                Text(reorderingTitle)
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                Text("드래그해 이동")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer(minLength: 0)

            reorderingActionButton
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reorderingTitle: String {
        return switch channel {
        case let .external(service):
            service.displayName
        case let .radio(configuration):
            configuration.displayName
        case .emptyRadio:
            "인터넷 라디오"
        }
    }

    @ViewBuilder
    private var reorderingActionButton: some View {
        switch channel {
        case let .radio(configuration):
            Button {
                onEditRadio(configuration.id)
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(configuration.displayName) 라디오 수정")
        case .emptyRadio:
            Button(action: onRegisterRadio) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("인터넷 라디오 등록")
        case .external:
            EmptyView()
        }
    }
    #endif

    private func externalContent(_ service: ExternalMusicService) -> some View {
        let isActive = activeExternalMusicService == service
        let isPlaying = isActive && externalMusicPlaybackState == .playing
        let title = isActive && !(externalMusicTrackTitle ?? "").isEmpty
            ? externalMusicTrackTitle!
            : service.displayName
        let nextAction = ExternalMusicTitleTapPolicy.action(
            isActive: isActive,
            playbackState: externalMusicPlaybackState
        )

        return ZStack {
            HomeMusicStripCardContent(
                systemImage: externalIcon(isActive: isActive),
                title: title,
                status: externalStatus(isActive: isActive),
                scrollsTitle: true
            )

            HomeMusicStripCardHalves(
                leadingLabel: "\(service.displayName) \(isPlaying ? "일시 정지" : "재생")",
                trailingLabel: "\(title), \(nextAction == .next ? "다음 곡" : "재생")",
                onLeading: { onToggleExternalMusic(service) },
                onTrailing: {
                    // 정지 상태에서는 오른쪽 절반도 기존 정책대로 이 항목부터 재생한다.
                    switch nextAction {
                    case .play:
                        onToggleExternalMusic(service)
                    case .next:
                        onSkipExternalMusic(service)
                    }
                }
            )
        }
        .accessibilityHint("왼쪽 절반은 재생과 일시 정지, 오른쪽 절반은 다음 곡으로 이동합니다")
    }

    private func radioContent(_ configuration: InternetRadioConfiguration) -> some View {
        let isActive = activeRadioChannelID == configuration.id
        let isPlaying = isActive && radioState == .playing
        return ZStack {
            HomeMusicStripCardContent(
                systemImage: radioIcon(isActive: isActive),
                title: configuration.displayName,
                status: isActive ? radioStatus : "대기 중",
                scrollsTitle: false
            )

            HomeMusicStripCardHalves(
                leadingLabel: "\(configuration.displayName) \(isPlaying ? "정지" : "재생")",
                trailingLabel: "\(configuration.displayName), \(radioState == .playing ? "다음 라디오" : "재생")",
                onLeading: { onToggleRadio(configuration.id) },
                // 정지 상태에서는 기존 InternetRadioTitleTapPolicy가 이 채널부터 재생한다.
                onTrailing: { onSelectRadioTitle(configuration.id) }
            )
        }
        .onLongPressGesture(minimumDuration: 0.8) { onEditRadio(configuration.id) }
        .accessibilityHint("왼쪽 절반은 재생과 정지, 오른쪽 절반은 다음 라디오로 이동하고 길게 눌러 채널을 편집합니다")
    }

    private var emptyRadioContent: some View {
        Button(action: onRegisterRadio) {
            HomeMusicStripCardContent(
                systemImage: "radio.fill",
                title: "인터넷 라디오",
                status: "등록을 기다림",
                scrollsTitle: false
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("인터넷 라디오, 등록을 기다림")
        .accessibilityHint("두 번 탭해 설정에서 라디오 주소를 등록합니다")
    }

    private func externalIcon(isActive: Bool) -> String {
        guard isActive else {
            if case let .external(service) = channel { return service.systemImage }
            return "music.note"
        }
        return externalMusicPlaybackState == .playing ? "pause.fill" : "play.fill"
    }

    private func externalStatus(isActive: Bool) -> String {
        guard isActive else { return "대기 중" }
        return switch externalMusicPlaybackState {
        case .loading: "준비 중"
        case .playing: "재생 중"
        case .paused: "일시 정지"
        case .idle, .unavailable: "대기 중"
        }
    }

    private func radioIcon(isActive: Bool) -> String {
        guard isActive else { return "radio.fill" }
        return switch radioState {
        case .loading: "antenna.radiowaves.left.and.right"
        case .reconnecting: "arrow.clockwise.circle.fill"
        case .playing: "stop.circle.fill"
        case .idle, .failed: "radio.fill"
        }
    }

    private var radioStatus: String {
        switch radioState {
        case .loading: "연결 중"
        case .reconnecting: "다시 연결 중"
        case .playing: "재생 중"
        case .idle: "대기 중"
        case .failed: "연결 실패"
        }
    }
}

/// 음악 스트립 카드의 공통 2행 본문: 가운데 정렬된 아이콘+제목, 가운데 정렬된 상태.
/// 터치는 받지 않고 `HomeMusicStripCardHalves`가 좌우 절반 히트 영역을 담당한다.
private struct HomeMusicStripCardContent: View {
    let systemImage: String
    let title: String
    let status: String
    let scrollsTitle: Bool

    var body: some View {
        VStack(spacing: HomeMusicStripCardMetrics.rowGap) {
            HStack(spacing: HomeMusicStripCardMetrics.iconTitleGap) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: HomeMusicStripCardMetrics.iconSize, weight: .semibold))
                    .frame(
                        width: HomeMusicStripCardMetrics.iconSize,
                        height: HomeMusicStripCardMetrics.iconSize
                    )
                    .accessibilityHidden(true)

                titleText
                    .font(.system(size: HomeMusicStripCardMetrics.titleFontSize, weight: .semibold))
                    .lineLimit(1)
                    .frame(height: HomeMusicStripCardMetrics.titleLineHeight)
            }
            .frame(maxWidth: .infinity)

            Text(status)
                .font(.system(size: HomeMusicStripCardMetrics.statusFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: HomeMusicStripCardMetrics.statusLineHeight)
                .frame(maxWidth: .infinity)
                .offset(y: -HomeMusicStripCardMetrics.statusLift)
        }
        .offset(y: -HomeMusicStripCardMetrics.contentLift)
        .padding(.horizontal, HomeMusicStripCardMetrics.horizontalPadding)
        .padding(.vertical, HomeMusicStripCardMetrics.verticalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var titleText: some View {
        if scrollsTitle {
            MarqueeText(text: title, fitsIntrinsicWidth: true)
        } else {
            Text(title)
                .truncationMode(.tail)
        }
    }
}

/// 카드를 정확히 좌우 50:50으로 나눈 두 개의 투명 버튼.
private struct HomeMusicStripCardHalves: View {
    let leadingLabel: String
    let trailingLabel: String
    let onLeading: () -> Void
    let onTrailing: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onLeading) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(leadingLabel)

            Button(action: onTrailing) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(trailingLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

#if targetEnvironment(macCatalyst)
private struct MusicChannelReorderDropDelegate: DropDelegate {
    let destinationIndex: Int
    @Binding var draggingChannelID: String?
    let onMove: (String, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingChannelID, !draggingChannelID.isEmpty else { return }
        onMove(draggingChannelID, destinationIndex)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingChannelID = nil
        return true
    }
}
#endif

private struct ExternalMusicPanel: View {
    let service: ExternalMusicService
    let isActive: Bool
    let playbackState: ExternalMusicPlaybackState
    let trackTitle: String?
    let isDimmed: Bool
    let dimmedIntensity: Double
    let renderedScale: Double
    let drawsSurface: Bool
    let onToggle: () -> Void
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            VStack(spacing: 2) {
                Image(systemName: service.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)
                Text(statusText)
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundStyle(.white.opacity(isDimmed ? 0.40 : 0.52))
                    .lineLimit(1)
            }
            .frame(width: 36)

            MarqueeText(text: displayTitle)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 11)
        .frame(width: InternetRadioPanelMetrics.width, height: InternetRadioPanelMetrics.height)
        .background {
            if drawsSurface {
                FlipPanelSurface(
                    isDimmed: isDimmed,
                    cornerRadius: InternetRadioPanelMetrics.cornerRadius,
                    splitGap: 2
                )
            }
        }
        .frame(
            width: InternetRadioPanelMetrics.interactionSize(renderedScale: renderedScale).width,
            height: InternetRadioPanelMetrics.interactionSize(renderedScale: renderedScale).height
        )
        .foregroundStyle(.white.opacity(isDimmed ? 0.46 : 0.78))
        .opacity(isDimmed ? min(1, max(0, dimmedIntensity)) : 1)
        .contentShape(Rectangle())
        .highPriorityGesture(
            LongPressGesture(minimumDuration: 0.8, maximumDistance: 12)
                .exclusively(before: TapGesture())
                .onEnded { result in
                    switch result {
                    case .first(true):
                        onEnd()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    case .second:
                        onToggle()
                    default:
                        break
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(service.displayName), 음악 듣기 모드")
        .accessibilityHint("두 번 탭하면 S.tand 안에서 재생 또는 일시 정지하고, 길게 누르면 음악 듣기 모드를 끝냅니다")
        .accessibilityAction { onToggle() }
        .accessibilityAction(named: Text("음악 듣기 모드 끝내기"), onEnd)
    }

    private var statusText: String {
        guard isActive else { return "대기 중" }
        return switch playbackState {
        case .loading: "준비 중"
        case .playing: "재생 중"
        case .paused: "일시 정지"
        case .idle, .unavailable: "대기 중"
        }
    }

    private var displayTitle: String {
        guard isActive, let trackTitle, !trackTitle.isEmpty else { return service.displayName }
        return trackTitle
    }
}

private struct MarqueeTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MarqueeText: View {
    let text: String
    /// true면 텍스트의 고유 폭(가용 폭 이내)만 차지해 옆 아이콘과 함께 가운데 정렬할 수 있다.
    var fitsIntrinsicWidth = false
    @State private var contentWidth: CGFloat = 0
    @State private var animationStartedAt = Date()

    var body: some View {
        if fitsIntrinsicWidth {
            // 숨긴 Text가 고유 폭(넘치면 가용 폭)을 잡고 그 위에서 마퀴가 흐른다.
            Text(text)
                .lineLimit(1)
                .hidden()
                .overlay { scrollingText }
                .accessibilityLabel(text)
        } else {
            scrollingText
        }
    }

    private var scrollingText: some View {
        GeometryReader { proxy in
            TimelineView(
                .animation(
                    minimumInterval: 1 / 30,
                    paused: UICatalogLaunch.disablesAnimations
                )
            ) { timeline in
                let overflow = max(0, contentWidth - proxy.size.width)
                let travelDuration = max(2.5, Double(overflow / 22))
                let cycleDuration = travelDuration + 2
                let elapsed = timeline.date.timeIntervalSince(animationStartedAt)
                    .truncatingRemainder(dividingBy: cycleDuration)
                let progress = min(1, max(0, (elapsed - 1) / travelDuration))

                Text(text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .background {
                        GeometryReader { textProxy in
                            Color.clear.preference(
                                key: MarqueeTextWidthKey.self,
                                value: textProxy.size.width
                            )
                        }
                    }
                    .offset(x: overflow > 0 ? -overflow * progress : 0)
                    // GeometryReader always places its single child at .topLeading,
                    // so the text must be re-centered explicitly within its bounds.
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .clipped()
        .onPreferenceChange(MarqueeTextWidthKey.self) { contentWidth = $0 }
        .onChange(of: text) { _, _ in animationStartedAt = .now }
        .accessibilityLabel(text)
    }
}

enum MateLockPresentationPolicy {
    static let backgroundOpacity = 0.68
    static let borderOpacity = 0.12
    static let foregroundOpacity = 0.35

    static func isVisible(
        modePreference: StandModePreference,
        experienceMode: StandExperienceMode
    ) -> Bool {
        modePreference == .mate && experienceMode != .startled
    }
}

private struct MateModeLockOverlay: View {
    let isPortrait: Bool

    var body: some View {
        let size: CGFloat = isPortrait ? 92 : 116

        ZStack {
            Circle()
                .fill(.black.opacity(MateLockPresentationPolicy.backgroundOpacity))
            Circle()
                .stroke(.white.opacity(MateLockPresentationPolicy.borderOpacity), lineWidth: 2)
            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.66, weight: .bold))
                .foregroundStyle(.white.opacity(MateLockPresentationPolicy.foregroundOpacity))
                .accessibilityHidden(true)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("매이트 모드 잠금")
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
        guard configuration != nil else { return "라디오 주소 등록" }
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

                TimelineView(
                    .animation(
                        minimumInterval: 1 / 30,
                        paused: overflow <= 0 || UICatalogLaunch.disablesAnimations
                    )
                ) { context in
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
    @Binding var clockFont: ClockFontChoice
    let hourMode: ClockHourMode
    let batteryText: String
    let batterySystemImage: String
    let onReset: () -> Void
    let onSave: () -> Void
    @State private var showFontPalette = false

    var body: some View {
        GeometryReader { proxy in
            let usesPhoneLandscapeSideControls = PhoneLandscapeSideControlsPolicy.isEnabled(
                isPortrait: isPortrait
            )
            let editingInsets = PanelEditingPolicy.editingRegion(
                canvasSize: proxy.size,
                safeAreaInsets: proxy.safeAreaInsets,
                isPortrait: isPortrait,
                fontPaletteVisible: showFontPalette,
                controlOrder: usesPhoneLandscapeSideControls ? nil : layout.controlOrder,
                bottomAvailableWidth: max(
                    0,
                    proxy.size.width - StandControlLayoutMetrics.rowSpacing * 2
                ),
                reservesBottomControlRow: !usesPhoneLandscapeSideControls,
                reservesPhoneLandscapeTopRow: usesPhoneLandscapeSideControls
            ).insets

            ZStack {
                Color.black.opacity(0.32).ignoresSafeArea()

                Rectangle().fill(.white.opacity(0.16)).frame(width: 0.5)
                Rectangle().fill(.white.opacity(0.16)).frame(height: 0.5)

                EditablePanel(
                    transform: $layout.clock,
                    canvasSize: proxy.size,
                    editingInsets: editingInsets,
                    clampsOnAppearance: isPortrait,
                    accessibilityName: "시계 패널",
                    onTap: { showFontPalette.toggle() }
                ) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        FlipClockFace(
                            date: UICatalogLaunch.fixedDate ?? context.date,
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
                    canvasSize: proxy.size,
                    editingInsets: editingInsets,
                    clampsOnAppearance: isPortrait,
                    accessibilityName: "초 패널"
                ) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ClockSecondsPanel(
                            date: UICatalogLaunch.fixedDate ?? context.date,
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
                    canvasSize: proxy.size,
                    editingInsets: editingInsets
                )

                EditablePanel(
                    transform: $layout.date,
                    canvasSize: proxy.size,
                    editingInsets: editingInsets,
                    clampsOnAppearance: isPortrait,
                    accessibilityName: "날짜 패널"
                ) {
                    StandDatePanel(date: .now, isPortrait: isPortrait)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.08), in: Capsule())
                }

                EditablePanel(
                    transform: $layout.battery,
                    canvasSize: proxy.size,
                    editingInsets: editingInsets,
                    clampsOnAppearance: isPortrait,
                    accessibilityName: "배터리 패널"
                ) {
                    Label(batteryText, systemImage: batterySystemImage)
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
                } else if isPortrait {
                    VStack {
                        Spacer()
                        Label(
                            "패널 이동·크기 조절 · 시계를 눌러 글꼴 선택",
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
    private func editableWeatherPanels(
        canvasSize: CGSize,
        editingInsets: EdgeInsets
    ) -> some View {
        let groupIDs = Array(Set(layout.weatherGroupIDs)).sorted()
        ForEach(groupIDs, id: \.self) { groupID in
            let pieces = WeatherPiece.allCases.filter {
                layout.weatherGroupIDs[$0.rawValue] == groupID
            }
            EditablePanel(
                transform: weatherBinding(for: groupID),
                canvasSize: canvasSize,
                editingInsets: editingInsets,
                clampsOnAppearance: isPortrait,
                accessibilityName: "날씨 패널",
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
    @State private var confirmsDeletion = false

    let configuration: InternetRadioConfiguration?
    let accent: Color
    let isSharedImport: Bool
    let allowsDeletion: Bool
    let onSave: (InternetRadioConfiguration) -> Bool
    let onDelete: () -> Void
    let onCancel: () -> Void

    init(
        configuration: InternetRadioConfiguration?,
        accent: Color = .orange,
        isSharedImport: Bool = false,
        allowsDeletion: Bool? = nil,
        onSave: @escaping (InternetRadioConfiguration) -> Bool,
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
                    TextField("http:// 또는 https://…", text: $address)
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
                            confirmsDeletion = true
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
            .confirmationDialog(
                "이 채널을 삭제할까요?",
                isPresented: $confirmsDeletion,
                titleVisibility: .visible
            ) {
                Button("채널 삭제", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("삭제한 채널 주소는 되돌릴 수 없습니다.")
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSharedImport)
    }

    private var radioInformationFooter: String {
        "직접 이용 권한을 확인한 HTTP 또는 HTTPS 스트림 주소만 등록해 주세요. HTTP 주소는 암호화되지 않습니다. 주소는 이 기기에만 저장되며 방송을 저장하거나 중계하지 않습니다."
    }

    private func save() {
        do {
            let configuration = try InternetRadioConfiguration(
                id: configuration?.id ?? UUID(),
                displayName: displayName,
                urlString: address
            )
            guard onSave(configuration) else {
                throw InternetRadioConfigurationError.channelLimitReached
            }
            validationMessage = nil
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
        bottomControlAreaHeight: CGFloat? = nil,
        reservesBottomControlRow: Bool = true,
        reservesPhoneLandscapeTopRow: Bool = false
    ) -> EdgeInsets {
        let topOuterPadding: CGFloat = isPortrait ? 18 : 14
        let topGuideClearance: CGFloat = isPortrait ? 12 : 2
        let bottomOuterPadding = StandControlLayoutMetrics.bottomPadding(isPortrait: isPortrait)
        let bottomGuideClearance: CGFloat = isPortrait ? 6 : 2
        let bottomRowCount: CGFloat = isPortrait ? 2 : 1
        let defaultBottomRowsHeight = StandControlLayoutMetrics.itemHeight * bottomRowCount
            + StandControlLayoutMetrics.rowSpacing * max(0, bottomRowCount - 1)
        let controlAreaHeight = reservesBottomControlRow
            ? (bottomControlAreaHeight ?? defaultBottomRowsHeight)
            : 0
        let controlBoundary = safeAreaInsets.bottom
            + bottomOuterPadding
            + controlAreaHeight
            + bottomGuideClearance

        let paletteHeight: CGFloat = isPortrait ? 190 : 126
        let paletteBottomPadding: CGFloat = isPortrait ? 22 : 14
        let paletteGuideClearance: CGFloat = isPortrait ? 8 : 2
        let fontPaletteBoundary = safeAreaInsets.bottom
            + paletteBottomPadding
            + paletteHeight
            + paletteGuideClearance

        let phoneLandscapeTopRowHeight = reservesPhoneLandscapeTopRow
            ? InternetRadioPanelMetrics.height + 8
            : 0

        return EdgeInsets(
            top: safeAreaInsets.top
                + topOuterPadding
                + StandControlLayoutMetrics.editorToolbarHeight
                + topGuideClearance
                + phoneLandscapeTopRowHeight,
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
        reservesEditorChrome: Bool = true,
        reservesBottomControlRow: Bool = true,
        reservesPhoneLandscapeTopRow: Bool = false
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
            bottomControlAreaHeight: controlAreaHeight,
            reservesBottomControlRow: reservesBottomControlRow,
            reservesPhoneLandscapeTopRow: reservesPhoneLandscapeTopRow
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
        proposed
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
    let editingInsets: EdgeInsets
    var clampsOnAppearance = true
    var accessibilityName = "편집 패널"
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
                        clampTransformToEditingArea()
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
                if clampsOnAppearance { clampTransformToEditingArea() }
            }
            .onChange(of: editingInsets) { _, _ in
                if clampsOnAppearance { clampTransformToEditingArea() }
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
                        let rawX = start.x + value.translation.width / canvasSize.width
                        let rawY = start.y + value.translation.height / canvasSize.height
                        let renderedSize = CGSize(
                            width: max(44, panelSize.width * transform.scale),
                            height: max(44, panelSize.height * transform.scale)
                        )
                        let clampedCenter = PanelEditingPolicy.clampedCenter(
                            CGPoint(
                                x: canvasSize.width / 2 + rawX * canvasSize.width,
                                y: canvasSize.height / 2 + rawY * canvasSize.height
                            ),
                            panelSize: renderedSize,
                            canvasSize: canvasSize,
                            insets: editingInsets
                        )
                        let proposedX = (clampedCenter.x - canvasSize.width / 2) / canvasSize.width
                        let proposedY = (clampedCenter.y - canvasSize.height / 2) / canvasSize.height
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
                        clampTransformToEditingArea()
                    }
                    .onEnded { _ in scaleStart = nil }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityName)
            .accessibilityValue("크기 \(Int((transform.scale * 100).rounded()))퍼센트")
            .accessibilityHint("동작 메뉴로 패널을 이동하고 위아래로 쓸어 크기를 조절합니다")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    transform.scale = min(
                        PanelEditingPolicy.maximumPanelScale,
                        transform.scale + 0.1
                    )
                case .decrement:
                    transform.scale = max(
                        PanelEditingPolicy.minimumPanelScale,
                        transform.scale - 0.1
                    )
                @unknown default:
                    return
                }
                clampTransformToEditingArea()
                onEnded()
                UISelectionFeedbackGenerator().selectionChanged()
            }
            .accessibilityAction(named: Text("위로 이동")) {
                moveForAccessibility(x: 0, y: -1)
            }
            .accessibilityAction(named: Text("아래로 이동")) {
                moveForAccessibility(x: 0, y: 1)
            }
            .accessibilityAction(named: Text("왼쪽으로 이동")) {
                moveForAccessibility(x: -1, y: 0)
            }
            .accessibilityAction(named: Text("오른쪽으로 이동")) {
                moveForAccessibility(x: 1, y: 0)
            }
            .accessibilityAction(named: Text("패널 열기")) {
                onTap?()
            }
    }

    private func moveForAccessibility(x: Double, y: Double) {
        let step: Double = 0.05
        transform.x += x * step
        transform.y += y * step
        clampTransformToEditingArea()
        onEnded()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func clampTransformToEditingArea() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let renderedSize = CGSize(
            width: max(44, panelSize.width * transform.scale),
            height: max(44, panelSize.height * transform.scale)
        )
        let center = PanelEditingPolicy.clampedCenter(
            CGPoint(
                x: canvasSize.width / 2 + transform.x * canvasSize.width,
                y: canvasSize.height / 2 + transform.y * canvasSize.height
            ),
            panelSize: renderedSize,
            canvasSize: canvasSize,
            insets: editingInsets
        )
        transform.x = (center.x - canvasSize.width / 2) / canvasSize.width
        transform.y = (center.y - canvasSize.height / 2) / canvasSize.height
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
        Label(levelText, systemImage: status.systemImage)
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

    private var accessibilityText: String {
        status.isCharging ? "배터리 \(levelText), 충전 중" : "배터리 \(levelText)"
    }
}

/// 잠소리·보이소·설정 카드가 공유하는 2행 본문(아이콘+제목 / 상태)과 타일 표면.
private struct HomeSharedControlCardBody<Icon: View>: View {
    let title: String
    let status: String
    let size: CGSize
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(spacing: HomeSharedControlMetrics.rowGap) {
            HStack(spacing: HomeSharedControlMetrics.iconTitleGap) {
                icon()
                    .frame(
                        width: HomeSharedControlMetrics.iconSize,
                        height: HomeSharedControlMetrics.iconSize
                    )
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: HomeSharedControlMetrics.titleFontSize, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: HomeSharedControlMetrics.titleLineHeight)
            }
            .frame(maxWidth: .infinity)

            Text(status)
                .font(.system(size: HomeSharedControlMetrics.statusFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.52))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(height: HomeSharedControlMetrics.statusLineHeight)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white.opacity(StandControlLayoutMetrics.foregroundOpacity))
        .padding(HomeSharedControlMetrics.padding)
        .frame(width: size.width, height: size.height)
        .background {
            FlipPanelSurface(
                isDimmed: false,
                cornerRadius: HomeSharedControlMetrics.cornerRadius,
                splitGap: HomeSharedControlMetrics.splitGap
            )
        }
        .opacity(StandControlLayoutMetrics.tileOpacity)
    }
}

private struct HomeSharedControlSymbolIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: HomeSharedControlMetrics.iconSize, weight: .semibold))
    }
}

private struct HomeSharedControlCard<Icon: View>: View {
    let title: String
    let status: String
    let size: CGSize
    var hint: String? = nil
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HomeSharedControlCardBody(title: title, status: status, size: size, icon: icon)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(status)
        .accessibilityHint(hint ?? "")
    }
}

private struct BoyisoHomeSharedControlCard: View {
    let title: String
    let status: String
    let size: CGSize
    let tap: () -> Void
    let longPress: () -> Void

    var body: some View {
        HomeSharedControlCardBody(title: title, status: status, size: size) {
            BoyisoBabyFaceIcon(lineWidth: 1.35)
        }
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: 0.7, maximumDistance: 12)
                .exclusively(before: TapGesture())
                .onEnded { result in
                    switch result {
                    case .first(true): longPress()
                    case .second: tap()
                    default: break
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(BoyisoBranding.representativeIconAccessibilityLabel), \(status)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "기본 동작", tap)
        .accessibilityAction(named: "\(BoyisoBranding.primaryName) 설정 열기", longPress)
    }
}

enum BoyisoOverlayKind: Equatable {
    case greeting, soundDetected, walkieCall

    var imageName: String { self == .soundDetected ? "BoyisoCryingChild" : "BoyisoGreeting" }
    var isHighSalience: Bool { self != .greeting }
    var primaryMessage: String {
        switch self {
        case .greeting: "같은 공간에서 인사가 왔어요"
        case .soundDetected: "말할 사람의 소리가 감지되었습니다."
        case .walkieCall: "무전기 호출이 왔어요"
        }
    }
    func accessibilityLabel(sender: String) -> String {
        guard !sender.isEmpty else { return primaryMessage }
        switch self {
        case .greeting: return "\(sender)님의 인사"
        case .soundDetected: return "\(primaryMessage) 보낸 기기, \(sender)"
        case .walkieCall: return "\(sender)님의 무전기 호출"
        }
    }
}

enum BoyisoReactionPolicy {
    static func chimeCount(for event: BoyisoEvent) -> Int {
        if event.kind == .toktok { return 1 }
        if event.kind == .walkie { return 2 }
        return event.isCryingSound ? 2 : 0
    }
}

enum BoyisoEventBannerPolicy {
    static let displayDurationSeconds: Double = 5

    static func shouldDismiss(displayedEventID: UUID?, timerEventID: UUID) -> Bool {
        displayedEventID == timerEventID
    }
}

private struct BoyisoGreetingOverlay: View {
    let sender: String
    let kind: BoyisoOverlayKind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            (kind.isHighSalience ? Color(red: 1, green: 0.93, blue: 0.72) : Color.black.opacity(0.78))
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image(kind.imageName)
                    .resizable().scaledToFit().frame(maxWidth: 320, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                VStack(spacing: 7) {
                    Text(kind.primaryMessage)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    if !sender.isEmpty {
                        Text(kind == .greeting ? "\(sender)님의 인사" : "보낸 기기 · \(sender)")
                            .font(.headline)
                            .opacity(0.72)
                    }
                }
                .foregroundStyle(kind.isHighSalience ? Color.black.opacity(0.86) : .white)
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(
                    kind.isHighSalience ? Color.white.opacity(0.9) : Color.white.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
            .padding(28)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4), value: sender)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.accessibilityLabel(sender: sender))
        .allowsHitTesting(false)
    }
}
