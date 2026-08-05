"""템포루틴 내보내기 JSON 분석 — 엔진 파라미터 검증 리포트.

동의 기반 수동 기증 루프(2026-08-05)의 분석 도구. 설정 「JSON으로 내보내기」 파일을 받아
§5.12가 "파일럿 후 확인"으로 미룬 것들을 실데이터로 검증한다:

  1. 주기 요약 — 에피소드·gap 분포·유효/무효 gap·averageLength(v1.1)
  2. 예측 백테스트 — 각 시점까지의 기록으로 다음 시작일을 예측해 실제와 비교
  3. 조화 적합 분포 — 주기별 진폭·편향 보정 클리핑률 (§5.12 ② "전원 저진폭형" 실패 모드 감지)
  4. 축 추정 — 칼만 궤적·유형 판정 + A₀ 민감도 (0.3~0.7에서 유형이 어떻게 갈리는지)
  5. 사분면 커버리지 — 주기별 기록 밀도 (§5.12 ⑤ 리마인더의 근거 데이터)

Swift 엔진(TempoCore)과 같은 산식의 재구현이다 — 상수·순서를 바꾸면 검증이 아니라
다른 엔진이 된다. 변경 시 원본(CyclePredictor·HarmonicFit·AxisEstimator)과 대조할 것.

사용:
  python tools/analyze_export.py <내보내기.json> [--out 리포트.txt]
"""

from __future__ import annotations

import argparse
import io
import json
import math
import sys
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

# ── 엔진 상수 (TempoCore와 동일 — 여기만 바꾸는 것 금지) ──
MIN_PERIOD_GAP_DAYS = 14          # PeriodMath.minPeriodGapDays
VALID_GAP_RANGE = range(21, 36)   # CyclePredictor.averageLength v1.1 ①
RECENT_GAP_WINDOW = 5             # v1.1 ②
DEFAULT_CYCLE_LENGTH = 28
MIN_FIT_SAMPLES = 4               # HarmonicFit.minimumSamples
BACKFILLED_WEIGHT = 0.5           # HarmonicFit.backfilledWeight
MIN_OBS_VARIANCE = 1.0 / 12.0     # AxisEstimator.minObservationVariance
MIN_STATE_VARIANCE = 1.0 / 24.0   # AxisEstimator.minStateVariance
PROCESS_VARIANCE = 0.02           # AxisEstimator.processVariance
BASELINE_AMPLITUDE = 0.5          # AxisEstimator.baselineAmplitude (A₀)
RUBATO_LOWER = 0.5
RUBATO_UPPER = 0.85
SCALE_MAX = 5                     # AxisScale.max
QUADRANTS = 4                     # QuadrantCoverage.count


@dataclass(frozen=True)
class CheckIn:
    day: date
    energy: int
    mood: int
    sleep: int | None
    pain: int | None
    irritability: int | None
    is_backfilled: bool


@dataclass(frozen=True)
class HarmonicResult:
    mean: float
    raw_amplitude: float
    amplitude: float
    sample_count: int

    @property
    def clipped(self) -> bool:
        return self.raw_amplitude > 0 and self.amplitude == 0


@dataclass(frozen=True)
class AxisState:
    amplitude: float
    variance: float
    observed_cycles: int


# ── 파싱 ──

def parse_day(value: str) -> date:
    return datetime.strptime(value, "%Y-%m-%d").date()


def load_export(path: Path) -> tuple[list[date], list[CheckIn]]:
    with path.open(encoding="utf-8") as f:
        raw = json.load(f)
    period_days = sorted({parse_day(entry["day"]) for entry in raw.get("periodDays", [])})
    check_ins: list[CheckIn] = []
    for entry in raw.get("checkIns", []):
        check_ins.append(CheckIn(
            day=parse_day(entry["day"]),
            energy=int(entry.get("energy", 0)),
            mood=int(entry.get("mood", 0)),
            sleep=entry.get("sleep"),
            pain=entry.get("pain"),
            irritability=entry.get("irritability"),
            is_backfilled=bool(entry.get("isBackfilled", False)),
        ))
    check_ins.sort(key=lambda c: c.day)
    return period_days, check_ins


# ── PeriodMath / CyclePredictor 재현 ──

def episode_starts(days: list[date], min_gap: int = MIN_PERIOD_GAP_DAYS) -> list[date]:
    """에피소드 시작일 — 직전 에피소드 '시작일 + minGap' 미만은 같은 에피소드."""
    starts: list[date] = []
    current_start: date | None = None
    for day in sorted(set(days)):
        if current_start is None or (day - current_start).days >= min_gap:
            starts.append(day)
            current_start = day
    return starts


def swift_round(value: float) -> int:
    """Swift .rounded() = half away from zero. 파이썬 round()는 짝수 반올림이라 다르다."""
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


def average_length(starts: list[date]) -> int:
    if len(starts) < 2:
        return DEFAULT_CYCLE_LENGTH
    ordered = sorted(starts)
    gaps = [(b - a).days for a, b in zip(ordered, ordered[1:])]
    valid = [g for g in gaps if g in VALID_GAP_RANGE][-RECENT_GAP_WINDOW:]
    if not valid:
        return DEFAULT_CYCLE_LENGTH
    return max(21, min(35, swift_round(sum(valid) / len(valid))))


def phase_spans(n: int) -> list[tuple[str, int, int]]:
    """(단계명, 시작일차, 길이) — §5.3 M=5/B=14/O=3, 짧은 주기 클램프."""
    m, b, o = 5, 14, 3
    men, fol, ovu, lut = m, (n - b) - m, o, b - o
    while fol < 1:
        if lut > 1:
            lut -= 1
        elif ovu > 1:
            ovu -= 1
        elif men > 1:
            men -= 1
        else:
            break
        fol += 1
    spans: list[tuple[str, int, int]] = []
    start = 1
    for name, length in (("겨울", men), ("봄", fol), ("여름", ovu), ("가을", lut)):
        spans.append((name, start, length))
        start += length
    return spans


def phase_for_day(day: int, n: int) -> str:
    d = min(max(day, 1), n)
    for name, start, length in phase_spans(n):
        if start <= d < start + length:
            return name
    return phase_spans(n)[-1][0]


# ── SignalConversion 재현 ──

def recorded(value: int | None) -> float | None:
    if value is None or not 1 <= value <= SCALE_MAX:
        return None
    return float(value)


def flipped(value: float) -> float:
    return float(SCALE_MAX + 1) - value


def emotional(mood: int | None, irritability: int | None) -> float | None:
    m = recorded(mood)
    flipped_mood = flipped(m) if m is not None else None
    i = recorded(irritability)
    if flipped_mood is not None and i is not None:
        return (flipped_mood + i) / 2
    return flipped_mood if flipped_mood is not None else i


# ── HarmonicFit 재현 ──

def solve3x3(matrix: list[list[float]], rhs: list[float]) -> list[float] | None:
    m = [row[:] for row in matrix]
    v = rhs[:]
    for col in range(3):
        pivot = max(range(col, 3), key=lambda r: abs(m[r][col]))
        if abs(m[pivot][col]) <= 1e-10:
            return None
        if pivot != col:
            m[pivot], m[col] = m[col], m[pivot]
            v[pivot], v[col] = v[col], v[pivot]
        for row in range(col + 1, 3):
            factor = m[row][col] / m[col][col]
            if factor == 0:
                continue
            for k in range(col, 3):
                m[row][k] -= factor * m[col][k]
            v[row] -= factor * v[col]
    out = [0.0, 0.0, 0.0]
    for row in (2, 1, 0):
        acc = v[row]
        for k in range(row + 1, 3):
            acc -= m[row][k] * out[k]
        out[row] = acc / m[row][row]
    return out if all(math.isfinite(x) for x in out) else None


def harmonic_fit(samples: list[tuple[float, float, float]]) -> HarmonicResult | None:
    """samples = (theta, value, weight). TempoCore HarmonicFit.fit와 동일 산식."""
    if len(samples) < MIN_FIT_SAMPLES:
        return None
    sw = sc = ss = scc = sss = scs = sy = syc = sys_ = 0.0
    for theta, y, w in samples:
        c, s = math.cos(theta), math.sin(theta)
        sw += w
        sc += w * c
        ss += w * s
        scc += w * c * c
        sss += w * s * s
        scs += w * c * s
        sy += w * y
        syc += w * y * c
        sys_ += w * y * s
    if sw <= 0:
        return None
    solution = solve3x3([[sw, sc, ss], [sc, scc, scs], [ss, scs, sss]], [sy, syc, sys_])
    if solution is None:
        return None
    c0, a, b = solution
    residual = sum(
        w * (y - (c0 + a * math.cos(theta) + b * math.sin(theta))) ** 2
        for theta, y, w in samples
    )
    dof = sw - 3
    noise = residual / dof if dof > 0 else 0.0
    raw_power = a * a + b * b
    corrected = max(0.0, raw_power - 2 * noise / sw)
    return HarmonicResult(
        mean=c0,
        raw_amplitude=math.sqrt(raw_power),
        amplitude=math.sqrt(corrected),
        sample_count=len(samples),
    )


# ── AxisEstimator 재현 ──

def kalman_update(state: AxisState | None, fit: HarmonicResult) -> AxisState:
    observation = fit.amplitude
    obs_var = max(MIN_OBS_VARIANCE, 1.0 / max(1, fit.sample_count))
    if state is None:
        return AxisState(observation, max(MIN_STATE_VARIANCE, obs_var), 1)
    predicted = max(MIN_STATE_VARIANCE, state.variance + PROCESS_VARIANCE)
    gain = predicted / (predicted + obs_var)
    amplitude = state.amplitude + gain * (observation - state.amplitude)
    variance = max(MIN_STATE_VARIANCE, (1 - gain) * predicted)
    return AxisState(amplitude, variance, state.observed_cycles + 1)


def normal_cdf(x: float) -> float:
    return 0.5 * (1 + math.erf(x / math.sqrt(2)))


def classify(state: AxisState, baseline: float) -> str:
    sigma = math.sqrt(state.variance)
    margin = state.amplitude - baseline
    phi = (1.0 if margin > 0 else 0.0) if sigma <= 0 else normal_cdf(margin / sigma)
    if phi < RUBATO_LOWER:
        return "안단테"
    if phi < RUBATO_UPPER:
        return "루바토"
    return "비바체"


# ── 리포트 ──

def cycle_signals(check_ins: list[CheckIn], start: date, length: int) -> list[tuple[int, CheckIn]]:
    """완료 주기 안의 (1-indexed 일차, 체크인). energy·mood 필수 규약(§5.6.3)."""
    result: list[tuple[int, CheckIn]] = []
    for entry in check_ins:
        offset = (entry.day - start).days
        if 0 <= offset < length and 1 <= entry.energy <= 5 and 1 <= entry.mood <= 5:
            result.append((offset + 1, entry))
    return result


def build_report(period_days: list[date], check_ins: list[CheckIn]) -> str:
    lines: list[str] = []
    out = lines.append
    starts = episode_starts(period_days)
    out("# 템포루틴 내보내기 분석")
    out("")

    # 1. 주기 요약
    out("## 1. 주기 요약")
    out(f"- 생리 기록 {len(period_days)}일 · 에피소드 {len(starts)}개")
    if len(starts) >= 2:
        gaps = [(b - a).days for a, b in zip(starts, starts[1:])]
        valid = [g for g in gaps if g in VALID_GAP_RANGE]
        out(f"- gap 전체 {len(gaps)}개: {gaps}")
        out(f"- 유효 gap(21~35) {len(valid)}개 / 무효(기록 공백·스포팅 추정) {len(gaps) - len(valid)}개")
        out(f"- averageLength(v1.1) = {average_length(starts)}일")
    out("")

    # 2. 예측 백테스트
    out("## 2. 예측 백테스트 (k번째 시작일까지의 기록 → k+1번째 예측)")
    errors: list[int] = []
    for k in range(2, len(starts)):
        history = starts[:k]
        predicted_len = average_length(history)
        actual_gap = (starts[k] - starts[k - 1]).days
        error = actual_gap - predicted_len
        marker = "" if actual_gap in VALID_GAP_RANGE else "  (무효 gap — 기록 공백 의심)"
        out(f"- {starts[k]}: 예측 {predicted_len}일 vs 실제 {actual_gap}일 → 오차 {error:+d}{marker}")
        if actual_gap in VALID_GAP_RANGE:
            errors.append(error)
    if errors:
        mae = sum(abs(e) for e in errors) / len(errors)
        bias = sum(errors) / len(errors)
        out(f"- 유효 주기 {len(errors)}개 기준: MAE {mae:.2f}일 · 부호 평균 {bias:+.2f}일")
    else:
        out("- 유효 주기 표본 없음")
    out("")

    # 3~5. 완료 주기 순회
    out("## 3. 조화 적합 분포 (정서 계열)")
    fits: list[HarmonicResult] = []
    coverage_rows: list[str] = []
    for idx in range(len(starts) - 1):
        start, end = starts[idx], starts[idx + 1]
        length = (end - start).days
        if length <= 0:
            continue
        rows = cycle_signals(check_ins, start, length)
        quad_counts = [0] * QUADRANTS
        samples: list[tuple[float, float, float]] = []
        for day_in_cycle, entry in rows:
            value = emotional(entry.mood, entry.irritability)
            if value is None:
                continue
            theta = 2 * math.pi * (day_in_cycle - 1) / length
            weight = BACKFILLED_WEIGHT if entry.is_backfilled else 1.0
            samples.append((theta, value, weight))
            quad = min(QUADRANTS - 1, (day_in_cycle - 1) * QUADRANTS // length)
            quad_counts[quad] += 1
        if rows:
            coverage_rows.append(f"- {start} ({length}일): 사분면 {quad_counts}"
                                 f"{'  ⚠ 빈 사분면' if 0 in quad_counts else ''}")
        fit = harmonic_fit(samples)
        if fit is None:
            if samples:
                out(f"- {start}: 표본 {len(samples)}개 — 적합 불가(최소 {MIN_FIT_SAMPLES} 또는 특이 행렬)")
            continue
        clip = "  ⚠ 클리핑(보정 후 0)" if fit.clipped else ""
        out(f"- {start}: raw {fit.raw_amplitude:.3f} → 보정 {fit.amplitude:.3f}"
            f" (표본 {fit.sample_count}){clip}")
        fits.append(fit)
    if fits:
        clipped = sum(1 for f in fits if f.clipped)
        out(f"- 적합 주기 {len(fits)}개 · 클리핑 {clipped}개"
            f" ({clipped / len(fits) * 100:.0f}% — §5.12 ②: 과반이면 전원 저진폭형 경보)")
    else:
        out("- 적합 가능한 주기 없음 (주기당 유효 표본 4개 미만)")
    out("")

    out("## 4. 축 추정 (칼만 궤적 + A₀ 민감도)")
    state: AxisState | None = None
    for fit in fits:
        state = kalman_update(state, fit)
        out(f"- 주기 {state.observed_cycles}: μ {state.amplitude:.3f} · σ² {state.variance:.4f}")
    if state is not None:
        out(f"- 현행 판정(A₀={BASELINE_AMPLITUDE}): {classify(state, BASELINE_AMPLITUDE)}")
        sensitivity = ", ".join(
            f"A₀={a:.1f}→{classify(state, a)}" for a in (0.3, 0.4, 0.5, 0.6, 0.7)
        )
        out(f"- A₀ 민감도: {sensitivity}")
    else:
        out("- 축 추정 불가 (적합 주기 0)")
    out("")

    out("## 5. 사분면 커버리지 (완료 주기별)")
    if coverage_rows:
        lines.extend(coverage_rows)
    else:
        out("- 완료 주기 안 체크인 없음")
    out("")

    total = len(check_ins)
    valid_rows = sum(1 for c in check_ins if 1 <= c.energy <= 5 and 1 <= c.mood <= 5)
    backfilled = sum(1 for c in check_ins if c.is_backfilled)
    out("## 6. 체크인 원자료")
    out(f"- 총 {total}건 · 집계 유효(energy·mood) {valid_rows}건 · 소급 {backfilled}건")
    return "\n".join(lines)


def main() -> None:
    # Windows 콘솔 기본이 cp949라 리포트의 —·⚠ 가 UnicodeEncodeError로 죽는다(실측).
    # PYTHONIOENCODING에 기대지 않고 스크립트가 스스로 UTF-8로 재구성한다.
    # (mypy: sys.stdout 타입은 TextIO라 reconfigure가 안 보인다 — 런타임 타입으로 좁힌다)
    if isinstance(sys.stdout, io.TextIOWrapper):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="템포루틴 내보내기 JSON 분석")
    parser.add_argument("export_path", type=Path, help="설정 「JSON으로 내보내기」 파일")
    parser.add_argument("--out", type=Path, default=None, help="리포트 저장 경로(생략 시 stdout)")
    args = parser.parse_args()

    period_days, check_ins = load_export(args.export_path)
    report = build_report(period_days, check_ins)
    if args.out is not None:
        args.out.write_text(report, encoding="utf-8")
        print(f"OK: -> {args.out}")
    else:
        print(report)


if __name__ == "__main__":
    main()
