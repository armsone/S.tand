import Combine
import Foundation

/// Mac Catalyst 전용 자체 업데이트 컨트롤러.
/// 앱 PlugIns에 내장된 STandUpdaterBridge.bundle(순수 macOS 번들)을 고정 경로에서 로드해
/// Sparkle 기반 업데이트를 구동한다. Catalyst 쪽은 Sparkle/AppKit을 import하지 않고
/// 셀렉터 호출로만 브리지와 통신하며, iPhone/iPad에서는 아무 동작도 하지 않는다.

enum MacUpdaterAvailability: Equatable {
    case unsupported
    case notStarted
    case unavailable(reason: String)
    case ready
}

enum MacUpdaterActivity: Equatable {
    case idle
    case checking
    case upToDate
    case updateFound(version: String?)
    case failed(message: String)
}

enum MacUpdaterBridgeEvent: Equatable {
    case updateFound(version: String?)
    case upToDate
    case finished(errorDescription: String?)

    init?(name: String, detail: String?) {
        switch name {
        case "updateFound": self = .updateFound(version: detail)
        case "upToDate": self = .upToDate
        case "finished": self = .finished(errorDescription: detail)
        default: return nil
        }
    }
}

enum MacUpdaterLogic {
    static func resolveAvailability(
        bridgeBundleFound: Bool,
        principalClassTrusted: Bool,
        startErrorDescription: String?
    ) -> MacUpdaterAvailability {
        guard bridgeBundleFound else {
            return .unavailable(reason: "업데이트 구성 요소가 이 빌드에 포함되어 있지 않습니다.")
        }
        guard principalClassTrusted else {
            return .unavailable(reason: "업데이트 구성 요소를 신뢰할 수 없습니다.")
        }
        if let startErrorDescription {
            return .unavailable(reason: startErrorDescription)
        }
        return .ready
    }

    static func reduce(
        _ activity: MacUpdaterActivity,
        event: MacUpdaterBridgeEvent
    ) -> MacUpdaterActivity {
        switch event {
        case .updateFound(let version):
            return .updateFound(version: version)
        case .upToDate:
            return .upToDate
        case .finished(let errorDescription):
            guard let errorDescription else {
                return activity == .checking ? .idle : activity
            }
            switch activity {
            case .upToDate, .updateFound:
                // 결과가 이미 확정된 뒤 따라오는 사이클 종료 오류(예: 업데이트 없음)는 무시한다.
                return activity
            case .idle, .checking, .failed:
                return .failed(message: errorDescription)
            }
        }
    }
}

final class MacUpdaterController: NSObject, ObservableObject {
    static let shared = MacUpdaterController()

    #if targetEnvironment(macCatalyst)
    @Published private(set) var availability: MacUpdaterAvailability = .notStarted
    #else
    @Published private(set) var availability: MacUpdaterAvailability = .unsupported
    #endif
    @Published private(set) var activity: MacUpdaterActivity = .idle

    private var bridge: NSObject?

    private override init() {
        super.init()
    }

    var canCheckManually: Bool {
        availability == .ready && activity != .checking
    }

    var statusText: String {
        switch availability {
        case .unsupported: return "지원 안 함"
        case .notStarted: return "준비 중"
        case .unavailable: return "사용할 수 없음"
        case .ready:
            switch activity {
            case .idle: return "눌러서 확인"
            case .checking: return "확인 중…"
            case .upToDate: return "최신 버전"
            case .updateFound(let version):
                if let version { return "새 버전 \(version)" }
                return "새 버전 있음"
            case .failed: return "확인 실패"
            }
        }
    }

    var detailText: String? {
        if case .unavailable(let reason) = availability { return reason }
        if case .failed(let message) = activity { return message }
        return nil
    }

    func startIfNeeded() {
        #if targetEnvironment(macCatalyst)
        guard availability == .notStarted else { return }
        availability = loadBridgeAndStart()
        #endif
    }

    func checkForUpdatesManually() {
        #if targetEnvironment(macCatalyst)
        guard canCheckManually, let bridge else { return }
        activity = .checking
        bridge.perform(Self.checkSelector)
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private static let bridgeBundleName = "STandUpdaterBridge.bundle"
    private static let bridgeClassName = "STandUpdaterBridge"
    private static let statusHandlerSelector = NSSelectorFromString("setStatusHandler:")
    private static let startSelector = NSSelectorFromString("startUpdater")
    private static let checkSelector = NSSelectorFromString("checkForUpdates")

    private func loadBridgeAndStart() -> MacUpdaterAvailability {
        guard
            let pluginsURL = Bundle.main.builtInPlugInsURL,
            let bundle = Bundle(url: pluginsURL.appendingPathComponent(Self.bridgeBundleName)),
            bundle.load()
        else {
            return MacUpdaterLogic.resolveAvailability(
                bridgeBundleFound: false,
                principalClassTrusted: false,
                startErrorDescription: nil
            )
        }

        guard
            let principal = bundle.principalClass as? NSObject.Type,
            NSStringFromClass(principal) == Self.bridgeClassName,
            principal.instancesRespond(to: Self.statusHandlerSelector),
            principal.instancesRespond(to: Self.startSelector),
            principal.instancesRespond(to: Self.checkSelector)
        else {
            return MacUpdaterLogic.resolveAvailability(
                bridgeBundleFound: true,
                principalClassTrusted: false,
                startErrorDescription: nil
            )
        }

        let bridge = principal.init()
        let handler: @convention(block) (String, String?) -> Void = { [weak self] name, detail in
            DispatchQueue.main.async {
                self?.handleBridgeEvent(name: name, detail: detail)
            }
        }
        _ = bridge.perform(Self.statusHandlerSelector, with: handler)
        let startError = bridge.perform(Self.startSelector)?.takeUnretainedValue() as? String
        let availability = MacUpdaterLogic.resolveAvailability(
            bridgeBundleFound: true,
            principalClassTrusted: true,
            startErrorDescription: startError
        )
        if availability == .ready {
            self.bridge = bridge
        }
        return availability
    }

    private func handleBridgeEvent(name: String, detail: String?) {
        guard let event = MacUpdaterBridgeEvent(name: name, detail: detail) else { return }
        activity = MacUpdaterLogic.reduce(activity, event: event)
    }
    #endif
}
