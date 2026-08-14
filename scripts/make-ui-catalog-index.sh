#!/bin/zsh
set -euo pipefail

attachment_dir="${1:?attachment directory is required}"
artifact_dir="${2:?artifact directory is required}"
manifest_path="${attachment_dir}/manifest.json"
index_path="${artifact_dir}/index.html"

if [[ ! -f "${manifest_path}" ]]; then
  echo "Attachment manifest not found: ${manifest_path}" >&2
  exit 1
fi

python3 - "${manifest_path}" "${index_path}" <<'PY'
import html
import json
import pathlib
import re
import shutil
import sys

manifest_path = pathlib.Path(sys.argv[1])
index_path = pathlib.Path(sys.argv[2])
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
screenshots_dir.mkdir(parents=True, exist_ok=True)
for _, exported, stable_name, _ in screenshots:
    shutil.copyfile(manifest_path.parent / exported, screenshots_dir / stable_name)

catalog_manifest = {
    "device": screenshots[0][3].get("deviceName") if screenshots else None,
    "screens": [
        {"id": name, "file": f"screenshots/{stable_name}"}
        for name, _, stable_name, _ in screenshots
    ],
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
