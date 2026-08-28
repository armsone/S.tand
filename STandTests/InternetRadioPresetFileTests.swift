import XCTest
@testable import STand

final class InternetRadioPresetFileTests: XCTestCase {
    // MARK: - Android v1 interchange compatibility

    func testDecodesAndroidCompatibleJSON() throws {
        let json = """
        {
          "format": "s.tand-radio",
          "version": 1,
          "exportedAt": 1735600000000,
          "channels": [
            {
              "id": "3fa5b6c2-1a2b-4c3d-9e0f-1234567890ab",
              "displayName": "SBS 파워FM",
              "streamUrl": "http://65.21.61.215:8000/snsd999"
            },
            {
              "id": "channel-2",
              "displayName": "KBS 클래식",
              "streamUrl": "https://kbs.example.com/stream"
            }
          ]
        }
        """
        let channels = try InternetRadioPresetCodec.parse(Data(json.utf8))

        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].displayName, "SBS 파워FM")
        XCTAssertEqual(channels[0].urlString, "http://65.21.61.215:8000/snsd999")
        XCTAssertTrue(channels[0].isInsecureStream)
        // "3fa5b6c2-..." parses as a valid UUID, so the identity survives the round trip.
        XCTAssertEqual(channels[0].id.uuidString.lowercased(), "3fa5b6c2-1a2b-4c3d-9e0f-1234567890ab")
        XCTAssertEqual(channels[1].displayName, "KBS 클래식")
        XCTAssertFalse(channels[1].isInsecureStream)
    }

    func testExportProducesAndroidCompatibleSchema() throws {
        let channel = try InternetRadioConfiguration(
            displayName: "테스트 채널",
            urlString: "https://example.com/stream"
        )
        let data = try InternetRadioPresetCodec.exportData(channels: [channel])
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(json["format"] as? String, "s.tand-radio")
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertNotNil(json["exportedAt"] as? Int64 ?? (json["exportedAt"] as? NSNumber)?.int64Value)

        let channels = try XCTUnwrap(json["channels"] as? [[String: Any]])
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0]["id"] as? String, channel.id.uuidString)
        XCTAssertEqual(channels[0]["displayName"] as? String, "테스트 채널")
        XCTAssertEqual(channels[0]["streamUrl"] as? String, "https://example.com/stream")
    }

    func testExportedFileRoundTripsThroughParse() throws {
        let channel = try InternetRadioConfiguration(
            displayName: "라운드트립",
            urlString: "https://round.example.com/trip"
        )
        let data = try InternetRadioPresetCodec.exportData(channels: [channel])
        let parsed = try InternetRadioPresetCodec.parse(data)

        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].id, channel.id)
        XCTAssertEqual(parsed[0].urlString, channel.urlString)
    }

    // MARK: - Format / version / size errors

    func testRejectsEmptyPayload() {
        XCTAssertThrowsError(try InternetRadioPresetCodec.parse(Data())) { error in
            XCTAssertEqual(error as? InternetRadioPresetError, .emptyPayload)
        }
    }

    func testRejectsOversizedPayload() {
        let oversizedChannels = (0..<20_000).map { index in
            "{\"id\":\"c\(index)\",\"displayName\":\"n\",\"streamUrl\":\"https://e.com/\(index)\"}"
        }.joined(separator: ",")
        let json = "{\"format\":\"s.tand-radio\",\"version\":1,\"exportedAt\":1,\"channels\":[\(oversizedChannels)]}"
        XCTAssertGreaterThan(json.utf8.count, InternetRadioPresetFile.maximumPayloadBytes)

        XCTAssertThrowsError(try InternetRadioPresetCodec.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? InternetRadioPresetError, .oversizedPayload)
        }
    }

    func testRejectsWrongFormat() {
        let json = """
        {"format":"other-app","version":1,"exportedAt":1,"channels":[]}
        """
        XCTAssertThrowsError(try InternetRadioPresetCodec.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? InternetRadioPresetError, .invalidFormat)
        }
    }

    func testRejectsUnsupportedVersion() {
        let json = """
        {"format":"s.tand-radio","version":2,"exportedAt":1,"channels":[]}
        """
        XCTAssertThrowsError(try InternetRadioPresetCodec.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? InternetRadioPresetError, .unsupportedVersion)
        }
    }

    func testRejectsFileWithNoValidChannels() {
        let json = """
        {"format":"s.tand-radio","version":1,"exportedAt":1,"channels":[
          {"id":"1","displayName":"bad scheme","streamUrl":"ftp://example.com/stream"},
          {"id":"2","displayName":"no host","streamUrl":"https:///path"}
        ]}
        """
        XCTAssertThrowsError(try InternetRadioPresetCodec.parse(Data(json.utf8))) { error in
            XCTAssertEqual(error as? InternetRadioPresetError, .noValidChannels)
        }
    }

    func testExportWithNoChannelsThrows() {
        XCTAssertThrowsError(try InternetRadioPresetCodec.exportData(channels: [])) { error in
            XCTAssertEqual(error as? InternetRadioPresetError, .noChannelsToExport)
        }
    }

    // MARK: - Duplicate handling and ID normalization

    func testGeneratesFreshUUIDForInvalidOrDuplicateIDs() throws {
        let json = """
        {"format":"s.tand-radio","version":1,"exportedAt":1,"channels":[
          {"id":"not a valid id!!","displayName":"a","streamUrl":"https://a.example.com/s"},
          {"id":"3fa5b6c2-1a2b-4c3d-9e0f-1234567890ab","displayName":"b","streamUrl":"https://b.example.com/s"},
          {"id":"3fa5b6c2-1a2b-4c3d-9e0f-1234567890ab","displayName":"c-duplicate-id","streamUrl":"https://c.example.com/s"}
        ]}
        """
        let channels = try InternetRadioPresetCodec.parse(Data(json.utf8))
        XCTAssertEqual(channels.count, 3)
        let ids = Set(channels.map(\.id))
        XCTAssertEqual(ids.count, 3, "each channel must end up with a unique id")
        XCTAssertNotEqual(channels[0].id.uuidString, "not a valid id!!")
    }

    func testDeduplicatesChannelsByNormalizedSchemeAndHost() throws {
        let json = """
        {"format":"s.tand-radio","version":1,"exportedAt":1,"channels":[
          {"id":"1","displayName":"first","streamUrl":"https://Example.com/Stream?x=1"},
          {"id":"2","displayName":"duplicate case", "streamUrl":"HTTPS://EXAMPLE.COM/Stream?x=1"},
          {"id":"3","displayName":"different path","streamUrl":"https://example.com/other"}
        ]}
        """
        let channels = try InternetRadioPresetCodec.parse(Data(json.utf8))
        XCTAssertEqual(channels.count, 2)
        XCTAssertEqual(channels[0].displayName, "first")
        XCTAssertEqual(channels[1].displayName, "different path")
    }

    func testPreviewMarksExistingChannelsAsDuplicate() throws {
        let existing = try InternetRadioConfiguration(
            displayName: "기존 채널",
            urlString: "https://existing.example.com/stream"
        )
        let imported = try InternetRadioConfiguration(
            displayName: "가져온 채널",
            urlString: "https://existing.example.com/stream"
        )
        XCTAssertTrue(InternetRadioPresetCodec.isDuplicate(imported, among: [existing]))

        let brandNew = try InternetRadioConfiguration(
            displayName: "새 채널",
            urlString: "https://new.example.com/stream"
        )
        XCTAssertFalse(InternetRadioPresetCodec.isDuplicate(brandNew, among: [existing]))
    }

    // MARK: - Merge/replace capacity behavior

    func testAddInternetRadioChannelDoesNotExceedMaximumCount() throws {
        var settings = AppSettings()
        for index in 0..<AppSettings.maximumInternetRadioChannelCount {
            let channel = try InternetRadioConfiguration(
                displayName: "채널 \(index)",
                urlString: "https://example.com/\(index)"
            )
            settings.addInternetRadioChannel(channel)
        }
        XCTAssertEqual(settings.internetRadioChannels.count, AppSettings.maximumInternetRadioChannelCount)

        let overflow = try InternetRadioConfiguration(
            displayName: "초과 채널",
            urlString: "https://example.com/overflow"
        )
        settings.addInternetRadioChannel(overflow)
        XCTAssertEqual(settings.internetRadioChannels.count, AppSettings.maximumInternetRadioChannelCount)
        XCTAssertFalse(settings.internetRadioChannels.contains { $0.id == overflow.id })
    }

    func testAddingOnlyFillsRemainingSlotsWithNonDuplicateImportedChannels() throws {
        var settings = AppSettings()
        let first = try InternetRadioConfiguration(displayName: "1", urlString: "https://example.com/1")
        let second = try InternetRadioConfiguration(displayName: "2", urlString: "https://example.com/2")
        settings.addInternetRadioChannel(first)
        settings.addInternetRadioChannel(second)
        XCTAssertEqual(settings.internetRadioChannels.count, 2)

        let json = """
        {"format":"s.tand-radio","version":1,"exportedAt":1,"channels":[
          {"id":"a","displayName":"dup","streamUrl":"https://example.com/1"},
          {"id":"b","displayName":"new1","streamUrl":"https://example.com/3"},
          {"id":"c","displayName":"new2","streamUrl":"https://example.com/4"},
          {"id":"d","displayName":"new3-should-not-fit","streamUrl":"https://example.com/5"}
        ]}
        """
        let parsed = try InternetRadioPresetCodec.parse(Data(json.utf8))
        let newChannels = parsed.filter {
            !InternetRadioPresetCodec.isDuplicate($0, among: settings.internetRadioChannels)
        }
        XCTAssertEqual(newChannels.count, 3)

        let availableSlots = AppSettings.maximumInternetRadioChannelCount - settings.internetRadioChannels.count
        for channel in newChannels.prefix(availableSlots) {
            settings.addInternetRadioChannel(channel, select: false)
        }
        XCTAssertEqual(settings.internetRadioChannels.count, AppSettings.maximumInternetRadioChannelCount)
    }

    // MARK: - HTTP validation

    func testAcceptsCredentialFreeHTTPStream() throws {
        let channel = try InternetRadioConfiguration(
            displayName: "레거시 스트림",
            urlString: "http://65.21.61.215:8000/snsd999"
        )
        XCTAssertTrue(channel.isInsecureStream)
        XCTAssertEqual(channel.streamURL.scheme, "http")
    }

    func testAcceptsCredentialFreeHTTPSStream() throws {
        let channel = try InternetRadioConfiguration(
            displayName: "안전한 스트림",
            urlString: "https://example.com/stream"
        )
        XCTAssertFalse(channel.isInsecureStream)
    }

    func testRejectsCredentialsInAddress() {
        XCTAssertThrowsError(
            try InternetRadioConfiguration(
                displayName: "위험",
                urlString: "http://user:pass@example.com/stream"
            )
        ) { error in
            XCTAssertEqual(error as? InternetRadioConfigurationError, .credentialsNotAllowed)
        }
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertThrowsError(
            try InternetRadioConfiguration(
                displayName: "지원 안 함",
                urlString: "ftp://example.com/stream"
            )
        ) { error in
            XCTAssertEqual(error as? InternetRadioConfigurationError, .secureAddressRequired)
        }
    }

    func testRejectsFragment() {
        XCTAssertThrowsError(
            try InternetRadioConfiguration(
                displayName: "프래그먼트",
                urlString: "https://example.com/stream#frag"
            )
        ) { error in
            XCTAssertEqual(error as? InternetRadioConfigurationError, .fragmentNotAllowed)
        }
    }

    func testRejectsMissingHost() {
        XCTAssertThrowsError(
            try InternetRadioConfiguration(
                displayName: "호스트 없음",
                urlString: "https:///stream"
            )
        ) { error in
            XCTAssertEqual(error as? InternetRadioConfigurationError, .missingHost)
        }
    }
}
