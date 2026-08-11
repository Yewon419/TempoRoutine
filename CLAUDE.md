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
- Swift 6 strict(CI Xcode 26.5) 실측 2건(2026-07-29, 각 CI 한 바퀴 소진): ① 전역 가변
  `static var`는 그대로 두면 concurrency 에러 — 쓰기 경로가 메인 한정이면
  `nonisolated(unsafe)` + 근거 주석(ThemeStore 사례. @MainActor 격리는 정적 API 콜사이트
  전파 비용 따져보고). ② 단일 식(switch·if) 함수에 문장을 추가하면 암묵 반환이 깨진다 —
  `return switch`로 명시.
