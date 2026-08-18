// 템포루틴 — 빠른 추가 추천 목록 (2026-08-16 사용자 지시 / 대본 SSOT = ../빠른추가_추천활동.md)
//
// 2026-08-18 개편(사용자 지시):
// - 축은 **에너지 하나로 통합** — 계절 폴백 표를 겨울→낮음, 봄·가을→보통, 여름→높음으로
//   매핑해 에너지 표에 합쳤다(별도 폴백 경로 폐기). 에너지 레벨이 없으면 계절로 레벨을 정한다.
// - 한 번에 **2개 랜덤**(3개 고정 → 풀에서 무작위 추출. "미묘하게 컨텐츠가 많아 보이게").
// - 칩이 제목만이 아니라 **진행 방식까지 세팅**한다. Input은 문구의 「N분」에서 타이머를
//   유추하고, 그 외는 체크만(nil). Output은 표의 지정값.
//
// ⚠ 여기 문구는 «처방»이 아니라 편집 가능한 기본값이다(§3.3). 탭하면 입력칸이 채워질 뿐
//   바로 저장되지 않는다. ⚠ 낮은 에너지 칸에 재촉을 넣지 않는다(§7).

import Foundation
import TempoCore   // InputCategory·OutputProgressKind·EnergyLevel 계열(repo CLAUDE.md 심볼 확인)

enum QuickAdd {
    /// 칩 하나 — 제목 + 세팅할 진행 방식.
    /// Input에서 kind nil = 「체크만」(Input의 체크만은 progressKind 자체가 nil이다).
    struct Suggestion: Hashable {
        let title: String
        var kind: OutputProgressKind?
        var sessions: Int = 0
        var seconds: Int = 0
    }

    /// 계절 → 에너지 매핑(2026-08-18 사용자 지시) — 겨울=낮음, 봄·가을=보통, 여름=높음.
    /// 에너지 레벨이 아직 없을 때(그 계절 체크인 3회 미만)의 초기값.
    static func level(forSeason name: String?) -> EnergyLevel {
        switch name {
        case "겨울": .low
        case "여름": .high
        default: .mid   // 봄·가을·미상
        }
    }

    /// Input 제목 → 진행 방식 유추: 「N분」이 있으면 타이머 N분, 없으면 체크만(nil)
    private static func input(_ title: String) -> Suggestion {
        if let range = title.range(of: #"([0-9]+)분"#, options: .regularExpression),
           let minutes = Int(title[range].dropLast()) {
            return Suggestion(title: title, kind: .timer, seconds: minutes * 60)
        }
        return Suggestion(title: title, kind: nil)
    }

    // ── Input : 카테고리 × 에너지 (2026-08-18 사용자 수정 문구 + 구 계절 폴백 병합) ──
    static func inputs(category: InputCategory, level: EnergyLevel) -> [Suggestion] {
        let titles: [String]
        switch (category, level) {
        case (.food, .low):
            titles = ["소화 편한 죽 한 그릇", "따뜻한 차 한 잔", "영양제 챙기기",
                      "따뜻한 국 한 그릇"]                                    // + 겨울
        case (.food, .mid):
            titles = ["제철 재료로 한 끼", "건강한 아침식사", "영양제 챙기기",
                      "가벼운 아침 식사", "샐러드 도시락",                      // + 봄
                      "든든한 저녁 챙기기", "제철 버섯 요리", "따뜻한 수프 한 그릇"] // + 가을
        case (.food, .high):
            titles = ["새 레시피 도전", "치팅데이", "영양제 챙기기",
                      "시원한 과일 한 접시"]                                  // + 여름
        case (.exercise, .low):
            titles = ["가벼운 스트레칭 10분", "폼롤러", "누워서 하는 요가",
                      "가볍게 걷기 20분", "실내 스트레칭 15분"]                 // + 겨울
        case (.exercise, .mid):
            titles = ["동네 산책 30분", "홈트 한 세트", "아침 요가",
                      "저녁 산책", "자전거 30분",                             // + 봄
                      "저녁 요가"]                                           // + 가을
        case (.exercise, .high):
            titles = ["러닝", "헬스장", "새로운 스포츠 도전",
                      "수영 30분", "아침 러닝", "실내 클라이밍"]                // + 여름
        case (.media, .low):
            titles = ["영화 한 편", "클래식 음악 듣기", "독서",
                      "힐링 드라마 한 편"]                                    // + 겨울
        case (.media, .mid):
            titles = ["팟캐스트 한 편", "전시 보러 가기", "독서",
                      "새 장르 노래 들어보기",                                 // + 봄
                      "책 한 챕터", "다큐 한 편"]                             // + 가을
        case (.media, .high):
            titles = ["악기 연주", "그림 그리기", "카페에서 독서",
                      "노래하기", "영화 보러 가기"]                            // + 여름
        case (.other, .low):
            titles = ["오늘은 일찍 잠들기", "따뜻한 물로 샤워"]                 // + 겨울
        case (.other, .mid):
            titles = ["물 자주 마시기",
                      "새 문구류 쇼핑", "화분에 물 주기",                       // + 봄
                      "반신욕", "다이어리 정리"]                              // + 가을
        case (.other, .high):
            titles = ["혼자만의 패션쇼",
                      "맛집탐방", "공원 피크닉"]                              // + 여름
        }
        // 병합으로 생길 수 있는 중복만 걷는다(순서 유지)
        var seen = Set<String>()
        return titles.filter { seen.insert($0).inserted }.map(input)
    }

    // ── Output : 에너지별 (2026-08-18 사용자 수정 표 전사) ──
    /// 「오늘 할 일 적어두기」는 체크만으로 복원 — 원래 체크만 취지였는데 Output에 체크만이
    /// 없어 퍼센트로 두었던 것(대본 각주). 이번에 체크만이 생겨 제자리로.
    static func outputs(level: EnergyLevel?) -> [Suggestion] {
        switch level ?? .mid {
        case .low:
            [Suggestion(title: "오늘 할 일 적어두기", kind: .checkOnly),
             Suggestion(title: "자료 한 편 읽기", kind: .timer, seconds: 20 * 60),
             Suggestion(title: "메일함 체크", kind: .timer, seconds: 15 * 60),
             Suggestion(title: "자격증 공부", kind: .timer, seconds: 30 * 60),
             Suggestion(title: "공부 한 챕터", kind: .sessions, sessions: 1)]
        case .mid:
            [Suggestion(title: "공부 한 챕터", kind: .sessions, sessions: 2),
             Suggestion(title: "초안 쓰기", kind: .percent),
             Suggestion(title: "강의 한 편 듣기", kind: .timer, seconds: 50 * 60),
             Suggestion(title: "자격증 공부", kind: .timer, seconds: 60 * 60)]
        case .high:
            [Suggestion(title: "자격증 공부", kind: .timer, seconds: 90 * 60),
             Suggestion(title: "프로젝트 한 단계 끝내기", kind: .percent),
             Suggestion(title: "발표 자료 만들기", kind: .sessions, sessions: 3),
             Suggestion(title: "공부 한 챕터", kind: .sessions, sessions: 3)]
        }
    }
}
