// 템포루틴 — Input·Output 전용 위젯 (A단계 표시 전용, 2026-08-02 / MASTER §8.2.8)
// 종전 TodayScheduleWidget은 중형 하나에 3열(일정·Input·Output)을 욱여넣어 각 열이 폭 1/3 —
// 제목이 한 줄로 잘렸다. 여기서는 Input·Output을 각각 전폭으로 편다.
// 데이터 = App Group 스냅샷만. 체크 인터랙션은 B단계(AppIntents + App Group 큐)에서 얹는다.
// 잠금화면 = Input 미완 개수 + Output 최상단 1건 (§8.2.8 프라이버시 원칙 = 주기 정보 한정).

import WidgetKit
import SwiftUI

// ══ 공용 조각 ══

/// 카드 위젯 머리 — 글리프 + 구획 라벨 + 우측 계절 일차(종전 TodayScheduleView 헤더와 동형)
private struct CardHeader: View {
    let day: WidgetDay?
    let label: String
    let trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            if let season = day?.season {
                GlyphShape(season: season)
                    .stroke(WInk.season(season), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 12, height: 12)
            }
            Text(label)
                .font(WFont.almanac(14, weight: .bold))
                .foregroundStyle(WInk.text)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(WInk.season(day?.season).opacity(0.9))
            }
        }
    }
}

/// 빈 상태 — 단정·추론 없는 중립 카피(§3)
private struct CardEmpty: View {
    let text: String

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Text(text)
                .font(WFont.almanac(12))
                .foregroundStyle(WInk.text.opacity(0.45))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 목표일 배지 — 앱 DDayBadge 축소판. 문구는 앱이 계산해 스냅샷으로 온다.
private struct WDDayBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .monospacedDigit()
            // 지난 목표일도 경고색을 쓰지 않는다(§7 가드레일 톤) — 앱과 동일 규칙
            .foregroundStyle(WInk.text.opacity(0.6))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(WInk.text.opacity(0.08), in: Capsule())
    }
}

// ══ Input 전용 (systemSmall · systemMedium) ══

struct InputTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InputToday", provider: ScheduleProvider()) { entry in
            InputTodayView(entry: entry)
                .containerBackground(WInk.paper, for: .widget)
        }
        .configurationDisplayName("오늘의 Input")
        .description("오늘 챙길 Input을 목록으로 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct InputTodayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    private var lines: [WidgetCheckLine] { entry.day?.inputs ?? [] }
    private var rowLimit: Int { family == .systemSmall ? 3 : 5 }

    /// 총계는 스냅샷의 잘리기 전 개수 — 배열을 세면 안 된다(위젯 예산으로 잘려 있음).
    /// 구 스냅샷(총계 필드 없음) 호환 폴백 = 배열 기준.
    private var total: Int { entry.day?.inputTotal ?? lines.count }
    private var doneCount: Int { entry.day?.inputDone ?? lines.filter(\.done).count }
    private var hiddenCount: Int { max(0, total - min(lines.count, rowLimit)) }

    private var counter: String? {
        guard total > 0 else { return nil }
        return "\(doneCount)/\(total)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CardHeader(day: entry.day, label: "Input", trailing: counter)
            if lines.isEmpty {
                CardEmpty(text: "오늘 챙길 Input이 없어요")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines.prefix(rowLimit).enumerated()), id: \.offset) { _, line in
                        row(line)
                    }
                    if hiddenCount > 0 {
                        Text("+\(hiddenCount)개 더")
                            .font(.system(size: 11))
                            .foregroundStyle(WInk.text.opacity(0.4))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func row(_ line: WidgetCheckLine) -> some View {
        HStack(spacing: 6) {
            Image(systemName: line.done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(line.done ? WInk.text.opacity(0.55) : WInk.text.opacity(0.35))
            Text(line.title)
                .font(.system(size: 13))
                .foregroundStyle(WInk.text.opacity(line.done ? 0.45 : 0.9))
                .strikethrough(line.done, color: WInk.text.opacity(0.35))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

// ══ Output 전용 (systemSmall · systemMedium) ══

struct OutputTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "OutputToday", provider: ScheduleProvider()) { entry in
            OutputTodayView(entry: entry)
                .containerBackground(WInk.paper, for: .widget)
        }
        .configurationDisplayName("오늘의 Output")
        .description("진행 중인 Output과 남은 날짜를 보여줘요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct OutputTodayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleEntry

    private var lines: [WidgetProgressLine] { entry.day?.outputs ?? [] }
    private var rowLimit: Int { family == .systemSmall ? 2 : 4 }
    private var total: Int { entry.day?.outputTotal ?? lines.count }
    private var hiddenCount: Int { max(0, total - min(lines.count, rowLimit)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            CardHeader(day: entry.day, label: "Output",
                       trailing: hiddenCount > 0 ? "+\(hiddenCount)" : nil)
            if lines.isEmpty {
                CardEmpty(text: "진행 중인 Output이 없어요")
            } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 9) {
                    ForEach(Array(lines.prefix(rowLimit).enumerated()), id: \.offset) { _, line in
                        row(line)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func row(_ line: WidgetProgressLine) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(line.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WInk.text)
                    .lineLimit(1)
                if let dday = line.dday {
                    WDDayBadge(text: dday)
                }
                Spacer(minLength: 4)
                Text(line.label)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(WInk.text.opacity(0.55))
            }
            bar(line.fraction)
        }
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WInk.text.opacity(0.12))
                Capsule().fill(WInk.text.opacity(0.75))
                    .frame(width: max(3, proxy.size.width * fraction))
            }
        }
        .frame(height: 4)
    }
}

// ══ 잠금화면 — Input 요약 + Output 1건 (accessoryRectangular) ══
// 프라이버시(§8.2.8 개정 2026-08-02): 주기 정보만 은유로 가린다. Input·Output은 사용자가 직접
// 적은 할 일이라 잠금화면 노출을 허용 — 다만 Input은 개수 요약으로 둔다(줄 수 예산 + 제목 다중 노출 회피).

struct CardLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CardLock", provider: ScheduleProvider()) { entry in
            CardLockView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("오늘의 카드")
        .description("잠금화면에서 Input 진행과 Output 한 건을 보여줘요.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct CardLockView: View {
    let entry: ScheduleEntry

    private var inputs: [WidgetCheckLine] { entry.day?.inputs ?? [] }
    private var topOutput: WidgetProgressLine? { entry.day?.outputs?.first }

    /// 잘린 배열이 아니라 총계로 판정 — 상위 몇 개만 완료인 날 "다 챙겼어요"가 거짓이 된다
    private var inputSummary: String {
        let total: Int = entry.day?.inputTotal ?? inputs.count
        guard total > 0 else { return "Input 없음" }
        let done: Int = entry.day?.inputDone ?? inputs.filter(\.done).count
        let remain: Int = max(0, total - done)
        return remain == 0 ? "Input 다 챙겼어요" : "Input \(remain)개 남음"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                GlyphShape(season: entry.day?.season ?? "winter")
                    .stroke(.primary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 14, height: 14)
                    .widgetAccentable()
                    .opacity(entry.day?.season == nil ? 0.4 : 1)
                Text(inputSummary)
                    .font(WFont.almanac(14, weight: .bold))
                    .lineLimit(1)
            }
            if let output = topOutput {
                HStack(spacing: 4) {
                    Text(output.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                    Text(output.label)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if let dday = output.dday {
                        Text(dday)
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(entry.day?.inline ?? "템포루틴")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
