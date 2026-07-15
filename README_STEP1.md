# Phase 0 ① 예측 엔진 — 아이폰 검증 (Mac 0)

`Playground/Step1_CyclePredictor.swift` = MASTER.md §5.6 예측 엔진(resolveDate + overflow + 단계 경계 + 상태)을
실행 가능한 Swift로 옮긴 것 + 단위 테스트 25케이스(T1~T16). 순수 Foundation이라 네이티브(SwiftData/HealthKit/UI)
의존 0 → **Swift Playgrounds 앱에서 폰으로 바로 실행·검증 가능.**

## 아이폰에서 돌리는 법
1. App Store에서 **Swift Playgrounds** 설치(무료).
2. 앱 열기 → **새 빈 항목**(App이 아니라 빈 Playground) 생성.
3. `Step1_CyclePredictor.swift` 내용을 **전체 복사 → 붙여넣기**.
4. **▶ 실행**.
5. 콘솔에 `✅` 25줄 + `— 25 passed, 0 failed —` 나오면 통과.
   - `❌`가 뜨면 그 테스트 이름 알려줘 — 엔진이나 스펙(MASTER §5.6) 중 어디가 어긋났는지 잡는다.

> iPad Swift Playgrounds가 가장 매끄럽지만 iPhone 버전도 코드 실행 됨. 안 되면 Mac/온라인 Swift 컴파일러로도 동일 검증 가능(순수 로직이라 어디서 돌려도 같음).

## 검증하는 것
- 단계 경계(§5.3 황체기 고정 모델, 28/35/21일)
- resolveDate + overflow(clamp/skip/carry, 주기 클램프)
- cycleDay 과거 실주기 앵커 / 미래·overdue 투영(§5.6.2 정정)
- confidence·isOverdue·averageLength

## 이 단계가 검증 못 하는 것 (다음 단계)
SwiftData @Model·HealthKit·EventKit·SwiftUI(Liquid Glass)는 네이티브라 Xcode 빌드 필요.
→ 클라우드 Mac(GitHub Actions / Xcode Cloud) → TestFlight → 아이폰. (§5.9 빌드 순서 2번~)
