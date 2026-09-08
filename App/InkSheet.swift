// 템포루틴 — 은필 시트 부품 (2026-09-08 베타 "추가 시트가 너무 애플 UI 같아서 재미없다" → 대표님 지시)
// 온보딩 「템포 렌즈」의 시트 문법을 앱 안 추가·수정 시트(일정·Input·Output)로 옮긴다: 테마 지면 + 밀크
// 글래스 구획 + 무광 스위치 + 먹 도장 칩 + 먹 캡슐 저장. 시스템 Form은 은퇴. 재질은 전부 테마 토큰
// (Ink·milkGlass·MatteToggleStyle)이라 은필 밖 테마도 자기 지면·카드 문법을 따른다.

import SwiftUI
import TempoCore

// ── 뼈대 ──────────────────────────────────────────────────
/// 상단 행(취소 · 표찰) → 스크롤 본문 → 하단 바(저장 먹 캡슐 + 보조). NavigationStack 없이 선다 —
/// 내비바의 시스템 버튼·제목이 곧 「애플 UI」였다. 키보드 「완료」는 호출부가 .toolbar(.keyboard)로 단다.
struct InkSheetScaffold<Content: View, Footer: View>: View {
    let eyebrow: String
    let saveTitle: String
    let saveEnabled: Bool
    let phase: CyclePhase?
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        ZStack {
            Ink.paper.ignoresSafeArea()
            SeasonLight(phase: phase, motif: .card)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 24)
                .centeredColumn(560)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    private var topBar: some View {
        HStack {
            Button(action: onCancel) { Text("취소") }
                .buttonStyle(GhostUnderlineButtonStyle())
                .frame(width: 64)
            Spacer()
            Text(eyebrow).eyebrowStyle()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .centeredColumn(560)
    }

    private var bottomBar: some View {
        VStack(spacing: 6) {
            Button(action: onSave) { Text(saveTitle) }
                .buttonStyle(InkCapsuleButtonStyle())
                .disabled(!saveEnabled)
                .opacity(saveEnabled ? 1 : 0.35)
            footer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .centeredColumn(560)
        .frame(maxWidth: .infinity)
        .background {
            Ink.paper.opacity(0.92)
                .overlay(alignment: .top) { Rectangle().fill(Ink.accent.opacity(0.18)).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

// ── 구획·행 ────────────────────────────────────────────────
/// 밀크 글래스 구획 — 표찰(eyebrow)은 선택
struct InkSection<Content: View>: View {
    var eyebrow: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let eyebrow { Text(eyebrow).eyebrowStyle() }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
    }
}

/// 구획 안 행 구분 괘선
struct InkDivider: View {
    var body: some View {
        Rectangle().fill(Ink.accent.opacity(0.14)).frame(height: 1)
    }
}

/// 제목 입력 — 시트의 표제 자리. 명조 24 + 아래 괘선(활자가 곧 표제라 카드에 담지 않는다)
struct InkTitleField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Ink.text.opacity(0.3)))
                .font(.almanac(size: 24, weight: .bold))
                .foregroundStyle(Ink.text)
                .submitLabel(.done)
            Rectangle().fill(Ink.accent.opacity(0.3)).frame(height: 1)
        }
        .padding(.top, 8)
    }
}

/// 무광 스위치 행
struct InkToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.almanacBody(.body, size: 16))
                .foregroundStyle(Ink.text)
        }
        .toggleStyle(MatteToggleStyle())
        .frame(minHeight: 32)
    }
}

/// 라벨 + 오른쪽 컨트롤 행(DatePicker 등)
struct InkRow<Trailing: View>: View {
    let label: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(label)
                .font(.almanacBody(.body, size: 16))
                .foregroundStyle(Ink.text)
            Spacer(minLength: 12)
            trailing()
        }
        .frame(minHeight: 32)
    }
}

/// 각주 한 줄
struct InkNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.almanacBody(.footnote, size: 13))
            .foregroundStyle(Ink.text.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 파괴 액션 — 붉은 활자, 구획 밖 단독(§8.2.6 문법)
struct InkDeleteButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Ink.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}

// ── 선택 칩 ────────────────────────────────────────────────
/// 선택 칩 — 은필 윤곽, 고르면 먹 도장(StampChip과 같은 재질, 아이콘 없음)
struct InkChoiceChip: View {
    let label: String
    let on: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 14, weight: on ? .medium : .regular))
                .foregroundStyle(on ? Ink.paper : Ink.text)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(on ? Ink.text : Color(red: 250 / 255, green: 250 / 255, blue: 248 / 255).opacity(0.6), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.white.opacity(0.12) : Ink.winter.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: on)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// 계절 칩 — 글리프 + 이름. 고르면 먹 도장, 글리프는 지면색으로 뒤집힌다
struct SeasonChipRow: View {
    @Binding var selection: SeasonAnchor

    var body: some View {
        InkChipFlow(spacing: 8, rowSpacing: 8) {
            ForEach(SeasonAnchor.allCases) { season in
                let meta = seasonMeta(for: season.phase)
                let on = selection == season
                Button { selection = season } label: {
                    HStack(spacing: 6) {
                        SeasonGlyph(phase: season.phase, size: 13, color: on ? Ink.paper : meta.color)
                        Text(meta.name)   // rawValue = 저장 키, 표시 아님
                            .font(.almanacBody(.subheadline, size: 14, weight: on ? .bold : .regular))
                            .foregroundStyle(on ? Ink.paper : meta.color)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(on ? Ink.text : Color(red: 250 / 255, green: 250 / 255, blue: 248 / 255).opacity(0.6), in: Capsule())
                    .overlay(Capsule().strokeBorder(on ? Color.white.opacity(0.12) : Ink.winter.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }
}

/// 값 조절 — 명조 값 + 괘선 원 버튼 36(캘린더 월 이동과 같은 재질)
struct InkStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1

    var body: some View {
        HStack {
            Text(label)
                .font(.almanacBody(.body, size: 16))
                .foregroundStyle(Ink.text)
                .contentTransition(.numericText())
            Spacer(minLength: 12)
            roundButton("minus", enabled: value > range.lowerBound) {
                value = max(range.lowerBound, value - step)
            }
            roundButton("plus", enabled: value < range.upperBound) {
                value = min(range.upperBound, value + step)
            }
        }
        .animation(.easeOut(duration: 0.2), value: value)
        .accessibilityRepresentation {
            Stepper(value: $value, in: range, step: step) { Text(label) }
        }
    }

    private func roundButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Ink.text.opacity(0.75))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Ink.surface.opacity(0.5)))
                .overlay(Circle().strokeBorder(Ink.accent.opacity(0.45), lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// 칩 줄바꿈 흐름 — CheckInCard의 ChipFlow와 같은 규칙(왼쪽부터 놓다가 폭을 넘기면 다음 줄)
struct InkChipFlow: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit: CGFloat = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > limit {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        let width: CGFloat = limit == .infinity ? widest : limit
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
