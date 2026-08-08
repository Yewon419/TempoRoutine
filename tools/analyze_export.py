"""템포루틴 내보내기 JSON 분석 — 엔진 파라미터 검증 리포트 (v2 — 윈도우 통계, 개정 M).

동의 기반 수동 기증 루프(2026-08-05)의 분석 도구. 설정 「JSON으로 내보내기」 파일을 받아
§5.12가 "파일럿 후 확인"으로 미룬 것들을 실데이터로 검증한다:

  1. 주기 요약 — 에피소드·gap 분포·유효/무효 gap·averageLength(v1.1)
  2. 예측 백테스트 — 각 시점까지의 기록으로 다음 시작일을 예측해 실제와 비교
  3. 윈도우 프로파일 — 완료 주기별 계절 윈도우 중앙값·range·프리 윈도우 후보
  4. 엔진 판정 재현 — P·H1·유형 + baselineRange(A₀) 민감도
     + 파일에 rhythmSummary 블록이 있으면(개정 M-6c) 재현값과 대조해 엔진 구현을 검증
  5. 사분면 커버리지 — 주기별 기록 밀도 (§5.12 ⑤ 리마인더의 근거 데이터)

Swift 엔진(TempoCore)과 같은 산식의 재구현이다 — 상수·순서를 바꾸면 검증이 아니라
다른 엔진이 된다. 변경 시 원본(CyclePredictor·WindowStats)과 대조할 것.
구 푸리에+칼만 재현부는 개정 M(2026-08-08)으로 폐기 — git 히스토리(`490eb20`)에 있다.

사용:
  python tools/analyze_export.py <내보내기.json> [--out 리포트.txt]
"""

from __future__ import annotations

import argparse
import io
import json
import math
import statistics
import sys
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

# ── 엔진 상수 (TempoCore와 동일 — 여기만 바꾸는 것 금지) ──
MIN_PERIOD_GAP_DAYS = 14          # PeriodMath.minPeriodGapDays
VALID_GAP_RANGE = range(21, 36)   # CyclePredictor.averageLength v1.1 ①
RECENT_GAP_WINDOW = 5             # v1.1 ②
DEFAULT_CYCLE_LENGTH = 28
SCALE_MAX = 5                     # AxisScale.max
QUADRANTS = 4                     # QuadrantCoverage.count
# WindowStatsEngine (개정 M)
RECENT_CYCLES = 5
MIN_CYCLES = 3
MIN_SAMPLES_PER_CYCLE = 4
MARGIN = 0.5
PRE_WINDOW_RANGE = range(2, 8)    # [2,7]
MIN_SUFFIX_SAMPLES = 2
LOW_DAY_FRACTION = 0.75
BASELINE_RANGE = 1.0
PHASES = ("겨울", "봄", "여름", "가을")
TYPE_NAMES = {"vivace": "비바체", "andante": "안단테", "rubato": "루바토"}


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
class WindowDay:
    """양방향 앵커 좌표(§5.12 ①) — d = 시작 후 일차, r = 다음 시작까지 남은 일수."""
    d: int
    r: int
    energy: int
    mood: int


@dataclass(frozen=True)
class WindowCycle:
    start: date
    length: int
    samples: tuple[WindowDay, ...]


# ── 파싱 ──

def parse_day(value: str) -> date:
    return datetime.strptime(value, "%Y-%m-%d").date()


def load_export(path: Path) -> tuple[list[date], list[CheckIn], dict[str, object] | None]:
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
    summary = raw.get("rhythmSummary")
    return period_days, check_ins, summary if isinstance(summary, dict) else None


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


# ── SignalConversion 재현 (사분면 커버리지 전용 — CoverageReminder와 동일 변환) ──

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


# ── WindowStatsEngine 재현 (§5.12 개정 M) ──

def signal_value(sample: WindowDay, signal: str) -> float | None:
    raw = sample.energy if signal == "energy" else sample.mood
    return float(raw) if 1 <= raw <= SCALE_MAX else None


def window_median(cycle: WindowCycle, signal: str,
                  days: list[WindowDay] | None = None) -> float | None:
    pool = cycle.samples if days is None else days
    values = [v for s in pool if (v := signal_value(s, signal)) is not None]
    return statistics.median(values) if values else None


def baseline(cycle: WindowCycle, signal: str) -> float | None:
    return window_median(cycle, signal)


def phase_median(cycle: WindowCycle, signal: str, phase: str) -> float | None:
    days = [s for s in cycle.samples if phase_for_day(s.d, cycle.length) == phase]
    return window_median(cycle, signal, days)


def usable(cycles: list[WindowCycle]) -> list[WindowCycle]:
    recent = cycles[-RECENT_CYCLES:]
    return [c for c in recent
            if sum(1 for s in c.samples
                   if signal_value(s, "energy") is not None
                   or signal_value(s, "mood") is not None) >= MIN_SAMPLES_PER_CYCLE]


def agreement_threshold(n: int) -> int:
    return max(MIN_CYCLES, n - 1)


def per_cycle_pre_window(cycle: WindowCycle) -> int | None:
    base = baseline(cycle, "energy")
    if base is None:
        return None
    best: int | None = None
    for p in PRE_WINDOW_RANGE:
        days = [v for s in cycle.samples if s.r <= p
                if (v := signal_value(s, "energy")) is not None]
        if len(days) < MIN_SUFFIX_SAMPLES:
            continue
        lows = sum(1 for v in days if v <= base - MARGIN)
        if lows / len(days) >= LOW_DAY_FRACTION:
            best = p
    return best


def pre_menstrual_window(cycles: list[WindowCycle]) -> int | None:
    pool = usable(cycles)
    if len(pool) < MIN_CYCLES:
        return None
    candidates = [p for c in pool if (p := per_cycle_pre_window(c)) is not None]
    if len(candidates) < agreement_threshold(len(pool)):
        return None
    mid = statistics.median(candidates)
    return min(PRE_WINDOW_RANGE[-1], max(PRE_WINDOW_RANGE[0], swift_round(float(mid))))


def h1_summer_mood_lift(cycles: list[WindowCycle]) -> bool | None:
    up = judged = 0
    for cycle in usable(cycles):
        base = baseline(cycle, "mood")
        summer = phase_median(cycle, "mood", "여름")
        if base is None or summer is None:
            continue
        judged += 1
        if summer >= base + MARGIN:
            up += 1
    if judged < MIN_CYCLES:
        return None
    threshold = agreement_threshold(judged)
    if up >= threshold:
        return True
    if judged - up >= threshold:
        return False
    return None


def per_cycle_range(cycle: WindowCycle, signal: str = "mood") -> float | None:
    medians = [m for phase in PHASES
               if (m := phase_median(cycle, signal, phase)) is not None]
    if len(medians) < 2:
        return None
    return max(medians) - min(medians)


def classify_ranges(ranges: list[float], baseline_range: float = BASELINE_RANGE) -> str | None:
    if len(ranges) < MIN_CYCLES:
        return None
    threshold = agreement_threshold(len(ranges))
    high = sum(1 for r in ranges if r >= baseline_range)
    if high >= threshold:
        return "vivace"
    if len(ranges) - high >= threshold:
        return "andante"
    return "rubato"


def group_cycles(starts: list[date], check_ins: list[CheckIn]) -> list[WindowCycle]:
    """완료 주기만 — AxisProfile.groupIntoCycles와 동일 기준(비백필 제외, r도 실측)."""
    cycles: list[WindowCycle] = []
    for idx in range(len(starts) - 1):
        start, end = starts[idx], starts[idx + 1]
        length = (end - start).days
        if length <= 0:
            continue
        samples = tuple(
            WindowDay(d=(c.day - start).days + 1, r=length - (c.day - start).days,
                      energy=c.energy, mood=c.mood)
            for c in check_ins
            if not c.is_backfilled and 0 <= (c.day - start).days < length
        )
        cycles.append(WindowCycle(start=start, length=length, samples=samples))
    return cycles


# ── 리포트 ──

def format_median(value: float | None) -> str:
    return "-" if value is None else f"{value:.1f}"


def compare_summary(lines: list[str], summary: dict[str, object],
                    cycles: list[WindowCycle]) -> None:
    """rhythmSummary 블록(개정 M-6c) vs 파이썬 재현 대조 — 불일치 = 엔진/도구 어느 쪽의 결함."""
    out = lines.append
    out("### rhythmSummary 대조 (파일 동봉 블록 vs 본 도구 재현)")
    engine = summary.get("engineVersion")
    if engine != "window-stats-1":
        out(f"- ⚠ engineVersion {engine!r} — 본 도구(window-stats-1)와 세대 불일치, 대조 생략")
        return
    checks: list[tuple[str, object, object]] = [
        ("usableCycles", summary.get("usableCycles"), len(usable(cycles))),
        ("preMenstrualWindow", summary.get("preMenstrualWindow"), pre_menstrual_window(cycles)),
        ("h1SummerMoodLift", summary.get("h1SummerMoodLift"), h1_summer_mood_lift(cycles)),
        ("rhythmType", summary.get("rhythmType"),
         classify_ranges([r for c in usable(cycles) if (r := per_cycle_range(c)) is not None])),
    ]
    mismatches = 0
    for name, theirs, ours in checks:
        ok = theirs == ours
        mismatches += 0 if ok else 1
        mark = "일치" if ok else f"⚠ 불일치 (파일 {theirs!r} vs 재현 {ours!r})"
        out(f"- {name}: {mark}")
    ranges_theirs = summary.get("perCycleRanges")
    ranges_ours = [r for c in usable(cycles) if (r := per_cycle_range(c)) is not None]
    if isinstance(ranges_theirs, list):
        floats = [float(x) for x in ranges_theirs if isinstance(x, (int, float))]
        ok = len(floats) == len(ranges_theirs) and len(floats) == len(ranges_ours) and all(
            abs(a - b) < 1e-9 for a, b in zip(floats, ranges_ours))
        mismatches += 0 if ok else 1
        out(f"- perCycleRanges: {'일치' if ok else f'⚠ 불일치 (파일 {floats} vs 재현 {ranges_ours})'}")
    out(f"- 종합: {'전 항목 일치 — 엔진 구현 검증 통과' if mismatches == 0 else f'{mismatches}건 불일치 — 원인 파야 함'}")


def build_report(period_days: list[date], check_ins: list[CheckIn],
                 summary: dict[str, object] | None) -> str:
    lines: list[str] = []
    out = lines.append
    starts = episode_starts(period_days)
    out("# 템포루틴 내보내기 분석 (v2 — 윈도우 통계)")
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

    # 3. 윈도우 프로파일 (완료 주기별)
    cycles = group_cycles(starts, check_ins)
    pool = usable(cycles)
    out("## 3. 윈도우 프로파일 (완료 주기별 — 비백필 표본)")
    for cycle in cycles:
        n_samples = sum(1 for s in cycle.samples
                        if signal_value(s, "energy") is not None
                        or signal_value(s, "mood") is not None)
        in_pool = "  (판정 포함)" if cycle in pool else ""
        rng = per_cycle_range(cycle)
        pre = per_cycle_pre_window(cycle)
        med = " ".join(
            f"{phase} {format_median(phase_median(cycle, 'mood', phase))}"
            for phase in PHASES
        )
        out(f"- {cycle.start} ({cycle.length}일, 표본 {n_samples}): mood [{med}]"
            f" · range {format_median(rng)} · 프리 윈도우 후보 {pre if pre is not None else '-'}"
            f"{in_pool}")
    if not cycles:
        out("- 완료 주기 없음")
    out("")

    # 4. 엔진 판정 재현
    out("## 4. 엔진 판정 재현 (윈도우 통계 — 최근 5주기·표본≥4)")
    ranges = [r for c in pool if (r := per_cycle_range(c)) is not None]
    verdict = classify_ranges(ranges)
    out(f"- 유효 주기 {len(pool)}개 · range 표본 {len(ranges)}개")
    out(f"- P(저컨디션 윈도우) = {pre_menstrual_window(cycles)}"
        f" · H1(여름 기분 상승) = {h1_summer_mood_lift(cycles)}"
        f" · 유형 = {TYPE_NAMES.get(verdict or '', '판정 불가(데이터 부족)')}")
    if ranges:
        sweep = ", ".join(
            f"A₀={a:.2f}→{TYPE_NAMES.get(classify_ranges(ranges, a) or '', '-')}"
            for a in (0.5, 0.75, 1.0, 1.25, 1.5)
        )
        out(f"- baselineRange 민감도: {sweep}")
    if summary is not None:
        out("")
        compare_summary(lines, summary, cycles)
    else:
        out("- (rhythmSummary 블록 없음 — 구 버전 내보내기 파일. 재현값만 표시)")
    out("")

    # 5. 사분면 커버리지
    out("## 5. 사분면 커버리지 (완료 주기별 — CoverageReminder 변환 기준)")
    coverage_rows: list[str] = []
    for cycle in cycles:
        quad_counts = [0] * QUADRANTS
        rows = 0
        for entry in check_ins:
            offset = (entry.day - cycle.start).days
            if not 0 <= offset < cycle.length:
                continue
            if emotional(entry.mood, entry.irritability) is None:
                continue
            rows += 1
            quad = min(QUADRANTS - 1, offset * QUADRANTS // cycle.length)
            quad_counts[quad] += 1
        if rows:
            coverage_rows.append(f"- {cycle.start} ({cycle.length}일): 사분면 {quad_counts}"
                                 f"{'  ⚠ 빈 사분면' if 0 in quad_counts else ''}")
    if coverage_rows:
        lines.extend(coverage_rows)
    else:
        out("- 완료 주기 안 체크인 없음")
    out("")

    total = len(check_ins)
    valid_rows = sum(1 for c in check_ins if 1 <= c.energy <= 5 and 1 <= c.mood <= 5)
    backfilled = sum(1 for c in check_ins if c.is_backfilled)
    out("## 6. 체크인 원자료")
    out(f"- 총 {total}건 · 집계 유효(energy·mood) {valid_rows}건 · 소급 {backfilled}건"
        f" (소급은 엔진 판정에서 제외 — §5.12 ②)")
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

    period_days, check_ins, summary = load_export(args.export_path)
    report = build_report(period_days, check_ins, summary)
    if args.out is not None:
        args.out.write_text(report, encoding="utf-8")
        print(f"OK: -> {args.out}")
    else:
        print(report)


if __name__ == "__main__":
    main()
