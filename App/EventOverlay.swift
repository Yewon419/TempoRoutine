// 템포루틴 — EventKit read-only 오버레이 (Phase 0 ⑥, MASTER §3.6.1 LOCKED)
// 시스템 캘린더가 출처 — SwiftData 미저장, 런타임 fetch만. 로컬 일정과 dedup 없음(신뢰 식별자 없음),
// 출처 배지("캘린더")로 구분만. 더블 컨센트: 앱 카드 → '불러올게요'에만 시스템 권한(기회 보존), 후통보 X.
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

    /// '불러올게요'를 눌렀을 때만 호출 — 더블 컨센트의 2단계
    func requestAccess() async {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        authorized = granted
    }

    func events(on day: Date) -> [OverlayEvent] {
        guard authorized else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
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
            HStack(spacing: 10) {
                Text(event.isAllDay ? "종일" : event.start.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Ink.text.opacity(0.5))
                    .frame(width: 56, alignment: .leading)
                Text(event.title)
                    .font(.subheadline)
                    .foregroundStyle(Ink.text.opacity(0.8))
                Spacer()
                // read-only 출처 배지 — dedup 없이 구분만(§3.6.1 G)
                Text("캘린더")
                    .font(.caption2)
                    .foregroundStyle(Ink.text.opacity(0.45))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(Capsule().stroke(Ink.text.opacity(0.25), lineWidth: 1))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(event.title), 캘린더에서 불러옴, 읽기 전용")
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
                    Text("캘린더 비추기")
                }
                .font(.caption)
                .foregroundStyle(Ink.text.opacity(0.55))
            }
            .sheet(isPresented: $showConsent) {
                CalendarConsentSheet()
                    .presentationDetents([.medium])
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
            Text("캘린더 비추기")
                .font(.system(.title2, design: .serif).weight(.bold))
                .foregroundStyle(Ink.text)
            if overlay.systemDenied {
                Text("캘린더 접근이 꺼져 있어요. 설정 앱의 개인정보 보호에서 캘린더 접근을 허용하면 다시 비출 수 있어요.")
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
                Text("기존 캘린더의 약속과 생일을 비춰드릴게요. 불러올까요?")
                    .font(.body)
                    .foregroundStyle(Ink.text.opacity(0.75))
                Text("읽기만 해요. 기록이 밖으로 나가지 않아요.")
                    .font(.footnote)
                    .foregroundStyle(Ink.text.opacity(0.5))
                Button {
                    Task {
                        await overlay.requestAccess()
                        dismiss()
                    }
                } label: {
                    Text("불러올게요")
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
