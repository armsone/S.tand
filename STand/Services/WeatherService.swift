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
    @Published private(set) var weather: CurrentWeather?
    @Published private(set) var locationName: String?
    @Published private(set) var availability = WeatherAvailability.idle
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLocationEnabled = true

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let session: URLSession
    private var refreshTask: Task<Void, Never>?

    var locationAuthorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
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
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func refreshIfNeeded(force: Bool = false) {
        guard isLocationEnabled else { return }
        if !force,
           let lastUpdated,
           Date().timeIntervalSince(lastUpdated) < 30 * 60 {
            return
        }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            availability = .requestingLocation
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            availability = .loading
            locationManager.requestLocation()
        case .denied, .restricted:
            availability = .locationDenied
        @unknown default:
            availability = .failed
        }
    }

    func setLocationEnabled(_ enabled: Bool) {
        guard isLocationEnabled != enabled else {
            if enabled { refreshIfNeeded() }
            return
        }
        isLocationEnabled = enabled
        if enabled {
            refreshIfNeeded(force: true)
        } else {
            refreshTask?.cancel()
            refreshTask = nil
            geocoder.cancelGeocode()
            weather = nil
            locationName = nil
            lastUpdated = nil
            availability = .idle
        }
    }

    private func loadWeather(at location: CLLocation) {
        refreshTask?.cancel()
        locationName = nil
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let weather = try await Self.fetchWeather(
                    at: location.coordinate,
                    session: session
                )
                guard !Task.isCancelled else { return }
                self.weather = weather
                self.lastUpdated = .now
                self.availability = .available

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
                   !Task.isCancelled {
                    self.locationName = resolvedName
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.availability = .failed
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
                availability = .loading
                manager.requestLocation()
            case .denied, .restricted:
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
            guard let self, isLocationEnabled else { return }
            loadWeather(at: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.availability = .failed
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
