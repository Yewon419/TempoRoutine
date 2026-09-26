"""씨앗 쿠폰 등록 — notices/notices.json의 `coupons`에 한 줄 추가한다.

리포가 public이라 코드 원문은 싣지 않고, 앱과 같은 정규화(소문자·공백 제거)를 거친
SHA-256 hex만 싣는다(App/Coupons.swift). 반영 = 커밋·push(앱 배포 불필요).

    python tools/make_coupon.py <코드> <씨앗 개수> [--id <쿠폰 id>]

id는 원장 키(`coupon:<id>`)라 한 번 쓴 id는 재사용하지 않는다 — 같은 id면 이미 받은 사람은
다시 못 받는다. 쿠폰을 끄려면 해당 항목을 지운다.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import date
from pathlib import Path

NOTICES = Path(__file__).resolve().parent.parent / "notices" / "notices.json"


def normalize(code: str) -> str:
    return code.strip().lower().replace(" ", "")


def digest(code: str) -> str:
    return hashlib.sha256(normalize(code).encode("utf-8")).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description="씨앗 쿠폰 등록")
    parser.add_argument("code")
    parser.add_argument("seeds", type=int)
    parser.add_argument("--id", dest="coupon_id", default=None)
    args = parser.parse_args()

    code: str = args.code
    seeds: int = args.seeds
    if seeds <= 0:
        raise SystemExit("씨앗 개수는 1 이상이어야 한다")
    if normalize(code).startswith("//"):
        raise SystemExit("'//'로 시작하는 코드는 앱이 커맨드 오타로 보고 버린다")

    envelope = json.loads(NOTICES.read_text(encoding="utf-8"))
    coupons: list[dict[str, str | int]] = envelope.setdefault("coupons", [])
    hashed = digest(code)
    coupon_id: str = args.coupon_id or f"{date.today().isoformat()}-{hashed[:6]}"
    for existing in coupons:
        if existing["id"] == coupon_id:
            raise SystemExit(f"이미 있는 id: {coupon_id}")
        if existing["hash"] == hashed:
            raise SystemExit(f"같은 코드가 이미 등록됨: id={existing['id']}")

    coupons.append({"id": coupon_id, "hash": hashed, "seeds": seeds})
    NOTICES.write_text(
        json.dumps(envelope, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"등록: id={coupon_id} seeds={seeds} hash={hashed}")


if __name__ == "__main__":
    main()
