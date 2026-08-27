// 템포루틴 — 개발자 모드 (2026-08-27 대표님 지시)
//
// 왜: 출시 후 대표님이 실사용자이기도 하다 — 업데이트 스크린샷·시연을 찍으려면 화면에
// 본인 기록이 없어야 한다. 개발자 모드는 **별도 스토어(dev-store)** 위에서 도는 깨끗한
// 앱이다: 실기록은 읽지도 쓰지도 않고, 모든 테마가 열려 있다.
//
// 계약:
// - 진입/종료 = 소식란 피드백 입력칸에 `//dev` 입력(+ dev 중엔 설정에 종료 행).
//   숨은 커맨드인 이유: 일반 사용자 표면에 버튼을 두면 심사·혼란 리스크만 늘고,
//   이 모드의 사용자는 한 명이다.
// - 데이터 = `dev-store.sqlite`(Application Support). 실스토어(default.store)와 파일부터
//   분리 — 모드 안에서 뭘 만들고 지워도 실기록 무접촉. 스크린샷용 표본은 dev 모드에서
//   「백업 가져오기」로 샘플 JSON(tools/make_review_sample.py)을 넣으면 된다.
// - dev 중 정지: 기기 간 동기화 미러·건강 앱 동기화·위젯 발행·알림 재예약.
//   전부 실데이터를 만지거나(동기화·건강) 실표면을 덮는(위젯·알림 — 빈 스토어 기준
//   재예약은 실알림 취소가 된다) 경로라서다. UserDefaults(테마·언어·원장)는 공유 —
//   단, 체크인 완성의 씨앗 원장 기입은 막는다(dev 기록이 실씨앗을 벌면 안 된다).
// - 소유 판정 = 전부 열림(테마 탭 「적용하기」만 남는다). 체험 종료 시트·평가 요청도 정지.

import Foundation

enum DevMode {
    static let key = "devModeActive"

    /// 켜져 있는가 — 판정 지점들이 읽는 단일 창구.
    static var active: Bool { UserDefaults.standard.bool(forKey: key) }

    /// 커맨드 문자열 — 소식란 피드백 입력칸에서 가로챈다.
    static let command = "//dev"

    /// 토글 — @AppStorage(key) 관찰자(앱 씬)가 이 쓰기를 받아 컨테이너를 갈아끼운다.
    /// 반환 = 토글 후 상태.
    @discardableResult
    static func toggle() -> Bool {
        let next = !active
        UserDefaults.standard.set(next, forKey: key)
        return next
    }
}
