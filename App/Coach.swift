// 템포루틴 — 기능 튜토리얼 코치마크 (2026-07-23 사용자 지시: JejuNow CoachMark 문법 이식)
// 문법(JejuNow coach.ts·CoachMark.tsx와 동형): 화면당 1개 코치 + 단계 배열(anchor·제목·본문),
// 스포트라이트(대상만 뚫린 어두운 오버레이 + 링) + 말풍선 카드(n/N·건너뛰기·다음/알겠어요),
// 1회 노출(UserDefaults), 대상 없으면 그 단계 스킵, 한 단계도 못 보여줬으면 완료 저장 안 함
// (콜드스타트 — 내용이 생기면 그때 보여준다), 완료 시 성공 햅틱, 설정 "사용법 다시 보기" 리셋.
// §3.6.1 준수: 설명만 한다 — 실권한·실동작을 태우지 않는다. 시각 언어는 앱 토큰(§4).

import SwiftUI

enum CoachAnchor: String {
    case todaySchedule, todayInput, todayOutput
    case calendarLog, calendarGrid
    case todaySeed                              // 씨앗 최초 획득 안내(2026-08-12)
    case themeSeedBalance, themeCardAction      // 테마 탭 첫 진입 안내(2026-08-12)
}

struct CoachStep {
    let anchor: CoachAnchor
    let title: String
    let body: String
}

enum CoachID: String, CaseIterable {
    case today, calendar
    /// 씨앗을 처음 얻은 뒤 오늘 탭 배지에서 1회(2026-08-12 사용자 지시)
    case seed
    /// 테마 탭 첫 진입 1회(2026-08-12 사용자 지시)
    case themeShop
}

enum CoachStore {
    private static func key(_ id: CoachID) -> String { "coach.\(id.rawValue)" }
    static func isDone(_ id: CoachID) -> Bool { UserDefaults.standard.bool(forKey: key(id)) }
    static func markDone(_ id: CoachID) { UserDefaults.standard.set(true, forKey: key(id)) }
    /// 설정 「사용법 다시 보기」 — 전 화면 완료 표시를 지운다(JejuNow resetAllCoach와 동형)
    static func resetAll() {
        CoachID.allCases.forEach { UserDefaults.standard.removeObject(forKey: key($0)) }
    }
}

enum CoachSteps {
    /// 오늘 탭 — 일정·Input·Output 3구획(§3.6 카드 정의를 사용자 언어로)
    static let today: [CoachStep] = [
        CoachStep(anchor: .todaySchedule, title: "일정",
                  body: "약속이나 생일같은 일정을 적어봐요. 텍스트에서 시간을 자동으로 읽어올수도 있어요."),
        CoachStep(anchor: .todayInput, title: "Input",
                  body: "식단이나 운동처럼 나를 채우는 일들이에요.\n각 계절에 맞는 인풋으로 당신을 채워봐요."),
        CoachStep(anchor: .todayOutput, title: "Output",
                  body: "프로젝트나 공부처럼 내보내는 일들이에요. 계절에 따라 분량을 조절해보면 어떨까요?"),
    ]
    /// 캘린더 탭 — 생리 기록 입구 + 그리드 읽는 법
    static let calendar: [CoachStep] = [
        CoachStep(anchor: .calendarLog, title: "생리 기록은 여기서",
                  body: "이 버튼이 기록의 입구예요. 날짜 칸을 탭해서 기록하고, 지난 기록도 고칠 수 있어요."),
        // 2026-08-11 정정: 계절 문법 대개정(2026-07-28 3차)을 안 따라온 카피였다.
        // 숫자는 먹색이고 계절은 숫자 뒤 글로우(numberColor) · 예상 생리일은 시각 표시 없음
        // (render.predicted = a11y 전용) · 코랄은 겨울 띠와 어긋난 기록만이라 범례에도 없어
        // (2026-08-01 「기록」 스와치 폐기) 첫 안내에서 뺀다.
        CoachStep(anchor: .calendarGrid, title: "날짜 아래 선으로 계절을 알 수 있어요",
                  body: "날짜를 탭하면 빠르게 일정을 추가할 수 있어요. 길게 누르고 드래그해 며칠에 걸친 일정도 추가할 수 있어요. \n길게 누르면 하루 상세 탭으로 넘어갑니다."),
    ]
    /// 씨앗 최초 획득 — 오늘 탭 우상단 배지에서 1회(2026-08-12 사용자 지시).
    /// 얻는 법·쓰는 곳을 한 번에 말한다. 재촉은 하지 않는다(§7) — 사실만.
    static let seed: [CoachStep] = [
        // 제목에 개수를 넣지 않는다 — 「사용법 다시 보기」로 리셋하면 이미 여러 개를 가진
        // 사람에게도 다시 뜬다(2026-08-12).
        CoachStep(anchor: .todaySeed, title: "씨앗이 모였어요",
                  body: "하루 체크인을 완성할 때마다 씨앗이 하나씩 모여요. 탭하면 테마 화면이 열리고, 모은 씨앗으로 새 테마를 구매할 수 있어요."),
    ]
    /// 테마 탭 첫 진입 — 잔액이 무엇인지, 구매와 적용이 왜 따로인지(§3.8.1 구매·적용 분리)
    static let themeShop: [CoachStep] = [
        CoachStep(anchor: .themeSeedBalance, title: "지금 가진 씨앗",
                  body: "하루 체크인을 완성하면 씨앗이 하나씩 모여요."),
        CoachStep(anchor: .themeCardAction, title: "테마의 적용도 이곳에서 할 수 있어요.",
                  body: "새로운 테마, 새로운 기분으로 템포루틴을 즐겨보세요!"),
    ]
}

// ── 앵커 수집 (JejuNow의 data-coach 속성 등가 — 좌표가 아니라 뷰에 붙어 따라간다) ──
struct CoachAnchorKey: PreferenceKey {
    static var defaultValue: [CoachAnchor: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [CoachAnchor: Anchor<CGRect>],
                       nextValue: () -> [CoachAnchor: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func coachAnchor(_ id: CoachAnchor) -> some View {
        anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// `enabled` = 화면 진입 말고 다른 순간에 열려야 하는 코치용(2026-08-12 씨앗 최초 획득).
    /// false로 시작해 true가 되는 순간에도 발동한다 — onAppear만 보면 화면에 머무는 동안
    /// 생긴 조건(체크인을 완성해 씨앗이 처음 생김)을 영영 못 잡는다.
    func coachOverlay(id: CoachID, steps: [CoachStep], enabled: Bool = true) -> some View {
        overlayPreferenceValue(CoachAnchorKey.self) { anchors in
            CoachOverlay(id: id, steps: steps, anchors: anchors, enabled: enabled)
        }
    }
}

// ── 스포트라이트 오버레이 ──
private struct CoachOverlay: View {
    let id: CoachID
    let steps: [CoachStep]
    let anchors: [CoachAnchor: Anchor<CGRect>]
    let enabled: Bool

    @State private var active = false
    @State private var index = 0
    @State private var shownAny = false
    @State private var successFeedback = 0

    private let pad: CGFloat = 8   // 스포트라이트가 대상보다 살짝 넓게

    var body: some View {
        GeometryReader { proxy in
            if active, let shownIndex = resolvedIndex(from: index) {
                let step = steps[shownIndex]
                let rect = proxy[anchors[step.anchor]!].insetBy(dx: -pad, dy: -pad)
                let isLast = resolvedIndex(from: shownIndex + 1) == nil
                ZStack(alignment: .topLeading) {
                    // 빈 공간 탭 = 다음 (2026-07-25 사용자 지시). 카드 버튼이 위에 있어 탭을 먼저 받는다
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { advance(from: shownIndex) }
                        .accessibilityHidden(true)
                    // 구멍 뚫린 배경(even-odd) + 링 — 히트테스트 제외 필수: 채운 Shape가 위에 있으면
                    // 아래 탭 캐처가 탭을 못 받는다(2026-07-27 리뷰 — 빈 공간 탭 진행이 막히는 결함)
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: proxy.size))
                        p.addRoundedRect(in: rect, cornerSize: CGSize(width: 12, height: 12))
                    }
                    .fill(Color.black.opacity(0.72), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.7), lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .allowsHitTesting(false)
                    card(step: step, shownIndex: shownIndex, isLast: isLast, rect: rect, size: proxy.size)
                }
                .onAppear { shownAny = true }
                .accessibilityAddTraits(.isModal)
            }
        }
        .ignoresSafeArea()
        .sensoryFeedback(.success, trigger: successFeedback)
        .onAppear { activateIfNeeded() }
        .onChange(of: enabled) { _, _ in activateIfNeeded() }
    }

    private func activateIfNeeded() {
        guard enabled, !active, !CoachStore.isDone(id) else { return }
        Task {   // 대상이 그려질 때까지 한 박자 양보(JejuNow 400ms와 동형)
            try? await Task.sleep(nanoseconds: 400_000_000)
            active = true
        }
    }

    /// index부터 앵커가 실제로 존재하는 첫 단계 — 없으면 nil(그 단계 스킵)
    private func resolvedIndex(from: Int) -> Int? {
        var i = from
        while i < steps.count {
            if anchors[steps[i].anchor] != nil { return i }
            i += 1
        }
        return nil
    }

    /// 다음 단계로 — 남은 단계가 없으면 종료 (버튼·빈 공간 탭 공용)
    private func advance(from shownIndex: Int) {
        if resolvedIndex(from: shownIndex + 1) == nil { finish() } else { index = shownIndex + 1 }
    }

    private func finish() {
        if shownAny {
            CoachStore.markDone(id)
            successFeedback += 1
        }
        active = false
    }

    private func card(step: CoachStep, shownIndex: Int, isLast: Bool,
                      rect: CGRect, size: CGSize) -> some View {
        let cardHeight: CGFloat = 250   // 배치용 추정치 — 본문이 길어져 상향(2026-07-25)
        let below = rect.maxY + cardHeight + 20 < size.height
        let y = below ? min(rect.maxY + 14, size.height - cardHeight - 20)
                      : max(rect.minY - cardHeight - 14, 20)
        return VStack(alignment: .leading, spacing: 8) {
            // 단계가 하나뿐인 코치(씨앗 획득)는 「1 / 1」이 정보가 아니라 잡음이다(2026-08-12)
            if steps.count > 1 {
                Text("\(shownIndex + 1) / \(steps.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Ink.winter)
            }
            Text(step.title)
                .font(.almanac(size: 19, weight: .bold))
                .foregroundStyle(Ink.text)
            Text(step.body)
                .font(.subheadline)
                .foregroundStyle(Ink.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                // 단계가 하나면 건너뛰기와 「알겠어요」가 같은 동작이라 버튼이 둘일 이유가 없다
                if steps.count > 1 {
                    Button("건너뛰기") { finish() }
                        .font(.subheadline)
                        .foregroundStyle(Ink.text.opacity(0.55))
                }
                Spacer()
                Button {
                    advance(from: shownIndex)
                } label: {
                    Text(isLast ? "알겠어요" : "다음")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Ink.paper)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Ink.text, in: Capsule())   // 먹색 채움(§8.1)
                }
            }
            .padding(.top, 6)
        }
        .padding(18)
        .background(Ink.paper, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        .frame(maxWidth: 440)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .offset(y: y)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(steps.count > 1
                            ? Loc.fmt("사용법 안내 %1$@ / %2$@. %3$@. %4$@", "\(shownIndex + 1)", "\(steps.count)", "\(step.title)", "\(step.body)")
                            : Loc.fmt("사용법 안내. %1$@. %2$@", "\(step.title)", "\(step.body)"))
    }
}
