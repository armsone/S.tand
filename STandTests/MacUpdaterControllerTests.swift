import XCTest
@testable import STand

final class MacUpdaterControllerTests: XCTestCase {
    // MARK: - resolveAvailability

    func testResolveAvailabilityFailsWhenBridgeBundleMissing() {
        let availability = MacUpdaterLogic.resolveAvailability(
            bridgeBundleFound: false,
            principalClassTrusted: false,
            startErrorDescription: nil
        )
        guard case .unavailable = availability else {
            return XCTFail("번들이 없으면 unavailable이어야 합니다: \(availability)")
        }
    }

    func testResolveAvailabilityFailsWhenPrincipalClassUntrusted() {
        let availability = MacUpdaterLogic.resolveAvailability(
            bridgeBundleFound: true,
            principalClassTrusted: false,
            startErrorDescription: nil
        )
        guard case .unavailable = availability else {
            return XCTFail("principal class 검증 실패 시 unavailable이어야 합니다: \(availability)")
        }
    }

    func testResolveAvailabilitySurfacesStartError() {
        let availability = MacUpdaterLogic.resolveAvailability(
            bridgeBundleFound: true,
            principalClassTrusted: true,
            startErrorDescription: "서명 키 미설정"
        )
        XCTAssertEqual(availability, .unavailable(reason: "서명 키 미설정"))
    }

    func testResolveAvailabilityReadyWhenAllChecksPass() {
        let availability = MacUpdaterLogic.resolveAvailability(
            bridgeBundleFound: true,
            principalClassTrusted: true,
            startErrorDescription: nil
        )
        XCTAssertEqual(availability, .ready)
    }

    // MARK: - MacUpdaterBridgeEvent parsing

    func testBridgeEventParsesKnownNames() {
        XCTAssertEqual(
            MacUpdaterBridgeEvent(name: "updateFound", detail: "1.0.0"),
            .updateFound(version: "1.0.0")
        )
        XCTAssertEqual(MacUpdaterBridgeEvent(name: "upToDate", detail: nil), .upToDate)
        XCTAssertEqual(
            MacUpdaterBridgeEvent(name: "finished", detail: "네트워크 오류"),
            .finished(errorDescription: "네트워크 오류")
        )
        XCTAssertEqual(
            MacUpdaterBridgeEvent(name: "finished", detail: nil),
            .finished(errorDescription: nil)
        )
    }

    func testBridgeEventRejectsUnknownNames() {
        XCTAssertNil(MacUpdaterBridgeEvent(name: "somethingElse", detail: nil))
        XCTAssertNil(MacUpdaterBridgeEvent(name: "", detail: "detail"))
    }

    // MARK: - reduce

    func testReduceUpdateFoundOverridesAnyState() {
        XCTAssertEqual(
            MacUpdaterLogic.reduce(.checking, event: .updateFound(version: "1.1.0")),
            .updateFound(version: "1.1.0")
        )
        XCTAssertEqual(
            MacUpdaterLogic.reduce(.failed(message: "이전 오류"), event: .updateFound(version: nil)),
            .updateFound(version: nil)
        )
    }

    func testReduceUpToDateOverridesChecking() {
        XCTAssertEqual(MacUpdaterLogic.reduce(.checking, event: .upToDate), .upToDate)
    }

    func testReduceCleanFinishReturnsToIdleOnlyFromChecking() {
        XCTAssertEqual(
            MacUpdaterLogic.reduce(.checking, event: .finished(errorDescription: nil)),
            .idle
        )
        XCTAssertEqual(
            MacUpdaterLogic.reduce(.upToDate, event: .finished(errorDescription: nil)),
            .upToDate
        )
    }

    func testReduceFinishErrorKeepsSettledResult() {
        // 업데이트 없음 등으로 결과가 확정된 뒤 따라오는 사이클 종료 오류는 결과를 덮지 않는다.
        XCTAssertEqual(
            MacUpdaterLogic.reduce(.upToDate, event: .finished(errorDescription: "업데이트 없음")),
            .upToDate
        )
        XCTAssertEqual(
            MacUpdaterLogic.reduce(
                .updateFound(version: "1.1.0"),
                event: .finished(errorDescription: "설치 연기")
            ),
            .updateFound(version: "1.1.0")
        )
    }

    func testReduceFinishErrorFailsWhileChecking() {
        XCTAssertEqual(
            MacUpdaterLogic.reduce(.checking, event: .finished(errorDescription: "네트워크 오류")),
            .failed(message: "네트워크 오류")
        )
    }
}
