"""로컬라이제이션 감사 — 소스의 한글 리터럴 ↔ String Catalog 키 대조.

Windows에서 Xcode 추출(빌드 시 .xcstrings 자동 갱신)을 돌릴 수 없어, 카탈로그를 손으로
쓴다. 그러면 「소스에는 있는데 카탈로그에 없는 문자열」이 조용히 한국어로 남는다 —
컴파일도 통과하고 CI도 그린이라 실기기 전까지 안 드러난다. 이 스크립트가 그 구멍을 센다.

사용법 (PowerShell, 리포 루트에서):
    python tools/loc_audit.py                 # 요약만
    python tools/loc_audit.py --report loc.md # 파일별 미커버 목록까지

판정 규칙
- 한글이 든 문자열 리터럴만 본다(식별자·키·심볼 이름은 ASCII라 자연히 빠진다).
- 주석(//, /* */)은 상태 기계로 걷어낸다 — 주석 안 한글이 전체의 절반이라 안 걷으면 무의미.
- 보간(`\\(...)`)이 든 리터럴은 **따로 센다**: SwiftUI가 런타임에 만드는 키는 보간을
  포맷 지정자로 바꾼 문자열(Int → %lld, String → %@)이라 소스 문자열과 다르다.
  타입을 소스에서 단정할 수 없으므로 자동 판정하지 않고 「손으로 확인할 목록」으로 낸다.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

HANGUL_START = "가"
HANGUL_END = "힣"

# 로컬라이즈 대상이 아닌 리터럴 — 화면에 안 나가는 값.
# 의학 단계명 4종: MASTER 개정 M-1c로 렌더 사용처 0(사용자 표면 금지). 데이터 라벨로만 남아
# 있어 번역 대상이 아니다. 새 UI에 쓰지 말 것 — 쓰게 되면 이 목록에서 빼고 번역을 넣는다.
IGNORED_LITERALS: frozenset[str] = frozenset({
    "월경기", "난포기", "배란기", "황체기",
    # 한국어 시각 파서 토큰(ScheduleTextParser) — 화면 문구가 아니라 **입력 해석**이다.
    # 「오후 3시 회의」를 읽는 사전이므로 번역하면 한국어 입력이 안 읽힌다. 영어·일본어
    # 입력 파서는 별도 기능이지 번역이 아니다(로컬라이제이션.md §5).
    "시", "분", "반", "경", "께", "간", "부터", "까지", "에", "에는",
    "오전", "오후", "새벽", "아침", "점심", "저녁", "정오", "자정",
    "([0-9]+)분",   # 제목에서 「N분」을 읽는 정규식(QuickAdd)
    # 개발자 진단 로그 — 사용자 표면 아님
    "invalidArguments — 프로덕션 스키마 미배포 의심",
})

# Swift 리터럴 이스케이프 → 실제 문자. 카탈로그 키는 실제 문자(줄바꿈 등)라 맞춰야 대조된다.
ESCAPES: dict[str, str] = {"n": "\n", "t": "\t", "0": "\0", '"': '"', "'": "'", "\\": "\\"}


def unescape_swift(raw: str) -> str:
    """Swift 문자열 리터럴의 이스케이프를 푼다. 보간 표시(`\\(`)는 그대로 둔다."""
    out: list[str] = []
    index = 0
    while index < len(raw):
        ch = raw[index]
        if ch == "\\" and index + 1 < len(raw):
            nxt = raw[index + 1]
            if nxt == "(":            # 보간 — 감지에 쓰이므로 원형 유지
                out.append("\\(")
                index += 2
                continue
            if nxt in ESCAPES:
                out.append(ESCAPES[nxt])
                index += 2
                continue
        out.append(ch)
        index += 1
    return "".join(out)


def has_hangul(text: str) -> bool:
    return any(HANGUL_START <= ch <= HANGUL_END for ch in text)


@dataclass(frozen=True)
class Literal:
    """소스에서 뽑은 문자열 리터럴 하나."""

    path: Path
    line: int
    text: str

    @property
    def interpolated(self) -> bool:
        return "\\(" in self.text


@dataclass
class Catalog:
    """String Catalog(.xcstrings) 한 장."""

    path: Path
    source_language: str
    keys: frozenset[str]
    translated: dict[str, frozenset[str]]  # 언어 → 그 언어로 번역이 채워진 키 집합


@dataclass
class AuditResult:
    literals: list[Literal] = field(default_factory=list)
    catalogs: list[Catalog] = field(default_factory=list)

    @property
    def catalog_keys(self) -> frozenset[str]:
        merged: set[str] = set()
        for catalog in self.catalogs:
            merged |= catalog.keys
        return frozenset(merged)


def strip_swift_noise(source: str) -> list[tuple[int, str]]:
    """주석을 지우고 (줄번호, 문자열 리터럴) 목록을 낸다.

    상태 기계로 읽는다 — 정규식은 문자열 안 `//`(URL)과 주석 안 따옴표에서 반드시 틀린다.
    다중 행 리터럴(\"\"\")은 화면 카피에 안 쓰이므로 리터럴 진입만 막고 내용은 버린다.
    """
    literals: list[tuple[int, str]] = []
    line = 1
    index = 0
    length = len(source)
    while index < length:
        ch = source[index]
        nxt = source[index + 1] if index + 1 < length else ""
        if ch == "\n":
            line += 1
            index += 1
        elif ch == "/" and nxt == "/":
            while index < length and source[index] != "\n":
                index += 1
        elif ch == "/" and nxt == "*":
            index += 2
            while index < length - 1 and not (source[index] == "*" and source[index + 1] == "/"):
                if source[index] == "\n":
                    line += 1
                index += 1
            index += 2
        elif ch == '"' and source[index : index + 3] == '"""':
            index += 3
            while index < length - 2 and source[index : index + 3] != '"""':
                if source[index] == "\n":
                    line += 1
                index += 1
            index += 3
        elif ch == '"':
            start_line = line
            index += 1
            buffer: list[str] = []
            while index < length and source[index] != '"':
                # 보간 `\(...)` — 안에 또 문자열이 들어갈 수 있다("a\(b ? "c" : "d")e").
                # 괄호 균형을 세며 통째로 건너뛰지 않으면 안쪽 따옴표에서 리터럴이 잘린다.
                if source[index] == "\\" and source[index : index + 2] == "\\(":
                    interp_start = index      # 보간 원문을 그대로 보존한다(변환기가 식을 쓴다)
                    index += 2
                    depth = 1
                    while index < length and depth > 0:
                        cur = source[index]
                        if cur == "(":
                            depth += 1
                        elif cur == ")":
                            depth -= 1
                            if depth == 0:
                                break
                        elif cur == '"':          # 보간 안 문자열은 통째로 건너뛴다
                            index += 1
                            while index < length and source[index] != '"':
                                index += 2 if source[index] == "\\" else 1
                        elif cur == "\n":
                            line += 1
                        index += 1
                    index += 1
                    buffer.append(source[interp_start:index])
                    continue
                if source[index] == "\\" and index + 1 < length:
                    buffer.append(source[index])
                    buffer.append(source[index + 1])
                    index += 2
                    continue
                if source[index] == "\n":
                    line += 1
                buffer.append(source[index])
                index += 1
            index += 1
            literals.append((start_line, "".join(buffer)))
        else:
            index += 1
    return literals


def collect_literals(roots: list[Path]) -> list[Literal]:
    found: list[Literal] = []
    for root in roots:
        for path in sorted(root.rglob("*.swift")):
            source = path.read_text(encoding="utf-8")
            for line, raw in strip_swift_noise(source):
                text = unescape_swift(raw)
                if not has_hangul(text) or text in IGNORED_LITERALS:
                    continue
                found.append(Literal(path=path, line=line, text=text))
    return found


def load_catalog(path: Path) -> Catalog:
    raw: object = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise RuntimeError(f"카탈로그 최상위가 객체가 아니다: {path}")
    source_language = raw.get("sourceLanguage")
    strings = raw.get("strings")
    if not isinstance(source_language, str) or not isinstance(strings, dict):
        raise RuntimeError(f"카탈로그 스키마 위반(sourceLanguage/strings): {path}")
    translated: dict[str, set[str]] = {}
    for key, entry in strings.items():
        if not isinstance(key, str) or not isinstance(entry, dict):
            raise RuntimeError(f"카탈로그 항목 스키마 위반: {path} → {key!r}")
        localizations = entry.get("localizations")
        if not isinstance(localizations, dict):
            continue
        for language, unit in localizations.items():
            if not isinstance(language, str) or not isinstance(unit, dict):
                raise RuntimeError(f"localizations 스키마 위반: {path} → {key!r}")
            translated.setdefault(language, set()).add(key)
    return Catalog(
        path=path,
        source_language=source_language,
        keys=frozenset(k for k in strings if isinstance(k, str)),
        translated={lang: frozenset(keys) for lang, keys in translated.items()},
    )


def audit(repo: Path, languages: list[str]) -> tuple[AuditResult, list[Literal], dict[str, list[str]]]:
    roots = [repo / "App", repo / "Widgets", repo / "Shared", repo / "TempoCore" / "Sources"]
    result = AuditResult(
        literals=collect_literals([r for r in roots if r.is_dir()]),
        catalogs=[load_catalog(p) for p in sorted(repo.rglob("*.xcstrings"))],
    )
    keys = result.catalog_keys
    uncovered = [lit for lit in result.literals if lit.text not in keys]
    missing: dict[str, list[str]] = {}
    for language in languages:
        done: set[str] = set()
        for catalog in result.catalogs:
            done |= set(catalog.translated.get(language, frozenset()))
        missing[language] = sorted(keys - done)
    return result, uncovered, missing


def main() -> int:
    parser = argparse.ArgumentParser(description="로컬라이제이션 커버리지 감사")
    parser.add_argument("--repo", default=".", help="리포 루트 (기본: 현재 폴더)")
    parser.add_argument("--report", help="파일별 미커버 목록을 쓸 마크다운 경로")
    parser.add_argument("--languages", default="en,ja", help="검사할 번역 언어(쉼표 구분)")
    args = parser.parse_args()

    repo = Path(args.repo).resolve()
    languages = [lang.strip() for lang in args.languages.split(",") if lang.strip()]
    result, uncovered, missing = audit(repo, languages)

    plain = [lit for lit in uncovered if not lit.interpolated]
    interpolated = [lit for lit in uncovered if lit.interpolated]
    total = len(result.literals)
    covered = total - len(uncovered)

    print(f"카탈로그 {len(result.catalogs)}장 · 키 {len(result.catalog_keys)}개")
    print(f"소스 한글 리터럴 {total}개 → 커버 {covered} / 미커버 {len(uncovered)}"
          f" (보간 없음 {len(plain)} · 보간 {len(interpolated)})")
    for language in languages:
        print(f"  {language}: 번역 빠진 키 {len(missing[language])}개")

    by_file: dict[Path, list[Literal]] = {}
    for lit in uncovered:
        by_file.setdefault(lit.path, []).append(lit)
    print("\n미커버 상위 파일")
    for path, lits in sorted(by_file.items(), key=lambda kv: -len(kv[1]))[:15]:
        print(f"  {len(lits):4d}  {path.relative_to(repo).as_posix()}")

    if args.report:
        lines = ["# 로컬라이제이션 미커버 목록", ""]
        for path, lits in sorted(by_file.items(), key=lambda kv: -len(kv[1])):
            lines.append(f"## {path.relative_to(repo).as_posix()} ({len(lits)})")
            lines.extend(
                f"- L{lit.line}{' [보간]' if lit.interpolated else ''} `{lit.text}`" for lit in lits
            )
            lines.append("")
        Path(args.report).write_text("\n".join(lines), encoding="utf-8")
        print(f"\n보고서: {args.report}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
