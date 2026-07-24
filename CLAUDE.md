# TempoRoutine — 빌드 규칙 (실수 → 규칙)

제품·설계 SSOT는 `..\MASTER.md`, 시안 SSOT는 `..\ui-mockup\DESIGN.md`. 여기는 코드 함정만.

- **새 `@Model` 추가 시 `StoreBootstrap.swift`의 AppStores 모델 목록에 반드시 등록**(2026-07-23
  2층 분리 후 등록처 이동 — 민감층 vs 플래너층 배치도 §5.2 계약으로 판단. HK read 데이터는 절대
  CloudKit 층 금지). 스키마 밖 모델은 컴파일은 통과하지만 실기기에서 insert/@Query가 조용히
  실패한다(2026-07-19 "Input 추가 안 됨" — CI 3잡 그린이어도 못 잡는 유형).
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
