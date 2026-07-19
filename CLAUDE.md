# TempoRoutine — 빌드 규칙 (실수 → 규칙)

제품·설계 SSOT는 `..\MASTER.md`, 시안 SSOT는 `..\ui-mockup\DESIGN.md`. 여기는 코드 함정만.

- **새 `@Model` 추가 시 `TempoRoutineApp`의 `.modelContainer(for:)` 목록에 반드시 등록.**
  스키마 밖 모델은 컴파일은 통과하지만 실기기에서 insert/@Query가 조용히 실패한다
  (2026-07-19 "Input 추가 안 됨" — CI 3잡 그린이어도 못 잡는 유형).
- CI는 컴파일·순수 로직만 검증한다. SwiftData 스키마·권한·제스처 같은 런타임 동작은
  TestFlight 실기기 확인 전까지 "완료"가 아니다.
- 연관값 enum을 저장·직렬화할 땐 discriminator 커스텀 Codable (§5.5.1, 실기기 실측 결함).
- Windows 환경 — Swift 컴파일 불가. 검증 루프 = push → GitHub Actions 3잡 → TestFlight.
