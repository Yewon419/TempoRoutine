// 템포루틴 — 데일리 체크인 카드 (MASTER §3.4 / §8.2.2 / §8.2.4)
// 오늘 탭·하루 상세 공용. 날짜만 다르고 문법은 같다 — 뒤늦은 기록·자정 넘겨 마무리하는 하루를
// 위해 지난 날짜에도 쓸 수 있어야 한다(2026-07-26 사용자 지적: "어제 기록할 방법이 없었다").
// 미래는 기록하지 않는다 — 생리 기록과 같은 원칙(§5.5.4 기록≠예측).
// 저장 조건 = 필수 2신호(energy·mood) 또는 노트(§5.5 — 한 줄 일기 단독 저장 허용).
// 스트릭·연속 표시 금지(§3.4), 전부 해제하면 기록 철회(스킵 무벌점).

import PhotosUI
import SwiftUI
import SwiftData
import TempoCore   // TrackedSignals

struct CheckInCard: View {
    let day: Date

    @Environment(\.modelContext) private var modelContext
    @Query private var checkIns: [DailyCheckIn]

    @State private var draftEnergy = 0
    @State private var draftMood = 0
    @State private var draftSleep = 0
    @State private var draftAppetite = 0
    @State private var draftNote = ""
    @State private var draftSymptoms: Set<CheckInSymptom> = []   // 아픈 날 증상(2026-09-01)
    /// 한 줄 기록 사진(2026-09-04 베타) — 파일 이름만 든다. 최대 1장이라 배열이 아니다.
    @State private var draftPhotoName: String?
    @State private var photoItem: PhotosPickerItem?
    /// 증상 칩 펼침(2026-09-04 베타 "아픈곳 저렇게 바로 노출하지 말고") — 기본은 접힘.
    /// 이미 적어 둔 증상이 있으면 로드 때 펼친다(기록이 있는데 안 보이면 안 된다).
    @State private var symptomsExpanded = false
    @State private var draftLoaded = false
    @State private var seedEarned = 0   // 씨앗 획득 연출 트리거(2026-08-09)

    /// 어떤 행을 보여줄지는 온보딩·설정에서 고른 추적 항목이 정한다(§3.10).
    /// ⚠ 종전에는 이 배선이 없어 통증·식욕을 켜도 카드에 나오지 않았다(2026-08-04 발견).
    private var signals: TrackedSignals { AppSettings.trackedSignals }
    @FocusState private var noteFocused: Bool   // 키보드 닫기 경로(베타 피드백 2026-07-22)

    private var cal: Calendar { Calendar.current }
    private var normalizedDay: Date { cal.startOfDay(for: day) }
    private var isToday: Bool { normalizedDay == cal.startOfDay(for: .now) }
    private var record: DailyCheckIn? { checkIns.first { $0.day == normalizedDay } }

    private var title: String { isToday ? Loc.str("오늘의 체크인") : Loc.str("이날의 체크인") }
    private var noteLabel: String { isToday ? Loc.str("오늘 한 줄") : Loc.str("그날 한 줄") }
    private var confirmLine: String {
        // 탭 개명 추종(2026-08-18 「나의 리듬」→「나의 템포」) — 이 문구는 그 탭을 가리킨다
        isToday ? Loc.str("오늘 기록이 나의 템포에 담겼어요.") : Loc.str("이날 기록이 나의 템포에 담겼어요.")
    }

    var body: some View {
        // 「오늘 한 줄」은 체크인과 다른 카드다(2026-09-05 베타 "오늘한줄이랑 사진넣는걸 아래칸에
        // 따로 카드로 빼자") — 척도 고르기와 글·사진 남기기는 성격이 다른 일이다. 초안·저장은
        // 한 뷰가 그대로 들고 있어 저장 경로는 갈라지지 않는다.
        VStack(spacing: 16) {
            checkInBody
            if signals.note { noteBody }
        }
        .seedBurst(trigger: seedEarned)   // 획득 연출(2026-08-09)
        .onAppear(perform: loadDraft)
        // 날짜가 바뀌면 그날 것으로 다시 읽는다(2026-08-03 베타 피드백 "어제 저장한 게 오늘까지 표시").
        // onAppear 한 번만 로드하면, 앱을 백그라운드에 둔 채 자정을 넘겼을 때 day는 오늘로 바뀌는데
        // 초안은 어제 값이 남아 칩·확인 문구가 어제 상태로 보이고, 손대는 순간 오늘로 복사된다.
        .onChange(of: normalizedDay) { _, _ in reloadDraft() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("완료") { noteFocused = false }.foregroundStyle(Ink.text)
            }
        }
    }

    private var checkInBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.almanac(size: 17, weight: .bold))
                .foregroundStyle(Ink.text)
            // 예민함·몸 행 = 2026-08-05 사용자 결정으로 제거(기분·에너지와 겹침, 6줄 부담).
            // 저장 필드는 남아 있고 과거 기록은 리듬 집계에 계속 유효하다 — 새 입력 경로만 없다.
            // 항목 ⓘ 설명 = 2026-08-06 베타 피드백 교정으로 여기서 걷고 온보딩 ③으로 이동
            // ("체크인 항목이 아니었어"). 구획 제목 ⓘ는 오늘 탭·하루 상세 셸이 담당.
            checkInRow(label: Loc.str("에너지는"), options: [Loc.str("낮음"), Loc.str("보통"), Loc.str("높음")], value: $draftEnergy)
            checkInRow(label: Loc.str("기분은"), options: [Loc.str("흐림"), Loc.str("보통"), Loc.str("맑음")], value: $draftMood)
            if signals.sleep {
                checkInRow(label: Loc.str("지난밤 잠은"), options: [Loc.str("뒤척임"), Loc.str("보통"), Loc.str("푹 잤어요")], value: $draftSleep)
            }
            if signals.appetite {
                checkInRow(label: Loc.str("식욕은"), options: [Loc.str("없음"), Loc.str("보통"), Loc.str("좋음")], value: $draftAppetite)
            }
            // 아픈 날 증상(2026-09-01 대표님 지시) — 다중 선택. 질병은 집계 제외·통증은 전량
            // 반영(판정은 aggregationWeight). 안내 문구 없이 칩만("안내 말고 증상 토글" — 지시 원문).
            symptomRow
            if draftEnergy > 0 && draftMood > 0 {
                Text(confirmLine)
                    .font(.system(.footnote, design: .serif))
                    .foregroundStyle(Ink.text.opacity(0.6))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
    }

    /// 두 번째 카드 — 한 줄과 사진(2026-09-05 베타). 추적 항목 토글을 따른다(2026-08-20 감사 —
    /// 온보딩 ③ 토글이 있는데 두 표면 다 무조건 렌더해 죽은 스위치였다). 꺼도 기존 노트는 보존된다.
    private var noteBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(noteLabel)
                .font(.almanac(size: 17, weight: .bold))
                .foregroundStyle(Ink.text)
            // 안내문구 = prompt(2026-08-05 베타 피드백 "하루를 간단히 남겨봐요" — 07-31 placeholder 제거의 교체)
            TextField("", text: $draftNote, prompt: Text("하루를 간단히 남겨봐요")
                .foregroundStyle(Ink.text.opacity(0.35)), axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(Ink.text)
                .focused($noteFocused)
                .onChange(of: draftNote) { persistDraft() }
            photoRow
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .milkGlass()
    }

    /// 영어·일본어 칩이 길어 한 줄에 안 들어가면 칩이 낱말 중간에서 꺾였다(2026-08-22 베타
    /// "체크인 줄바꿈 엄청나다"). 한 줄에 들어가면 종전 조판, 안 들어가면 라벨 위·칩 아래.
    private func checkInRow(label: String, options: [String], value: Binding<Int>) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                checkInLabel(label).frame(width: 108, alignment: .leading)
                checkInChips(label: label, options: options, value: value)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                checkInLabel(label)
                HStack(spacing: 8) {
                    checkInChips(label: label, options: options, value: value)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func checkInLabel(_ label: String) -> some View {
        Text(label)
            .font(.subheadline)
            .foregroundStyle(Ink.text.opacity(0.75))
    }

    private func checkInChips(label: String, options: [String], value: Binding<Int>) -> some View {
        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let mapped = index * 2 + 1   // 3탭 = 1·3·5
                let current = value.wrappedValue
                let selected = current == mapped
                // 중간값(2·4)은 양옆 두 칩이 함께 옅게 찬다 — 3버튼 UI를 유지하면서
                // 저장은 5점으로 받는다(v1.5 §3-2: 3점 척도는 진폭 추정 정보량이 부족).
                let half = current > 0 && (current == mapped - 1 || current == mapped + 1)
                Button {
                    value.wrappedValue = selected ? 0 : mapped
                    persistDraft()
                } label: {
                    Text(option)
                        .font(.caption)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)   // 칩은 낱말을 꺾지 않는다
                        .foregroundStyle(selected ? Ink.paper : Ink.text.opacity(half ? 0.9 : 0.7))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(chipFill(selected: selected, half: half), in: Capsule())
                }
                // 왼쪽 칩과의 사이값 = mapped-1. 첫 칩은 왼쪽이 없어 중간값이 없다.
                .onLongPressGesture {
                    guard mapped > 1 else { return }
                    value.wrappedValue = current == mapped - 1 ? 0 : mapped - 1
                    persistDraft()
                }
                .accessibilityLabel("\(label) \(option)")
                .accessibilityValue(half ? Loc.str("이전 항목과의 중간") : "")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                // 롱프레스는 VoiceOver로 닿기 어렵다 — 같은 동작을 명시 액션으로도 연다
                .accessibilityAction(named: Loc.str("중간값으로")) {
                    guard mapped > 1 else { return }
                    value.wrappedValue = mapped - 1
                    persistDraft()
                }
        }
    }

    /// 증상 행 — **접혀 있다가 눌러야 펼쳐진다**(2026-09-04 베타 "아픈곳 저렇게 바로 노출하지
    /// 말고 … 버튼 클릭 시 아래에 띄워줘"). 아픈 날은 드물어서 매일 다섯 개를 펼쳐 두면
    /// 체크인 카드가 증상 목록처럼 읽힌다. 중간값 롱프레스 없음 — 증상은 있다/없다이지 정도가 아니다.
    private var symptomRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { symptomsExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    checkInLabel(Loc.str("아픈 곳이 있어요"))
                    if !draftSymptoms.isEmpty {
                        Text(verbatim: "\(draftSymptoms.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Ink.paper)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Ink.text, in: Capsule())
                    }
                    Image(systemName: symptomsExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Ink.text.opacity(0.4))
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(symptomsExpanded ? .isSelected : [])
            if symptomsExpanded {
                // 칩 5개를 한 줄 HStack에 두면 영어(Cold·Fever·aches·Upset stomach·Muscle ache·
                // Headache ≈ 422pt > 카드 330pt)에서 카드 폭을 넘고, 그 폭이 오늘 탭 VStack
                // 전체로 전파돼 centeredColumn이 화면 밖으로 양쪽 균등히 밀어냈다
                // (2026-09-04 찰칵 실측 + 실기기 영어 재현). 줄바꿈 흐름으로 폭 안에 가둔다.
                ChipFlow(spacing: 8, rowSpacing: 6) {
                    symptomChips
                }
            }
        }
    }

    private var symptomChips: some View {
        ForEach(CheckInSymptom.allCases, id: \.rawValue) { symptom in
            let selected = draftSymptoms.contains(symptom)
            Button {
                if selected { draftSymptoms.remove(symptom) } else { draftSymptoms.insert(symptom) }
                persistDraft()
            } label: {
                Text(symptom.title)
                    .font(.caption)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(selected ? Ink.paper : Ink.text.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(selected ? AnyShapeStyle(Ink.text) : AnyShapeStyle(Ink.text.opacity(0.08)),
                                in: Capsule())
            }
            .accessibilityLabel(Loc.fmt("증상 %1$@", symptom.title))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
    }

    /// SwiftUI 뷰 한 식에 조건 분기를 몰면 타입체크가 터진다 — 배경만 떼어 낸다(CLAUDE.md 실측)
    private func chipFill(selected: Bool, half: Bool) -> AnyShapeStyle {
        if selected { return AnyShapeStyle(Ink.text) }
        if half { return AnyShapeStyle(Ink.text.opacity(0.35)) }
        return AnyShapeStyle(Ink.text.opacity(0.08))
    }

    /// 신호를 먼저 비우고 노트를 마지막에 비운다 — 노트의 onChange가 persistDraft를 부르는데,
    /// 그 시점에 신호가 남아 있으면 새 날짜에 어제 값이 저장된다.
    private func reloadDraft() {
        draftEnergy = 0
        draftMood = 0
        draftSleep = 0
        draftAppetite = 0
        draftSymptoms = []
        draftNote = ""
        draftLoaded = false
        loadDraft()
    }

    private func loadDraft() {
        guard !draftLoaded else { return }
        draftLoaded = true
        if let existing = record {
            draftEnergy = existing.energy
            draftMood = existing.mood
            draftSleep = existing.sleep ?? 0
            draftAppetite = existing.appetite ?? 0
            draftSymptoms = existing.symptomSet
            symptomsExpanded = !draftSymptoms.isEmpty   // 적어 둔 게 있으면 펼친 채로 연다
            draftNote = existing.note ?? ""
            draftPhotoName = existing.photoName
        }
    }

    /// 한 줄 아래 사진(2026-09-04 베타 "오늘 한줄 밑에 사진 넣기 추가" · "사진 넣는건 최대 한장").
    /// 한 장뿐이라 갤러리가 아니라 자리 하나다 — 있으면 그 자리에 사진, 없으면 넣기 버튼.
    /// PhotosPicker는 앱 밖 프로세스에서 고르게 하므로 사진 접근 권한 문구가 필요 없다.
    @ViewBuilder
    private var photoRow: some View {
        if let image = CheckInPhotoStore.image(named: draftPhotoName) {
            ZStack(alignment: .topTrailing) {
                // ⚠ `maxHeight:`로는 안 된다(2026-09-05 베타 "사진 넣으니까 터치가 안돼").
                // maxHeight는 상한일 뿐 크기를 확정하지 않아서 scaledToFill이 원본 비율대로
                // 부풀고, 그 커진 프레임이 카드 밖까지 깔려 **카드 전체의 탭을 가로챘다**.
                // 높이를 확정(frame(height:))하고 clipped로 자른 뒤 히트 영역까지 프레임으로
                // 고정한다. 사진 자체는 누를 대상이 아니라 히트테스트를 아예 끈다(지우기는 X 버튼).
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 220)
                    .clipped()
                    .contentShape(Rectangle())
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
                Button {
                    removePhoto()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Ink.paper)
                        .padding(6)
                        .background(Ink.text.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel(Loc.str("사진 지우기"))
            }
        } else {
            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.caption)
                    Text("사진 넣기")
                        .font(.caption)
                }
                .foregroundStyle(Ink.text.opacity(0.55))
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { @MainActor in
                    // 고른 사진을 줄여 파일로 저장하고 이름만 기록에 붙인다(원본은 안 들고 온다)
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let name = CheckInPhotoStore.save(data) else { photoItem = nil; return }
                    CheckInPhotoStore.delete(draftPhotoName)   // 갈아 끼울 땐 옛 파일을 남기지 않는다
                    draftPhotoName = name
                    photoItem = nil
                    persistDraft()
                }
            }
        }
    }

    private func removePhoto() {
        CheckInPhotoStore.delete(draftPhotoName)
        draftPhotoName = nil
        persistDraft()
    }

    /// 저장 조건 = 필수 2신호(energy·mood) 또는 노트(§5.5 개정 2026-07-22 — 노트 단독 저장 허용,
    /// 한 줄 일기 유실 방지). 리듬 집계는 energy·mood 둘 다 1...5인 행만 쓴다(§5.6.3).
    private func persistDraft() {
        let hasSignals = draftEnergy > 0 && draftMood > 0
        let hasNote = !draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // 증상 단독도 저장(2026-09-01) — 아픈 날은 신호를 안 매길 수 있다. 그 자체가 기록이다.
        let hasSymptoms = !draftSymptoms.isEmpty
        // 사진 단독도 기록이다(2026-09-04) — 글은 없고 사진만 남기는 날이 있다
        let hasPhoto = draftPhotoName != nil
        if let existing = record {
            if hasSignals || hasNote || hasSymptoms || hasPhoto {
                existing.energy = draftEnergy
                existing.mood = draftMood
                existing.sleep = draftSleep > 0 ? draftSleep : nil
                // irritability·pain은 건드리지 않는다 — 입력 행이 사라졌을 뿐(2026-08-05 병합),
                // 과거에 기록된 값을 0 초안으로 덮어쓰면 리듬 집계 표본이 파괴된다.
                existing.appetite = draftAppetite > 0 ? draftAppetite : nil
                existing.symptomSet = draftSymptoms
                existing.note = hasNote ? draftNote : nil
                existing.photoName = draftPhotoName
                if Seeds.stampCompletion(existing, signals: signals) { seedEarned += 1 }   // 씨앗 도장+연출
            } else {
                CheckInPhotoStore.delete(existing.photoName)   // 기록이 사라지면 사진도 남기지 않는다
                modelContext.delete(existing)   // 전부 해제 = 기록 철회(스킵 무벌점)
            }
        } else if hasSignals || hasNote || hasSymptoms || hasPhoto {
            // 지난 날짜에 쓰는 기록 = 회상 기반이라 적합 가중치가 다르다(v1.5 §3-4).
            // 판정 기준은 "카드가 보고 있는 날 ≠ 오늘" — 자정 넘겨 마무리하는 하루도 여기 걸린다.
            let created = DailyCheckIn(day: normalizedDay, energy: draftEnergy, mood: draftMood,
                                       isBackfilled: !isToday)
            created.sleep = draftSleep > 0 ? draftSleep : nil
            created.appetite = draftAppetite > 0 ? draftAppetite : nil
            created.symptomSet = draftSymptoms
            created.note = hasNote ? draftNote : nil
            created.photoName = draftPhotoName
            if Seeds.stampCompletion(created, signals: signals) { seedEarned += 1 }   // 씨앗 도장+연출
            modelContext.insert(created)
        }
    }
}

/// 칩 줄바꿈 흐름 — HStack처럼 왼쪽부터 놓다가 제안 폭을 넘기면 다음 줄로 (2026-09-04).
/// 칩은 fixedSize라 ideal 크기로 잰다. 제안 폭이 없으면(ViewThatFits 측정 등) 한 줄로 친다.
private struct ChipFlow: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

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
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
