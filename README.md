# TempoRoutine (템포루틴)

여성 호르몬 주기를 네 계절로 푼 온디바이스 iOS 루틴/플래너 앱. 태그라인 "당신 몸의 템포에 맞게."

설계 SSOT는 로컬 `MASTER.md`(repo 외부), UI 시안 SSOT는 `ui-mockup/DESIGN.md`(repo 외부).

## 구조

```
TempoCore/     순수 Foundation SPM 패키지 — 예측 엔진·주기 값 타입 (SwiftData 의존 금지)
  Sources/TempoCore/
    CycleTypes.swift        CyclePhase·CycleAnchor(+커스텀 Codable)·CycleRecurrence 등
    CyclePredictor.swift    averageLength·phaseSpans·resolveDate(+overflow)·cycleDay·confidence
  Tests/TempoCoreTests/     T1~T16, 25 assertions (아이폰 Playground 검증본 이식)
Playground/    Step1 검증용 단일 파일 (역사 보존 — SSOT는 TempoCore)
.github/workflows/ci.yml    잡 1: TempoCore swift test (Linux). 앱 빌드 잡은 빌드 2에서
```

## 테스트

```bash
swift test --package-path TempoCore
```

로컬에 Swift가 없으면 push — CI(Linux, 공식 Swift 컨테이너)가 실행한다.

## 로드맵 (Phase 0)

빌드 순서는 MASTER §5.9. 다음 = 빌드 2: XcodeGen `project.yml` + 앱 타깃(SwiftUI·SwiftData) + macOS 러너 잡 활성화(게이트: Apple Developer + ASC API 키 → GitHub Secrets).
