// 템포루틴 — 테마 미디어 온디맨드 저장소 (2026-08-25 대표님 결정 "앞으론 많아질 것 같아서")
//
// 무거운 테마 에셋(영상·대형 이미지)을 번들에서 빼고 **테마 첫 적용 시** 받아 온다.
// 호스팅 = GitHub Releases 정적 파일 — notices.json과 같은 프라이버시 경계(§5.2 무서버:
// 수신 전용 GET, 기기에서 나가는 식별자 0). Apple 쪽 대안은 기각: On-Demand Resources는
// deprecated, Background Assets는 34MB급에 도구 체인 비용이 과하다.
//
// 계약:
// - **번들 우선.** `localURL`은 번들에 있으면 그걸 준다 — 전환기(에셋이 아직 번들에 있는
//   빌드)와 온디맨드기가 같은 코드로 돈다. 번들에서 파일을 지우는 순간 캐시 경로가 이어받는다.
// - **폴백은 호출측 소유.** 다운로드 전·실패 시 nil을 주면 지면은 지면색으로 그린다(§4.5) —
//   여기서 스피너·에러를 띄우지 않는다. 테마가 미디어 없이도 깨지지 않아야 한다.
// - 캐시 = Application Support/ThemeMedia, iCloud 백업 제외(재다운로드 가능한 파생물).
// - 갱신 = 파일 이름에 버전을 박는다(릴리스 태그 교체 아님 — 캐시 무효화가 이름으로 끝난다).

import Foundation
import SwiftUI

@MainActor
@Observable
final class ThemeMedia {
    static let shared = ThemeMedia()

    /// GitHub Releases 태그 하나가 배달 창구다. 에셋이 늘면 이 태그에 파일을 추가한다
    /// (태그를 갈면 구버전 앱의 URL이 죽는다 — 추가만, 교체 금지).
    private static let base = URL(string: "https://github.com/Yewon419/TempoRoutine/releases/download/theme-media-v1")!

    /// 테마 → 필요한 에셋 파일명. 새 미디어 테마는 여기 한 줄 + 릴리스 업로드가 전부다.
    private static let manifest: [AppTheme: [String]] = [
        // -v2 = 2026-08-25 업스케일본(Kling 원본 960²를 2K로 올린 뒤 팬·크로스페이드 재적용).
        // 구 파일명은 릴리스에 그대로 둔다 — 갱신은 이름으로만(위 계약).
        .playlist: ["playlist-spring-bg-v2.mp4", "playlist-summer-bg-v2.mp4",
                    "playlist-autumn-bg-v2.mp4", "playlist-winter-bg.png"],
    ]

    /// 파일이 새로 내려앉을 때마다 +1 — 영상 뷰는 `.id(revision)`으로 재생성해 새 파일을 문다
    /// (AVPlayer는 만들 때의 URL에 묶여서, 다운로드 완료를 스스로 알아채지 못한다).
    private(set) var revision = 0
    private var inFlight: Set<String> = []

    private var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ThemeMedia", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = dir
            try? mutable.setResourceValues(values)
        }
        return dir
    }

    /// 에셋의 지금 위치 — 번들 → 캐시 순서. 없으면 nil(호출측이 지면색 폴백).
    func localURL(named name: String) -> URL? {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        if let bundled = Bundle.main.url(forResource: stem, withExtension: ext) {
            return bundled
        }
        let cached = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: cached.path) ? cached : nil
    }

    /// 테마의 미디어를 보장한다 — 없는 것만 받는다. 실패는 조용히 두고(폴백이 지면을 지킨다)
    /// 다음 호출(테마 재적용·지면 재등장)이 곧 재시도다.
    func ensure(for theme: AppTheme) {
        guard let names = Self.manifest[theme] else { return }
        for name in names where localURL(named: name) == nil && !inFlight.contains(name) {
            inFlight.insert(name)
            let remote = Self.base.appendingPathComponent(name)
            let target = dir.appendingPathComponent(name)
            Task {
                defer { inFlight.remove(name) }
                guard let (temp, response) = try? await URLSession.shared.download(from: remote),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let size = try? FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int,
                      size > 0
                else { return }
                try? FileManager.default.removeItem(at: target)
                guard (try? FileManager.default.moveItem(at: temp, to: target)) != nil else { return }
                revision += 1
            }
        }
    }

    /// 현재 테마 기준 보장 — 앱 시작·테마 변경 훅에서 부른다.
    func ensureCurrent() {
        ensure(for: ThemeStore.current)
    }

    /// 캐시가 지금 쓰는 바이트 — 설정 「캐시 비우기」 표기용. 번들 에셋은 지울 수 없으니 안 센다.
    /// 파일 시스템을 훑으므로 렌더 경로에서 부르지 말 것(설정 진입·삭제 직후에만 재계산).
    var cachedBytes: Int {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return items.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// 캐시 전량 삭제 — 앱 초기화(2026-08-25)와 설정 「캐시 비우기」(2026-08-25 대표님 지시)의
    /// 공통 경로. 기록이 아니라 **재다운로드 가능한 파생물**이라 undo가 없다. 지금 쓰는 테마 몫은
    /// 지면이 다시 필요해질 때 `ensure`가 받아 온다 — 여기서 곧바로 다시 받지는 않는다.
    func purge() {
        try? FileManager.default.removeItem(at: dir)
        revision += 1
    }
}
