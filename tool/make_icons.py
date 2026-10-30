"""Make every Absorb Plus icon from one drawing (the drop with sound bars).

Renders SVG with headless Microsoft Edge (no Python image libraries needed)
and writes the Windows .ico itself. Each output keeps the size of the file it
replaces. Run from the repo root on Windows:

    python tool/make_icons.py            # write all icons
    python tool/make_icons.py --preview  # only build/icons/preview.html

The drawing lives in mark_svg() below; assets/icon/source/ gets a copy of the
master SVGs for anyone who wants to edit them in a design tool.
"""

import argparse
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build" / "icons"

TILE = "#101014"     # dark tile behind the mark
COLOR = "#5fd0c0"    # the mark's teal
TILE_RADIUS = 230    # of 1024

# The drop, in a 1024 box: tip at y=170, round bottom of radius 238 at y=600.
DROP = ("M512 170 C 590 290 750 450 750 600 "
        "A 238 238 0 0 1 274 600 C 274 450 434 290 512 170 Z")
DROP_BOX = (274, 170, 750, 838)  # x0, y0, x1, y1


def _bars(scale: float = 0.6, cy: float = 620) -> str:
    """The three sound bars, as rects in the 1024 box (they are cut out)."""
    out = []
    for x, h in ((-168, 220), (0, 500), (168, 320)):
        w = 104 * scale
        hh = h * scale
        out.append(f'<rect x="{512 + x * scale - w / 2:.1f}" y="{cy - hh / 2:.1f}" '
                   f'width="{w:.1f}" height="{hh:.1f}" rx="{w / 2:.1f}"/>')
    return "".join(out)


def mark_svg(color: str = COLOR, mark_height: float = 0.65, size: int = 1024,
             tile: str | None = None, tile_radius: float = TILE_RADIUS,
             square_bg: str | None = None) -> str:
    """The drop with the bars cut out (transparent holes), scaled so the drop
    is mark_height of the canvas, centered. Optionally on a rounded tile or a
    full square background."""
    x0, y0, x1, y1 = DROP_BOX
    s = mark_height * 1024 / (y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    transform = f"translate(512 512) scale({s:.4f}) translate({-cx} {-cy})"
    bg = ""
    if square_bg:
        bg = f'<rect width="1024" height="1024" fill="{square_bg}"/>'
    elif tile:
        bg = f'<rect width="1024" height="1024" rx="{tile_radius}" fill="{tile}"/>'
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 1024 1024">'
        f'<defs><mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">'
        f'<rect width="1024" height="1024" fill="#fff"/><g fill="#000">{_bars()}</g></mask></defs>'
        f'{bg}<g transform="{transform}"><path d="{DROP}" fill="{color}" mask="url(#m)"/></g></svg>'
    )


# What each icon file is: (path, kind). Sizes come from the existing files.
#   tile       mark on the dark rounded tile (launcher, desktop, favicon)
#   foreground mark alone for Android's adaptive icon (the XML adds a 16% inset)
#   splash     mark alone for splash screens (fits Android 12's round mask)
#   notify     white silhouette for the Android notification bar
#   maskable   mark on a full dark square, inside the web "maskable" safe zone
KINDS = {
    "tile": dict(tile=TILE, mark_height=0.62),
    "foreground": dict(mark_height=0.58),
    "splash": dict(mark_height=0.58),
    "notify": dict(color="#ffffff", mark_height=0.86),
    "maskable": dict(square_bg=TILE, mark_height=0.50),
}

TARGETS = [
    ("assets/icon/app_icon.png", "tile"),
    ("assets/icon/app_icon_foreground.png", "foreground"),
    ("assets/icon/splash_logo.png", "splash"),
    ("web/favicon.png", "tile"),
    ("web/icons/Icon-192.png", "tile"),
    ("web/icons/Icon-512.png", "tile"),
    ("web/icons/Icon-maskable-192.png", "maskable"),
    ("web/icons/Icon-maskable-512.png", "maskable"),
    ("android/app/src/main/res/drawable/ic_notification.png", "notify"),
]
for d in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
    TARGETS += [
        (f"android/app/src/main/res/mipmap-{d}/ic_launcher.png", "tile"),
        (f"android/app/src/main/res/drawable-{d}/ic_launcher_foreground.png", "foreground"),
        (f"android/app/src/main/res/drawable-{d}/splash.png", "splash"),
        (f"android/app/src/main/res/drawable-{d}/android12splash.png", "splash"),
        (f"android/app/src/main/res/drawable-night-{d}/android12splash.png", "splash"),
    ]

ICO = "windows/runner/resources/app_icon.ico"
ICO_SIZES = (256, 64, 48, 40, 32, 24, 20, 16)


def png_size(path: Path) -> int:
    data = path.read_bytes()[:24]
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"not a PNG: {path}")
    w, h = struct.unpack(">II", data[16:24])
    if w != h:
        raise SystemExit(f"not square: {path} ({w}x{h})")
    return w


def edge() -> str:
    for p in (r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
              r"C:\Program Files\Microsoft\Edge\Application\msedge.exe"):
        if Path(p).exists():
            return p
    raise SystemExit("Microsoft Edge not found (needed to render the SVG)")


def render(svg: str, size: int, dest: Path, profile: Path) -> None:
    """Render svg to a size x size PNG with a transparent background."""
    page = Path(tempfile.mkdtemp(dir=OUT)) / "icon.html"
    page.write_text(
        '<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:transparent}'
        f'svg{{display:block;width:{size}px;height:{size}px}}</style>{svg}', encoding="utf-8")
    dest.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        edge(), "--headless=new", "--disable-gpu", "--hide-scrollbars",
        f"--user-data-dir={profile}", "--default-background-color=00000000",
        f"--window-size={size},{size}", f"--screenshot={dest}", page.as_uri(),
    ], check=True, capture_output=True)
    if not dest.exists() or png_size(dest) != size:
        raise SystemExit(f"render failed for {dest}")


def write_ico(pngs: list[tuple[int, bytes]], dest: Path) -> None:
    """A .ico holding PNG images (supported since Windows Vista)."""
    header = struct.pack("<HHH", 0, 1, len(pngs))
    entries, blobs = b"", b""
    offset = 6 + 16 * len(pngs)
    for size, data in pngs:
        dim = 0 if size >= 256 else size
        entries += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
        blobs += data
        offset += len(data)
    dest.write_bytes(header + entries + blobs)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", action="store_true", help="only write build/icons/preview.html")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)

    src = ROOT / "assets" / "icon" / "source"
    src.mkdir(parents=True, exist_ok=True)
    (src / "absorb-plus-logo.svg").write_text(mark_svg(tile=TILE, mark_height=0.62), encoding="utf-8")
    (src / "absorb-plus-mark.svg").write_text(mark_svg(mark_height=0.9), encoding="utf-8")

    preview = "".join(
        f'<figure style="display:inline-block;margin:8px;text-align:center;font:12px sans-serif">'
        f'<div style="width:{n}px;height:{n}px;background:{bg}">{mark_svg(size=n, **KINDS[k])}</div>{k} {n}</figure>'
        for k, bg in (("tile", "#fff"), ("tile", "#222"), ("foreground", "#101014"),
                      ("splash", "#000"), ("notify", "#333"), ("maskable", "#fff"))
        for n in (192, 48, 20))
    (OUT / "preview.html").write_text(f"<!doctype html><body style='background:#888'>{preview}", encoding="utf-8")
    if args.preview:
        print(f"preview: {OUT / 'preview.html'}")
        return 0

    profile = OUT / "edge-profile"
    for rel, kind in TARGETS:
        path = ROOT / rel
        if not path.exists():
            raise SystemExit(f"missing icon file to replace: {rel}")
        size = png_size(path)
        render(mark_svg(size=size, **KINDS[kind]), size, path, profile)
        print(f"ok {size:>4} {kind:<10} {rel}")

    ico_pngs = []
    for size in ICO_SIZES:
        tmp = OUT / f"ico-{size}.png"
        render(mark_svg(size=size, **KINDS["tile"]), size, tmp, profile)
        ico_pngs.append((size, tmp.read_bytes()))
    write_ico(ico_pngs, ROOT / ICO)
    print(f"ok  ico {'/'.join(map(str, ICO_SIZES))} {ICO}")

    for p in OUT.iterdir():
        if p.is_dir() and p.name != "edge-profile" and (p / "icon.html").exists():
            (p / "icon.html").unlink()
            p.rmdir()
    return 0


if __name__ == "__main__":
    sys.exit(main())
