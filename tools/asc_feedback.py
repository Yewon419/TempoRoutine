"""App Store Connect 베타 피드백(스크린샷 제출) 조회.

사용법 (PowerShell):
    $env:TEMPO_ASC_KEYS = "<AuthKey_*.p8 / ISSUER_ID.txt / KEY_ID_ADMIN.txt 가 있는 폴더>"
    $env:PYTHONIOENCODING = "utf-8"
    python tools/asc_feedback.py --out feedback.txt

키 폴더 경로는 환경변수로만 받는다 — 이 리포는 public이라 로컬 경로를 박지 않는다.
출력은 --out 으로 받은 경로에만 쓴다(리포 안에 쓰면 .gitignore 확인할 것).

실측 함정 (401 원인 순서대로):
- exp - iat 가 20분을 넘으면 거부된다. iat를 60초 백데이트했다면 exp는 그만큼 당겨야 한다
  (iat=now-60 + exp=now+20분 = 간격 21분 → 401). 여기선 15분으로 잡는다.
- iat 백데이트가 없으면 로컬 시계가 애플 서버보다 앞설 때 401.
- KEY_ID 파일에 설명이 붙어 있을 수 있다("G3BLG7SZ27 (admin, ...)") — 첫 토큰만 키 ID.
- 콘솔이 cp949라 한글이 깨진다 — 파일로 뽑아 읽는다.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
from pathlib import Path

import jwt
import requests

BUNDLE_ID = "app.temporoutine.TempoRoutine"
BASE = "https://api.appstoreconnect.apple.com/v1"


def keys_dir() -> Path:
    raw = os.environ.get("TEMPO_ASC_KEYS")
    if not raw:
        raise RuntimeError("환경변수 TEMPO_ASC_KEYS 가 없다 — 키 폴더 경로를 지정할 것")
    path = Path(raw)
    if not path.is_dir():
        raise RuntimeError(f"키 폴더가 없다: {path}")
    return path


def make_token(keys: Path) -> str:
    key_id = keys.joinpath("KEY_ID_ADMIN.txt").read_text(encoding="utf-8").split()[0]
    issuer_id = keys.joinpath("ISSUER_ID.txt").read_text(encoding="utf-8").strip()
    private_key = keys.joinpath(f"AuthKey_{key_id}.p8").read_text(encoding="utf-8")
    now = int(dt.datetime.now(dt.timezone.utc).timestamp())
    payload = {
        "iss": issuer_id,
        "iat": now - 60,
        "exp": now + 15 * 60,   # iat 기준 16분 — 20분 상한을 넘기면 401
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def get(url: str, token: str, params: dict[str, str] | None = None) -> dict[str, object]:
    res = requests.get(url, headers={"Authorization": f"Bearer {token}"},
                       params=params, timeout=30)
    if res.status_code != 200:
        raise RuntimeError(f"GET {url} -> {res.status_code}\n{res.text[:800]}")
    parsed: dict[str, object] = res.json()
    return parsed


def main() -> int:
    parser = argparse.ArgumentParser(description="ASC 베타 피드백 조회")
    parser.add_argument("--out", required=True, help="결과를 쓸 텍스트 파일 경로")
    parser.add_argument("--limit", default="50", help="가져올 최대 건수 (기본 50)")
    args = parser.parse_args()

    token = make_token(keys_dir())
    apps = get(f"{BASE}/apps", token, {"filter[bundleId]": BUNDLE_ID})
    data = apps.get("data")
    if not isinstance(data, list) or not data:
        raise RuntimeError(f"앱을 못 찾음: {BUNDLE_ID}")
    app_id = str(data[0]["id"])
    name = str(data[0]["attributes"]["name"])

    feedback = get(f"{BASE}/apps/{app_id}/betaFeedbackScreenshotSubmissions", token,
                   {"limit": args.limit, "sort": "-createdDate"})
    items = feedback.get("data")
    rows: list[dict[str, object]] = items if isinstance(items, list) else []

    lines: list[str] = [f"# {name} — 스크린샷 피드백 {len(rows)}건", ""]
    for row in rows:
        attrs = row.get("attributes", {})
        if not isinstance(attrs, dict):
            continue
        lines.append(f"## {attrs.get('createdDate')} | {attrs.get('deviceModel')} "
                     f"| {attrs.get('osVersion')}")
        comment = attrs.get("comment")
        lines.append(f"코멘트: {comment if comment else '(없음)'}")
        shots = attrs.get("screenshots") or []
        if isinstance(shots, list) and shots:
            lines.append(f"스크린샷 {len(shots)}장:")
            for shot in shots:
                if isinstance(shot, dict):
                    lines.append(f"  {shot.get('url')}")
        lines.append("")

    out = Path(args.out)
    out.write_text("\n".join(lines), encoding="utf-8")
    print(f"OK: {len(rows)} rows -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
