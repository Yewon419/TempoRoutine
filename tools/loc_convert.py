"""보간 리터럴 → `Loc.fmt` 명시 포맷 변환기 (로컬라이제이션 이관 보조).

왜 필요한가: SwiftUI 보간 리터럴의 **런타임 키**는 보간부가 포맷 지정자로 바뀐 문자열이라
소스만 보고 단정할 수 없다(Int → %lld, String → %@). Windows라 Xcode 추출을 못 돌리므로,
포맷을 소스에 직접 적어 키를 확정한다.

방식: 모든 인자를 **문자열로** 넘기고 지정자는 `%1$@`·`%2$@` 위치형으로만 쓴다.
- 타입 오추론이 원천 차단된다(%lld에 String을 넘기면 쓰레기 값이 나온다).
- 번역에서 어순이 바뀌어도 위치형이라 안전하다.
- 숫자 표기는 종전(보간)과 동일하다 — 보간도 그냥 십진 문자열이었다.

`--apply` 없이 돌리면 무엇을 바꿀지만 보여준다(기본 = 드라이런).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from loc_audit import audit  # noqa: E402

INTERP = re.compile(r"\\\(")


@dataclass(frozen=True)
class Conversion:
    path: Path
    line: int
    original: str          # 소스에 있는 리터럴 본문(보간 표기 그대로)
    key: str               # 포맷 키(보간 → %n$@)
    args: list[str]        # 보간 안 식(순서대로)


def split_interpolations(text: str) -> tuple[str, list[str]]:
    """`"a\\(x)b"` → (`"a%1$@b"`, ["x"]). 중첩 괄호·안쪽 문자열을 균형으로 건너뛴다."""
    out: list[str] = []
    args: list[str] = []
    index = 0
    while index < len(text):
        if text.startswith("\\(", index):
            index += 2
            depth = 1
            start = index
            while index < len(text) and depth > 0:
                ch = text[index]
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth == 0:
                        break
                elif ch == '"':
                    index += 1
                    while index < len(text) and text[index] != '"':
                        index += 2 if text[index] == "\\" else 1
                index += 1
            args.append(text[start:index])
            out.append(f"%{len(args)}$@")
            index += 1
            continue
        if text[index] == "%":       # 리터럴 퍼센트는 포맷 문자열에서 %%
            out.append("%%")
            index += 1
            continue
        out.append(text[index])
        index += 1
    return "".join(out), args


def build(repo: Path) -> list[Conversion]:
    _, uncovered, _ = audit(repo, ["en", "ja"])
    conversions: list[Conversion] = []
    for lit in uncovered:
        if not INTERP.search(lit.text):
            continue
        # TempoCore는 순수 모듈 — Loc 헬퍼(Shared)가 닿지 않는다. 그 안의 문자열 합성은
        # 앱에서 조회할 키가 안 되므로 별도 설계가 필요하다(로컬라이제이션.md §5).
        if "TempoCore" in lit.path.as_posix():
            continue
        source = lit.path.read_text(encoding="utf-8")
        raw = _raw_literal(source, lit.line, lit.text)
        if raw is None:
            print(f"⚠ 원문 리터럴을 못 찾음: {lit.path}:{lit.line}", file=sys.stderr)
            continue
        key, args = split_interpolations(raw)
        conversions.append(Conversion(path=lit.path, line=lit.line, original=raw,
                                      key=key, args=args))
    return conversions


def _raw_literal(source: str, line: int, unescaped: str) -> str | None:
    """감사 결과는 이스케이프를 푼 텍스트다 — 소스에 그대로 있는 원문을 되찾는다."""
    lines = source.splitlines()
    if line - 1 >= len(lines):
        return None
    candidates = [unescaped, unescaped.replace("\n", "\\n")]
    for cand in candidates:
        if cand in lines[line - 1]:
            return cand
    window = "\n".join(lines[line - 1 : line + 2])
    for cand in candidates:
        if cand in window:
            return cand
    return None


def swift_call(conv: Conversion) -> str:
    args = ", ".join(f'"\\({a})"' for a in conv.args)
    return f'Loc.fmt("{conv.key}", {args})'


def main() -> int:
    parser = argparse.ArgumentParser(description="보간 리터럴 → Loc.fmt 변환")
    parser.add_argument("--repo", default=".")
    parser.add_argument("--apply", action="store_true", help="실제로 파일을 고친다")
    parser.add_argument("--only", help="이 경로 조각을 포함하는 파일만")
    parser.add_argument("--keys-out", help="새 포맷 키 ↔ 원문 대응을 쓸 JSON")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    conversions = [c for c in build(repo)
                   if not args.only or args.only in c.path.as_posix()]
    print(f"변환 대상 {len(conversions)}곳")

    mapping: dict[str, str] = {}
    by_path: dict[Path, list[Conversion]] = {}
    for conv in conversions:
        by_path.setdefault(conv.path, []).append(conv)
        mapping[conv.original] = conv.key

    for path, items in sorted(by_path.items()):
        source = path.read_text(encoding="utf-8")
        changed = 0
        done: set[str] = set()
        for conv in items:
            old = f'"{conv.original}"'
            if conv.original in done:
                continue                      # 같은 리터럴이 여러 번 — 첫 회차에 전부 바꿨다
            count = source.count(old)
            if count == 0:
                print(f"  ⚠ 없음: {path.name}:{conv.line} {conv.original[:40]}")
                continue
            if count > 1:
                print(f"  · 같은 리터럴 {count}곳 일괄 변환: {conv.original[:40]}")
            source = source.replace(old, swift_call(conv))
            done.add(conv.original)
            changed += count
        print(f"  {path.as_posix()}: {changed}/{len(items)}")
        if args.apply and changed:
            path.write_text(source, encoding="utf-8")

    if args.keys_out:
        Path(args.keys_out).write_text(json.dumps(mapping, ensure_ascii=False, indent=1),
                                       encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
