# TempoRoutine — 빌드 규칙 (실수 → 규칙)

제품·설계 SSOT는 `..\MASTER.md`, 시안 SSOT는 `..\ui-mockup\DESIGN.md`. 여기는 코드 함정만.

- **새 `@Model` 추가 시 `TempoRoutineApp`의 `.modelContainer(for:)` 배열에 반드시 등록.**
  스키마 밖 모델은 컴파일은 통과하지만 실기기에서 insert/@Query가 조용히 실패한다
  (2026-07-19 "Input 추가 안 됨" — CI 3잡 그린이어도 못 잡는 유형).
- **⚠ 2층 CloudKit 스토어 = 2026-07-24 롤백.** 2-configuration ModelContainer가 실기기서
  저장 후 재시작 시 @Query 0을 읽는 결함(저장은 됨=fetchCount N, 재시작 후 0). split-brain
  폴백 수정·재실행 마이그레이션 회수 모두 실패. **Windows/CI-only로는 재현·디버그 불가** —
  시뮬레이터 없이 SwiftData 멀티컨피그를 깜깜이 왕복으로 잡으려다 10빌드 소진. 단일
  default.store로 복귀. 재도전은 맥+시뮬레이터 확보 후에만.
- CI는 컴파일·순수 로직만 검증한다. SwiftData 스키마·권한·제스처 같은 런타임 동작은
  TestFlight 실기기 확인 전까지 "완료"가 아니다.
- 연관값 enum을 저장·직렬화할 땐 discriminator 커스텀 Codable (§5.5.1, 실기기 실측 결함).
- **연관값 enum·복합 Codable 값은 `@Model` 저장 프로퍼티로 직접 두지 않는다** — SwiftData
  composite 처리에서 실기기 크래시(2026-07-20 앱 충돌). `Data` 인코딩 저장 + computed 노출
  (`InputItem.scheduleData`·`OutputItem.recurrenceData` 패턴). raw String enum은 직접 저장 가능.
- 관계는 optional + inverse 명시(`@Relationship(inverse:)`) — CloudKit 호환 P0 규칙의 연장.
- Windows 환경 — Swift 컴파일 불가. 검증 루프 = push → GitHub Actions 3잡 → TestFlight.
- **한글 포함 소스에 PowerShell 텍스트 파이프라인(Get-Content|-replace|Set-Content) 금지** —
  PS 5.1 기본 인코딩이 UTF-8 소스를 깨뜨림(2026-07-20 TodayView 파손→git 복원). 편집은 Edit 도구로만.
- ASC 업로드 일일 한도 존재(실측 2026-07-20: 하루 ~16빌드에서 차단, Upload limit reached).
  한도 중엔 컴파일 잡 그린이면 코드 검증은 유효, TestFlight만 다음 날 재개.
- **빌드는 몰아서(2026-07-20 사용자 결정):** TestFlight 잡 = workflow_dispatch 수동 전용.
  작업 여러 개를 커밋으로 쌓고, 배포는 `gh workflow run CI --ref main` 1회. push는 컴파일 검증만.
- **배포 디스패치는 명시 지시가 있을 때만**(2026-08-09 교정: 검증 루프 중이라는 이유로
  수정 건마다 자동 디스패치하다 제지됨 — "배포는 나중에"). 직전 턴에 배포 지시가 있었어도
  다음 수정의 배포 승인으로 이월되지 않는다.
- push 직후 dispatch하면 런이 2개 생긴다 — `gh run list` 최신 1개는 push 런(업로드 skipped)일 수
  있으니 배포 확인은 `event=workflow_dispatch`인 런으로 (2026-07-22 혼동 실측).
- exportArchive "The data couldn't be read because it isn't in the correct format" = ASC cloud
  signing 일시 오류 사례 있음(2026-07-23, 동일 설정 30분 전 성공·재시도 즉시 성공) — 설정 무변경이면
  원인 파기 전에 1회 재디스패치 먼저.
- 수동 생성 ModelContainer는 `mainContext.autosaveEnabled = true` 명시 + 대량 쓰기 후 `save()`.
  암묵 기본값 의존 금지 — .modelContainer(for:) 모디파이어와 달리 보장이 불명확(2026-07-23).
- HealthKit 권한은 앱 삭제·재설치로 초기화되지 않는다 — 재설치해도 권한 시트가 다시 안 뜨고
  이전 거부 상태를 물려받아 read가 조용히 빈 배열이 된다(2026-07-23 실기기 실측).
- **2층 스토어 폴백은 절대 default.store로 갈라지지 않는다**(2026-07-24 split-brain 실측): 폴백까지
  같은 named config(tempo-sensitive/tempo-planner)를 써야 저장 위치가 실행마다 안 바뀐다. `try!
  ModelContainer(for: fullSchema)`(무설정=default.store)는 금지. 증상 = "저장 후 fetchCount N, 재시작
  후 @Query 0". 회수는 migrateLegacyStoreIfNeeded 재실행(멱등 merge)으로 default.store를 drain.
- SwiftUI 뷰 한 식에 shape+fill+frame+overlay+offset을 다 몰면 "unable to type-check this
  expression in reasonable time"으로 빌드가 깨진다(2026-07-25 실측). 지역 상수에 타입을 명시하고
  하위 뷰 함수로 쪼갤 것 — Windows에선 컴파일이 안 돌아 CI 한 바퀴를 버리게 된다.
  **RootTabView body는 모디파이어 체인이 이미 한계선**(2026-08-30 실측: `.task` 1개 추가로 초과,
  CI 33289665318) — 새 시작 작업은 모디파이어를 늘리지 말고 기존 `.task`/`.onChange` 블록 안에 합칠 것.
- 익스텐션 추가 시 cloud signing은 새 번들 ID·App Group을 자동 등록하지 못한다(2026-07-27 실측:
  "Authentication failed" + "No profiles"). 번들 ID·capability는 ASC API로 대행 가능하지만
  **App Group 생성·번들 연결은 공개 API에 없다**(/v1/appGroups=404) — 개발자 포털 수동(또는
  브라우저 대행). capability 변경은 기존 프로파일을 무효화하며 다음 export가 재생성한다.
- 무서명 archive의 entitlement ad-hoc 심기는 **중첩 appex 먼저, 앱 나중** 순서(ci.yml 실장).
- 드래그처럼 프레임마다 @State를 갱신하는 제스처는 그 뷰 body를 초당 60~120회 재평가한다 —
  body 경로에 파생 데이터 계산(occurrence 열거·Set 생성·주기 연산)이 있으면 앱이 통째로 버벅인다
  (2026-07-27 캘린더 캐러셀 실측). 드래그 시작 때 한 번 캐시하고 프레임 경로는 조회만. 유휴 시엔
  화면 밖 콘텐츠(캐러셀 옆 패널)를 아예 렌더하지 않는다.
- **이 리포 커밋은 명시 경로로만** — `git add -A` 금지(2026-07-28 실측: 병렬 세션의 브랜딩
  작업 파일이 무관한 커밋에 딸려 들어감). 병렬 Claude 세션이 같은 워킹트리를 쓸 수 있다.
- **CloudKit 커스텀 레코드 타입은 콘솔 스키마 프로덕션 배포가 선행 조건**(2026-08-11 실측:
  PlannerSync TRItem이 오류 12 invalidArguments). TestFlight = 프로덕션 환경이고 JIT 스키마
  생성은 개발 환경 전용 — 새 레코드 타입/필드를 코드로 추가하면 콘솔에서 Development에 만들고
  Deploy to Production까지 해야 실기기에서 저장된다. TestFlight 빌드가 안 뜰 땐 ASC API로
  builds(VALID)·buildBetaDetail(IN_BETA_TESTING) 확인 — 처리 지연이 20분+일 수 있다.
- **잠금·AOD에서 위젯·Live Activity가 「빈 흰 덩어리」로 뜨면 redaction이다**(2026-08-16 실측).
  시스템이 잠금 상태 콘텐츠에 privacy redaction을 걸고 그 placeholder가 내용 없는 박스로 그려진다.
  배경을 두지 않은 배너는 화면 전체가 빈 흰 사각형이 된다. 가릴 이유가 없는 콘텐츠면 `.unredacted()`.
  ⚠ 이 증상을 「렌더 실패」로 오진하기 쉽다 — 2026-08-14에 body의 `Date.now`를 원인으로 지목했다가
  배포 후 증상이 그대로여서 뒤집혔다. **잠금 관련 표시 이상은 redaction부터 의심할 것.**
- **위젯·Live Activity body에서 `Date.now` 금지**(위 건과 별개의 결함). 시스템이 미리 렌더해 둔 뷰를
  나중에 다시 그리므로 body의 현재 시각은 박제되거나 어긋난다. `Text(timerInterval:)` 구간을
  `Date.now`로 만들면 `now...now`로 무너질 수 있다. 시각 의존 값은 ContentState에 실어 불변으로 둘 것.
- **잠금화면 버튼이 암호를 묻는다면 `authenticationPolicy`**(2026-08-16 실측). AppIntent 기본값은
  `.requiresAuthentication`이라 탭마다 잠금 해제를 요구한다 — 잠금화면 버튼의 존재 이유를 무력화한다.
  상태 토글처럼 데이터를 열람·수정하지 않는 인텐트는 `.alwaysAllowed`로 명시.
- 잠금화면·위젯 버튼이 앱 데이터를 바꿔야 하면 **`LiveActivityIntent`**(또는 `AudioPlaybackIntent`).
  이것만 앱 프로세스 실행이 보장된다 — 일반 `AppIntent`는 위젯 익스텐션에서 돌아 SwiftData에
  닿지 못한다. 인텐트 타입은 두 타깃 공용이어야 하므로 @Model을 참조하는 실행부는 앱 타깃에
  두고 Shared에는 슬롯만(TimerIntentBridge 패턴).
- **새 파일·이식 전 심볼 확인 3종**(2026-08-17 — 한 사이클에 CI를 세 번 깨뜨린 원인).
  Windows라 컴파일이 안 돌아 전부 CI 한 바퀴씩 태우고서야 드러나는 유형이다.
  ① **`import TempoCore`** — 카드·주기 계열 타입(`InputCategory`·`OutputProgressKind`·
  `CyclePhase`…)은 TempoCore 소유다. 새 파일에 `import Foundation`만 넣으면 "cannot find type"이
  뜨고, 멤버 타입을 못 찾아 `Hashable` 자동 합성까지 연쇄로 깨진다.
  ② **이름 충돌** — 새 타입을 만들기 전에 `grep -rn "struct <이름>" App/ Widgets/ Shared/`.
  `TicketStub`이 캘린더에 이미 있는 줄 모르고 카드용으로 또 만들어 redeclaration이 났다.
  ③ **다른 화면 코드를 옮겨올 때 헬퍼 이름** — 같은 일을 화면마다 다른 이름으로 갖고 있다
  (오늘 탭 `isChecked` ↔ 하루 상세 `isCompleted`). 붙여넣기 전에 그 파일에 그 이름이 있는지 볼 것.
- **iOS 신규 OS API는 서드파티 레퍼런스 교차 확인으로도 확장 파라미터를 확신하지 않는다**
  (2026-08-19 실측: `glassEffect`의 `isEnabled:`가 레퍼런스 3곳에 있었지만 SDK엔 없음 —
  CI 한 바퀴 소진). 기본 파라미터 최소 형태로만 쓰고, 확장 파라미터는 CI 컴파일로 검증.
- **병렬 세션 활동 중엔 편집 즉시 커밋(더티 구간 최소화)** — 커밋 경합으로 내 변경이 상대
  커밋에 쓸려 들어간 사고 실측(2026-08-19, 677dd20). 같은 파일에 두 세션 변경이 혼재하면
  파일 단위 add 대신 **hunk 스테이징**(`git diff > p.patch` → 내 hunk만 필터 →
  `git apply --cached`)으로 분리한다.
- Swift 6 strict(CI Xcode 26.5) 실측 2건(2026-07-29, 각 CI 한 바퀴 소진): ① 전역 가변
  `static var`는 그대로 두면 concurrency 에러 — 쓰기 경로가 메인 한정이면
  `nonisolated(unsafe)` + 근거 주석(ThemeStore 사례. @MainActor 격리는 정적 API 콜사이트
  전파 비용 따져보고). ② 단일 식(switch·if) 함수에 문장을 추가하면 암묵 반환이 깨진다 —
  `return switch`로 명시.
- **로컬라이제이션 — 화면에 나갈 String을 만드는 자리는 예외 없이 `Loc.str`**(2026-08-22 실측: switch·배열·
  삼항으로 만든 한글 리터럴 341개가 카탈로그에 키가 있어도 번역을 안 탔다 — "3개국어 혼재"). 조회 경로는
  `Bundle.main` 클래스 덮어쓰기(`LocalizedBundle`) 하나로 모인다. `python tools/loc_audit.py`의
  「값 컨텍스트」 지표가 0이어야 한다. 보간은 `Loc.fmt` + 명시 `%lld`/`%1$@` 키(네이티브 보간은 Windows에서
  키를 실측할 수 없다 — 추출 생략 + Int도 `%@`).
- **iOS 26 `Glass.clear`는 미디어 위 전용 — 밝은 지면에 감광층을 깔아 회색 판이 된다**(2026-08-22 실기기).
  `.regular`는 재질 자체가 뿌옇다. 플레이리스트 카드는 자체 공식(`playlistGlass`)을 쓴다.
- **루트 `.id` 리빌드(테마·언어 변경)마다 `.task`가 다시 돈다** — 시작 작업(HealthKit 동기화·위젯 발행·
  알림 재예약·동기화 왕복)은 프로세스당 1회로 게이트(`RootTabView.bootstrapped`). 안 하면 "적용이 느리다".
- **`UserDefaults(suiteName:)`을 핫 패스에서 매번 만들지 않는다** — 문자열 조회마다 생성했다가 렌더가 굼떴다
  (2026-08-22). static let 1회.
- **enum rawValue(한글)는 저장·식별 키다 — 표시에 쓰지 않는다**(SeasonAnchor「겨울」이 영어에서 "Repeats 겨울").
  표시는 `title`/`seasonMeta(for:).name`. 비교도 이름이 아니라 `phase`로(번역되면 어긋난다).

- **TestFlight 배포(workflow_dispatch)는 대표님 명시 지시가 있을 때만** — push는 컴파일 검증까지가
  세션의 권한이다. "수정했으니 실기기 확인엔 배포가 필요하다"는 판단으로 대신 태우지 않는다
  (2026-08-26 교정 "왜 허락없이 빌드함"). 배포는 테스터에게 바로 나가는 외부 액션 + ASC 일일
  업로드 한도(~16빌드) 소모. 수정이 쌓이면 "미배포 N건" 보고 후 지시를 기다린다.
- **모드·환경 게이트는 호출부가 아니라 진입점(함수 안)에 건다** — 개발자 모드 1차판은 시작
  작업(RootTabView)만 막았는데, 설정 `refreshDerivedSurfaces`가 임포트·삭제마다 같은 함수들을
  우회로로 불러 실알림 취소·클라우드 업로드가 그대로 샜다(2026-08-28 전체 점검). 지금은
  `WidgetBridge.publish`·`DailyNotices/CoverageReminder.reschedule`·`ScheduleReminder.schedule`·
  `PlannerSync.kick/syncNow` 안에서 막는다. 호출부는 계속 늘어난다.
- **AVPlayer는 레이어 하나에만 그려진다** — 두 화면이 공유 플레이어를 쓰면 나중 레이어가
  소유권을 가져가고 먼저 있던 화면은 빈 채로 남는다(2026-08-27 플리 지면 실종). 공유 풀을 쓸
  땐 보이는 뷰가 `updateUIView`에서 소유권을 되찾아야 한다 — `player == nil`이면 return 하는
  구현은 한 번 뺏기면 영영 복구되지 않는다.
