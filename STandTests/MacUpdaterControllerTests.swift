import XCTest
@testable import STand

final class MacUpdaterControllerTests: XCTestCase {
    func testAutomaticDownloadStatusIsExplicit() {
        XCTAssertEqual(MacUpdaterLogic.automaticDownloadStatusText(enabled: true), "새 버전을 자동으로 다운로드합니다.")
        XCTAssertEqual(MacUpdaterLogic.automaticDownloadStatusText(enabled: false), "새 버전을 확인한 뒤 직접 다운로드합니다.")
    }

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

    // MARK: - TestFlightUpdateCheck numericBuild

    func testNumericBuildFromTextValid() {
        XCTAssertEqual(TestFlightUpdateCheck.numericBuild(fromText: "340467"), 340467)
        XCTAssertEqual(TestFlightUpdateCheck.numericBuild(fromText: "  123 \n"), 123)
        XCTAssertEqual(TestFlightUpdateCheck.numericBuild(fromText: "0"), 0)
    }

    func testNumericBuildFromTextInvalid() {
        XCTAssertNil(TestFlightUpdateCheck.numericBuild(fromText: ""))
        XCTAssertNil(TestFlightUpdateCheck.numericBuild(fromText: "   "))
        XCTAssertNil(TestFlightUpdateCheck.numericBuild(fromText: "340467a"))
        XCTAssertNil(TestFlightUpdateCheck.numericBuild(fromText: "-10"))
        XCTAssertNil(TestFlightUpdateCheck.numericBuild(fromText: "12.34"))
        XCTAssertNil(TestFlightUpdateCheck.numericBuild(fromText: "340 467"))
    }

    func testNumericBuildFromJSONValue() {
        XCTAssertEqual(TestFlightUpdateCheck.numericBuild(fromJSONValue: "340468"), 340468)
        XCTAssertEqual(TestFlightUpdateCheck.numericBuild(fromJSONValue: 340468), 340468)
        XCTAssertEqual(TestFlightUpdateCheck.numericBuild(fromJSONValue: NSNumber(value: 340468)), 340468)
        XCTAssertNil(TestFlightUpdateCheck.numericBuild(fromJSONValue: nil))
        XCTAssertNil(TestFlightUpdateCheck.numericBuild(fromJSONValue: true))
        XCTAssertNil(TestFlightUpdateCheck.numericBuild(fromJSONValue: false))
        XCTAssertNil(TestFlightUpdateCheck.numericBuild(fromJSONValue: 12.34))
        XCTAssertNil(TestFlightUpdateCheck.numericBuild(fromJSONValue: -5))
        XCTAssertNil(TestFlightUpdateCheck.numericBuild(fromJSONValue: ["invalid": "type"]))
    }

    // MARK: - TestFlightUpdateCheck evaluate

    func testEvaluateNewerBuildAvailable() {
        let json = """
        {
            "builds": [
                {
                    "slug": "stand",
                    "build": "340468",
                    "version": "2.1.0"
                }
            ]
        }
        """.data(using: .utf8)!

        let outcome = TestFlightUpdateCheck.evaluate(
            responseData: json,
            currentBuildText: "340467"
        )
        XCTAssertEqual(
            outcome,
            .newerAvailable(latestBuild: 340468, version: "2.1.0")
        )
    }

    func testEvaluateUpToDateEqualBuild() {
        let json = """
        {
            "builds": [
                {
                    "slug": "stand",
                    "build": "340467",
                    "version": "2.1.0"
                }
            ]
        }
        """.data(using: .utf8)!

        let outcome = TestFlightUpdateCheck.evaluate(
            responseData: json,
            currentBuildText: "340467"
        )
        XCTAssertEqual(outcome, .upToDate(latestBuild: 340467))
    }

    func testEvaluateUpToDateOlderBuild() {
        let json = """
        {
            "builds": [
                {
                    "slug": "stand",
                    "build": "340460",
                    "version": "2.0.9"
                }
            ]
        }
        """.data(using: .utf8)!

        let outcome = TestFlightUpdateCheck.evaluate(
            responseData: json,
            currentBuildText: "340467"
        )
        XCTAssertEqual(outcome, .upToDate(latestBuild: 340460))
    }

    func testEvaluateAcceptsNumericIntegerBuildInJSON() {
        let json = """
        {
            "builds": [
                {
                    "slug": "stand",
                    "build": 340468
                }
            ]
        }
        """.data(using: .utf8)!

        let outcome = TestFlightUpdateCheck.evaluate(
            responseData: json,
            currentBuildText: "340467"
        )
        XCTAssertEqual(outcome, .newerAvailable(latestBuild: 340468, version: nil))
    }

    func testEvaluateSelectsStandSlugAmongMultipleBuilds() {
        let json = """
        {
            "builds": [
                {
                    "slug": "otherapp",
                    "build": "999999",
                    "version": "9.9.9"
                },
                {
                    "slug": "stand",
                    "build": "340468",
                    "version": "2.1.0"
                }
            ]
        }
        """.data(using: .utf8)!

        let outcome = TestFlightUpdateCheck.evaluate(
            responseData: json,
            currentBuildText: "340467"
        )
        XCTAssertEqual(
            outcome,
            .newerAvailable(latestBuild: 340468, version: "2.1.0")
        )
    }

    func testEvaluateMalformedWhenSlugMissing() {
        let json = """
        {
            "builds": [
                {
                    "slug": "otherapp",
                    "build": "100"
                }
            ]
        }
        """.data(using: .utf8)!

        let outcome = TestFlightUpdateCheck.evaluate(
            responseData: json,
            currentBuildText: "340467"
        )
        XCTAssertEqual(outcome, .malformed(reason: "S.tand 빌드 정보를 찾지 못했어요."))
    }

    func testEvaluateMalformedWhenBuildFieldMissingOrInvalid() {
        let missingBuild = """
        {
            "builds": [
                {
                    "slug": "stand",
                    "version": "2.1.0"
                }
            ]
        }
        """.data(using: .utf8)!

        let outcome1 = TestFlightUpdateCheck.evaluate(
            responseData: missingBuild,
            currentBuildText: "340467"
        )
        XCTAssertEqual(outcome1, .malformed(reason: "서버의 빌드 번호 형식이 올바르지 않아요."))

        let invalidBuild = """
        {
            "builds": [
                {
                    "slug": "stand",
                    "build": "not-a-number"
                }
            ]
        }
        """.data(using: .utf8)!

        let outcome2 = TestFlightUpdateCheck.evaluate(
            responseData: invalidBuild,
            currentBuildText: "340467"
        )
        XCTAssertEqual(outcome2, .malformed(reason: "서버의 빌드 번호 형식이 올바르지 않아요."))
    }

    func testEvaluateMalformedWhenResponseIsNotValidJSON() {
        let invalidData = "<html>502 Bad Gateway</html>".data(using: .utf8)!
        let outcome = TestFlightUpdateCheck.evaluate(
            responseData: invalidData,
            currentBuildText: "340467"
        )
        XCTAssertEqual(outcome, .malformed(reason: "서버 응답 형식을 읽지 못했어요."))
    }

    func testEvaluateMalformedWhenCurrentBuildTextIsInvalid() {
        let json = """
        {
            "builds": [
                {
                    "slug": "stand",
                    "build": "340468"
                }
            ]
        }
        """.data(using: .utf8)!

        let outcome = TestFlightUpdateCheck.evaluate(
            responseData: json,
            currentBuildText: "invalid_current_build"
        )
        XCTAssertEqual(outcome, .malformed(reason: "현재 앱의 빌드 번호를 읽지 못했어요."))
    }
}
