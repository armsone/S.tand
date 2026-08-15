#!/bin/zsh
set -euo pipefail

attachment_dir="${1:?attachment directory is required}"
artifact_dir="${2:?artifact directory is required}"
project_dir="${3:?project directory is required}"
manifest_path="${attachment_dir}/manifest.json"
index_path="${artifact_dir}/index.html"

if [[ ! -f "${manifest_path}" ]]; then
  echo "Attachment manifest not found: ${manifest_path}" >&2
  exit 1
fi

python3 - "${manifest_path}" "${index_path}" "${project_dir}" <<'PY'
import datetime
import hashlib
import html
import json
import pathlib
import re
import shutil
import struct
import subprocess
import sys

manifest_path = pathlib.Path(sys.argv[1])
index_path = pathlib.Path(sys.argv[2])
project_path = pathlib.Path(sys.argv[3])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

groups = manifest if isinstance(manifest, list) else [manifest]
attachments = [
    attachment
    for group in groups
    for attachment in group.get("attachments", [])
]
screenshots = []
for item in attachments:
    suggested_name = item.get("suggestedHumanReadableName") or "screenshot.png"
    name = re.sub(r"_0_[0-9A-F-]+\.(png|jpe?g)$", "", suggested_name, flags=re.I)
    exported = item.get("exportedFileName") or item.get("filename")
    if exported and exported.lower().endswith((".png", ".jpg", ".jpeg")):
        extension = pathlib.Path(exported).suffix.lower()
        screenshots.append((name, exported, f"{name}{extension}", item))

screenshots.sort(key=lambda pair: pair[0])
screenshots_dir = index_path.parent / "screenshots"
originals_dir = index_path.parent / "originals"
screenshots_dir.mkdir(parents=True, exist_ok=True)
originals_dir.mkdir(parents=True, exist_ok=True)

def png_size(path):
    with path.open("rb") as stream:
        signature = stream.read(24)
    if signature[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not a PNG: {path}")
    return struct.unpack(">II", signature[16:24])

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

orientation_by_state = {"home_landscape": "landscapeRight"}
device_orientation_by_state = {"home_landscape": "landscapeLeft"}
palette_by_state = {
    "settings_midnight_theme": "midnight",
    "clock_font_options": "midnight",
    "settings_lower_sections": "midnight",
    "radio_channel_editor": "midnight",
    "radio_delete_confirmation": "midnight",
}

screen_records = []
for name, exported, stable_name, item in screenshots:
    source_path = manifest_path.parent / exported
    original_path = originals_dir / stable_name
    normalized_path = screenshots_dir / stable_name
    shutil.copyfile(source_path, original_path)
    orientation = orientation_by_state.get(name, "portrait")
    if name == "home_landscape":
        subprocess.run(
            ["sips", "-r", "-90", str(original_path), "--out", str(normalized_path)],
            check=True,
            stdout=subprocess.DEVNULL,
        )
    else:
        shutil.copyfile(original_path, normalized_path)
    width, height = png_size(normalized_path)
    screen_records.append({
        "id": name,
        "originalFile": f"originals/{stable_name}",
        "file": f"screenshots/{stable_name}",
        "originalSha256": sha256(original_path),
        "sha256": sha256(normalized_path),
        "pixelWidth": width,
        "pixelHeight": height,
        "orientation": orientation,
        "deviceOrientation": device_orientation_by_state.get(name, "portrait"),
        "normalizationRotationDegrees": -90 if name == "home_landscape" else 0,
        "theme": palette_by_state.get(name, "orange"),
        "appBoundsPixels": [0, 0, width, height],
        "captureTimestamp": item.get("timestamp"),
    })

revision = subprocess.run(
    ["git", "-C", str(project_path), "rev-parse", "HEAD"],
    check=True,
    capture_output=True,
    text=True,
).stdout.strip()
status_output = subprocess.run(
    ["git", "-C", str(project_path), "status", "--porcelain"],
    check=True,
    capture_output=True,
    text=True,
).stdout
dirty = bool(status_output.strip())
source_fingerprint = hashlib.sha256()
source_fingerprint.update(subprocess.run(
    ["git", "-C", str(project_path), "diff", "--binary", "HEAD"],
    check=True,
    capture_output=True,
).stdout)
for line in status_output.splitlines():
    if not line.startswith("?? "):
        continue
    relative_path = line[3:]
    untracked_path = project_path / relative_path
    source_fingerprint.update(relative_path.encode("utf-8"))
    if untracked_path.is_file():
        source_fingerprint.update(untracked_path.read_bytes())
version_text = (project_path / "Configuration/Versions.xcconfig").read_text(encoding="utf-8")
marketing = re.search(r"MARKETING_VERSION\s*=\s*([^\s]+)", version_text)
build = re.search(r"CURRENT_PROJECT_VERSION\s*=\s*([^\s]+)", version_text)

catalog_manifest = {
    "schemaVersion": 2,
    "fixtureId": "ui_catalog_v2",
    "platform": "ios",
    "deviceClass": "phone",
    "device": screenshots[0][3].get("deviceName") if screenshots else None,
    "deviceId": screenshots[0][3].get("deviceId") if screenshots else None,
    "sharedProfile": {
        "locale": "ko-KR",
        "timezone": "Asia/Seoul",
        "theme": "dark",
        "animations": False,
        "fontScale": 1.0,
    },
    "fixedClock": "2026-08-15T07:42:05+09:00",
    "revision": revision,
    "dirty": dirty,
    "sourceStateSha256": source_fingerprint.hexdigest(),
    "marketingVersion": marketing.group(1) if marketing else None,
    "buildVersion": build.group(1) if build else None,
    "generatedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "screens": screen_records,
}
(index_path.parent / "manifest.json").write_text(
    json.dumps(catalog_manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)

cards = "\n".join(
    f'<article><img src="screenshots/{html.escape(stable_name)}" '
    f'alt="{html.escape(name)}"><h2>{html.escape(name)}</h2></article>'
    for name, _, stable_name, _ in screenshots
)

index_path.write_text(f"""<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>S.tand UI Catalog</title>
  <style>
    :root {{ color-scheme: dark; font-family: -apple-system, sans-serif; }}
    body {{ margin: 0; padding: 32px; background: #111; color: #f5f5f5; }}
    main {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 24px; }}
    article {{ padding: 16px; border-radius: 18px; background: #1c1c1e; }}
    img {{ display: block; width: 100%; border-radius: 12px; background: #000; }}
    h2 {{ margin: 12px 2px 0; font-size: 15px; }}
  </style>
</head>
<body>
  <h1>S.tand UI Catalog</h1>
  <main>{cards}</main>
</body>
</html>
""", encoding="utf-8")
PY
