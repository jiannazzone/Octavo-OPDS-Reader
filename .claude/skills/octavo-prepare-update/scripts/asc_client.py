#!/usr/bin/env python3
"""
App Store Connect client for the octavo-prepare-update skill.

The repo's docs/app-store/ files say what the listing should be. This compares
them with App Store Connect and sends the differences.

  check     Apple's limits on the repo's files. No network.
  status    The app's versions, and the repo's version and build.
  fetch     What App Store Connect has now.
  diff      The fields that differ.
  publish   Prints the diff. Sends it only with --confirm, then re-fetches.

It changes only the fields in the allow-lists below. It never uploads or
attaches a build, submits, releases or creates a version, and never touches
price, age rating, privacy answers or screenshots.

The API key comes from 1Password through `op`, and never reaches a file, the
repo or the output. Only a signed token is cached, for 20 minutes at most.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

BUNDLE_ID = "com.ianazzone.ereader"
OP_VAULT = "QRV"
OP_ITEM = "QRV · Apple · App Store Connect API"

API_BASE = "https://api.appstoreconnect.apple.com/v1"
REPO = Path(__file__).resolve().parents[4]
LISTING_FILE = REPO / "docs/app-store/listing.json"
CHANGELOG_FILE = REPO / "docs/app-store/changelog.json"
VERSIONS_FILE = REPO / "Config/Versions.xcconfig"

CACHE_FILE = Path.home() / ".cache" / "octavo-asc-client" / "session.json"
JWT_LIFETIME = 1200  # Apple's maximum.
REFRESH_MARGIN = 120

EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "READY_FOR_REVIEW",
    "REJECTED",
    "METADATA_REJECTED",
    "DEVELOPER_REJECTED",
    "INVALID_BINARY",
}
LIVE_STATES = {"READY_FOR_SALE", "READY_FOR_DISTRIBUTION"}

APP_INFO_FIELDS = {"name", "subtitle", "privacyPolicyUrl"}
VERSION_LOC_FIELDS = {"description", "keywords", "promotionalText", "supportUrl", "marketingUrl", "whatsNew"}

# Field: (limit, unit). Apple counts keywords in bytes.
LIMITS = {
    "name": (30, "characters"),
    "subtitle": (30, "characters"),
    "promotionalText": (170, "characters"),
    "description": (4000, "characters"),
    "whatsNew": (4000, "characters"),
    "keywords": (100, "bytes"),
}


# ---------- The repo's files ----------


def load_listing() -> dict:
    return json.loads(LISTING_FILE.read_text())


def load_changelog() -> list[dict]:
    return json.loads(CHANGELOG_FILE.read_text()) if CHANGELOG_FILE.exists() else []


def repo_version() -> tuple[str, str]:
    text = VERSIONS_FILE.read_text()
    def value(key: str) -> str:
        match = re.search(rf"^{key} = (\S+)$", text, re.M)
        if not match:
            sys.exit(f"{VERSIONS_FILE.name} has no {key}")
        return match.group(1)
    return value("MARKETING_VERSION"), value("CURRENT_PROJECT_VERSION")


def limit_problems(fields: dict) -> list[str]:
    problems = []
    for field, value in fields.items():
        if field not in LIMITS or value is None:
            continue
        limit, unit = LIMITS[field]
        size = len(value.encode()) if unit == "bytes" else len(value)
        if size > limit:
            problems.append(f"{field}: {size} {unit}, limit {limit}")
    keywords = fields.get("keywords")
    if keywords:
        problems += [f"keywords: {word!r} is too short" for word in keywords.split(",") if len(word.strip()) <= 2]
    return problems


def wanted(version_string: str | None, has_live_version: bool) -> dict:
    """What the repo says, as {group: {field: value}}."""
    listing = load_listing()
    localization = dict(listing["version"])
    # Apple doesn't take What's New on an app's first version.
    if has_live_version:
        entry = next((e for e in load_changelog() if e["version"] == version_string), None)
        if entry is None:
            sys.exit(f"{CHANGELOG_FILE.name} has no entry for {version_string}")
        localization["whatsNew"] = entry["notes"]
    return {
        "appInfo": dict(listing["appInfo"]),
        "localization": localization,
        "version": {"copyright": listing["copyright"]},
        "review": {"notes": listing["reviewNotes"]},
    }


# ---------- The session ----------


def op_credentials() -> dict[str, str]:
    item = json.loads(subprocess.run(
        ["op", "item", "get", OP_ITEM, "--vault", OP_VAULT, "--format", "json"],
        check=True, capture_output=True, text=True,
    ).stdout)
    fields = {f.get("label"): f.get("value") for f in item.get("fields", [])}
    if not (fields.get("ASC_KEY_ID") and fields.get("ASC_ISSUER_ID")):
        sys.exit(f"1Password item {OP_ITEM!r} needs ASC_KEY_ID and ASC_ISSUER_ID")
    p8 = next((f["name"] for f in item.get("files", []) if f.get("name", "").endswith(".p8")), None)
    if not p8:
        sys.exit(f"1Password item {OP_ITEM!r} has no .p8 attached")
    key = subprocess.run(
        ["op", "read", f"op://{OP_VAULT}/{item['id']}/{p8}"],
        check=True, capture_output=True, text=True,
    ).stdout
    return {"key_id": fields["ASC_KEY_ID"], "issuer_id": fields["ASC_ISSUER_ID"], "private_key": key}


def token() -> str:
    try:
        cached = json.loads(CACHE_FILE.read_text())
        if cached["exp"] > time.time() + REFRESH_MARGIN:
            return cached["token"]
    except (FileNotFoundError, json.JSONDecodeError, KeyError, TypeError):
        pass
    import jwt

    credentials = op_credentials()
    now = int(time.time())
    exp = now + JWT_LIFETIME
    signed = jwt.encode(
        {"iss": credentials["issuer_id"], "iat": now, "exp": exp, "aud": "appstoreconnect-v1"},
        credentials["private_key"],
        algorithm="ES256",
        headers={"kid": credentials["key_id"], "typ": "JWT"},
    )
    CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(CACHE_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as file:
        json.dump({"token": signed, "exp": exp}, file)
    return signed


class ASC:
    def __init__(self):
        import requests

        self.http = requests.Session()
        self.http.headers["Authorization"] = f"Bearer {token()}"
        self.http.headers["Accept"] = "application/json"

    def _send(self, method: str, path: str, **kwargs) -> dict:
        response = self.http.request(method, f"{API_BASE}{path}", timeout=60, **kwargs)
        if response.status_code >= 400:
            sys.exit(f"{method} {path} failed: {response.status_code}\n{response.text}")
        return response.json() if response.content else {}

    def get(self, path: str, **params) -> dict:
        return self._send("GET", path, params=params)

    def patch(self, kind: str, path_kind: str, id: str, attributes: dict) -> None:
        self._send("PATCH", f"/{path_kind}/{id}", json={"data": {"id": id, "type": kind, "attributes": attributes}})

    def app_id(self) -> str:
        apps = self.get("/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
        if len(apps) != 1:
            sys.exit(f"Expected one app for {BUNDLE_ID}, found {len(apps)}")
        return apps[0]["id"]

    def versions(self, app_id: str) -> list[dict]:
        rows = self.get(f"/apps/{app_id}/appStoreVersions", **{"filter[platform]": "IOS", "limit": 20})["data"]
        return [{
            "id": row["id"],
            "versionString": row["attributes"]["versionString"],
            "state": row["attributes"].get("appVersionState") or row["attributes"].get("appStoreState"),
            "copyright": row["attributes"].get("copyright"),
        } for row in rows]


# ---------- What App Store Connect has ----------


def editable_version(versions: list[dict]) -> dict:
    editable = [v for v in versions if v["state"] in EDITABLE_STATES]
    if len(editable) != 1:
        listed = ", ".join(f"{v['versionString']} ({v['state']})" for v in versions) or "none"
        sys.exit(f"Need exactly one editable version; App Store Connect has: {listed}. "
                 "This tool never creates one: add it in App Store Connect.")
    return editable[0]


def fetch_remote(asc: ASC, app_id: str, version: dict, locale: str) -> dict:
    """App Store Connect's values and the IDs to change them, for one version."""
    infos = asc.get(f"/apps/{app_id}/appInfos", limit=5)["data"]
    def info_state(info):
        return info["attributes"].get("state") or info["attributes"].get("appStoreState")
    info = next((i for i in infos if info_state(i) not in LIVE_STATES), None)
    if info is None:
        sys.exit("No editable app info: name and subtitle can't change right now")
    info_loc = next(
        (l for l in asc.get(f"/appInfos/{info['id']}/appInfoLocalizations", limit=50)["data"]
         if l["attributes"]["locale"] == locale), None)
    version_loc = next(
        (l for l in asc.get(f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations", limit=50)["data"]
         if l["attributes"]["locale"] == locale), None)
    if not info_loc or not version_loc:
        sys.exit(f"App Store Connect has no {locale} localization")
    review = asc.get(f"/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    return {
        "ids": {
            "appInfo": info_loc["id"],
            "localization": version_loc["id"],
            "version": version["id"],
            "review": review["id"] if review else None,
        },
        "appInfo": {k: info_loc["attributes"].get(k) for k in APP_INFO_FIELDS},
        "localization": {k: version_loc["attributes"].get(k) for k in VERSION_LOC_FIELDS},
        "version": {"copyright": version["copyright"]},
        "review": {"notes": review["attributes"].get("notes") if review else None},
    }


def differences(want: dict, have: dict) -> dict:
    return {
        group: {k: v for k, v in fields.items() if (have[group].get(k) or "") != (v or "")}
        for group, fields in want.items()
    }


def print_diff(diff: dict, have: dict) -> int:
    count = 0
    for group, fields in diff.items():
        for field, value in fields.items():
            count += 1
            print(f"--- {group}.{field}\n  now: {have[group].get(field)!r}\n  new: {value!r}\n")
    print(f"{count} field(s) differ." if count else "No differences.")
    return count


# ---------- Commands ----------


def cmd_check(_) -> None:
    listing = load_listing()
    fields = {**listing["appInfo"], **listing["version"]}
    problems = limit_problems(fields)
    for entry in load_changelog():
        problems += [f"{entry['version']}: {p}" for p in limit_problems({"whatsNew": entry["notes"]})]
    version, build = repo_version()
    print(f"Repo version {version} ({build})")
    for field, (limit, unit) in LIMITS.items():
        if fields.get(field):
            size = len(fields[field].encode()) if unit == "bytes" else len(fields[field])
            print(f"  {field}: {size} of {limit} {unit}")
    if problems:
        sys.exit("Problems:\n  " + "\n  ".join(problems))
    print("OK")


def cmd_status(_) -> None:
    asc = ASC()
    app_id = asc.app_id()
    version, build = repo_version()
    print(json.dumps({
        "appId": app_id,
        "repoVersion": version,
        "repoBuild": build,
        "versions": [
            {"versionString": v["versionString"], "state": v["state"], "editable": v["state"] in EDITABLE_STATES}
            for v in asc.versions(app_id)
        ],
    }, indent=2))


def _prepare():
    asc = ASC()
    app_id = asc.app_id()
    versions = asc.versions(app_id)
    version = editable_version(versions)
    has_live = any(v["state"] in LIVE_STATES for v in versions)
    return asc, app_id, version, has_live


def cmd_fetch(_) -> None:
    asc, app_id, version, _live = _prepare()
    have = fetch_remote(asc, app_id, version, load_listing()["locale"])
    print(json.dumps({"version": version["versionString"], "state": version["state"], **{
        k: v for k, v in have.items() if k != "ids"
    }}, indent=2, ensure_ascii=False))


def cmd_diff(_) -> None:
    asc, app_id, version, has_live = _prepare()
    have = fetch_remote(asc, app_id, version, load_listing()["locale"])
    print(f"Version {version['versionString']} ({version['state']})\n")
    print_diff(differences(wanted(version["versionString"], has_live), have), have)


def cmd_publish(args) -> None:
    asc, app_id, version, has_live = _prepare()
    locale = load_listing()["locale"]
    want = wanted(version["versionString"], has_live)
    problems = limit_problems({**want["appInfo"], **want["localization"]})
    if problems:
        sys.exit("Problems:\n  " + "\n  ".join(problems))
    have = fetch_remote(asc, app_id, version, locale)
    print(f"Version {version['versionString']} ({version['state']})\n")
    diff = differences(want, have)
    if not print_diff(diff, have):
        return
    if not args.confirm:
        print("\nNothing sent. Run again with --confirm once Adam has said go ahead.")
        return

    ids = have["ids"]
    if diff["appInfo"]:
        asc.patch("appInfoLocalizations", "appInfoLocalizations", ids["appInfo"], diff["appInfo"])
    if diff["localization"]:
        asc.patch("appStoreVersionLocalizations", "appStoreVersionLocalizations", ids["localization"], diff["localization"])
    if diff["version"]:
        asc.patch("appStoreVersions", "appStoreVersions", ids["version"], diff["version"])
    if diff["review"]:
        if ids["review"]:
            asc.patch("appStoreReviewDetails", "appStoreReviewDetails", ids["review"], diff["review"])
        else:
            asc._send("POST", "/appStoreReviewDetails", json={"data": {
                "type": "appStoreReviewDetails",
                "attributes": diff["review"],
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": ids["version"]}}},
            }})

    version = next(v for v in asc.versions(app_id) if v["id"] == version["id"])
    after = differences(want, fetch_remote(asc, app_id, version, locale))
    left = {group: fields for group, fields in after.items() if fields}
    if left:
        sys.exit("Sent, but these still differ:\n" + json.dumps(left, indent=2, ensure_ascii=False))
    print("\nSent, and App Store Connect now matches the repo.")


def main() -> None:
    parser = argparse.ArgumentParser(prog="asc_client.py")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check").set_defaults(run=cmd_check)
    commands.add_parser("status").set_defaults(run=cmd_status)
    commands.add_parser("fetch").set_defaults(run=cmd_fetch)
    commands.add_parser("diff").set_defaults(run=cmd_diff)
    publish = commands.add_parser("publish")
    publish.add_argument("--confirm", action="store_true", help="Send the differences. Without it, nothing is sent.")
    publish.set_defaults(run=cmd_publish)
    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    main()
