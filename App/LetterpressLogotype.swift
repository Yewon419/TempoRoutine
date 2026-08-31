// 템포루틴 — 활판 계절 로고타입 (시안 SSOT: ui-mockup/theme/DESIGN.md §2.3, 2026-08-31 이식)
// 대표님 레퍼런스 = 자이언트 Didone 탁상 캘린더("JANU / A / RY"): 계절 라틴명을 여러 행으로
// 쪼개 편집 포스터처럼 세운다. 오늘 탭 활판 표제가 한글 음각 대신 이 로고타입으로 간다.
//
// 규칙 둘:
// ① **글자 크기는 전 계절 고정**(2026-08-31 "글씨 크기는 바꾸지마") — 계절 구분은 행 분할과
//    들여쓰기로만. 크기를 계절마다 달리하면 같은 지면에서 표제 무게가 널뛴다.
// ② **잉크 + 눌린 자국**(같은 날 "음각느낌") — §2.3-1 음각은 지면색 활자였지만 여기선 색을
//    살린다. 실제 활판 인쇄가 그렇다: 잉크가 얹히고 종이가 눌린다. 어두운 선(상좌) + 흰 선(하우).
//
// ⚠ 겨울 기각 4안: 1-4-1(가을 4-1-1과 실루엣 중복) · 3-3 대칭(봄과 구조 중복) ·
//   넓은 자간 단일 행(날짜 스탬프와 충돌) · 스케일 대비 2-4(①위반).

import SwiftUI
import TempoCore

enum LetterpressLogotype {
    /// 활판 잉크 — 시안 `--lp-ink`(#8A5A3E). 월 표제 07도 같은 값을 쓴다.
    static let ink = Color(red: 138 / 255, green: 90 / 255, blue: 62 / 255)

    /// 표제 크기(pt) — 시안 86px 동값(100 → 86, 2026-09-01 베타 "Spring 위아랫줄이
    /// 겹쳐보이니 글씨크기 좀 줄이자"). 전 계절 공통(규칙 ①)은 유지.
    static let size: CGFloat = 86

    /// 행 = (글자, 좌 들여쓰기 = 폭 비율). 시안 SEASON_SIM과 동값.
    static func rows(for phase: CyclePhase) -> [(String, CGFloat)] {
        switch phase {
        case .follicular: [("SPR", 0), ("ING", 0.34)]          // 봄 = 3-3 대각
        case .ovulation:  [("SU", 0), ("MM", 0.26), ("ER", 0.52)]   // 여름 = 2-2-2 균일 계단
        case .luteal:     [("AUTU", 0), ("M", 0.37), ("N", 0.63)]   // 가을 = 4-1-1(레퍼런스 원형)
        case .menstrual:  [("WI", 0), ("NTE", 0.18), ("R", 0.62)]   // 겨울 = 2-3-1 불규칙 계단
        }
    }

    /// 날짜 스탬프가 앉을 세로 자리 — 계절마다 로고타입이 비우는 자리가 다르다(시안 stampTop).
    /// 가을만 첫 행(AUTU)이 폭을 다 써서 스탬프를 M 행 옆으로 내린다.
    static func stampTop(for phase: CyclePhase) -> CGFloat {
        phase == .luteal ? 86 : 16   // 크기 100 → 86 동반 조정
    }

    /// 행 높이 = 시안 line-height .8
    static let lineHeight: CGFloat = 0.8
}

/// 오늘 탭 활판 표제 — 계절 라틴명 행분할 로고타입.
/// 라틴 전용이라 로컬라이제이션 대상이 아니다(활판 인용문·라틴 날짜 스탬프와 같은 규약, §2.3-5).
struct LetterpressSeasonLogotype: View {
    let phase: CyclePhase

    private var rows: [(String, CGFloat)] { LetterpressLogotype.rows(for: phase) }

    var body: some View {
        // 들여쓰기가 폭 비율이라 부모 폭이 필요하다. 높이는 행수로 확정해 레이아웃에 돌려준다
        // (GeometryReader는 높이를 스스로 못 정한다).
        let size = LetterpressLogotype.size
        let lineBox = size * LetterpressLogotype.lineHeight
        return GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    line(row.0, indent: geo.size.width * row.1, box: lineBox)
                }
            }
        }
        .frame(height: lineBox * CGFloat(rows.count))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(seasonMeta(for: phase).name)
    }

    /// 한 행 — Bodoni 대문자 + 잉크 음각 2겹. 라인박스를 시안 값으로 못 박는다
    /// (서체 기본 리딩을 두면 행 사이가 벌어져 로고타입이 안 된다 — 월 표제 150pt 전례).
    private func line(_ text: String, indent: CGFloat, box: CGFloat) -> some View {
        Text(text)
            .font(.letterpressLatin(size: LetterpressLogotype.size))
            .foregroundStyle(LetterpressLogotype.ink)
            .shadow(color: Color(red: 66 / 255, green: 38 / 255, blue: 22 / 255).opacity(0.42),
                    radius: 0.8, x: -1, y: -1)
            .shadow(color: .white.opacity(0.95), radius: 1, x: 1, y: 1.4)
            .fixedSize()
            .frame(height: box, alignment: .center)
            .padding(.leading, indent)
    }
}

extension Font {
    /// 활판 라틴 표제 — Bodoni Moda(variable named instance). 미등록 시 시스템 세리프 폴백.
    static func letterpressLatin(size: CGFloat) -> Font {
        guard LetterpressFont.available else { return .system(size: size, design: .serif) }
        return .custom("BodoniModa-Regular", size: size)
    }
}
