"""App Review용 샘플 백업 생성기 — 심사자가 「재현할 수 없는 화면」을 열 수 있게 한다.

왜 필요한가: 이 앱의 핵심 화면(나의 템포의 계절 패턴·예측 정확도·신호 서술)은 **여러 주기의
기록이 쌓여야** 보인다. 새로 설치한 심사자에게는 전부 「아직 또렷하지 않아요」로만 보이고,
씨앗은 하루 1개씩만 모여(당일·다음날 작성분만 인정) 테마 구매도 재현할 수 없다.
그 상태로 제출하면 심사가 「기능을 확인할 수 없다」로 막힌다(제주나우 1.0이 그 사유로 REJECTED).

대응: 설정 > 백업 가져오기로 한 번에 채울 수 있는 **합성 백업**을 만들어 심사 메모에 링크한다.
봉투(ExportEnvelopeV1)에 씨앗 원장(earnedDays)까지 들어가므로 테마 구매까지 시연 가능하다.

⚠ 대표님 실제 기록을 심사자에게 보내지 않는다 — 생리 기록이 든 파일이다. 이 스크립트가 만드는
값은 전부 합성이다.

사용법 (리포 루트에서):
    python tools/make_review_sample.py --out review-sample-backup.json
    python tools/make_review_sample.py --out ... --end 2026-08-21   # 기준일 고정(재현성)

스키마 출처 = `TempoCore/Sources/TempoCore/ExportSchema.swift`(schemaVersion 1).
날짜 규칙: day 계열은 "yyyy-MM-dd", instant 계열은 ISO8601(디코더가 .iso8601).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import random
import sys
import uuid
from pathlib import Path

SCHEMA_VERSION = 1
CYCLE_LENGTH = 29
CYCLES = 4                     # 4주기 ≈ 116일 — 「기록된 N주기」·예측 정확도가 켜지는 표본
PERIOD_DAYS_PER_CYCLE = 5
SEED_THEME_PRICE = 7           # 테마 구매 시연용 최소 씨앗


def iso(moment: dt.datetime) -> str:
    """ISO8601 — 디코더가 `.iso8601`이라 소수점 없는 Z 표기로 맞춘다."""
    return moment.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def day_str(date: dt.date) -> str:
    return date.strftime("%Y-%m-%d")


def new_id(rng: random.Random) -> str:
    return str(uuid.UUID(int=rng.getrandbits(128), version=4)).upper()


KST = dt.timezone(dt.timedelta(hours=9))


def at(date: dt.date, hour: int, minute: int = 0) -> dt.datetime:
    """벽시계 시각은 KST로 적는다 — 봉투에는 `iso()`가 UTC로 바꿔 넣는다.
    시각이 든 항목(반복 일정)은 여는 기기의 시간대만큼 밀려 보인다. 한국 사용자·대표님
    실기기에서 자연스러운 쪽을 기준으로 잡았다(심사자 기기에선 그만큼 이동하지만, 날짜 키로
    도는 기록·루틴·완료는 영향을 받지 않고 하루 안 순서도 그대로다)."""
    return dt.datetime.combine(date, dt.time(hour, minute), tzinfo=KST)


# ── 플래너 표면 ──
# 심사가 언제 열리든 「오늘」이 채워져 있어야 한다. 그래서 단발 항목에 기대지 않는다:
# 일정은 daily·weekly 반복, 루틴은 daily, 목표는 `.once`(완료까지 계속 표시)로 깔아 둔다.
# 날짜가 박힌 항목(종일 여러 날 띠·디데이)은 캘린더 문법 시연용으로만 소수 둔다.

def build_schedule(end: dt.date, start: dt.date, rng: random.Random) -> list[dict[str, object]]:
    items: list[dict[str, object]] = []

    def repeating(title: str, hour: int, minute: int, rule: str,
                  reminder: int | None) -> dict[str, object]:
        # 반복 일정의 date는 「첫 회차」 — 이후 회차는 앱이 rule로 펼친다.
        return {
            "id": new_id(rng),
            "title": title,
            "date": iso(at(start, hour, minute)),
            "isAllDay": False,
            "repeatRule": rule,
            "createdAt": iso(at(start, 9)),
            "endDate": iso(at(start, hour + 1, minute)),
            "reminderMinutes": reminder,
            "endDay": None,
        }

    items.append(repeating("아침 스트레칭", 7, 30, "daily", 10))
    items.append(repeating("팀 회의", 10, 0, "weekly", 15))
    items.append(repeating("요가 수업", 19, 30, "weekly", 30))

    # 여러 날 종일 일정 — 캘린더의 기간 띠를 보여준다(종일은 endDay가 정본, endDate는 병기).
    trip_start = end + dt.timedelta(days=5)
    trip_end = end + dt.timedelta(days=7)
    items.append({
        "id": new_id(rng),
        "title": "짧은 여행",
        "date": day_str(trip_start),
        "isAllDay": True,
        "repeatRule": "none",
        "createdAt": iso(at(start, 9)),
        "endDate": iso(at(trip_end, 23, 59)),
        "reminderMinutes": None,
        "endDay": day_str(trip_end),
    })
    return items


def build_inputs(start: dt.date, rng: random.Random) -> list[dict[str, object]]:
    """매일의 루틴 — timeMinutes는 자정 기준 분(하루 안 시간순 정렬에 쓰인다)."""
    rows = [
        ("물 여덟 잔", "other", "daily", None),
        ("아침 산책", "exercise", "daily", 8 * 60),
        ("영양제", "other", "daily", 9 * 60),
        ("저녁 스트레칭", "exercise", "daily", 21 * 60),
        ("드라마 한 편", "media", "weekly", 22 * 60),
    ]
    return [{
        "id": new_id(rng),
        "title": title,
        "category": category,
        "schedule": {"type": rule},
        "createdAt": iso(at(start, 9)),
        "backfilled": False,
        "timeMinutes": minutes,
        "progressKind": None,
        "targetSessions": None,
        "targetSeconds": None,
        "subtasks": None,
    } for title, category, rule, minutes in rows]


def build_outputs(end: dt.date, start: dt.date, rng: random.Random) -> list[dict[str, object]]:
    """해내고 싶은 일 — 진행도 4종(퍼센트·체크리스트·횟수·타이머)을 한 눈에 보여준다."""

    def base(title: str, kind: str, schedule: str = "once") -> dict[str, object]:
        return {
            "id": new_id(rng),
            "title": title,
            "schedule": {"type": schedule},
            "progressKind": kind,
            "subtasks": [],
            "targetSessions": 0,
            "loggedSessions": 0,
            "percent": 0.0,
            "createdAt": iso(at(start, 9)),
            "targetDate": None,
            "targetSeconds": None,
            "elapsedSeconds": None,
            "timeMinutes": None,
        }

    book = base("책 한 권 읽기", "percent")
    book["percent"] = 0.45

    resume = base("이력서 고치기", "subtasks")
    resume["subtasks"] = [
        {"id": new_id(rng), "title": "경력 정리", "isDone": True, "order": 0},
        {"id": new_id(rng), "title": "포트폴리오 링크", "isDone": True, "order": 1},
        {"id": new_id(rng), "title": "맞춤법 검토", "isDone": False, "order": 2},
    ]
    # 디데이 — 캘린더·오늘 탭의 목표일 표기를 보여준다
    resume["targetDate"] = iso(at(end + dt.timedelta(days=10), 9))

    running = base("달리기 스무 번", "sessions")
    running["targetSessions"] = 20
    running["loggedSessions"] = 8

    focus = base("집중 25분", "timer", schedule="daily")
    focus["targetSeconds"] = 25 * 60
    focus["elapsedSeconds"] = 0.0

    return [book, resume, running, focus]


def build_completions(end: dt.date, inputs: list[dict[str, object]],
                      rng: random.Random) -> list[dict[str, object]]:
    """지난 3주의 루틴 체크 — 캘린더 완료 표시와 오늘 탭의 「해오던 흐름」을 만든다."""
    rows: list[dict[str, object]] = []
    daily = [item for item in inputs if item["schedule"] == {"type": "daily"}]
    for back in range(21):
        date = end - dt.timedelta(days=back)
        for item in daily:
            if rng.random() < 0.25:       # 빠진 날이 있어야 실제 기록처럼 보인다
                continue
            rows.append({
                "id": new_id(rng),
                "itemID": item["id"],
                "occurredOn": day_str(date),
                "completedAt": iso(at(date, 22)),
            })
    return rows


def build(end: dt.date, rng: random.Random) -> dict[str, object]:
    start = end - dt.timedelta(days=CYCLE_LENGTH * CYCLES)

    period_days: list[dict[str, object]] = []
    for cycle in range(CYCLES):
        first = start + dt.timedelta(days=CYCLE_LENGTH * cycle)
        for offset in range(PERIOD_DAYS_PER_CYCLE):
            period_days.append({
                "day": day_str(first + dt.timedelta(days=offset)),
                # PeriodDayOrigin.local = 이 앱에서 직접 기록(App/PeriodModels.swift 실측)
                "origin": "local",
                "healthKitUUID": None,
            })

    # 체크인 — 계절에 따라 값이 오르내리게 만든다(패턴이 「보이는」 표본이어야 의미가 있다).
    check_ins: list[dict[str, object]] = []
    earned_days: list[str] = []
    for offset in range((end - start).days + 1):
        date = start + dt.timedelta(days=offset)
        if rng.random() < 0.15:          # 빠진 날이 있어야 실제 기록처럼 보인다
            continue
        phase_day = offset % CYCLE_LENGTH
        if phase_day < 5:                 # 겨울(월경)
            energy, mood, sleep = 2, 2, 3
        elif phase_day < 13:              # 봄
            energy, mood, sleep = 4, 4, 4
        elif phase_day < 18:              # 여름
            energy, mood, sleep = 5, 5, 4
        else:                             # 가을
            energy, mood, sleep = 3, 3, 3
        jitter = rng.choice([-1, 0, 0, 1])
        stamped = dt.datetime.combine(date, dt.time(21, 30), tzinfo=dt.timezone.utc)
        check_ins.append({
            "id": str(uuid.UUID(int=rng.getrandbits(128), version=4)).upper(),
            "day": day_str(date),
            "energy": max(1, min(5, energy + jitter)),
            "mood": max(1, min(5, mood + jitter)),
            "sleep": max(1, min(5, sleep + jitter)),
            "pain": max(1, min(5, 4 - energy)),
            "appetite": max(1, min(5, energy)),
            "irritability": max(1, min(5, 6 - mood)),
            "note": None,
            "isBackfilled": False,
            "createdAt": iso(stamped),
            # 씨앗 획득 근거 — 당일 작성으로 찍는다(당일·다음날만 인정)
            "completedAt": iso(stamped),
        })
        earned_days.append(day_str(date))

    schedule_items = build_schedule(end, start, rng)
    input_items = build_inputs(start, rng)
    output_items = build_outputs(end, start, rng)
    completions = build_completions(end, input_items, rng)

    envelope: dict[str, object] = {
        "schemaVersion": SCHEMA_VERSION,
        "exportedAt": iso(dt.datetime.combine(end, dt.time(9, 0), tzinfo=dt.timezone.utc)),
        "periodDays": period_days,
        "scheduleItems": schedule_items,
        "inputItems": input_items,
        "outputItems": output_items,
        "completions": completions,
        "checkIns": check_ins,
        "trackedSignals": {"sleep": True, "pain": True, "appetite": True,
                           "note": True, "irritability": True},
        # 씨앗: 획득 원장만 넣는다(구매 0) — 심사자가 테마 구매를 **직접** 눌러 볼 수 있게.
        "seedLedger": {"purchases": {}, "claims": {}, "legacyBonus": 0,
                       "earnedDays": sorted(set(earned_days))},
        "inputProgress": [],
        "selfReports": [],
    }
    return envelope


def main() -> int:
    parser = argparse.ArgumentParser(description="심사자용 샘플 백업 생성")
    parser.add_argument("--out", required=True, help="쓸 JSON 경로")
    parser.add_argument("--end", help="마지막 기록일 yyyy-MM-dd (기본: 오늘)")
    parser.add_argument("--seed", type=int, default=20260821, help="난수 시드(재현성)")
    args = parser.parse_args()

    end = (dt.datetime.strptime(args.end, "%Y-%m-%d").date() if args.end
           else dt.date.today())
    envelope = build(end, random.Random(args.seed))
    Path(args.out).write_text(json.dumps(envelope, ensure_ascii=False, indent=2),
                              encoding="utf-8")

    check_ins = envelope["checkIns"]
    period_days = envelope["periodDays"]
    ledger = envelope["seedLedger"]
    assert isinstance(check_ins, list) and isinstance(period_days, list)
    assert isinstance(ledger, dict)
    earned = ledger.get("earnedDays")
    assert isinstance(earned, list)
    schedule_items = envelope["scheduleItems"]
    input_items = envelope["inputItems"]
    output_items = envelope["outputItems"]
    completions = envelope["completions"]
    assert isinstance(schedule_items, list) and isinstance(input_items, list)
    assert isinstance(output_items, list) and isinstance(completions, list)
    print(f"기록 범위: {end - dt.timedelta(days=CYCLE_LENGTH * CYCLES)} ~ {end}")
    print(f"생리 기록 {len(period_days)}일 · 체크인 {len(check_ins)}건 · 씨앗 {len(earned)}개")
    print(f"일정 {len(schedule_items)}건 · 루틴 {len(input_items)}건 · "
          f"해내고 싶은 일 {len(output_items)}건 · 루틴 체크 {len(completions)}건")
    print(f"→ {args.out}")
    if len(earned) < SEED_THEME_PRICE:
        print("⚠ 씨앗이 테마 가격보다 적다 — 구매 시연이 안 된다", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
