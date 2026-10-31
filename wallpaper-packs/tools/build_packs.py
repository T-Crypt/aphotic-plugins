#!/usr/bin/env python3
"""Write the pack manifests from pinned source checkouts.

community.toml lists the curated picks from the community collection.
classic.toml lists the wallpapers Aphotic used to ship in its theme
folders, served from the Aphotic repo at the commit before they moved
out. Every row carries the file's sha256 and pixel size, so a fetch
verifies what it downloads and an ultrawide screen can prefer 21:9.

    python3 tools/build_packs.py \
        --community-src <checkout> --community-rev <sha> --community-url <raw base for rev> \
        --classic-src ~/Aphotic-Hypr --classic-rev <sha>
"""
import argparse
import hashlib
import subprocess
import sys
import tomllib
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
PACKS = HERE.parent / "packs"
IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp", ".gif"}
# Below this a picked image is softer than the screens it would cover.
MIN_WIDTH, MIN_HEIGHT = 1880, 1000


def size_of(data: bytes) -> tuple[int, int]:
    from io import BytesIO
    with Image.open(BytesIO(data)) as im:
        return im.size


def row(theme: str, rel: str, data: bytes) -> str:
    w, h = size_of(data)
    digest = hashlib.sha256(data).hexdigest()
    return f'[[wallpaper]]\ntheme = "{theme}"\npath = "{rel}"\nsha256 = "{digest}"\nwidth = {w}\nheight = {h}\n'


def header(pack_id: str, label: str, base_url: str, note: str) -> str:
    return f'[pack]\nid = "{pack_id}"\nlabel = "{label}"\nbase_url = "{base_url}"\nnote = "{note}"\n'


def git_blob(repo: Path, rev: str, path: str) -> bytes:
    return subprocess.run(["git", "-C", str(repo), "show", f"{rev}:{path}"], capture_output=True, check=True).stdout


def build_community(src: Path, rev: str, base_url: str) -> int:
    themes = tomllib.loads((HERE / "curation.toml").read_text())["themes"]
    parts = [header("community", "Community collection",
                    base_url,
                    "Picked by palette match and by eye. Credit belongs to the original artists; the collection names none per image.")]
    count = 0
    for theme, files in themes.items():
        for name in files:
            data = git_blob(src, rev, f"images/{name}")
            w, h = size_of(data)
            if w < MIN_WIDTH or h < MIN_HEIGHT:
                print(f"  below {MIN_WIDTH}x{MIN_HEIGHT}, left out: {theme}/{name} {w}x{h}", file=sys.stderr)
                continue
            parts.append(row(theme, name, data))
            count += 1
    (PACKS / "community.toml").write_text("\n".join(parts))
    return count


def build_classic(repo: Path, rev: str) -> int:
    listing = subprocess.run(["git", "-C", str(repo), "ls-tree", "-r", "--name-only", rev, "Configs/awww"],
                             capture_output=True, text=True, check=True).stdout.split()
    current = set(subprocess.run(["git", "-C", str(repo), "ls-files", "Configs/awww"],
                                 capture_output=True, text=True, check=True).stdout.split())
    parts = [header("classic", "Aphotic classic",
                    f"https://raw.githubusercontent.com/T-Crypt/aphotic-hypr/{rev}/Configs/awww/",
                    "The wallpapers Aphotic shipped in its theme folders before they moved to packs.")]
    count = 0
    for path in listing:
        p = Path(path)
        if p.suffix.lower() not in IMAGE_EXT or path in current:
            continue
        theme, rel = p.parts[2], "/".join(p.parts[2:])
        parts.append(row(theme, rel, git_blob(repo, rev, path)))
        count += 1
    (PACKS / "classic.toml").write_text("\n".join(parts))
    return count


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--community-src", type=Path, required=True)
    ap.add_argument("--community-rev", required=True)
    ap.add_argument("--community-url", required=True, help="raw file base URL at --community-rev, ending in /images/")
    ap.add_argument("--classic-src", type=Path, required=True)
    ap.add_argument("--classic-rev", required=True)
    args = ap.parse_args(argv)
    PACKS.mkdir(exist_ok=True)
    print("community", build_community(args.community_src, args.community_rev, args.community_url))
    print("classic", build_classic(args.classic_src, args.classic_rev))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
