// 템포루틴 — 날씨 데이터 공급자 (시안 §5.5, Phase ② 2026-08-19)
// WeatherKit + CoreLocation 대략적 위치(NSLocationDefaultAccuracyReduced — 시 단위면 충분).
// 실패 폴백 = 마지막 값 유지 → 맑음(§5.7. 마지막 값은 WxState가 UserDefaults에 저장).
// 진입점 = WeatherSky.task(하늘 지면이 뜰 때) — 하늘이 필요할 때만 위치·네트워크를 쓴다.
// 위치는 델리게이트 없이 `manager.location`(마지막 알려진 위치)만 읽는다 — 날씨엔 충분하고,
// Swift 6 격리에서 델리게이트 콜백 홉을 피한다. 권한 직후 캐시가 비면 다음 등장 때 잡힌다.

import CoreLocation
import WeatherKit

@MainActor
final class WxProvider: NSObject {
    static let shared = WxProvider()

    private let manager = CLLocationManager()
    private var lastFetch: Date?
    /// 적용 게이트의 권한 대기(ThemeShop) — 시스템 시트 응답까지 suspend
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override private init() {
        super.init()
        manager.delegate = self
    }

    /// 현재 권한 — 적용 게이트(ThemeShop)가 읽는다
    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    /// 날씨 테마 적용 게이트(2026-08-19 사용자 확정 — 체험 포함): 미결정이면 시스템 시트를
    /// 띄우고 응답을 기다린다. 이미 결정된 상태면 그 값을 바로 돌려준다.
    func requestAuthorization() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    /// 30분 스로틀 — 화면 등장마다 불리는 진입점이라 여기서 막는다
    func refreshIfNeeded() async {
        guard ThemeStore.chrome.skyGround else { return }
        if let lastFetch, Date.now.timeIntervalSince(lastFetch) < 1800 { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            // 테마 적용 후 첫 하늘에서 묻는다(§5.5 「테마 적용 시 요청」과 같은 순간)
            manager.requestWhenInUseAuthorization()
            return
        case .authorizedWhenInUse, .authorizedAlways:
            break
        default:
            return   // 거부·제한 = 마지막 값 유지(적용 차단 안내는 테마 탭 게이트 몫)
        }
        guard let location = manager.location else {
            // 캐시 워밍 — 결과는 다음 등장 때 location으로 집어간다
            manager.startUpdatingLocation()
            manager.stopUpdatingLocation()
            return
        }
        lastFetch = .now
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            WxState.applyCondition(Self.fourWay(weather.currentWeather.condition))
        } catch {
            // 실패 = 마지막 값 유지(§5.7) — 다음 스로틀 창에서 재시도
            lastFetch = nil
        }
    }

    /// WeatherKit 세분 조건 → 시안 4분류(§5.7). 모르는 조건은 구름으로 접는다 —
    /// 하늘이 아예 틀리는 것보다 흐린 쪽이 안전하다.
    static func fourWay(_ condition: WeatherCondition) -> WxCondition {
        switch condition {
        case .clear, .mostlyClear:
            .clear
        case .rain, .heavyRain, .drizzle, .freezingRain, .freezingDrizzle,
             .thunderstorms, .isolatedThunderstorms, .scatteredThunderstorms,
             .strongStorms, .hail, .sunShowers:
            .rain
        case .snow, .heavySnow, .flurries, .sunFlurries, .sleet, .wintryMix, .blizzard:
            .snow
        default:
            .cloud   // cloudy·partlyCloudy·foggy·haze·smoky·windy 등 구름 계열
        }
    }
}

extension WxProvider: CLLocationManagerDelegate {
    /// 권한 변경 — 적용 게이트의 대기(continuation)를 깨운다.
    /// ⚠ 델리게이트 설정 직후에도 한 번 불린다(.notDetermined) — 그건 응답이 아니다.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        Task { @MainActor in
            self.authContinuation?.resume(returning: status)
            self.authContinuation = nil
        }
    }
}
