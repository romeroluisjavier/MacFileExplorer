#!/usr/bin/env zsh
set -euo pipefail

REPO="romeroluisjavier/MacFileExplorer"

curl -fsSL "https://api.github.com/repos/${REPO}/releases?per_page=30" | python3 -c '
import json, sys

releases = json.load(sys.stdin)
if not isinstance(releases, list) or not releases:
    print("Todavía no hay GitHub Releases publicadas en romeroluisjavier/MacFileExplorer.")
    print("Cuando subas el workflow y lo ejecutes (o pushees un tag v*), acá vas a ver cada descarga real del .dmg.")
    sys.exit(0)

total = 0
print(f"{'\''Versión'\'':<12} {'\''Archivo'\'':<32} {'\''Descargas'\'':>10}  {'\''Publicada'\''}")
print("-" * 72)
for rel in releases:
    tag = rel.get("tag_name", "?")
    published = (rel.get("published_at") or "")[:10]
    assets = rel.get("assets", [])
    if not assets:
        print(f"{tag:<12} {'\''(sin .dmg adjunto)'\'':<32} {0:>10}  {published}")
        continue
    for asset in assets:
        count = int(asset.get("download_count", 0))
        total += count
        print(f"{tag:<12} {asset.get('\''name'\'', '\''?'\''):<32} {count:>10}  {published}")
print("-" * 72)
print(f"{'\''TOTAL'\'':<45} {total:>10}")
'
