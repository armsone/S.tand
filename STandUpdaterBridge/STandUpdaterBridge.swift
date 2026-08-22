import AppKit
import Foundation
import Sparkle

/// Catalyst 호스트(S.tand.app)의 PlugIns에 내장되는 순수 macOS 번들의 principal class.
/// Catalyst 쪽은 Sparkle/AppKit을 import하지 않고 셀렉터 호출로만 이 클래스와 통신한다.
/// Sparkle은 이 플러그인 번들이 아니라 호스트 앱 번들(Bundle.main)을 대상으로 초기화되어,
/// 호스트 종료 후 서명된 DMG 업데이트를 설치하고 호스트를 다시 실행한다.
@objc(STandUpdaterBridge)
public final class STandUpdaterBridge: NSObject {
    public typealias StatusHandler = @convention(block) (String, String?) -> Void

    private var updater: SPUUpdater?
    private var userDriver: SPUStandardUserDriver?
    private var statusHandler: StatusHandler?

    @objc public func setStatusHandler(_ handler: @escaping StatusHandler) {
        statusHandler = handler
    }

    /// 성공 시 nil, 실패 시 설정 화면에 보여줄 원인 문자열을 반환한다.
    @objc public func startUpdater() -> String? {
        guard updater == nil else { return nil }

        // 플러그인으로 로드되므로 Bundle.main은 이 번들이 아니라 S.tand.app 호스트다.
        let host = Bundle.main
        let publicKey = host.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !publicKey.isEmpty else {
            return "업데이트 서명 키가 빌드에 포함되지 않았습니다. 릴리스 빌드에서 STAND_SPARKLE_ED_PUBLIC_KEY를 설정해야 합니다."
        }
        guard host.object(forInfoDictionaryKey: "SUFeedURL") is String else {
            return "업데이트 피드 주소(SUFeedURL)가 설정되지 않았습니다."
        }

        let driver = SPUStandardUserDriver(hostBundle: host, delegate: nil)
        let updater = SPUUpdater(
            hostBundle: host,
            applicationBundle: host,
            userDriver: driver,
            delegate: self
        )
        do {
            try updater.start()
        } catch {
            return error.localizedDescription
        }
        self.userDriver = driver
        self.updater = updater
        return nil
    }

    @objc public var canCheckForUpdates: Bool {
        updater?.canCheckForUpdates ?? false
    }

    @objc public func checkForUpdates() {
        updater?.checkForUpdates()
    }
}

extension STandUpdaterBridge: SPUUpdaterDelegate {
    public func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        statusHandler?("updateFound", item.displayVersionString)
    }

    public func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        statusHandler?("upToDate", nil)
    }

    public func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        statusHandler?("finished", error?.localizedDescription)
    }
}
