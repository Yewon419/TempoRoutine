// 템포루틴 — 온보딩 「템포 렌즈」 굴절 셰이더 (2026-09-07)
// 시스템 glassEffect는 실기기에서 2회 기각(Almanac.swift:314) — 렌즈 굴절은 distortionEffect로 직접 그린다.
// 볼록 렌즈: 가장자리는 그대로 두고 중심으로 갈수록 샘플 지점을 안쪽으로 당겨(= 확대) 유리 볼록면처럼 읽히게.
// strength 0.10 = 중심 배율 약 1.11. maxSampleOffset은 호출부가 지름의 6%로 준다(최대 변위 ≈ 4%).

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[ stitchable ]] float2 lensWarp(float2 position, float2 size, float strength) {
    float2 center = size * 0.5;
    float radius = min(size.x, size.y) * 0.5;
    float2 p = (position - center) / radius;
    float r = length(p);
    if (r >= 1.0) { return position; }
    float k = 1.0 - strength * (1.0 - r * r);
    return center + p * k * radius;
}
