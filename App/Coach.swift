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
}

struct CoachStep {
    let anchor: CoachAnchor
    let title: String
    let body: String
}

enum CoachID: String, CaseIterable {
    case today, calendar
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
                  body: "약속이나 생일처럼 못 옮기는 날들이에요. 하루의 닻이라, 계절과 상관없이 그대로 둬요."),
        CoachStep(anchor: .todayInput, title: "Input",
                  body: "식단이나 운동처럼 나를 채우는 일들이에요. 가볍게 체크만 하면 되고, 주기 기준으로 반복시킬 수도 있어요."),
        CoachStep(anchor: .todayOutput, title: "Output",
                  body: "프로젝트나 공부처럼 내보내는 일들이에요. 진행도로 쌓이고, 계절에 맞춰 시동과 마무리를 비춰드려요."),
    ]
    /// 캘린더 탭 — 생리 기록 입구 + 그리드 읽는 법
    static let calendar: [CoachStep] = [
        CoachStep(anchor: .calendarLog, title: "생리 기록은 여기서",
                  body: "이 버튼이 기록의 입구예요. 날짜 칸을 탭해서 기록하고, 지난 기록도 같은 화면에서 고칠 수 있어요."),
        CoachStep(anchor: .calendarGrid, title: "숫자 색이 계절이에요",
                  body: "날짜를 탭하면 그날의 일정과 계획이 열려요. 코랄 형광펜은 기록한 날, 회색은 예상이에요."),
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

    func coachOverlay(id: CoachID, steps: [CoachStep]) -> some View {
        overlayPreferenceValue(CoachAnchorKey.self) { anchors in
            CoachOverlay(id: id, steps: steps, anchors: anchors)
        }
    }
}

// ── 스포트라이트 오버레이 ──
private struct CoachOverlay: View {
    let id: CoachID
    let steps: [CoachStep]
    let anchors: [CoachAnchor: Anchor<CGRect>]

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
                    // 구멍 뚫린 배경(even-odd) + 링
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: proxy.size))
                        p.addRoundedRect(in: rect, cornerSize: CGSize(width: 12, height: 12))
                    }
                    .fill(Color.black.opacity(0.72), style: FillStyle(eoFill: true))
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.7), lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                    card(step: step, shownIndex: shownIndex, isLast: isLast, rect: rect, size: proxy.size)
                }
                .onAppear { shownAny = true }
                .accessibilityAddTraits(.isModal)
            }
        }
        .ignoresSafeArea()
        .sensoryFeedback(.success, trigger: successFeedback)
        .onAppear {
            guard !CoachStore.isDone(id) else { return }
            Task {   // 대상이 그려질 때까지 한 박자 양보(JejuNow 400ms와 동형)
                try? await Task.sleep(nanoseconds: 400_000_000)
                active = true
            }
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

    private func finish() {
        if shownAny {
            CoachStore.markDone(id)
            successFeedback += 1
        }
        active = false
    }

    private func card(step: CoachStep, shownIndex: Int, isLast: Bool,
                      rect: CGRect, size: CGSize) -> some View {
        let cardHeight: CGFloat = 220
        let below = rect.maxY + cardHeight + 20 < size.height
        let y = below ? min(rect.maxY + 14, size.height - cardHeight - 20)
                      : max(rect.minY - cardHeight - 14, 20)
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(shownIndex + 1) / \(steps.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Ink.winter)
            Text(step.title)
                .font(.almanac(size: 19, weight: .bold))
                .foregroundStyle(Ink.text)
            Text(step.body)
                .font(.subheadline)
                .foregroundStyle(Ink.text.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("건너뛰기") { finish() }
                    .font(.subheadline)
                    .foregroundStyle(Ink.text.opacity(0.55))
                Spacer()
                Button {
                    if isLast { finish() } else { index = shownIndex + 1 }
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
        .accessibilityLabel("사용법 안내 \(shownIndex + 1) / \(steps.count). \(step.title). \(step.body)")
    }
}
