// 템포루틴 — 앱 내 자기보고 설문 화면 (v1.6 §4 / MASTER §3.11)
//
// 웹 설문과 다른 점 하나: **결과를 보여주지 않는다.**
// 앱은 이미 기록에서 유형을 계산하는데(§5.12), 자기보고 유형까지 화면에 띄우면
// 산출 경로가 다른 두 값이 나란히 보이게 된다. 어느 쪽이 "내 유형"인지 물어보는 순간
// 답이 없다. 그래서 응답은 저장만 하고 대조는 내부에서만 쓴다.
//
// 마무리 카피도 이득을 약속하지 않는다 — 자기보고를 실제로 쓰는 경로가 아직 없어서,
// "더 정확해져요" 류는 검증 불가능한 주장이 된다(§7 가드레일).

import SwiftUI
import SwiftData
import TempoCore

struct SelfReportFlow: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var answers: [String: String] = [:]
    /// 제시 순서만 섞는다. 한 번 섞은 순서를 유지해야 화면을 오갈 때 문항이 튀지 않는다.
    @State private var symptomOrder: [SurveyQuestion] = SelfReportSurvey.symptomQuestions.shuffled()

    private var totalSteps: Int { 5 }
    /// 스크롤 리셋 대상(2026-08-12) — 장이 바뀌면 여기로 되돌린다.
    private static let topAnchor = "survey-top"

    /// 문항이 하나뿐인 장 — 선택이 곧 그 장의 답이라 「다음」을 한 번 더 누를 이유가 없다
    /// (2026-08-12 베타 피드백 "선택하면 다음 안눌러도 넘어가게"). 1장 = 캘리브레이션 단문항.
    private var isSingleQuestionStep: Bool { step == 1 }

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.paper.ignoresSafeArea()
                // "설문지" 인상 걷어내기(2026-08-08 베타 피드백 "하기 싫게 생겼어") —
                // 온보딩과 같은 겨울 광 + 감쇠 텍스처로 앱의 지면 어휘를 잇는다
                SeasonLight(phase: .menstrual, motif: .onboarding)
                // 장을 넘기면 맨 위부터 보여준다(2026-08-12 베타 피드백) — 종전엔 이전 장의
                // 스크롤 위치가 남아 새 장이 중간부터 열렸다.
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            progressHeader.id(Self.topAnchor)
                            content
                            actions
                        }
                        .padding(20)
                        .centeredColumn(640)
                    }
                    .onChange(of: step) { _, _ in
                        proxy.scrollTo(Self.topAnchor, anchor: .top)
                    }
                }
            }
            .navigationTitle("리듬 설문")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }.foregroundStyle(Ink.text)
                }
            }
        }
    }

    // 진행도 명시(2026-08-08 베타 피드백 "진행도도 표시해줘") — 얇은 실선만으론 안 읽혔다
    private var progressHeader: some View {
        HStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.text.opacity(0.12))
                    Capsule().fill(Ink.text.opacity(0.65))
                        .frame(width: max(step > 0 ? 6 : 0,
                                          proxy.size.width * Double(step) / Double(totalSteps)))
                }
            }
            .frame(height: 4)
            if step > 0 {
                Text("\(step) / \(totalSteps)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Ink.text.opacity(0.55))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Loc.fmt("진행도 %1$@ / %2$@", "\(step)", "\(totalSteps)"))
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: intro
        case 1: questionGroup(title: nil,
                              note: "이제 그때를 떠올리면서 답해주세요.",
                              questions: [SelfReportSurvey.calibration])
        case 2: questionGroup(title: nil, note: nil, questions: SelfReportSurvey.phaseQuestions)
        case 3: questionGroup(title: symptomAnchorTitle(p2: answers["P2"]),
                              note: "꼭 생리 중이 아니라도 가장 힘들었던 때를 떠올려주세요.",
                              questions: symptomOrder)
        case 4: questionGroup(title: nil, note: nil, questions: SelfReportSurvey.amplitudeQuestions)
        default: optionalGroup
        }
    }

    /// 증상 문항의 시간 앵커 문구 — TempoCore의 `symptomAnchorLine`은 선택지 라벨을 문장에
    /// **합성**해서 돌려주므로 그대로는 번역 키가 아니다. 순수 모듈을 건드리지 않으려고
    /// 합성만 앱으로 가져온다(판정 규칙·선택지 자체는 그대로 TempoCore가 소유).
    private func symptomAnchorTitle(p2: String?) -> String {
        guard let p2, p2 != "none", p2 != "unknown",
              let choice = SelfReportSurvey.phaseChoices.first(where: { $0.value == p2 })
        else { return String(localized: "그나마 힘들었던 때를 떠올려서, 평소와 비교해서 답해주세요.") }
        return Loc.fmt("「%1$@」, 평소와 비교해서 답해주세요.", Loc.text(choice.label))
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 줄바꿈 = 의미 단위로(2026-08-05 베타 피드백 "줄바꿈 신경써줘")
            Text("이맘때 이야기를 하려면\n몇 가지 알아야 해요.")
                .font(.almanac(size: 26, weight: .bold))
                .foregroundStyle(Ink.text)
            Text("리듬의 모양은 사람마다 달라요.\n2분 정도 소요돼요.")
                .font(.system(.body, design: .serif))
                .foregroundStyle(Ink.text.opacity(0.75))
            Text("응답은 이 기기에만 저장됩니다.")
                .font(.footnote)
                .foregroundStyle(Ink.text.opacity(0.5))
        }
    }

    private func questionGroup(title: String?, note: String?, questions: [SurveyQuestion]) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            if let title {
                Text(title)
                    .font(.almanac(size: 19, weight: .bold))
                    .foregroundStyle(Ink.text)
            }
            if let note {
                Text(note).font(.footnote).foregroundStyle(Ink.text.opacity(0.55))
            }
            ForEach(questions, id: \.id) { question in
                questionBlock(question)
            }
        }
    }

    private var optionalGroup: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("이 페이지의 질문은 건너뛰셔도 괜찮아요.")
                    .font(.footnote).foregroundStyle(Ink.text.opacity(0.55))
            }
            ForEach(SelfReportSurvey.optionalQuestions, id: \.id) { question in
                questionBlock(question)
            }
        }
    }

    // 문항 = 세리프 표제 + 라디오·괘선 리스트(2026-08-08 베타 피드백 — 회색 캡슐 12개가
    // 벽처럼 쌓이던 조판 폐기, 책력 개방 조판으로). 측정 로직·저장 키는 무변경.
    private func questionBlock(_ question: SurveyQuestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question.text)
                .font(.almanacBody(.subheadline, size: 16, weight: .bold))
                .foregroundStyle(Ink.text)
                .padding(.bottom, 4)
            ForEach(question.choices, id: \.value) { choice in
                choiceRow(question: question, choice: choice)
            }
        }
    }

    private func choiceRow(question: SurveyQuestion, choice: SurveyChoice) -> some View {
        let selected = answers[question.id] == choice.value
        return Button {
            select(question: question, choice: choice, wasSelected: selected)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "circle.inset.filled" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(selected ? Ink.text : Ink.text.opacity(0.3))
                Text(choice.label)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(Ink.text.opacity(selected ? 1.0 : 0.75))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .almanacRule(opacity: 0.12)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // 2026-08-05 베타 피드백: 다음 = 우하단 글씨만(검정 캡슐 제거), 이전 = 모든 문항 단계에.
    private var actions: some View {
        HStack(spacing: 18) {
            if step > 0 {
                Button("이전") { step -= 1 }
                    .font(.body.weight(.medium))
                    .foregroundStyle(Ink.text.opacity(0.55))
            }
            Spacer(minLength: 0)
            if step == totalSteps {
                Button("건너뛰기") { finish() }
                    .font(.body)
                    .foregroundStyle(Ink.text.opacity(0.55))
            }
            Button(step == totalSteps ? "제출" : "다음") { advance() }
                .font(.body.weight(.semibold))
                .foregroundStyle(canAdvance ? Ink.text : Ink.text.opacity(0.3))
                .disabled(!canAdvance)
        }
        .padding(.top, 6)
    }

    /// 선택 문항 단계 말고는 그 화면의 문항이 전부 채워져야 넘어간다.
    private var canAdvance: Bool {
        switch step {
        case 0: true
        case 1: answers[SelfReportSurvey.calibration.id] != nil
        case 2: SelfReportSurvey.phaseQuestions.allSatisfy { answers[$0.id] != nil }
        case 3: SelfReportSurvey.symptomQuestions.allSatisfy { answers[$0.id] != nil }
        case 4: SelfReportSurvey.amplitudeQuestions.allSatisfy { answers[$0.id] != nil }
        default: true
        }
    }

    /// 선택 반영 + 단문항 장이면 자동 진행(2026-08-12). 재탭 해제로는 넘어가지 않는다.
    /// 한 박자 늦추는 이유 = 고른 표시(라디오 채움)를 보고 넘어가야 무엇을 골랐는지 남는다.
    private func select(question: SurveyQuestion, choice: SurveyChoice, wasSelected: Bool) {
        answers[question.id] = wasSelected ? nil : choice.value
        guard !wasSelected, isSingleQuestionStep else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            // 사이에 사용자가 직접 넘겼거나 답을 지웠으면 손대지 않는다
            guard isSingleQuestionStep, canAdvance else { return }
            advance()
        }
    }

    private func advance() {
        if step < totalSteps {
            step += 1
        } else {
            finish()
        }
    }

    private func finish() {
        // 화이트리스트 밖 키가 섞이지 않게 한 번 거른다(웹 서버와 같은 규칙)
        let allowed = SelfReportSurvey.allQuestionIDs
        let cleaned = answers.filter { allowed.contains($0.key) }
        modelContext.insert(SelfReportRecord(answers: cleaned))
        SelfReportStore.hasPrompted = true
        dismiss()
    }
}
