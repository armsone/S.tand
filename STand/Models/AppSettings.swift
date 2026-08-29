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
    case midnight
    case sage

    mutating func toggle() {
        let themes = Self.allCases
        let index = themes.firstIndex(of: self) ?? 0
        self = themes[(index + 1) % themes.count]
    }

    var title: String {
        switch self {
        case .color: "오렌지"
        case .grayscale: "그레이"
        case .midnight: "미드나이트"
        case .sage: "세이지"
        }
    }

    var accentColor: Color {
        switch self {
        case .color: .orange
        case .grayscale: .white
        case .midnight: Color(red: 0.38, green: 0.68, blue: 1.0)
        case .sage: Color(red: 0.55, green: 0.78, blue: 0.62)
        }
    }
}

enum StandModePreference: String, Codable, CaseIterable, Identifiable {
    case automatic
    case object
    case mate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "자동"
        case .object: "오브제 유지"
        case .mate: "매이트 유지"
        }
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
    // Decoding-only legacy value. It is intentionally excluded from defaultOrder.
    case stopDetection
    case recordings
    case boyiso
    case settings

    var id: String { rawValue }

    static let defaultOrder: [StandControlKind] = [
        .recordings,
        .boyiso,
        .settings
    ]

    static func normalizedOrder(_ order: [StandControlKind]?) -> [StandControlKind] {
        var result: [StandControlKind] = []
        for kind in (order ?? []) + defaultOrder
        where defaultOrder.contains(kind) && !result.contains(kind) {
            result.append(kind)
        }
        return result
    }
}

struct StandScreenLayout: Codable, Equatable {
    static let defaultRadioPanelTransform = PanelTransform(
        x: 0.26,
        y: 0.215,
        scale: 0.75
    )
    static let defaultSecondaryRadioPanelTransform = PanelTransform(
        x: -0.26,
        y: 0.215,
        scale: 0.75
    )

    var clock: PanelTransform
    var seconds: PanelTransform
    var weatherIcon: PanelTransform
    var weatherTemperature: PanelTransform
    var weatherCondition: PanelTransform
    var date: PanelTransform
    var status: PanelTransform
    var brightnessRule: PanelTransform
    var battery: PanelTransform
    var radio: PanelTransform
    var secondaryRadio: PanelTransform
    var radiosGrouped: Bool
    var weatherGroupIDs: [Int]
    var controlOrder: [StandControlKind]

    init(
        clock: PanelTransform = .init(x: 0, y: 0),
        seconds: PanelTransform = .init(x: 0.27, y: 0.036),
        weatherIcon: PanelTransform,
        weatherTemperature: PanelTransform,
        weatherCondition: PanelTransform,
        date: PanelTransform,
        status: PanelTransform,
        brightnessRule: PanelTransform,
        battery: PanelTransform = .init(x: 0, y: 0.18),
        radio: PanelTransform = StandScreenLayout.defaultRadioPanelTransform,
        secondaryRadio: PanelTransform = StandScreenLayout.defaultSecondaryRadioPanelTransform,
        radiosGrouped: Bool = false,
        weatherGroupIDs: [Int],
        controlOrder: [StandControlKind] = StandControlKind.defaultOrder
    ) {
        self.clock = clock
        self.seconds = seconds
        self.weatherIcon = weatherIcon
        self.weatherTemperature = weatherTemperature
        self.weatherCondition = weatherCondition
        self.date = date
        self.status = status
        self.brightnessRule = brightnessRule
        self.battery = battery
        self.radio = radio
        self.secondaryRadio = secondaryRadio
        self.radiosGrouped = radiosGrouped
        self.weatherGroupIDs = weatherGroupIDs
        self.controlOrder = StandControlKind.normalizedOrder(controlOrder)
    }

    private enum CodingKeys: String, CodingKey {
        case clock, seconds
        case weatherIcon, weatherTemperature, weatherCondition
        case date, status, brightnessRule, battery, radio, secondaryRadio, radiosGrouped
        case weatherGroupIDs, controlOrder
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clock = try values.decodeIfPresent(PanelTransform.self, forKey: .clock)
            ?? .init(x: 0, y: 0)
        seconds = try values.decodeIfPresent(PanelTransform.self, forKey: .seconds)
            ?? .init(x: 0.27, y: 0.036)
        weatherIcon = try values.decode(PanelTransform.self, forKey: .weatherIcon)
        weatherTemperature = try values.decode(PanelTransform.self, forKey: .weatherTemperature)
        weatherCondition = try values.decode(PanelTransform.self, forKey: .weatherCondition)
        date = try values.decode(PanelTransform.self, forKey: .date)
        status = try values.decode(PanelTransform.self, forKey: .status)
        brightnessRule = try values.decode(PanelTransform.self, forKey: .brightnessRule)
        battery = try values.decodeIfPresent(PanelTransform.self, forKey: .battery)
            ?? .init(x: 0, y: 0.18)
        radio = try values.decodeIfPresent(PanelTransform.self, forKey: .radio)
            ?? StandScreenLayout.defaultRadioPanelTransform
        secondaryRadio = try values.decodeIfPresent(PanelTransform.self, forKey: .secondaryRadio)
            ?? StandScreenLayout.defaultSecondaryRadioPanelTransform
        radiosGrouped = try values.decodeIfPresent(Bool.self, forKey: .radiosGrouped) ?? false
        weatherGroupIDs = try values.decode([Int].self, forKey: .weatherGroupIDs)
        let rawControlOrder = try? values.decode([String].self, forKey: .controlOrder)
        controlOrder = StandControlKind.normalizedOrder(
            rawControlOrder?.compactMap(StandControlKind.init(rawValue:))
        )
    }

    static let portrait = StandScreenLayout(
        clock: .init(x: 0, y: 0, scale: 1.2919049397971205),
        seconds: .init(x: 0.33550580431177457, y: 0.05785089974293066),
        weatherIcon: .init(x: 0, y: -0.20497429305912612, scale: 0.8692271910752357),
        weatherTemperature: .init(x: 0, y: -0.20497429305912612, scale: 0.8692271910752357),
        weatherCondition: .init(x: 0, y: -0.20497429305912612, scale: 0.8692271910752357),
        date: .init(x: 0, y: 0.1179948586118252),
        status: .init(x: 0, y: 0.15),
        brightnessRule: .init(x: 0, y: 0.21),
        battery: .init(x: 0, y: 0.2069837189374465),
        radio: .init(x: 0, y: -0.31070694087403605, scale: 1.0476520613791829),
        secondaryRadio: .init(
            x: -0.17436152570480928,
            y: 0.31097257926306765,
            scale: 0.75
        ),
        radiosGrouped: true,
        weatherGroupIDs: [1, 1, 1],
        controlOrder: [.recordings, .boyiso, .settings]
    )

    static let landscape = StandScreenLayout(
        clock: .init(x: 0, y: 0.21553228621291443, scale: 1.112291215059065),
        seconds: .init(x: 0.19200000000000014, y: 0.2910122164048866, scale: 0.8205408216328642),
        weatherIcon: .init(x: 0, y: -0.06745200698080275, scale: 0.55),
        weatherTemperature: .init(x: 0, y: -0.06745200698080275, scale: 0.55),
        weatherCondition: .init(x: 0, y: -0.06745200698080275, scale: 0.55),
        date: .init(x: 0, y: 0.43815008726003507, scale: 0.85),
        status: .init(x: 0, y: 0.5),
        brightnessRule: .init(x: 0, y: 0.34),
        battery: .init(x: 0, y: 0.5245898778359511),
        radio: .init(x: 0.4, y: -0.3, scale: 0.75),
        secondaryRadio: .init(x: -0.4, y: -0.3, scale: 0.75),
        radiosGrouped: false,
        weatherGroupIDs: [1, 1, 1],
        controlOrder: [.recordings, .boyiso, .settings]
    )

    // Keep every device type on the same normalized landscape default captured
    // from the representative iPhone layout.
    static let phoneLandscape = landscape
}

struct HomeMusicChannelSelection: Codable, Equatable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case appleMusic
        case appleClassical
        case internetRadio
    }

    let kind: Kind
    let radioID: UUID?
    let radioSlot: Int?

    var id: String {
        switch kind {
        case .appleMusic: "appleMusic"
        case .appleClassical: "appleClassical"
        case .internetRadio:
            "internetRadio:\(radioSlot.map(String.init) ?? "legacy"):\(radioID?.uuidString ?? "empty")"
        }
    }

    static let appleMusic = Self(kind: .appleMusic, radioID: nil, radioSlot: nil)
    static let appleClassical = Self(kind: .appleClassical, radioID: nil, radioSlot: nil)

    static func internetRadio(_ id: UUID, slot: Int? = nil) -> Self {
        Self(kind: .internetRadio, radioID: id, radioSlot: slot)
    }

    static func emptyInternetRadio(slot: Int) -> Self {
        Self(kind: .internetRadio, radioID: nil, radioSlot: slot)
    }
}

struct AppSettings: Codable, Equatable {
    static let maximumInternetRadioChannelCount = 4
    static let defaultClockScale = 1.0059052830861586
    static let minimumClockScale = 0.7
    static let maximumClockScale = 3.0

    var lampIntensity = 0.72
    var silhouetteIntensity = 0.05
    var clockScale = Self.defaultClockScale
    var clockFont = ClockFontChoice.tenada
    var displayTheme = StandDisplayTheme.color
    var portraitLayout = StandScreenLayout.portrait
    var landscapeLayout = StandScreenLayout.landscape
    var brightnessModeThreshold = 0.4
    var holdDuration = 5.0
    var fadeDuration = 30.0
    var automaticDimmingEnabled = false
    var preventAutoDimmingWhenScreenBright = true
    var soundThresholdDB: Float = -36
    var recordingEnabled = true
    var soundSensingEnabled = true
    var torchEnabled = true
    var torchIntensity = 0.25
    var wakeOnSleepSound = false
    var multiStimulusWakeEnabled = true
    var modePreference = StandModePreference.automatic
    var cameraAmbientSensingEnabled = false
    var backgroundModeEnabled = false
    var weatherLocationEnabled = true
    private(set) var internetRadioChannels: [InternetRadioConfiguration] = []
    private(set) var selectedInternetRadioID: UUID?
    private(set) var secondaryInternetRadioID: UUID?
    private(set) var homeMusicChannels: [HomeMusicChannelSelection] = []

    /// The selected channel kept as a compatibility surface for the original
    /// single-station UI. New channel-management code should use the collection
    /// mutation methods below so adding a station does not replace this one.
    var internetRadio: InternetRadioConfiguration? {
        get {
            guard !internetRadioChannels.isEmpty else { return nil }
            if let selectedInternetRadioID,
               let selected = internetRadioChannels.first(where: { $0.id == selectedInternetRadioID }) {
                return selected
            }
            return internetRadioChannels.first
        }
        set {
            guard let newValue else {
                internetRadioChannels.removeAll()
                selectedInternetRadioID = nil
                secondaryInternetRadioID = nil
                return
            }

            if let existingIndex = internetRadioChannels.firstIndex(where: { $0.id == newValue.id }) {
                internetRadioChannels[existingIndex] = newValue
            } else if let selectedInternetRadioID,
                      let selectedIndex = internetRadioChannels.firstIndex(where: {
                          $0.id == selectedInternetRadioID
                      }) {
                // The original editor creates a fresh configuration on save.
                // Treat that assignment as replacing the selected station.
                internetRadioChannels[selectedIndex] = newValue
            } else {
                internetRadioChannels.append(newValue)
            }
            selectedInternetRadioID = newValue.id
            if secondaryInternetRadioID == newValue.id {
                secondaryInternetRadioID = nil
            }
        }
    }

    var secondaryInternetRadio: InternetRadioConfiguration? {
        guard let secondaryInternetRadioID,
              secondaryInternetRadioID != selectedInternetRadioID
        else { return nil }
        return internetRadioChannels.first { $0.id == secondaryInternetRadioID }
    }

    var homeInternetRadios: [InternetRadioConfiguration] {
        Array(internetRadioChannels.prefix(2))
    }

    func internetRadioChannel(id: UUID) -> InternetRadioConfiguration? {
        internetRadioChannels.first { $0.id == id }
    }

    static let recommended = AppSettings()

    init(
        lampIntensity: Double = 0.72,
        silhouetteIntensity: Double = 0.05,
        clockScale: Double = AppSettings.defaultClockScale,
        clockFont: ClockFontChoice = .tenada,
        displayTheme: StandDisplayTheme = .color,
        portraitLayout: StandScreenLayout = .portrait,
        landscapeLayout: StandScreenLayout = .landscape,
        brightnessModeThreshold: Double = 0.4,
        holdDuration: Double = 5,
        fadeDuration: Double = 30,
        automaticDimmingEnabled: Bool = false,
        preventAutoDimmingWhenScreenBright: Bool = true,
        soundThresholdDB: Float = -36,
        recordingEnabled: Bool = true,
        soundSensingEnabled: Bool = true,
        torchEnabled: Bool = true,
        torchIntensity: Double = 0.25,
        wakeOnSleepSound: Bool = false,
        multiStimulusWakeEnabled: Bool = true,
        modePreference: StandModePreference = .automatic,
        cameraAmbientSensingEnabled: Bool = false,
        backgroundModeEnabled: Bool = false,
        weatherLocationEnabled: Bool = true,
        internetRadio: InternetRadioConfiguration? = nil,
        internetRadioChannels: [InternetRadioConfiguration] = [],
        selectedInternetRadioID: UUID? = nil,
        secondaryInternetRadioID: UUID? = nil,
        homeMusicChannels: [HomeMusicChannelSelection] = []
    ) {
        self.lampIntensity = lampIntensity
        self.silhouetteIntensity = silhouetteIntensity
        self.clockScale = clockScale
        self.clockFont = clockFont
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
        self.soundSensingEnabled = soundSensingEnabled
        self.torchEnabled = torchEnabled
        self.torchIntensity = torchIntensity
        self.wakeOnSleepSound = wakeOnSleepSound
        self.multiStimulusWakeEnabled = multiStimulusWakeEnabled
        self.modePreference = modePreference
        self.cameraAmbientSensingEnabled = cameraAmbientSensingEnabled
        self.backgroundModeEnabled = backgroundModeEnabled
        self.weatherLocationEnabled = weatherLocationEnabled
        let initialChannels = internetRadioChannels.isEmpty
            ? internetRadio.map { [$0] } ?? []
            : internetRadioChannels
        self.internetRadioChannels = Self.normalizedChannels(initialChannels)
        self.selectedInternetRadioID = Self.resolvedSelection(
            requestedID: selectedInternetRadioID ?? internetRadio?.id,
            channels: self.internetRadioChannels
        )
        self.secondaryInternetRadioID = Self.resolvedSecondarySelection(
            requestedID: secondaryInternetRadioID,
            primaryID: self.selectedInternetRadioID,
            channels: self.internetRadioChannels
        )
        self.homeMusicChannels = Self.normalizedHomeMusicChannels(
            homeMusicChannels,
            radioChannels: self.internetRadioChannels
        )
    }

    private enum CodingKeys: String, CodingKey {
        case lampIntensity
        case silhouetteIntensity
        case clockScale
        case clockFont
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
        case soundSensingEnabled
        case torchEnabled
        case torchIntensity
        case wakeOnSleepSound
        case multiStimulusWakeEnabled
        case modePreference
        case cameraAmbientSensingEnabled
        case backgroundModeEnabled
        case weatherLocationEnabled
        case internetRadioChannels
        case selectedInternetRadioID
        case secondaryInternetRadioID
        case homeMusicChannels
        case internetRadio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lampIntensity = try container.decodeIfPresent(Double.self, forKey: .lampIntensity) ?? 0.72
        silhouetteIntensity = try container.decodeIfPresent(
            Double.self,
            forKey: .silhouetteIntensity
        ) ?? 0.05
        clockScale = min(Self.maximumClockScale, max(
            Self.minimumClockScale,
            try container.decodeIfPresent(Double.self, forKey: .clockScale)
                ?? Self.defaultClockScale
        ))
        clockFont = try container.decodeIfPresent(
            ClockFontChoice.self,
            forKey: .clockFont
        ) ?? .tenada
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
            try container.decodeIfPresent(Double.self, forKey: .brightnessModeThreshold) ?? 0.3
        ))
        holdDuration = min(300, max(
            5,
            try container.decodeIfPresent(Double.self, forKey: .holdDuration) ?? 5
        ))
        fadeDuration = try container.decodeIfPresent(Double.self, forKey: .fadeDuration) ?? 30
        automaticDimmingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticDimmingEnabled
        ) ?? false
        preventAutoDimmingWhenScreenBright = try container.decodeIfPresent(
            Bool.self,
            forKey: .preventAutoDimmingWhenScreenBright
        ) ?? true
        soundThresholdDB = try container.decodeIfPresent(Float.self, forKey: .soundThresholdDB) ?? -36
        recordingEnabled = try container.decodeIfPresent(Bool.self, forKey: .recordingEnabled) ?? true
        soundSensingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .soundSensingEnabled
        ) ?? true
        torchEnabled = try container.decodeIfPresent(Bool.self, forKey: .torchEnabled) ?? true
        torchIntensity = try container.decodeIfPresent(Double.self, forKey: .torchIntensity) ?? 0.25
        wakeOnSleepSound = try container.decodeIfPresent(Bool.self, forKey: .wakeOnSleepSound) ?? false
        multiStimulusWakeEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .multiStimulusWakeEnabled
        ) ?? true
        modePreference = try container.decodeIfPresent(
            StandModePreference.self,
            forKey: .modePreference
        ) ?? .automatic
        cameraAmbientSensingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .cameraAmbientSensingEnabled
        ) ?? false
        backgroundModeEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .backgroundModeEnabled
        ) ?? false
        weatherLocationEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .weatherLocationEnabled
        ) ?? true
        let decodedChannels: [InternetRadioConfiguration]?
        do {
            decodedChannels = try container.decodeIfPresent(
                [InternetRadioConfiguration].self,
                forKey: .internetRadioChannels
            )
        } catch {
            decodedChannels = nil
        }
        let legacyConfiguration = try? container.decode(
            InternetRadioConfiguration.self,
            forKey: .internetRadio
        )
        internetRadioChannels = Self.normalizedChannels(
            decodedChannels ?? legacyConfiguration.map { [$0] } ?? []
        )
        selectedInternetRadioID = Self.resolvedSelection(
            requestedID: try? container.decode(UUID.self, forKey: .selectedInternetRadioID),
            channels: internetRadioChannels
        )
        secondaryInternetRadioID = Self.resolvedSecondarySelection(
            requestedID: try? container.decode(UUID.self, forKey: .secondaryInternetRadioID),
            primaryID: selectedInternetRadioID,
            channels: internetRadioChannels
        )
        homeMusicChannels = Self.normalizedHomeMusicChannels(
            (try? container.decode([HomeMusicChannelSelection].self, forKey: .homeMusicChannels)) ?? [],
            radioChannels: internetRadioChannels
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lampIntensity, forKey: .lampIntensity)
        try container.encode(silhouetteIntensity, forKey: .silhouetteIntensity)
        try container.encode(clockScale, forKey: .clockScale)
        try container.encode(clockFont, forKey: .clockFont)
        try container.encode(displayTheme, forKey: .displayTheme)
        try container.encode(portraitLayout, forKey: .portraitLayout)
        try container.encode(landscapeLayout, forKey: .landscapeLayout)
        try container.encode(brightnessModeThreshold, forKey: .brightnessModeThreshold)
        try container.encode(holdDuration, forKey: .holdDuration)
        try container.encode(fadeDuration, forKey: .fadeDuration)
        try container.encode(automaticDimmingEnabled, forKey: .automaticDimmingEnabled)
        try container.encode(
            preventAutoDimmingWhenScreenBright,
            forKey: .preventAutoDimmingWhenScreenBright
        )
        try container.encode(soundThresholdDB, forKey: .soundThresholdDB)
        try container.encode(recordingEnabled, forKey: .recordingEnabled)
        try container.encode(soundSensingEnabled, forKey: .soundSensingEnabled)
        try container.encode(torchEnabled, forKey: .torchEnabled)
        try container.encode(torchIntensity, forKey: .torchIntensity)
        try container.encode(wakeOnSleepSound, forKey: .wakeOnSleepSound)
        try container.encode(multiStimulusWakeEnabled, forKey: .multiStimulusWakeEnabled)
        try container.encode(modePreference, forKey: .modePreference)
        try container.encode(cameraAmbientSensingEnabled, forKey: .cameraAmbientSensingEnabled)
        try container.encode(backgroundModeEnabled, forKey: .backgroundModeEnabled)
        try container.encode(weatherLocationEnabled, forKey: .weatherLocationEnabled)
        try container.encode(internetRadioChannels, forKey: .internetRadioChannels)
        try container.encodeIfPresent(selectedInternetRadioID, forKey: .selectedInternetRadioID)
        try container.encodeIfPresent(secondaryInternetRadioID, forKey: .secondaryInternetRadioID)
        try container.encode(homeMusicChannels, forKey: .homeMusicChannels)

        // Keep the selected station in the former key so a downgraded build can
        // still open the user's current station. New builds read the array first.
        try container.encodeIfPresent(internetRadio, forKey: .internetRadio)
    }

    @discardableResult
    mutating func addInternetRadioChannel(
        _ configuration: InternetRadioConfiguration,
        select: Bool = true
    ) -> Bool {
        if let index = internetRadioChannels.firstIndex(where: { $0.id == configuration.id }) {
            internetRadioChannels[index] = configuration
        } else {
            guard internetRadioChannels.count < Self.maximumInternetRadioChannelCount else {
                return false
            }
            internetRadioChannels.append(configuration)
        }
        if select || selectedInternetRadioID == nil {
            selectedInternetRadioID = configuration.id
        }
        homeMusicChannels = Self.normalizedHomeMusicChannels(
            homeMusicChannels,
            radioChannels: internetRadioChannels
        )
        return true
    }

    @discardableResult
    mutating func updateInternetRadioChannel(_ configuration: InternetRadioConfiguration) -> Bool {
        guard let index = internetRadioChannels.firstIndex(where: {
            $0.id == configuration.id
        }) else { return false }
        internetRadioChannels[index] = configuration
        return true
    }

    @discardableResult
    mutating func selectInternetRadioChannel(id: UUID) -> Bool {
        guard internetRadioChannels.contains(where: { $0.id == id }) else { return false }
        selectedInternetRadioID = id
        if secondaryInternetRadioID == id { secondaryInternetRadioID = nil }
        return true
    }

    @discardableResult
    mutating func selectSecondaryInternetRadioChannel(id: UUID?) -> Bool {
        guard let id else {
            secondaryInternetRadioID = nil
            return true
        }
        guard id != selectedInternetRadioID,
              internetRadioChannels.contains(where: { $0.id == id })
        else { return false }
        secondaryInternetRadioID = id
        return true
    }

    @discardableResult
    mutating func removeInternetRadioChannel(id: UUID) -> InternetRadioConfiguration? {
        guard let index = internetRadioChannels.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let removed = internetRadioChannels.remove(at: index)
        if selectedInternetRadioID == id {
            selectedInternetRadioID = internetRadioChannels.isEmpty
                ? nil
                : internetRadioChannels[min(index, internetRadioChannels.count - 1)].id
        }
        if secondaryInternetRadioID == id { secondaryInternetRadioID = nil }
        if secondaryInternetRadioID == selectedInternetRadioID { secondaryInternetRadioID = nil }
        homeMusicChannels = Self.normalizedHomeMusicChannels(
            homeMusicChannels,
            radioChannels: internetRadioChannels
        )
        return removed
    }

    @discardableResult
    mutating func moveInternetRadioChannel(id: UUID, to destinationIndex: Int) -> Bool {
        guard let sourceIndex = internetRadioChannels.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let channel = internetRadioChannels.remove(at: sourceIndex)
        let boundedDestination = min(max(0, destinationIndex), internetRadioChannels.count)
        internetRadioChannels.insert(channel, at: boundedDestination)
        return true
    }

    @discardableResult
    mutating func assignHomeMusicChannel(
        _ selection: HomeMusicChannelSelection,
        to slot: Int
    ) -> Bool {
        guard homeMusicChannels.indices.contains(slot),
              Self.isValidHomeMusicChannel(selection, radioChannels: internetRadioChannels)
        else { return false }

        if let otherSlot = homeMusicChannels.firstIndex(of: selection), otherSlot != slot {
            homeMusicChannels.swapAt(slot, otherSlot)
        } else {
            homeMusicChannels[slot] = selection
        }
        return true
    }

    @discardableResult
    mutating func moveHomeMusicChannel(id: String, to destinationIndex: Int) -> Bool {
        guard let sourceIndex = homeMusicChannels.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let channel = homeMusicChannels.remove(at: sourceIndex)
        let boundedDestination = min(max(0, destinationIndex), homeMusicChannels.count)
        homeMusicChannels.insert(channel, at: boundedDestination)
        return true
    }

    private static func uniqueChannels(
        _ channels: [InternetRadioConfiguration]
    ) -> [InternetRadioConfiguration] {
        var seenIDs = Set<UUID>()
        return channels.filter { seenIDs.insert($0.id).inserted }
    }

    private static func normalizedChannels(
        _ channels: [InternetRadioConfiguration]
    ) -> [InternetRadioConfiguration] {
        Array(uniqueChannels(channels).prefix(maximumInternetRadioChannelCount))
    }

    mutating func applyCurrentExperienceDefaults() {
        clockScale = Self.defaultClockScale
        portraitLayout = .portrait
        landscapeLayout = .landscape
        internetRadioChannels = Self.normalizedChannels(internetRadioChannels)
        selectedInternetRadioID = Self.resolvedSelection(
            requestedID: selectedInternetRadioID,
            channels: internetRadioChannels
        )
        secondaryInternetRadioID = Self.resolvedSecondarySelection(
            requestedID: secondaryInternetRadioID,
            primaryID: selectedInternetRadioID,
            channels: internetRadioChannels
        )
        homeMusicChannels = Self.normalizedHomeMusicChannels(
            homeMusicChannels,
            radioChannels: internetRadioChannels
        )
    }

    private static func normalizedHomeMusicChannels(
        _ requested: [HomeMusicChannelSelection],
        radioChannels: [InternetRadioConfiguration]
    ) -> [HomeMusicChannelSelection] {
        var result: [HomeMusicChannelSelection] = []
        var remainingRadios = radioChannels
        var usedSlots = Set<Int>()
        var hasAppleMusic = false
        var hasAppleClassical = false

        for candidate in requested {
            switch candidate.kind {
            case .appleMusic where !hasAppleMusic:
                result.append(.appleMusic)
                hasAppleMusic = true
            case .appleClassical where !hasAppleClassical:
                result.append(.appleClassical)
                hasAppleClassical = true
            case .internetRadio:
                guard let slot = normalizedRadioSlot(candidate.radioSlot, usedSlots: usedSlots)
                else { continue }
                usedSlots.insert(slot)
                if let radioID = candidate.radioID,
                   let index = remainingRadios.firstIndex(where: { $0.id == radioID }) {
                    result.append(.internetRadio(remainingRadios.remove(at: index).id, slot: slot))
                } else if candidate.radioID == nil, !remainingRadios.isEmpty {
                    result.append(.internetRadio(remainingRadios.removeFirst().id, slot: slot))
                } else {
                    result.append(.emptyInternetRadio(slot: slot))
                }
            default:
                continue
            }
        }

        if !hasAppleMusic { result.append(.appleMusic) }
        if !hasAppleClassical { result.append(.appleClassical) }

        for slot in 0..<maximumInternetRadioChannelCount where !usedSlots.contains(slot) {
            if !remainingRadios.isEmpty {
                result.append(.internetRadio(remainingRadios.removeFirst().id, slot: slot))
            } else {
                result.append(.emptyInternetRadio(slot: slot))
            }
        }

        return result
    }

    private static func normalizedRadioSlot(_ requested: Int?, usedSlots: Set<Int>) -> Int? {
        if let requested,
           (0..<maximumInternetRadioChannelCount).contains(requested),
           !usedSlots.contains(requested) {
            return requested
        }
        return (0..<maximumInternetRadioChannelCount).first { !usedSlots.contains($0) }
    }

    private static func isValidHomeMusicChannel(
        _ selection: HomeMusicChannelSelection,
        radioChannels: [InternetRadioConfiguration]
    ) -> Bool {
        switch selection.kind {
        case .appleMusic, .appleClassical:
            true
        case .internetRadio:
            selection.radioID == nil || selection.radioID.map { id in
                radioChannels.contains(where: { $0.id == id })
            } == true
        }
    }

    private static func resolvedSelection(
        requestedID: UUID?,
        channels: [InternetRadioConfiguration]
    ) -> UUID? {
        guard !channels.isEmpty else { return nil }
        if let requestedID, channels.contains(where: { $0.id == requestedID }) {
            return requestedID
        }
        return channels.first?.id
    }

    private static func resolvedSecondarySelection(
        requestedID: UUID?,
        primaryID: UUID?,
        channels: [InternetRadioConfiguration]
    ) -> UUID? {
        guard let requestedID,
              requestedID != primaryID,
              channels.contains(where: { $0.id == requestedID })
        else { return nil }
        return requestedID
    }
}

enum SettingsMigration {
    static let torchEnabledByDefaultKey = "settingsMigration.torchEnabledByDefault.v1"
    static let fiveSecondHoldDurationKey = "settingsMigration.fiveSecondHoldDuration.v1"
    static let internetRadioChannelsKey = "settingsMigration.internetRadioChannels.v1"
    static let currentExperienceDefaultsKey = "settingsMigration.currentExperienceDefaults.v1"
    static let landscapeLayoutDefaultKey = "settingsMigration.landscapeLayoutDefault.v4"

    static func applyingTorchDefault(
        to settings: AppSettings,
        hasMigrated: Bool
    ) -> AppSettings {
        guard !hasMigrated else { return settings }
        var migrated = settings
        migrated.torchEnabled = true
        return migrated
    }

    static func applyingFiveSecondHoldDuration(
        to settings: AppSettings,
        hasMigrated: Bool
    ) -> AppSettings {
        guard !hasMigrated else { return settings }
        var migrated = settings
        migrated.holdDuration = 5
        return migrated
    }

    static func applyingCurrentExperienceDefaults(
        to settings: AppSettings,
        hasMigrated: Bool
    ) -> AppSettings {
        guard !hasMigrated else { return settings }
        var migrated = settings
        migrated.applyCurrentExperienceDefaults()
        return migrated
    }

    static func applyingLandscapeLayoutDefault(
        to settings: AppSettings,
        hasMigrated: Bool
    ) -> AppSettings {
        guard !hasMigrated else { return settings }
        var migrated = settings
        migrated.landscapeLayout = .landscape
        return migrated
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

        let savedData = defaults.data(forKey: storageKey)
        let decodedSettings = savedData.flatMap {
            try? JSONDecoder().decode(AppSettings.self, from: $0)
        }
        let saved = decodedSettings ?? .recommended
        let hasMigratedTorchDefault = defaults.bool(
            forKey: SettingsMigration.torchEnabledByDefaultKey
        )
        let hasMigratedHoldDuration = defaults.bool(
            forKey: SettingsMigration.fiveSecondHoldDurationKey
        )
        let hasMigratedInternetRadioChannels = defaults.bool(
            forKey: SettingsMigration.internetRadioChannelsKey
        )
        let hasMigratedCurrentExperienceDefaults = defaults.bool(
            forKey: SettingsMigration.currentExperienceDefaultsKey
        )
        let hasMigratedLandscapeLayoutDefault = defaults.bool(
            forKey: SettingsMigration.landscapeLayoutDefaultKey
        )
        let torchMigrated = SettingsMigration.applyingTorchDefault(
            to: saved,
            hasMigrated: hasMigratedTorchDefault
        )
        let holdDurationMigrated = SettingsMigration.applyingFiveSecondHoldDuration(
            to: torchMigrated,
            hasMigrated: hasMigratedHoldDuration
        )
        let currentExperienceDefaultsMigrated = SettingsMigration.applyingCurrentExperienceDefaults(
            to: holdDurationMigrated,
            hasMigrated: hasMigratedCurrentExperienceDefaults
        )
        value = SettingsMigration.applyingLandscapeLayoutDefault(
            to: currentExperienceDefaultsMigrated,
            hasMigrated: hasMigratedLandscapeLayoutDefault
        )

        // Preserve an unreadable payload until the user explicitly changes a setting.
        // A launch from an older build must not overwrite recoverable newer-version data.
        guard savedData == nil || decodedSettings != nil else { return }
        guard !hasMigratedTorchDefault
                || !hasMigratedHoldDuration
                || !hasMigratedInternetRadioChannels
                || !hasMigratedCurrentExperienceDefaults
                || !hasMigratedLandscapeLayoutDefault
        else { return }
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: storageKey)
            if !hasMigratedTorchDefault {
                defaults.set(true, forKey: SettingsMigration.torchEnabledByDefaultKey)
            }
            if !hasMigratedHoldDuration {
                defaults.set(true, forKey: SettingsMigration.fiveSecondHoldDurationKey)
            }
            if !hasMigratedInternetRadioChannels {
                defaults.set(true, forKey: SettingsMigration.internetRadioChannelsKey)
            }
            if !hasMigratedCurrentExperienceDefaults {
                defaults.set(true, forKey: SettingsMigration.currentExperienceDefaultsKey)
            }
            if !hasMigratedLandscapeLayoutDefault {
                defaults.set(true, forKey: SettingsMigration.landscapeLayoutDefaultKey)
            }
        }
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "BuildStamp") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "202608230737"
    }

    static var display: String { "\(marketing) (\(build))" }
}
