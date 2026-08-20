// 템포루틴 — EventKit read-only 오버레이 (Phase 0 ⑥, MASTER §3.6.1 LOCKED)
// 시스템 캘린더가 출처 — SwiftData 미저장, 런타임 fetch만. 로컬 일정과 dedup 없음(신뢰 식별자 없음),
// 출처 배지("캘린더")로 구분만. 더블 컨센트: 앱 카드 → '가져올게요'에만 시스템 권한(기회 보존), 후통보 X.
// 문구는 "가져오기"로 통일(2026-07-25 사용자 지시 — 구 "비추기"·"불러오기" 혼용 폐기).
// 거부/미연동 폴백 = 직접 입력(기능 잠금 없음).

import EventKit
import SwiftUI
import UIKit

struct OverlayEvent: Identifiable {
    let id: String
    let title: String
    let isAllDay: Bool
    let start: Date
}

@MainActor
@Observable
final class EventOverlay {
    static let shared = EventOverlay()

    private let store = EKEventStore()
    private(set) var authorized: Bool

    private init() {
        authorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// 시스템 프롬프트는 거부 후 재요청 불가 — 이 경우 설정 앱 유도만 가능(§3.6.1)
    var systemDenied: Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .denied, .restricted, .writeOnly: true
        default: false
        }
    }

    /// '가져올게요'를 눌렀을 때만 호출 — 더블 컨센트의 2단계
    func requestAccess() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        authorized = granted
    }

    /// 애플 기본 캘린더의 공휴일 구독 캘린더(제목 "공휴일"/"holiday") — 표기 소스(2026-07-28)
    private var holidayCalendars: [EKCalendar] {
        store.calendars(for: .event).filter { c in
            let title = c.title.lowercased()
            return title.contains("공휴일") || title.contains("holiday")
        }
    }

    /// 구간의 공휴일 이름(일 단위 키). 미연동·공휴일 캘린더 없음 = nil — 호출측이 내장 테이블 폴백.
    func holidayNames(from start: Date, to end: Date) -> [Date: [String]]? {
        guard authorized else { return nil }
        let calendars = holidayCalendars
        guard !calendars.isEmpty else { return nil }
        let cal = Calendar.current
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        var out: [Date: [String]] = [:]
        for event in store.events(matching: predicate) {
            guard let title = event.title, let eventStart = event.startDate else { continue }
            // 며칠짜리 연휴가 한 이벤트로 온 경우 — 걸치는 날 전부에 표기
            var day = cal.startOfDay(for: eventStart)
            let last = cal.startOfDay(for: event.endDate ?? eventStart)
            var hops = 0
            while day <= last && hops < 31 {
                if day >= start && day < end && !(out[day]?.contains(title) ?? false) {
                    out[day, default: []].append(title)
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                hops += 1
            }
        }
        return out
    }

    func events(on day: Date) -> [OverlayEvent] {
        guard authorized else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        // 공휴일 캘린더는 일정 행에서 제외 — 공휴일 표기는 셀 글줄·상세 표제가 담당(중복 방지)
        let normal = store.calendars(for: .event).filter { c in
            let title = c.title.lowercased()
            return !title.contains("공휴일") && !title.contains("holiday")
        }
        let predicate = store.predicateForEvents(withStart: start, end: end,
                                                 calendars: normal.isEmpty ? nil : normal)
        return store.events(matching: predicate)
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map {
                OverlayEvent(id: "\($0.eventIdentifier ?? UUID().uuidString)-\($0.startDate.timeIntervalSince1970)",
                             title: $0.title ?? "", isAllDay: $0.isAllDay, start: $0.startDate)
            }
    }
}

// ── 일정 구획 공용: 오버레이 행 + 연동 진입 ──

struct OverlayEventRows: View {
    let day: Date
    private let overlay = EventOverlay.shared

    var body: some View {
        ForEach(overlay.events(on: day)) { event in
            // 제목 먼저·시각 trailing(2026-08-09 베타 피드백 — 오늘 탭 로컬 일정 행과 같은 문법)
            HStack(spacing: 10) {
                Text(event.title)
                    .font(.subheadline)
                    .foregroundStyle(Ink.text.opacity(0.8))
                Spacer()
                Text(event.isAllDay ? "종일" : event.start.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Ink.text.opacity(0.5))
                // read-only 출처 배지 — dedup 없이 구분만(§3.6.1 G)
                Text("캘린더")
                    .font(.caption2)
                    .foregroundStyle(Ink.text.opacity(0.45))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(Capsule().stroke(Ink.text.opacity(0.25), lineWidth: 1))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(event.title), 캘린더에서 가져옴, 읽기 전용")
        }
    }
}

struct CalendarConnectRow: View {
    @State private var showConsent = false
    private let overlay = EventOverlay.shared

    var body: some View {
        if !overlay.authorized {
            Button {
                showConsent = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.plus")
                    Text("캘린더 가져오기")
                }
                .font(.caption)
                .foregroundStyle(Ink.text.opacity(0.55))
            }
            .sheet(isPresented: $showConsent) {
                CalendarConsentSheet()
                    .presentationDetents([.medium])
                    .themeColorScheme()
            }
        }
    }
}

/// 더블 컨센트 1단계 — 앱 화면. '나중에'는 시스템 프롬프트를 태우지 않는다(기회 보존).
struct CalendarConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let overlay = EventOverlay.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("캘린더 가져오기")
                .font(.system(.title2, design: .serif).weight(.bold))
                .foregroundStyle(Ink.text)
            if overlay.systemDenied {
                Text("캘린더 접근이 꺼져 있어요. 설정 앱의 개인정보 보호에서 캘린더 접근을 허용하면 다시 가져올 수 있어요.")
                    .font(.body)
                    .foregroundStyle(Ink.text.opacity(0.75))
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    dismiss()
                } label: {
                    Text("설정 열기")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Ink.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Ink.text, in: Capsule())
                }
            } else {
                Text("기존 캘린더의 약속과 생일을 가져올까요?")
                    .font(.body)
                    .foregroundStyle(Ink.text.opacity(0.75))
                Button {
                    Task {
                        await overlay.requestAccess()
                        dismiss()
                    }
                } label: {
                    Text("가져올게요")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Ink.paper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Ink.text, in: Capsule())
                }
                Button {
                    dismiss()
                } label: {
                    Text("나중에")
                        .font(.body)
                        .foregroundStyle(Ink.text.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(Capsule().stroke(Ink.text.opacity(0.3), lineWidth: 1))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.paper)
    }
}
