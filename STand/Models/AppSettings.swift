import Combine
import Foundation
import SwiftUI

enum ClockFontChoice: String, Codable, CaseIterable, Identifiable {
    case systemRounded
    case pretendard
    case kakaoBigSans
    case nanumGothic
    case tenada
    case blackHanSans
    case doHyeon
    case paperlogyBold
    case nexonLv1Gothic
    case poppins

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemRounded: "시스템 둥근체"
        case .pretendard: "프리텐다드"
        case .kakaoBigSans: "카카오 Big Sans"
        case .nanumGothic: "나눔고딕"
        case .tenada: "태나다"
        case .blackHanSans: "검은고딕"
        case .doHyeon: "도현"
        case .paperlogyBold: "페이퍼로지 Bold"
        case .nexonLv1Gothic: "넥슨 Lv.1 고딕"
        case .poppins: "Poppins"
        }
    }

    var postScriptName: String? {
        switch self {
        case .systemRounded: nil
        case .pretendard: "Pretendard-Regular"
        case .kakaoBigSans: "KakaoBigSans-Regular"
        case .nanumGothic: "NanumGothic"
        case .tenada: "Tenada"
        case .blackHanSans: "BlackHanSans-Regular"
        case .doHyeon: "DoHyeon-Regular"
        case .paperlogyBold: "Paperlogy-7Bold"
        case .nexonLv1Gothic: "NEXONLv1GothicRegular"
        case .poppins: "Poppins-Regular"
        }
    }

    var licenseFilename: String? {
        switch self {
        case .systemRounded: nil
        case .pretendard: "Pretendard-LICENSE"
        case .kakaoBigSans: "KakaoBigSans-OFL"
        case .nanumGothic: "NanumGothic-OFL"
        case .tenada: "Tenada-LICENSE"
        case .blackHanSans: "BlackHanSans-OFL"
        case .doHyeon: "DoHyeon-OFL"
        case .paperlogyBold: "Paperlogy-OFL"
        case .nexonLv1Gothic: "NEXONLv1Gothic-LICENSE"
        case .poppins: "Poppins-OFL"
        }
    }

    func font(size: CGFloat) -> Font {
        guard let postScriptName else {
            return .system(size: size, weight: .thin, design: .rounded)
        }
        return .custom(postScriptName, size: size)
    }

    func clockVerticalOffset(size: CGFloat) -> CGFloat {
        let adjustmentAt64Points: CGFloat = switch self {
        case .systemRounded: -1.5
        case .pretendard: 0
        case .kakaoBigSans: -3
        case .nanumGothic: 1.5
        case .tenada: 8
        case .blackHanSans: 1.5
        case .doHyeon: 2.5
        case .paperlogyBold: 0
        case .nexonLv1Gothic: 3.5
        case .poppins: 0.5
        }
        return adjustmentAt64Points * size / 64
    }
}

enum OrientationPreference: String, Codable, CaseIterable, Identifiable {
    case automatic
    case portrait
    case landscape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "기기 설정 따르기"
        case .portrait: "세로 고정"
        case .landscape: "가로 고정"
        }
    }

    var systemImage: String {
        switch self {
        case .automatic: "rectangle.rotate"
        case .portrait: "rectangle.portrait"
        case .landscape: "rectangle"
        }
    }
}

enum ClockHourMode: String, Codable, CaseIterable {
    case twelve
    case twentyFour

    mutating func toggle() {
        self = self == .twelve ? .twentyFour : .twelve
    }
}

enum StandDisplayTheme: String, Codable, CaseIterable {
    case color
    case grayscale

    mutating func toggle() {
        self = self == .color ? .grayscale : .color
    }
}

struct PanelTransform: Codable, Equatable {
    var x: Double
    var y: Double
    var scale: Double

    init(x: Double, y: Double, scale: Double = 1) {
        self.x = x
        self.y = y
        self.scale = scale
    }
}

enum StandControlKind: String, Codable, CaseIterable, Identifiable {
    case flashlight
    case brightness
    case stopDetection
    case orientation
    case recordings
    case aiShot
    case settings

    var id: String { rawValue }

    static let defaultOrder: [StandControlKind] = [
        .flashlight,
        .brightness,
        .stopDetection,
        .orientation,
        .recordings,
        .aiShot,
        .settings
    ]

    static func normalizedOrder(_ order: [StandControlKind]?) -> [StandControlKind] {
        var result: [StandControlKind] = []
        for kind in (order ?? []) + defaultOrder where !result.contains(kind) {
            result.append(kind)
        }
        return result
    }
}

struct StandScreenLayout: Codable, Equatable {
    var clock: PanelTransform
    var weatherIcon: PanelTransform
    var weatherTemperature: PanelTransform
    var weatherCondition: PanelTransform
    var date: PanelTransform
    var status: PanelTransform
    var brightnessRule: PanelTransform
    var battery: PanelTransform
    var weatherGroupIDs: [Int]
    var controlOrder: [StandControlKind]

    init(
        clock: PanelTransform = .init(x: 0, y: 0),
        weatherIcon: PanelTransform,
        weatherTemperature: PanelTransform,
        weatherCondition: PanelTransform,
        date: PanelTransform,
        status: PanelTransform,
        brightnessRule: PanelTransform,
        battery: PanelTransform = .init(x: 0, y: 0.18),
        weatherGroupIDs: [Int],
        controlOrder: [StandControlKind] = StandControlKind.defaultOrder
    ) {
        self.clock = clock
        self.weatherIcon = weatherIcon
        self.weatherTemperature = weatherTemperature
        self.weatherCondition = weatherCondition
        self.date = date
        self.status = status
        self.brightnessRule = brightnessRule
        self.battery = battery
        self.weatherGroupIDs = weatherGroupIDs
        self.controlOrder = StandControlKind.normalizedOrder(controlOrder)
    }

    private enum CodingKeys: String, CodingKey {
        case clock
        case weatherIcon, weatherTemperature, weatherCondition
        case date, status, brightnessRule, battery, weatherGroupIDs, controlOrder
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clock = try values.decodeIfPresent(PanelTransform.self, forKey: .clock)
            ?? .init(x: 0, y: 0)
        weatherIcon = try values.decode(PanelTransform.self, forKey: .weatherIcon)
        weatherTemperature = try values.decode(PanelTransform.self, forKey: .weatherTemperature)
        weatherCondition = try values.decode(PanelTransform.self, forKey: .weatherCondition)
        date = try values.decode(PanelTransform.self, forKey: .date)
        status = try values.decode(PanelTransform.self, forKey: .status)
        brightnessRule = try values.decode(PanelTransform.self, forKey: .brightnessRule)
        battery = try values.decodeIfPresent(PanelTransform.self, forKey: .battery)
            ?? .init(x: 0, y: 0.18)
        weatherGroupIDs = try values.decode([Int].self, forKey: .weatherGroupIDs)
        let rawControlOrder = try? values.decode([String].self, forKey: .controlOrder)
        controlOrder = StandControlKind.normalizedOrder(
            rawControlOrder?.compactMap(StandControlKind.init(rawValue:))
        )
    }

    static let portrait = StandScreenLayout(
        clock: .init(x: 0, y: 0),
        weatherIcon: .init(x: 0, y: -0.22811053984575841, scale: 0.86922719107523572),
        weatherTemperature: .init(x: 0, y: -0.22811053984575841, scale: 0.86922719107523572),
        weatherCondition: .init(x: 0, y: -0.22811053984575841, scale: 0.86922719107523572),
        date: .init(x: 0, y: 0.10),
        status: .init(x: 0, y: 0.15),
        brightnessRule: .init(x: 0, y: 0.21),
        battery: .init(x: 0, y: 0.20698371893744649),
        weatherGroupIDs: [1, 1, 1]
    )

    static let landscape = StandScreenLayout(
        clock: .init(x: 0, y: 0.044502617801047181, scale: 1.2810187063251741),
        weatherIcon: .init(x: 0, y: -0.26890924956369971, scale: 0.68640335461830571),
        weatherTemperature: .init(x: 0, y: -0.26890924956369971, scale: 0.68640335461830571),
        weatherCondition: .init(x: 0, y: -0.26890924956369971, scale: 0.68640335461830571),
        date: .init(x: -0.17822222222222225, y: -0.10184991273996505),
        status: .init(x: 0, y: 0.36518324607329838),
        brightnessRule: .init(x: 0, y: 0.32),
        battery: .init(x: 0, y: 0.27773123909249542),
        weatherGroupIDs: [1, 1, 1]
    )
}

struct AppSettings: Codable, Equatable {
    var lampIntensity = 0.72
    var silhouetteIntensity = 0.05
    var clockScale = 1.0
    var clockFont = ClockFontChoice.tenada
    var clockHourMode = ClockHourMode.twelve
    var displayTheme = StandDisplayTheme.color
    var portraitLayout = StandScreenLayout.portrait
    var landscapeLayout = StandScreenLayout.landscape
    var brightnessModeThreshold = 0.35
    var holdDuration = 60.0
    var fadeDuration = 30.0
    var automaticDimmingEnabled = true
    var preventAutoDimmingWhenScreenBright = true
    var soundThresholdDB: Float = -36
    var recordingEnabled = true
    var orientationPreference: OrientationPreference = .automatic
    var torchEnabled = true
    var torchIntensity = 0.25
    var wakeOnSleepSound = false
    var multiStimulusWakeEnabled = true

    static let recommended = AppSettings()

    init(
        lampIntensity: Double = 0.72,
        silhouetteIntensity: Double = 0.05,
        clockScale: Double = 1,
        clockFont: ClockFontChoice = .tenada,
        clockHourMode: ClockHourMode = .twelve,
        displayTheme: StandDisplayTheme = .color,
        portraitLayout: StandScreenLayout = .portrait,
        landscapeLayout: StandScreenLayout = .landscape,
        brightnessModeThreshold: Double = 0.35,
        holdDuration: Double = 60,
        fadeDuration: Double = 30,
        automaticDimmingEnabled: Bool = true,
        preventAutoDimmingWhenScreenBright: Bool = true,
        soundThresholdDB: Float = -36,
        recordingEnabled: Bool = true,
        orientationPreference: OrientationPreference = .automatic,
        torchEnabled: Bool = true,
        torchIntensity: Double = 0.25,
        wakeOnSleepSound: Bool = false,
        multiStimulusWakeEnabled: Bool = true
    ) {
        self.lampIntensity = lampIntensity
        self.silhouetteIntensity = silhouetteIntensity
        self.clockScale = clockScale
        self.clockFont = clockFont
        self.clockHourMode = clockHourMode
        self.displayTheme = displayTheme
        self.portraitLayout = portraitLayout
        self.landscapeLayout = landscapeLayout
        self.brightnessModeThreshold = brightnessModeThreshold
        self.holdDuration = holdDuration
        self.fadeDuration = fadeDuration
        self.automaticDimmingEnabled = automaticDimmingEnabled
        self.preventAutoDimmingWhenScreenBright = preventAutoDimmingWhenScreenBright
        self.soundThresholdDB = soundThresholdDB
        self.recordingEnabled = recordingEnabled
        self.orientationPreference = orientationPreference
        self.torchEnabled = torchEnabled
        self.torchIntensity = torchIntensity
        self.wakeOnSleepSound = wakeOnSleepSound
        self.multiStimulusWakeEnabled = multiStimulusWakeEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case lampIntensity
        case silhouetteIntensity
        case clockScale
        case clockFont
        case clockHourMode
        case displayTheme
        case portraitLayout
        case landscapeLayout
        case brightnessModeThreshold
        case holdDuration
        case fadeDuration
        case automaticDimmingEnabled
        case preventAutoDimmingWhenScreenBright
        case soundThresholdDB
        case recordingEnabled
        case orientationPreference
        case torchEnabled
        case torchIntensity
        case wakeOnSleepSound
        case multiStimulusWakeEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lampIntensity = try container.decodeIfPresent(Double.self, forKey: .lampIntensity) ?? 0.72
        silhouetteIntensity = try container.decodeIfPresent(
            Double.self,
            forKey: .silhouetteIntensity
        ) ?? 0.05
        clockScale = min(1.35, max(
            0.7,
            try container.decodeIfPresent(Double.self, forKey: .clockScale) ?? 1
        ))
        clockFont = try container.decodeIfPresent(
            ClockFontChoice.self,
            forKey: .clockFont
        ) ?? .tenada
        clockHourMode = try container.decodeIfPresent(
            ClockHourMode.self,
            forKey: .clockHourMode
        ) ?? .twelve
        displayTheme = try container.decodeIfPresent(
            StandDisplayTheme.self,
            forKey: .displayTheme
        ) ?? .color
        portraitLayout = try container.decodeIfPresent(
            StandScreenLayout.self,
            forKey: .portraitLayout
        ) ?? .portrait
        landscapeLayout = try container.decodeIfPresent(
            StandScreenLayout.self,
            forKey: .landscapeLayout
        ) ?? .landscape
        brightnessModeThreshold = min(1, max(
            0,
            try container.decodeIfPresent(Double.self, forKey: .brightnessModeThreshold) ?? 0.35
        ))
        holdDuration = min(300, max(
            10,
            try container.decodeIfPresent(Double.self, forKey: .holdDuration) ?? 60
        ))
        fadeDuration = try container.decodeIfPresent(Double.self, forKey: .fadeDuration) ?? 30
        automaticDimmingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticDimmingEnabled
        ) ?? true
        preventAutoDimmingWhenScreenBright = try container.decodeIfPresent(
            Bool.self,
            forKey: .preventAutoDimmingWhenScreenBright
        ) ?? true
        soundThresholdDB = try container.decodeIfPresent(Float.self, forKey: .soundThresholdDB) ?? -36
        recordingEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordingEnabled) ?? true
        orientationPreference = try container.decodeIfPresent(
            OrientationPreference.self,
            forKey: .orientationPreference
        ) ?? .automatic
        torchEnabled = try container.decodeIfPresent(Bool.self, forKey: .torchEnabled) ?? true
        torchIntensity = try container.decodeIfPresent(Double.self, forKey: .torchIntensity) ?? 0.25
        wakeOnSleepSound = try container.decodeIfPresent(Bool.self, forKey: .wakeOnSleepSound) ?? false
        multiStimulusWakeEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .multiStimulusWakeEnabled
        ) ?? true
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var value: AppSettings {
        didSet { save() }
    }

    private let defaults: UserDefaults
    private let storageKey = "appSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        guard
            let data = defaults.data(forKey: storageKey),
            let saved = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            value = .recommended
            return
        }

        value = saved
    }

    func restoreRecommendedValues() {
        value = .recommended
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0.10.0"
    }

    static var display: String { "\(marketing) (\(build))" }
}
