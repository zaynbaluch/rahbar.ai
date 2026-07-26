#!/usr/bin/env python3
"""Static repository checks that do not require the Flutter SDK.

This intentionally does not pretend to replace `flutter analyze`, `flutter test`, or an
Android build. It catches damaged assets, unresolved local imports, invalid configuration,
line-ending regressions, and bundled-database corruption before those commands are run.
"""
from __future__ import annotations

import argparse
import ast
import json
import re
import sqlite3
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import yaml

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"


@dataclass
class CheckResult:
    name: str
    status: str
    detail: str


# Ignored SDKs, caches, generated output, and vendored external sources. These are
# not tracked repository sources, and `.fvm/flutter_sdk` in particular is a symlink
# into a Flutter install that may be absent or broken on a given machine.
EXCLUDED_DIRS = frozenset(
    {
        ".git",
        ".fvm",
        ".dart_tool",
        "build",
        "third_party",
        "__pycache__",
        ".pytest_cache",
        ".venv",
    }
)


def iter_files(root: Path, suffixes: set[str]) -> Iterable[Path]:
    for path in root.rglob("*"):
        if EXCLUDED_DIRS.intersection(path.parts):
            continue
        if path.is_file() and path.suffix.lower() in suffixes:
            yield path


def check_yaml() -> CheckResult:
    files = [APP / "pubspec.yaml", APP / "analysis_options.yaml", ROOT / "pipeline" / "pyproject.toml"]
    parsed = 0
    for path in files[:2]:
        yaml.safe_load(path.read_text(encoding="utf-8"))
        parsed += 1
    # pyproject is TOML. tomllib is stdlib from 3.11; tomli is the backport below that.
    try:
        import tomllib
    except ModuleNotFoundError:
        import tomli as tomllib

    tomllib.loads(files[2].read_text(encoding="utf-8"))
    return CheckResult("configuration parsing", "PASS", f"{parsed} YAML files and pyproject.toml")


def check_xml() -> CheckResult:
    files = list(iter_files(APP / "android", {".xml"}))
    for path in files:
        ET.parse(path)
    return CheckResult("Android XML", "PASS", f"{len(files)} XML files")


def check_python() -> CheckResult:
    files = list(iter_files(ROOT, {".py"}))
    for path in files:
        ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    return CheckResult("Python syntax", "PASS", f"{len(files)} Python files")


def _strip_dart_comments_and_strings(text: str) -> str:
    # Conservative lexical pass for delimiter validation. It is not a Dart parser.
    output: list[str] = []
    i = 0
    state = "code"
    quote = ""
    triple = False
    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if state == "code":
            if ch == "/" and nxt == "/":
                state = "line_comment"
                output.extend("  ")
                i += 2
                continue
            if ch == "/" and nxt == "*":
                state = "block_comment"
                output.extend("  ")
                i += 2
                continue
            if ch in {"'", '"'}:
                quote = ch
                triple = text[i : i + 3] == ch * 3
                state = "string"
                width = 3 if triple else 1
                output.extend(" " * width)
                i += width
                continue
            output.append(ch)
            i += 1
            continue
        if state == "line_comment":
            if ch == "\n":
                state = "code"
                output.append(ch)
            else:
                output.append(" ")
            i += 1
            continue
        if state == "block_comment":
            if ch == "*" and nxt == "/":
                output.extend("  ")
                i += 2
                state = "code"
            else:
                output.append("\n" if ch == "\n" else " ")
                i += 1
            continue
        if state == "string":
            if ch == "\\":
                output.extend("  ")
                i += min(2, len(text) - i)
                continue
            if triple and text[i : i + 3] == quote * 3:
                output.extend("   ")
                i += 3
                state = "code"
                continue
            if not triple and ch == quote:
                output.append(" ")
                i += 1
                state = "code"
                continue
            output.append("\n" if ch == "\n" else " ")
            i += 1
    if state in {"block_comment", "string"}:
        raise ValueError(f"unterminated Dart {state}")
    return "".join(output)


def check_dart_structure() -> CheckResult:
    files = list(iter_files(APP / "lib", {".dart"})) + list(iter_files(APP / "test", {".dart"}))
    import_pattern = re.compile(r"^\s*import\s+['\"]([^'\"]+)['\"]", re.MULTILINE)
    unresolved: list[str] = []
    delimiters = {"(": ")", "[": "]", "{": "}"}
    closing = {value: key for key, value in delimiters.items()}
    for path in files:
        text = path.read_text(encoding="utf-8")
        stripped = _strip_dart_comments_and_strings(text)
        stack: list[tuple[str, int]] = []
        for index, ch in enumerate(stripped):
            if ch in delimiters:
                stack.append((ch, index))
            elif ch in closing:
                if not stack or stack[-1][0] != closing[ch]:
                    raise ValueError(f"{path.relative_to(ROOT)}: mismatched {ch} at byte {index}")
                stack.pop()
        if stack:
            raise ValueError(f"{path.relative_to(ROOT)}: unclosed delimiter {stack[-1][0]}")
        for target in import_pattern.findall(text):
            if target.startswith("dart:") or target.startswith("package:"):
                continue
            resolved = (path.parent / target).resolve()
            if not resolved.is_file():
                unresolved.append(f"{path.relative_to(ROOT)} -> {target}")
    if unresolved:
        raise ValueError("unresolved local imports: " + "; ".join(unresolved))
    return CheckResult("Dart structural checks", "PASS", f"{len(files)} files; delimiters and local imports")


def check_assets() -> CheckResult:
    pubspec = yaml.safe_load((APP / "pubspec.yaml").read_text(encoding="utf-8"))
    entries = pubspec.get("flutter", {}).get("assets", [])
    missing: list[str] = []
    covered = 0
    for raw in entries:
        entry = str(raw).split("#", 1)[0].strip()
        path = APP / entry
        if not path.exists():
            missing.append(entry)
        else:
            covered += 1
    if missing:
        raise ValueError("missing pubspec assets: " + ", ".join(missing))
    return CheckResult("Flutter asset manifest", "PASS", f"{covered} entries exist")


def check_databases() -> CheckResult:
    databases = [APP / "assets/content/content_pack.db", APP / "assets/rag/curriculum.db"]
    details: list[str] = []
    for path in databases:
        with sqlite3.connect(path) as db:
            integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
            if integrity != "ok":
                raise ValueError(f"{path.name}: {integrity}")
            tables = db.execute(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
            ).fetchall()
            details.append(f"{path.name}:{len(tables)} tables")
    return CheckResult("SQLite integrity", "PASS", ", ".join(details))


def check_line_endings() -> CheckResult:
    files = list(iter_files(ROOT / "scripts", {".sh"}))
    bad = [str(path.relative_to(ROOT)) for path in files if b"\r\n" in path.read_bytes()]
    if bad:
        raise ValueError("CRLF shell files: " + ", ".join(bad))
    return CheckResult("Shell line endings", "PASS", f"{len(files)} shell scripts use LF")


def check_android_baseline() -> CheckResult:
    settings = (APP / "android/settings.gradle.kts").read_text(encoding="utf-8")
    wrapper = (APP / "android/gradle/wrapper/gradle-wrapper.properties").read_text(encoding="utf-8")
    build = (APP / "android/app/build.gradle.kts").read_text(encoding="utf-8")
    native_setup = (ROOT / "scripts/setup-llama.sh").read_text(encoding="utf-8")
    expected = {
        'id("com.android.application") version "8.11.1"': settings,
        'id("org.jetbrains.kotlin.android") version "2.3.20"': settings,
        "gradle-9.1.0-all.zip": wrapper,
        'ndkVersion = "28.2.13676358"': build,
        "JavaVersion.VERSION_17": build,
        'abiFilters += listOf("arm64-v8a")': build,
        'ANDROID_NDK_VERSION="${ANDROID_NDK_VERSION:-28.2.13676358}"': native_setup,
        'ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-24}"': native_setup,
    }
    missing = [needle for needle, haystack in expected.items() if needle not in haystack]
    forbidden = [
        value
        for value in ("ndk/28.2.13676358", "-DANDROID_PLATFORM=android-29")
        if value in native_setup
    ]
    if missing or forbidden:
        details = []
        if missing:
            details.append("missing: " + ", ".join(missing))
        if forbidden:
            details.append("obsolete native defaults: " + ", ".join(forbidden))
        raise ValueError("Android baseline mismatch: " + "; ".join(details))
    return CheckResult(
        "Android build baseline",
        "PASS",
        "AGP 8.11.1, Kotlin 2.3.20, Gradle 9.1.0, NDK 28.2.13676358, Java 17, native API 24, arm64-only",
    )


def check_lockfile() -> CheckResult:
    pubspec = yaml.safe_load((APP / "pubspec.yaml").read_text(encoding="utf-8"))
    lock_path = APP / "pubspec.lock"
    if not lock_path.exists():
        return CheckResult(
            "Flutter lockfile",
            "BLOCKED",
            "run flutter pub get with Flutter 3.44.4 and commit the generated lockfile",
        )
    lock = yaml.safe_load(lock_path.read_text(encoding="utf-8"))
    declared = set(pubspec.get("dependencies", {})) | set(pubspec.get("dev_dependencies", {}))
    packages = lock.get("packages", {})
    missing = sorted(name for name in declared if name not in packages)
    stale_direct = sorted(
        name
        for name, details in packages.items()
        if details.get("dependency") in {"direct main", "direct dev"} and name not in declared
    )
    if missing or stale_direct:
        parts = []
        if missing:
            parts.append("missing direct entries: " + ", ".join(missing))
        if stale_direct:
            parts.append("stale direct entries: " + ", ".join(stale_direct))
        return CheckResult("Flutter lockfile", "BLOCKED", "; ".join(parts) + "; regenerate with Flutter 3.44.4")
    return CheckResult("Flutter lockfile", "PASS", "direct dependencies match pubspec.yaml")


def check_brand_copy() -> CheckResult:
    current_paths = [ROOT / "README.md", APP / "README.md", ROOT / "RUN_ON_ANDROID.md"]
    offenders = [
        str(path.relative_to(ROOT))
        for path in current_paths
        if path.exists() and "Rahbar AI" in path.read_text(encoding="utf-8")
    ]
    if offenders:
        raise ValueError("legacy visible product name in current docs: " + ", ".join(offenders))
    return CheckResult("Current product naming", "PASS", "current user/developer entry documents use Bayaz AI")


def run() -> tuple[list[CheckResult], int]:
    checks = [
        check_yaml,
        check_xml,
        check_python,
        check_dart_structure,
        check_assets,
        check_databases,
        check_line_endings,
        check_android_baseline,
        check_lockfile,
        check_brand_copy,
    ]
    results: list[CheckResult] = []
    exit_code = 0
    for check in checks:
        try:
            result = check()
        except Exception as error:  # noqa: BLE001 - validation should report all failures.
            result = CheckResult(check.__name__.removeprefix("check_").replace("_", " "), "FAIL", str(error))
            exit_code = 1
        results.append(result)
    return results, exit_code


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    args = parser.parse_args()
    results, exit_code = run()
    if args.json:
        print(json.dumps([result.__dict__ for result in results], indent=2))
    else:
        for result in results:
            print(f"{result.status:7} {result.name}: {result.detail}")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
