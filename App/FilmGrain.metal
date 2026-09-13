// 템포루틴 — 온보딩 사계절 장 필름 그레인 (2026-09-13 J2 조판)
// 프로토(ui-mockup/onboarding-v2 ?variant=j)의 feTurbulence 오버레이(16%)를 colorEffect로 옮긴 것.
// 픽셀 좌표 해시 노이즈를 밝기에 더한다 — 인쇄물처럼 읽히게 하는 게 목적이라 색은 건드리지 않는다.
// amount = 진폭(0.16 ≈ 프로토). 정적 노이즈(시간 축 없음) — 매 프레임 달라지면 영상 노이즈로 읽힌다.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[ stitchable ]] half4 filmGrain(float2 position, half4 color, float amount) {
    float2 p = floor(position);
    float n = fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
    half g = half((n - 0.5) * amount);
    return half4(clamp(color.rgb + g * color.a, half3(0.0), half3(1.0)), color.a);
}
