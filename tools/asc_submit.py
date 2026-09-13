"""App Store 업데이트 제출 — 버전 레코드에 빌드를 붙이고 심사 제출(재제출 포함).

실행(PowerShell):
    $env:TEMPO_ASC_KEYS = "<AuthKey_*.p8 / ISSUER_ID.txt / KEY_ID_ADMIN.txt 가 있는 폴더>"
    $env:PYTHONIOENCODING = "utf-8"
    python tools/asc_submit.py --version 1.0.1 --build 709            # 붙이고 제출
    python tools/asc_submit.py --version 1.0.1 --build 709 --dry-run  # 상태만 보고 아무것도 안 바꿈

흐름: 버전 문자열로 appStoreVersion을 찾고 → 빌드 번호로 builds를 찾아(VALID만) 연결 →
진행 중(UNRESOLVED_ISSUES 등) 제출이 있으면 재제출을 시도하고, 거부되면 취소 후 새 제출을 만든다.
판정은 마지막에 찍는 reviewSubmissions.state / appVersionState로만(콘솔 표기는 근거 아님).
⚠ 리젝 사유(Resolution Center)는 API에 없다 — REJECTED를 보면 콘솔 스레드를 먼저 읽을 것.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))
from asc_feedback import BASE, BUNDLE_ID, get, keys_dir, make_token  # noqa: E402


def call(method: str, url: str, token: str, body: dict[str, object]) -> requests.Response:
    res = requests.request(method, url, headers={"Authorization": f"Bearer {token}",
                                                 "Content-Type": "application/json"},
                           json=body, timeout=30)
    print(f"{method} {url.replace(BASE, '')} -> {res.status_code}")
    if res.status_code >= 300:
        print(res.text[:800])
    return res


def main() -> int:
    parser = argparse.ArgumentParser(description="ASC 버전에 빌드 연결 + 심사 제출")
    parser.add_argument("--version", required=True, help="appStoreVersion 문자열, 예: 1.0.1")
    parser.add_argument("--build", required=True, help="빌드 번호(CURRENT_PROJECT_VERSION), 예: 709")
    parser.add_argument("--dry-run", action="store_true", help="조회만 하고 변경하지 않는다")
    args = parser.parse_args()

    token = make_token(keys_dir())
    apps = get(f"{BASE}/apps", token, {"filter[bundleId]": BUNDLE_ID})["data"]
    if not isinstance(apps, list) or not apps:
        raise RuntimeError(f"앱을 못 찾음: {BUNDLE_ID}")
    app_id = str(apps[0]["id"])

    versions = get(f"{BASE}/apps/{app_id}/appStoreVersions", token,
                   {"filter[platform]": "IOS", "filter[versionString]": args.version,
                    "fields[appStoreVersions]": "versionString,appVersionState"})["data"]
    if not isinstance(versions, list) or not versions:
        raise RuntimeError(f"버전 레코드가 없다: {args.version} — 콘솔에서 먼저 만들 것")
    version_id = str(versions[0]["id"])
    print("version", args.version, version_id, versions[0]["attributes"]["appVersionState"])

    builds = get(f"{BASE}/builds", token,
                 {"filter[app]": app_id, "filter[version]": args.build,
                  "filter[processingState]": "VALID", "fields[builds]": "version,processingState"})["data"]
    if not isinstance(builds, list) or not builds:
        raise RuntimeError(f"VALID 빌드가 없다: {args.build}")
    build_id = str(builds[0]["id"])
    print("build", args.build, build_id)

    subs = get(f"{BASE}/apps/{app_id}/reviewSubmissions", token,
               {"filter[platform]": "IOS", "limit": "5",
                "fields[reviewSubmissions]": "state,submittedDate"})["data"]
    open_ids = [str(s["id"]) for s in subs
                if s["attributes"]["state"] in ("READY_FOR_REVIEW", "WAITING_FOR_REVIEW",
                                                "IN_REVIEW", "UNRESOLVED_ISSUES")]
    print("open submissions:", open_ids or "none")
    if args.dry_run:
        print("dry-run — 변경 없음")
        return 0

    call("PATCH", f"{BASE}/appStoreVersions/{version_id}/relationships/build", token,
         {"data": {"type": "builds", "id": build_id}})

    submitted = False
    for sid in open_ids:
        res = call("PATCH", f"{BASE}/reviewSubmissions/{sid}", token,
                   {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
        if res.status_code < 300:
            submitted = True
            break
        call("PATCH", f"{BASE}/reviewSubmissions/{sid}", token,
             {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"canceled": True}}})
    if not submitted:
        res = call("POST", f"{BASE}/reviewSubmissions", token,
                   {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"},
                             "relationships": {"app": {"data": {"type": "apps", "id": app_id}}}}})
        res.raise_for_status()
        new_id = str(res.json()["data"]["id"])
        call("POST", f"{BASE}/reviewSubmissionItems", token,
             {"data": {"type": "reviewSubmissionItems",
                       "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": new_id}},
                                         "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}}}})
        call("PATCH", f"{BASE}/reviewSubmissions/{new_id}", token,
             {"data": {"type": "reviewSubmissions", "id": new_id, "attributes": {"submitted": True}}})

    final = get(f"{BASE}/apps/{app_id}/reviewSubmissions", token,
                {"filter[platform]": "IOS", "limit": "3", "fields[reviewSubmissions]": "state,submittedDate"})["data"]
    for s in final:
        print("submission", s["id"], s["attributes"]["state"], (s["attributes"].get("submittedDate") or "")[:16])
    state = get(f"{BASE}/appStoreVersions/{version_id}", token,
                {"fields[appStoreVersions]": "versionString,appVersionState"})["data"]["attributes"]
    print("version final:", state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
