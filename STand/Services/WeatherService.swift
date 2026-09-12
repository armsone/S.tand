import CoreLocation
import Foundation

struct CurrentWeather: Codable, Equatable {
    let temperature: Double
    let apparentTemperature: Double
    let precipitation: Double
    let weatherCode: Int
    let isDay: Bool

    var summary: String {
        switch weatherCode {
        case 0: "맑음"
        case 1: "대체로 맑음"
        case 2: "구름 조금"
        case 3: "흐림"
        case 45, 48: "안개"
        case 51, 53, 55, 56, 57: "이슬비"
        case 61, 63, 65, 66, 67: "비"
        case 71, 73, 75, 77: "눈"
        case 80, 81, 82: "소나기"
        case 85, 86: "눈 소나기"
        case 95, 96, 99: "뇌우"
        default: "날씨 정보"
        }
    }

    var systemImage: String {
        switch weatherCode {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

enum WeatherAvailability: Equatable {
    case idle
    case requestingLocation
    case loading
    case available
    case locationDenied
    case failed
}

@MainActor
final class WeatherService: NSObject, ObservableObject {
    /// 전면 자동 갱신 정책. 값은 초 단위이며 UI에는 노출하지 않는다.
    enum RefreshPolicy {
        /// 마지막 성공 이후 이 시간이 지나면 전면에서 자동으로 다시 가져온다.
        static let refreshInterval: TimeInterval = 15 * 60
        /// 실패 이후 재시도까지 기다리는 시간. 이동 감지도 이 대기를 건너뛰지 못한다.
        static let retryInterval: TimeInterval = 5 * 60
        /// 어떤 이유로든 연속 요청 사이에 보장하는 최소 간격.
        static let minimumRequestGap: TimeInterval = 60
        /// 마지막으로 날씨를 가져온 지점에서 이 거리 이상 움직이면 캐시가 신선해도 다시 가져온다.
        static let movementThreshold: CLLocationDistance = 3_000
        /// 이동 감지용 CoreLocation distanceFilter. 3km 판정은 별도로 누적 거리로 계산한다.
        static let monitoringDistanceFilter: CLLocationDistance = 1_000
        /// 갱신이 진행 중이라 예약 시각을 정할 수 없을 때 스케줄러가 다시 확인하기까지 기다리는 시간.
        static let schedulerFallbackInterval: TimeInterval = 30

        /// 다음 자동 갱신이 허용되는 가장 이른 시각.
        /// 실패가 마지막 성공보다 최근이면 실패 시각 + retryInterval, 아니면 성공 시각 + refreshInterval.
        /// 어느 경우든 마지막 요청 시작 + minimumRequestGap 이전으로는 앞당기지 않는다.
        static func nextRefreshDate(
            now: Date,
            lastUpdated: Date?,
            lastFailureAt: Date?,
            lastRequestStartedAt: Date?
        ) -> Date {
            var due: Date
            if let lastFailureAt, lastFailureAt >= (lastUpdated ?? .distantPast) {
                due = lastFailureAt.addingTimeInterval(retryInterval)
            } else if let lastUpdated {
                due = lastUpdated.addingTimeInterval(refreshInterval)
            } else {
                due = now
            }
            if let lastRequestStartedAt {
                due = max(due, lastRequestStartedAt.addingTimeInterval(minimumRequestGap))
            }
            return due
        }


    }

    @Published private(set) var weather: CurrentWeather?
    @Published private(set) var locationName: String?
    @Published private(set) var availability = WeatherAvailability.idle
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLocationEnabled = true

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let session: URLSession
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    // 전면 스케줄러 / 이동 감지 상태
    private var isForeground = false
    private var isMonitoringMovement = false
    private var isAwaitingLocation = false
    private var pollingTask: Task<Void, Never>?
    private var lastRequestStartedAt: Date?
    private var lastFailureAt: Date?
    private var pendingForcedRefresh = false
    private var locationRequestStartedAt: Date?
    /// 마지막으로 날씨를 성공적으로 가져온 지점. 이동 거리 판정 기준.
    private var lastFetchedLocation: CLLocation?
    /// 현재 `locationName`이 가리키는 지점. 지오코딩 실패 시 이름을 유지할지 판단하는 기준.
    private var namedLocation: CLLocation?
    /// 이동 감지 스트림에서 마지막으로 받은 위치. 예약 갱신 시 새 위치 요청 없이 재사용한다.
    private var lastObservedLocation: CLLocation?

    var locationAuthorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    private var hasLocationAuthorization: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    private var isRefreshing: Bool {
        isAwaitingLocation || refreshTask != nil
    }

    init(
        session: URLSession = .shared,
        initialWeather: CurrentWeather? = nil,
        initialLocationName: String? = nil,
        initialLastUpdated: Date? = nil
    ) {
        self.session = session
        weather = initialWeather
        locationName = initialLocationName
        lastUpdated = initialLastUpdated
        super.init()
        locationManager.delegate = self
        // 3km 이동 판정에 쓸 수 있을 만큼의 정확도. 추가 권한은 필요 없다.
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.distanceFilter = RefreshPolicy.monitoringDistanceFilter
    }

    deinit {
        pollingTask?.cancel()
        refreshTask?.cancel()
        locationManager.stopUpdatingLocation()
    }

    // MARK: - 외부 진입점

    func refreshIfNeeded(force: Bool = false, requestPermission: Bool = false) {
        guard isLocationEnabled else { return }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            if requestPermission {
                availability = .requestingLocation
                locationManager.requestWhenInUseAuthorization()
            } else {
                availability = .locationDenied
            }
        case .authorizedAlways, .authorizedWhenInUse:
            if force { pendingForcedRefresh = true }
            guard isForeground else { return }
            if !isRefreshing, isRefreshDue(now: .now) {
                beginLocationRefresh()
            }
            restartScheduler()
        case .denied, .restricted:
            availability = .locationDenied
        @unknown default:
            availability = .failed
        }
    }

    func setLocationEnabled(_ enabled: Bool, requestPermission: Bool = false) {
        guard isLocationEnabled != enabled else {
            if enabled { refreshIfNeeded(requestPermission: requestPermission) }
            return
        }
        isLocationEnabled = enabled
        if enabled {
            refreshIfNeeded(force: true, requestPermission: requestPermission)
            syncForegroundLifecycle()
        } else {
            cancelInFlightRefresh()
            stopScheduler()
            stopMovementMonitoring()
            weather = nil
            locationName = nil
            lastUpdated = nil
            lastFailureAt = nil
            lastRequestStartedAt = nil
            lastFetchedLocation = nil
            pendingForcedRefresh = false
            namedLocation = nil
            availability = .idle
        }
    }

    /// 앱이 전면으로 들어왔을 때 호출. 15분 주기 갱신과 이동 감지를 시작한다. 여러 번 불러도 안전하다.
    func appDidEnterForeground() {
        guard !isForeground else { return }
        isForeground = true
        syncForegroundLifecycle()
    }

    /// 앱이 전면을 벗어났을 때 호출. 주기 갱신과 이동 감지를 멈추고 진행 중인 요청을 취소한다.
    /// 취소는 실패로 기록하지 않으며 기존 날씨와 위치 이름은 그대로 둔다.
    func appDidEnterBackground() {
        guard isForeground else { return }
        isForeground = false
        cancelInFlightRefresh()
        stopScheduler()
        stopMovementMonitoring()
    }

    // MARK: - 스케줄러 / 이동 감지

    private func syncForegroundLifecycle() {
        let shouldRun = isForeground && isLocationEnabled && hasLocationAuthorization
        if shouldRun {
            startMovementMonitoring()
            restartScheduler()
        } else {
            stopScheduler()
            stopMovementMonitoring()
        }
    }

    private func startMovementMonitoring() {
        guard !isMonitoringMovement, !isAwaitingLocation else { return }
        isMonitoringMovement = true
        locationManager.startUpdatingLocation()
    }

    private func stopMovementMonitoring() {
        isMonitoringMovement = false
        locationManager.stopUpdatingLocation()
        lastObservedLocation = nil
    }

    private func stopScheduler() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// 다음 갱신 시각을 다시 계산해 대기하는 루프를 새로 시작한다.
    /// 요청이 끝날 때마다 호출해 예약 시각을 최신 상태로 맞춘다.
    private func restartScheduler() {
        stopScheduler()
        guard isForeground, isLocationEnabled, hasLocationAuthorization else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let wait = self?.schedulerTick(now: .now) else { return }
                try? await Task.sleep(nanoseconds: UInt64(max(wait, 1) * 1_000_000_000))
            }
        }
    }

    /// 갱신이 필요하면 시작하고, 다음 확인까지 기다릴 시간을 돌려준다.
    private func schedulerTick(now: Date) -> TimeInterval {
        guard isForeground, isLocationEnabled, hasLocationAuthorization else {
            return RefreshPolicy.schedulerFallbackInterval
        }
        if isAwaitingLocation, let locationRequestStartedAt,
           now.timeIntervalSince(locationRequestStartedAt) >= 30 {
            isAwaitingLocation = false
            self.locationRequestStartedAt = nil
            recordFailure()
        }
        if isRefreshing {
            return RefreshPolicy.schedulerFallbackInterval
        }
        let due = nextRefreshDate(now: now)
        if due <= now {
            beginLocationRefresh()
            return RefreshPolicy.schedulerFallbackInterval
        }
        return due.timeIntervalSince(now)
    }

    private func nextRefreshDate(now: Date) -> Date {
        let moved = lastObservedLocation.flatMap { observed in
            lastFetchedLocation.map { observed.distance(from: $0) >= RefreshPolicy.movementThreshold }
        } ?? false
        return RefreshPolicy.nextRefreshDate(
            now: now,
            lastUpdated: pendingForcedRefresh || moved ? nil : lastUpdated,
            lastFailureAt: lastFailureAt,
            lastRequestStartedAt: lastRequestStartedAt
        )
    }

    private func isRefreshDue(now: Date) -> Bool {
        nextRefreshDate(now: now) <= now
    }

    /// 예약 갱신마다 현재 위치를 다시 확보한다. 위치 응답이 없으면 스케줄러가 30초 후 실패로 처리한다.
    private func beginLocationRefresh() {
        guard isForeground, isLocationEnabled, hasLocationAuthorization,
              !isRefreshing, isRefreshDue(now: .now) else { return }
        // 단발 요청은 연속 위치 갱신을 멈춘 뒤 실행해야 정지한 상태에서도 새 응답을 받는다.
        stopMovementMonitoring()
        isAwaitingLocation = true
        locationRequestStartedAt = .now
        if weather == nil { availability = .loading }
        locationManager.requestLocation()
    }

    private func cancelInFlightRefresh() {
        refreshGeneration += 1
        refreshTask?.cancel()
        refreshTask = nil
        geocoder.cancelGeocode()
        isAwaitingLocation = false
        locationRequestStartedAt = nil
    }

    private func recordFailure() {
        lastFailureAt = .now
        // 이전 날씨와 위치 이름은 유지한다. 표시할 것이 아무것도 없을 때만 실패 상태를 드러낸다.
        if weather == nil { availability = .failed }
    }

    private func handleObservedLocation(_ location: CLLocation) {
        guard isForeground, isLocationEnabled, hasLocationAuthorization,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) <= 120 else { return }
        if isMonitoringMovement { lastObservedLocation = location }

        if isAwaitingLocation {
            isAwaitingLocation = false
            locationRequestStartedAt = nil
            startMovementMonitoring()
            lastObservedLocation = location
            loadWeather(at: location)
            return
        }

        guard isMonitoringMovement, let lastFetchedLocation,
              location.distance(from: lastFetchedLocation) >= RefreshPolicy.movementThreshold
        else { return }
        // 간격 제한 중이거나 요청 중인 이동도 마지막 관측 위치로 보존해 다음 예약에 반영한다.
        if refreshTask == nil, isRefreshDue(now: .now) {
            loadWeather(at: location)
        } else {
            restartScheduler()
        }
    }

    private func handleLocationFailure() {
        guard isForeground, isLocationEnabled else { return }
        if isAwaitingLocation {
            isAwaitingLocation = false
            recordFailure()
            restartScheduler()
        } else if weather == nil, availability == .loading {
            recordFailure()
            restartScheduler()
        }
    }

    // MARK: - 네트워크

    private func loadWeather(at location: CLLocation) {
        guard isForeground, isLocationEnabled, hasLocationAuthorization else { return }
        cancelInFlightRefresh()
        pendingForcedRefresh = false
        let generation = refreshGeneration
        lastRequestStartedAt = .now
        if weather == nil { availability = .loading }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if generation == refreshGeneration {
                    refreshTask = nil
                    restartScheduler()
                }
            }
            do {
                let weather = try await Self.fetchWeather(
                    at: location.coordinate,
                    session: session
                )
                guard !Task.isCancelled, generation == refreshGeneration else { return }
                self.weather = weather
                self.lastUpdated = .now
                self.lastFailureAt = nil
                self.lastFetchedLocation = location
                self.availability = .available
                // 지점이 바뀌었으면 이전 이름은 새 날씨와 맞지 않으므로 지오코딩 결과가 올 때까지 비운다.
                if let namedLocation,
                   namedLocation.distance(from: location) >= RefreshPolicy.movementThreshold {
                    self.locationName = nil
                    self.namedLocation = nil
                }

                if let placemark = try? await geocoder.reverseGeocodeLocation(
                    location,
                    preferredLocale: Locale(identifier: "ko_KR")
                ).first,
                   let resolvedName = Self.locationName(
                       administrativeArea: placemark.administrativeArea,
                       locality: placemark.locality,
                       subAdministrativeArea: placemark.subAdministrativeArea,
                       subLocality: placemark.subLocality,
                       country: placemark.country
                   ),
                   !Task.isCancelled, generation == refreshGeneration {
                    self.locationName = resolvedName
                    self.namedLocation = location
                }
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled, generation == refreshGeneration else { return }
                recordFailure()
            }
        }
    }

    static func fetchWeather(
        at coordinate: CLLocationCoordinate2D,
        session: URLSession = .shared
    ) async throws -> CurrentWeather {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,precipitation,weather_code,is_day"
            ),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1")
        ]

        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { throw URLError(.badServerResponse) }

        return try decodeWeather(from: data)
    }

    nonisolated static func decodeWeather(from data: Data) throws -> CurrentWeather {
        let payload = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return CurrentWeather(
            temperature: payload.current.temperature,
            apparentTemperature: payload.current.apparentTemperature,
            precipitation: payload.current.precipitation,
            weatherCode: payload.current.weatherCode,
            isDay: payload.current.isDay == 1
        )
    }

    nonisolated static func locationName(
        administrativeArea: String?,
        locality: String?,
        subAdministrativeArea: String?,
        subLocality: String?,
        country: String?
    ) -> String? {
        let regionalComponents = [
            administrativeArea,
            locality,
            subAdministrativeArea,
            subLocality
        ]
        .compactMap { value -> String? in
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        .reduce(into: [String]()) { result, component in
            guard !result.contains(where: {
                $0.compare(component, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) else { return }
            result.append(component)
        }

        if !regionalComponents.isEmpty {
            return regionalComponents.joined(separator: " ")
        }

        let trimmedCountry = country?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCountry?.isEmpty == false ? trimmedCountry : nil
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard isLocationEnabled else {
                availability = .idle
                return
            }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                if weather == nil, !isRefreshing { availability = .loading }
                refreshIfNeeded()
                syncForegroundLifecycle()
            case .denied, .restricted:
                cancelInFlightRefresh()
                syncForegroundLifecycle()
                availability = .locationDenied
            case .notDetermined:
                availability = .requestingLocation
            @unknown default:
                availability = .failed
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        Task { @MainActor [weak self] in
            self?.handleObservedLocation(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.handleLocationFailure()
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    let current: OpenMeteoCurrent
}

private struct OpenMeteoCurrent: Decodable {
    let temperature: Double
    let apparentTemperature: Double
    let precipitation: Double
    let weatherCode: Int
    let isDay: Int

    private enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case apparentTemperature = "apparent_temperature"
        case precipitation
        case weatherCode = "weather_code"
        case isDay = "is_day"
    }
}
