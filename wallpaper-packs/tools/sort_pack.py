#!/usr/bin/env python3
"""Score wallpapers against theme palettes and write a sorted pack manifest.

Each theme's reference palette is its published colours plus k-means
colours of the wallpapers Aphotic already ships for it. An image scores
by the share of its pixels that land near a reference colour in Lab
space, chromatic and neutral pixels weighted separately so an image that
is mostly black does not match every dark theme. An image goes to its
best theme only when it clears a floor and beats the runner-up by a
margin; the rest stay out.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

PUBLISHED = {
    "nordic": "2E3440 3B4252 434C5E 4C566A D8DEE9 E5E9F0 ECEFF4 8FBCBB 88C0D0 81A1C1 5E81AC BF616A D08770 EBCB8B A3BE8C B48EAD",
    "gruvbox": "282828 1d2021 3c3836 504945 665c54 928374 ebdbb2 fbf1c7 cc241d 98971a d79921 458588 b16286 689d6a d65d0e fb4934 b8bb26 fabd2f 83a598 d3869b 8ec07c fe8019",
    "latte": "eff1f5 e6e9ef dce0e8 ccd0da bcc0cc acb0be 9ca0b0 8c8fa1 7c7f93 6c6f85 5c5f77 4c4f69 dc8a78 dd7878 ea76cb 8839ef d20f39 e64553 fe640b df8e1d 40a02b 179299 04a5e5 209fb5 1e66f5 7287fd",
    "rosepine": "191724 1f1d2e 26233a 21202e 403d52 524f67 6e6a86 908caa e0def4 eb6f92 f6c177 ebbcba 31748f 9ccfd8 c4a7e7",
    "tokyonight": "1a1b26 16161e 24283b 414868 565f89 a9b1d6 c0caf5 7aa2f7 7dcfff bb9af7 9ece6a e0af68 f7768e ff9e64 2ac3de 73daca",
    "dracula": "282a36 44475a f8f8f2 6272a4 8be9fd 50fa7b ffb86c ff79c6 bd93f9 ff5555 f1fa8c",
    "hackthebox": "141d2b 1a2332 111927 9fef00 a4b1cd ffffff 2e6cff",
    "lofi": "",
    "windows11": "",
}

IMAGE_EXT = {".png", ".jpg", ".jpeg", ".webp"}


def hex_rgb(h: str) -> list[int]:
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def srgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    c = rgb.astype(np.float64) / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], axis=-1)


def load_pixels(path: Path, side: int = 96) -> tuple[np.ndarray, int, int]:
    with Image.open(path) as im:
        w, h = im.size
        im = im.convert("RGB")
        im.thumbnail((side, side))
        return srgb_to_lab(np.asarray(im).reshape(-1, 3)), w, h


def kmeans(lab: np.ndarray, k: int, iters: int = 12) -> np.ndarray:
    rng = np.random.default_rng(0)
    centers = lab[rng.choice(len(lab), size=min(k, len(lab)), replace=False)]
    for _ in range(iters):
        d = ((lab[:, None, :] - centers[None]) ** 2).sum(-1)
        idx = d.argmin(1)
        centers = np.array([lab[idx == i].mean(0) if (idx == i).any() else centers[i] for i in range(len(centers))])
    return centers


def reference_palettes(curated_root: Path) -> dict[str, np.ndarray]:
    refs = {}
    for theme, published in PUBLISHED.items():
        colours = [srgb_to_lab(np.array(hex_rgb(h))) for h in published.split()]
        theme_dir = curated_root / theme
        if theme_dir.is_dir():
            pixels = [load_pixels(p, 64)[0] for p in sorted(theme_dir.iterdir()) if p.suffix.lower() in IMAGE_EXT]
            if pixels:
                colours.extend(kmeans(np.concatenate(pixels), 10 if published else 16))
        if colours:
            refs[theme] = np.array(colours)
    return refs


def score(lab: np.ndarray, ref: np.ndarray, tol: float) -> float:
    chroma = np.hypot(lab[:, 1], lab[:, 2])
    near = np.sqrt(((lab[:, None, :] - ref[None]) ** 2).sum(-1)).min(1) < tol
    chromatic = chroma > 14
    parts = []
    if chromatic.any():
        parts.append((0.65, near[chromatic].mean()))
    if (~chromatic).any():
        parts.append((0.35, near[~chromatic].mean()))
    total = sum(w for w, _ in parts)
    return sum(w * v for w, v in parts) / total


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("images", type=Path)
    ap.add_argument("--curated", type=Path, required=True, help="Configs/awww of an Aphotic checkout")
    ap.add_argument("--exclude", type=Path, help="file of name substrings to skip, one per line")
    ap.add_argument("--tol", type=float, default=13.0)
    ap.add_argument("--floor", type=float, default=0.42)
    ap.add_argument("--margin", type=float, default=0.06)
    ap.add_argument("--out", type=Path, required=True, help="scores JSON")
    args = ap.parse_args(argv)

    exclude = [l.strip().lower() for l in args.exclude.read_text().splitlines() if l.strip() and not l.startswith("#")] if args.exclude else []
    refs = reference_palettes(args.curated)
    rows = []
    for path in sorted(args.images.iterdir()):
        if path.suffix.lower() not in IMAGE_EXT:
            continue
        if any(x in path.name.lower() for x in exclude):
            continue
        try:
            lab, w, h = load_pixels(path)
        except OSError as exc:
            print(f"skip {path.name}: {exc}", file=sys.stderr)
            continue
        scores = sorted(((score(lab, ref, args.tol), t) for t, ref in refs.items()), reverse=True)
        (best, theme), (second, _) = scores[0], scores[1]
        rows.append({
            "file": path.name,
            "theme": theme if best >= args.floor and best - second >= args.margin else None,
            "best": round(best, 3),
            "second": round(second, 3),
            "width": w,
            "height": h,
            "sha256": sha256(path),
            "scores": {t: round(s, 3) for s, t in scores[:3]},
        })
    args.out.write_text(json.dumps(rows, indent=1))
    by_theme: dict[str, int] = {}
    for r in rows:
        by_theme[r["theme"] or "-"] = by_theme.get(r["theme"] or "-", 0) + 1
    print(json.dumps(by_theme, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
