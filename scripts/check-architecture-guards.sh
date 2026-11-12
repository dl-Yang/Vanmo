#!/usr/bin/env bash
# Architecture structure guards: XcodeGen drift, target source/dependency
# whitelist, and unconditional VanmoCore UI imports.
# Does not run xcodebuild or regenerate the committed Xcode project.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

pass() {
  echo "PASS: $1"
}

echo "== Architecture structure guards =="

for command in xcodegen python3 git; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "FAIL: required command not found: $command" >&2
    echo "== Summary: 1 failure(s) =="
    exit 1
  fi
done

echo "xcodegen $(xcodegen --version)"

status_before="$(git status --short)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/vanmo-architecture-guards.XXXXXX")"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

DUMP_JSON="$TMP/project-spec.json"
if ! xcodegen dump --spec "$ROOT/project.yml" --type json --file "$DUMP_JSON"; then
  fail "xcodegen dump failed"
  echo "== Summary: $failures failure(s) =="
  exit 1
fi

MIRROR="$TMP/mirror"
mkdir -p "$MIRROR"
ln -s "$ROOT/project.yml" "$MIRROR/project.yml"
ln -s "$ROOT/Vanmo" "$MIRROR/Vanmo"
ln -s "$ROOT/VanmoMac" "$MIRROR/VanmoMac"
ln -s "$ROOT/VanmoDownloadWidget" "$MIRROR/VanmoDownloadWidget"
ln -s "$ROOT/Packages" "$MIRROR/Packages"
ln -s "$ROOT/Config" "$MIRROR/Config"

if ! xcodegen generate --spec "$MIRROR/project.yml" --project "$MIRROR" --project-root "$MIRROR" --quiet; then
  fail "xcodegen generate failed (non-mutating temp mirror)"
  echo "== Summary: $failures failure(s) =="
  exit 1
fi

status_after="$(git status --short)"
if [[ "$status_before" != "$status_after" ]]; then
  fail "xcodegen generate mutated the working tree"
  printf '%s\n' "$status_after" >&2
else
  pass "xcodegen generate stayed outside the working tree"
fi

set +e
python3 - "$ROOT" "$DUMP_JSON" "$MIRROR" <<'PY'
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
dump_path = Path(sys.argv[2])
generated_project = Path(sys.argv[3]) / "Vanmo.xcodeproj"
committed_project = root / "Vanmo.xcodeproj"
failures = 0


def pass_check(message):
    print(f"PASS: {message}")


def fail_check(message):
    global failures
    failures += 1
    print(f"FAIL: {message}", file=sys.stderr)


MACOS_SHARED_SOURCES = (
    "Vanmo/Shared/Components/MediaTitleLogoView.swift",
    "Vanmo/Shared/Components/LoadingIndicatorView.swift",
)

SOURCE_ALLOWLIST = {
    "Vanmo": {"roots": ("Vanmo",), "files": ()},
    "Vanmo-macOS": {"roots": ("VanmoMac",), "files": MACOS_SHARED_SOURCES},
    "VanmoDownloadWidget": {
        "roots": ("VanmoDownloadWidget",),
        "files": (
            "Vanmo/LiveActivity/DownloadLiveActivityAttributes.swift",
            "Vanmo/LiveActivity/DownloadLiveActivityIntents.swift",
        ),
    },
}

APP_TARGETS = ("Vanmo", "Vanmo-macOS")
FORBIDDEN_CROSS_TARGET = {
    "Vanmo": "Vanmo-macOS",
    "Vanmo-macOS": "Vanmo",
}


def source_path(entry):
    if isinstance(entry, str):
        return entry
    if isinstance(entry, dict):
        return entry.get("path")
    return None


def normalize_source_path(raw):
    path = raw.replace("\\", "/").strip().lstrip("./")
    while path.endswith("/") and path != "/":
        path = path[:-1]
    return path


def is_vanmocore_source(path):
    return path == "Packages/VanmoCore" or path.startswith("Packages/VanmoCore/")


def source_allowed(target, path):
    if is_vanmocore_source(path):
        return False
    allow = SOURCE_ALLOWLIST[target]
    if path in allow["files"]:
        return True
    for prefix in allow["roots"]:
        if path == prefix or path.startswith(prefix + "/"):
            return True
    return False


def collapse_swift_flags(match):
    flags = re.findall(r'"([^"]+)"', match.group(1))
    return f'OTHER_SWIFT_FLAGS = "{" ".join(flags)}";'


def normalize_file_reference(match):
    body = match.group(1)
    pairs = re.findall(r"(\w+) = ([^;]+);", body)
    normalized = []
    for key, value in pairs:
        if key == "explicitFileType":
            key = "lastKnownFileType"
        normalized.append((key, value))
    normalized.sort()
    inner = " ".join(f"{key} = {value};" for key, value in normalized)
    return "{ " + inner + " };"


def normalize_pbxproj(text):
    text = re.sub(r"objectVersion = \d+;", "objectVersion = NORMALIZED;", text)
    text = re.sub(r"\n[ \t]*preferredProjectObjectVersion = \d+;", "", text)
    text = re.sub(r"\n[ \t]*DevelopmentTeam = [^;]*;", "", text)
    text = re.sub(r"\n[ \t]*DEVELOPMENT_TEAM = [^;]*;", "", text)
    text = re.sub(
        r"OTHER_SWIFT_FLAGS = \(\s*((?:\"[^\"]+\",?\s*)+)\);",
        collapse_swift_flags,
        text,
    )
    text = re.sub(
        r"/\* [^*]+ \*/ = \{([^}]*isa = PBXFileReference;[^}]*)\};",
        normalize_file_reference,
        text,
    )
    return text


def strip_swift_comments(source):
    result = []
    i = 0
    length = len(source)
    block_depth = 0
    in_line = False
    in_string = False
    string_delim = ""
    while i < length:
        ch = source[i]
        nxt = source[i + 1] if i + 1 < length else ""
        if in_line:
            if ch == "\n":
                in_line = False
                result.append(ch)
            i += 1
            continue
        if block_depth:
            if ch == "/" and nxt == "*":
                block_depth += 1
                i += 2
                continue
            if ch == "*" and nxt == "/":
                block_depth -= 1
                i += 2
                continue
            if ch == "\n":
                result.append(ch)
            i += 1
            continue
        if in_string:
            result.append(ch)
            if ch == "\\" and nxt:
                result.append(nxt)
                i += 2
                continue
            if source.startswith(string_delim, i):
                if string_delim != '"':
                    result.append(source[i + 1 : i + len(string_delim)])
                in_string = False
                i += len(string_delim)
                continue
            i += 1
            continue
        if ch == "/" and nxt == "/":
            in_line = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            block_depth = 1
            i += 2
            continue
        if source.startswith('"""', i):
            in_string = True
            string_delim = '"""'
            result.append('"""')
            i += 3
            continue
        if ch == '"':
            in_string = True
            string_delim = '"'
            result.append(ch)
            i += 1
            continue
        result.append(ch)
        i += 1
    return "".join(result)


IF_RE = re.compile(r"^\s*#\s*(if|ifdef|ifndef|elseif|else|endif)\b")
IMPORT_RE = re.compile(
    r"^\s*(?:@_exported\s+)?import\s+"
    r"(?:(?:class|struct|enum|protocol|func|var|let|typealias)\s+)?"
    r"(UIKit|AppKit|SwiftUI)\b"
)


def unconditional_ui_imports(path):
    text = strip_swift_comments(path.read_text(encoding="utf-8"))
    depth = 0
    hits = []
    for line_number, line in enumerate(text.splitlines(), 1):
        directive = IF_RE.match(line)
        if directive:
            kind = directive.group(1)
            if kind in ("if", "ifdef", "ifndef"):
                depth += 1
            elif kind == "endif" and depth:
                depth -= 1
            continue
        if depth:
            continue
        imported = IMPORT_RE.match(line)
        if imported:
            hits.append((path, line_number, imported.group(1)))
    return hits


try:
    spec = json.loads(dump_path.read_text(encoding="utf-8"))
except json.JSONDecodeError as error:
    fail_check(f"xcodegen dump is not valid JSON: {error}")
    sys.exit(1)

targets = spec.get("targets")
if not isinstance(targets, dict) or not targets:
    fail_check("xcodegen dump has no targets")
    sys.exit(1)

expected_targets = set(SOURCE_ALLOWLIST)
actual_targets = set(targets)
if actual_targets != expected_targets:
    fail_check(
        "unexpected project.yml targets: "
        + ", ".join(sorted(actual_targets))
        + f" (expected {', '.join(sorted(expected_targets))})"
    )

for name in sorted(expected_targets & actual_targets):
    target = targets[name]
    sources = target.get("sources") or []
    illegal = []
    for entry in sources:
        raw = source_path(entry)
        if not raw:
            illegal.append(repr(entry))
            continue
        path = normalize_source_path(raw)
        if not source_allowed(name, path):
            illegal.append(path)
    if illegal:
        fail_check(f"{name} sources are outside the whitelist: {', '.join(illegal)}")
    else:
        pass_check(f"{name} sources stay inside the declared whitelist")

    dependencies = target.get("dependencies") or []
    target_deps = {
        item.get("target")
        for item in dependencies
        if isinstance(item, dict) and item.get("target")
    }
    package_deps = {
        item.get("package")
        for item in dependencies
        if isinstance(item, dict) and item.get("package")
    }
    forbidden = FORBIDDEN_CROSS_TARGET.get(name)
    if forbidden and forbidden in target_deps:
        fail_check(f"{name} depends on forbidden target {forbidden}")
    elif name in APP_TARGETS:
        pass_check(f"{name} does not depend on the other app target")
    if name in APP_TARGETS:
        if "VanmoCore" in package_deps:
            pass_check(f"{name} declares package VanmoCore")
        else:
            fail_check(f"{name} is missing package VanmoCore")

committed_pbx = committed_project / "project.pbxproj"
generated_pbx = generated_project / "project.pbxproj"
if not committed_pbx.is_file():
    fail_check("committed Vanmo.xcodeproj/project.pbxproj is missing")
elif not generated_pbx.is_file():
    fail_check("generated project.pbxproj is missing")
else:
    committed_text = normalize_pbxproj(committed_pbx.read_text(encoding="utf-8"))
    generated_text = normalize_pbxproj(generated_pbx.read_text(encoding="utf-8"))
    if committed_text == generated_text:
        pass_check(
            "committed pbxproj matches xcodegen generate after format normalization"
        )
    else:
        fail_check(
            "committed pbxproj drifted from project.yml; "
            "edit project.yml and regenerate, do not hand-edit project.pbxproj"
        )
        import difflib

        diff = difflib.unified_diff(
            committed_text.splitlines(),
            generated_text.splitlines(),
            fromfile="Vanmo.xcodeproj/project.pbxproj (normalized)",
            tofile="generated/Vanmo.xcodeproj/project.pbxproj (normalized)",
            lineterm="",
        )
        for line in list(diff)[:80]:
            print(line, file=sys.stderr)

committed_scheme_dir = committed_project / "xcshareddata" / "xcschemes"
generated_scheme_dir = generated_project / "xcshareddata" / "xcschemes"
committed_schemes = {
    path.name: path.read_text(encoding="utf-8")
    for path in committed_scheme_dir.glob("*.xcscheme")
}
generated_schemes = {
    path.name: path.read_text(encoding="utf-8")
    for path in generated_scheme_dir.glob("*.xcscheme")
}
if committed_schemes.keys() != generated_schemes.keys():
    fail_check(
        "shared schemes drifted: committed="
        + ", ".join(sorted(committed_schemes))
        + " generated="
        + ", ".join(sorted(generated_schemes))
    )
else:
    mismatched = [
        name
        for name, text in committed_schemes.items()
        if text != generated_schemes[name]
    ]
    if mismatched:
        fail_check("shared schemes drifted: " + ", ".join(mismatched))
    else:
        pass_check("shared schemes match xcodegen generate")

core_root = root / "Packages" / "VanmoCore" / "Sources" / "VanmoCore"
if not core_root.is_dir():
    fail_check("VanmoCore sources directory is missing")
else:
    import_hits = []
    for swift_file in sorted(core_root.rglob("*.swift")):
        import_hits.extend(unconditional_ui_imports(swift_file))
    if import_hits:
        details = "\n".join(
            f"{path.relative_to(root)}:{line}: import {module}"
            for path, line, module in import_hits
        )
        fail_check(
            "VanmoCore contains unconditional UIKit/AppKit/SwiftUI imports:\n"
            + details
        )
    else:
        pass_check("VanmoCore has no unconditional UIKit/AppKit/SwiftUI imports")


def git(*args):
    return subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)


# OAuth credentials live only in the untracked Local.xcconfig.
if git("ls-files", "--error-unmatch", "Local.xcconfig").returncode == 0:
    fail_check("Local.xcconfig is tracked by git; remove it from the index (git rm --cached Local.xcconfig)")
else:
    pass_check("Local.xcconfig is not tracked")
if git("check-ignore", "-q", "Local.xcconfig").returncode != 0:
    fail_check("Local.xcconfig must be listed in .gitignore")
else:
    pass_check("Local.xcconfig is git-ignored")


def filled_credentials(source):
    return [
        match.group(1)
        for match in re.finditer(r"^[ \t]*(VANMO_[A-Z0-9_]+)[ \t]*=[ \t]*(\S.*)$", source, re.MULTILINE)
    ]


SECRETS_XCCONFIG = "Config/Secrets.xcconfig"
secrets_path = root / SECRETS_XCCONFIG
if not secrets_path.is_file():
    fail_check(f"{SECRETS_XCCONFIG} is missing")
else:
    sources = [("working tree", secrets_path.read_text(encoding="utf-8"))]
    staged = git("show", f":{SECRETS_XCCONFIG}")
    if staged.returncode == 0:
        sources.append(("git index", staged.stdout))
    for label, source in sources:
        filled = filled_credentials(source)
        if filled:
            fail_check(
                f"{SECRETS_XCCONFIG} must keep every credential empty in the {label}; "
                f"move {', '.join(filled)} to Local.xcconfig"
            )
        else:
            pass_check(f"{SECRETS_XCCONFIG} credentials are empty in the {label}")

OAUTH_CONFIG = "Packages/VanmoCore/Sources/VanmoCore/Network/OAuth/OAuthProviderConfiguration.swift"
oauth_source = (root / OAUTH_CONFIG).read_text(encoding="utf-8")
credential_region = oauth_source.split("public static func clientID", 1)[-1].split("public static func scope", 1)[0]
literals = [value for value in re.findall(r'return\s+"([^"]*)"', credential_region) if value.strip()]
if "public static func clientID" not in oauth_source or "public static func scope" not in oauth_source:
    fail_check(f"credential guard could not locate clientID/scope in {OAUTH_CONFIG}")
elif literals:
    fail_check(f"{OAUTH_CONFIG} returns literal OAuth credentials; read them from Local.xcconfig instead")
else:
    pass_check("OAuth credentials are not hard-coded in OAuthProviderConfiguration")

for plist_path in ("Vanmo/Resources/Info.plist", "VanmoMac/Resources/Info-Mac.plist"):
    with open(root / plist_path, "rb") as handle:
        credentials = plistlib.load(handle).get("VanmoOAuthCredentials")
    if not isinstance(credentials, dict) or not credentials:
        fail_check(f"{plist_path} is missing VanmoOAuthCredentials")
        continue
    literal_keys = [
        key for key, value in credentials.items()
        if not re.fullmatch(r"\$\(VANMO_[A-Z0-9_]+\)", str(value))
    ]
    if literal_keys:
        fail_check(f"{plist_path} VanmoOAuthCredentials must only reference $(VANMO_*): {', '.join(literal_keys)}")
    else:
        pass_check(f"{plist_path} VanmoOAuthCredentials only references build settings")

with open(root / "Vanmo/Resources/Info.plist", "rb") as handle:
    url_types = plistlib.load(handle).get("CFBundleURLTypes", [])
credential_schemes = {
    entry.get("CFBundleURLName"): entry.get("CFBundleURLSchemes", [])
    for entry in url_types
    if entry.get("CFBundleURLName") in ("com.vanmo.oauth.google", "YandexLoginSDK")
}
bad_schemes = [
    f"{name}: {scheme[:12]}…"
    for name, schemes in credential_schemes.items()
    for scheme in schemes
    if not re.fullmatch(r"(yx)?\$\(VANMO_[A-Z0-9_]+\)", scheme)
]
if len(credential_schemes) != 2:
    fail_check("Vanmo/Resources/Info.plist must keep the Google and Yandex OAuth URL types")
elif bad_schemes:
    fail_check("Vanmo/Resources/Info.plist OAuth URL schemes must reference $(VANMO_*): " + ", ".join(bad_schemes))
else:
    pass_check("Vanmo/Resources/Info.plist OAuth URL schemes only reference build settings")

for domain_path in ("project.yml", "Vanmo/Vanmo-Cloud.entitlements"):
    domains = re.findall(r"applinks:yx([^.\s<]*)\.oauth\.yandex\.com", (root / domain_path).read_text(encoding="utf-8"))
    if not domains or any(domain != "$(VANMO_YANDEX_DISK_CLIENT_ID)" for domain in domains):
        fail_check(f"{domain_path} Yandex associated domain must be applinks:yx$(VANMO_YANDEX_DISK_CLIENT_ID).oauth.yandex.com")
    else:
        pass_check(f"{domain_path} Yandex associated domain only references the build setting")

sys.exit(failures)
PY
python_status=$?
set -e
if [[ "$python_status" -ne 0 ]]; then
  failures=$((failures + python_status))
fi

echo "== Summary: $failures failure(s) =="
if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
exit 0
