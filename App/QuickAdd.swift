// 템포루틴 — 빠른 추가 추천 목록 (2026-08-16 사용자 지시 / 대본 SSOT = ../빠른추가_추천활동.md)
//
// 축 = **에너지만**(D1·D3 결정 — 기분은 쓰지 않는다). 한 번에 **3개**(D2).
// 컨디션 기록이 아직 없으면(그 계절 체크인 3회 미만) **계절 일반 경향**으로 대체한다(D5).
//
// ⚠ 여기 문구는 «처방»이 아니라 편집 가능한 기본값이다(§3.3). 탭하면 입력칸이 채워질 뿐
//   바로 저장되지 않는다 — 시트에는 저장 버튼이 따로 있고, 잘못 눌렀을 때 되돌릴 자리가 필요하다.
// ⚠ 낮은 에너지 칸에 재촉을 넣지 않는다(§7).

import Foundation
import TempoCore   // InputCategory·OutputProgressKind는 TempoCore 소유(CardTypes.swift)

enum QuickAdd {
    // ── Input : 카테고리 × 에너지 ──
    // ①은 종전 EnergyProfile.inputExample 값(placeholder로 쓰이던 것)을 그대로 승계한다.
    static func inputs(category: InputCategory, level: EnergyLevel) -> [String] {
        switch (category, level) {
        case (.food, .low):      ["소화 편한 죽 한 그릇", "따뜻한 차 한 잔", "과일 몇 조각"]
        case (.food, .mid):      ["제철 재료로 한 끼", "도시락 싸기", "국 한 냄비 끓여두기"]
        case (.food, .high):     ["새 레시피 도전", "밑반찬 세 가지 만들기", "장 봐서 채워두기"]
        case (.exercise, .low):  ["가볍게 스트레칭 10분", "목·어깨 풀기 5분", "누워서 다리 뻗기"]
        case (.exercise, .mid):  ["동네 산책 30분", "요가 20분", "계단으로 올라가기"]
        case (.exercise, .high): ["달리기 5km", "근력 운동 40분", "자전거로 한 바퀴"]
        case (.media, .low):     ["포근한 영화 한 편", "좋아하는 앨범 듣기", "짧은 영상 하나"]
        case (.media, .mid):     ["팟캐스트 한 편", "드라마 한 편", "책 20쪽"]
        case (.media, .high):    ["미뤄둔 다큐 정주행", "전시 보러 가기", "새 앨범 통으로 듣기"]
        case (.other, .low):     ["오늘은 일찍 잠들기", "따뜻한 물로 샤워", "조명 낮추고 쉬기"]
        case (.other, .mid):     ["물 자주 마시기", "침구 정리", "창문 열고 환기"]
        case (.other, .high):    ["책상 정리", "옷장 한 칸 비우기", "미뤄둔 연락하기"]
        }
    }

    // ── Input 폴백 : 카테고리 × 계절 (D5) ──
    // 에너지 레벨이 아직 없을 때. ①은 종전 CardAddSheets.examples 값 승계.
    // 계절명은 SeasonMeta.name과 같은 문자열을 키로 쓴다.
    static func inputs(category: InputCategory, season: String) -> [String] {
        let table: [InputCategory: [String: [String]]] = [
            .food: [
                "겨울": ["따뜻한 국 한 그릇", "뜨끈한 죽 한 그릇", "생강차 한 잔"],
                "봄":   ["가벼운 아침 식사", "나물 한 접시", "샐러드 도시락"],
                "여름": ["시원한 과일 한 접시", "냉국 한 그릇", "물 한 병 챙기기"],
                "가을": ["든든한 저녁 챙기기", "제철 버섯 요리", "따뜻한 수프 한 그릇"],
            ],
            .exercise: [
                "겨울": ["가볍게 걷기 20분", "실내 스트레칭 15분", "홈트 20분"],
                "봄":   ["아침 러닝", "꽃길 산책 40분", "자전거 30분"],
                "여름": ["수영 30분", "이른 아침 산책", "실내 클라이밍"],
                "가을": ["저녁 요가", "단풍길 걷기 1시간", "등산 반나절"],
            ],
            .media: [
                "겨울": ["포근한 영화 한 편", "겨울 플레이리스트", "긴 소설 시작하기"],
                "봄":   ["새 플레이리스트 찾기", "산책하며 팟캐스트", "사진 정리"],
                "여름": ["팟캐스트 한 편", "시원한 스릴러 한 편", "여행 영상 보기"],
                "가을": ["책 한 챕터", "다큐 한 편", "전시 관람"],
            ],
            .other: [
                "겨울": ["철분 챙기기", "가습기 물 채우기", "손발 따뜻하게"],
                "봄":   ["새 노트 펴기", "옷장 정리", "화분에 물 주기"],
                "여름": ["물 자주 마시기", "선크림 챙기기", "이불 햇볕에 널기"],
                "가을": ["반신욕", "침구 두껍게 바꾸기", "다이어리 정리"],
            ],
        ]
        return table[category]?[season] ?? []
    }

    // ── Output : 에너지별 ──
    /// 제목과 함께 진행 방식·목표까지 채운다 — 탭 한 번으로 목표가 서게(대본 3번 표).
    /// ⚠ Output 진행 방식에는 「체크만」이 없다(Input에만 있다) — kind는 optional이 아니다.
    struct OutputSuggestion: Hashable {
        let title: String
        let kind: OutputProgressKind
        /// .sessions 목표 회수(그 외 0)
        var sessions: Int = 0
        /// .timer 목표 초(그 외 0)
        var seconds: Int = 0
    }

    /// ⚠ Output에는 계절 폴백 대본이 없다 — 에너지 레벨이 없으면 **보통** 목록으로 간다.
    ///   Input과 달리 Output 활동은 계절색이 옅어(공부·정리·작성) 계절판을 따로 두는 실익이 없었다.
    static func outputs(level: EnergyLevel?) -> [OutputSuggestion] {
        switch level ?? .mid {
        case .low:
            // 「체크만」이 없어 가장 가벼운 퍼센트로 둔다 — 적어두고 0%에서 시작하는 자리
            [OutputSuggestion(title: "오늘 할 일 적어두기", kind: .percent),
             OutputSuggestion(title: "자료 한 편 읽기", kind: .timer, seconds: 20 * 60),
             OutputSuggestion(title: "메일함 비우기", kind: .timer, seconds: 15 * 60)]
        case .mid:
            [OutputSuggestion(title: "공부 한 챕터", kind: .sessions, sessions: 2),
             OutputSuggestion(title: "초안 쓰기", kind: .percent),
             OutputSuggestion(title: "강의 한 편 듣기", kind: .timer, seconds: 50 * 60)]
        case .high:
            [OutputSuggestion(title: "자격증 공부", kind: .timer, seconds: 90 * 60),
             OutputSuggestion(title: "프로젝트 한 단계 끝내기", kind: .percent),
             OutputSuggestion(title: "발표 자료 만들기", kind: .sessions, sessions: 3)]
        }
    }
}
