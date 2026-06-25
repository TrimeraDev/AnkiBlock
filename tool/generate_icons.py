"""Generate launcher icons from lib/src/assets/logo.png.

Removes the baked-in dark outer background, softens cutout edges, and
composites the shield on the app background (#081020).
"""
from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
LOGO_PATH = ROOT / "lib" / "src" / "assets" / "logo.png"
BG = (8, 16, 32, 255)  # #081020


def _is_outer_background(rgb: tuple[int, int, int]) -> bool:
    """Dark corner fill and outer icon padding (not shield interior blues)."""
    r, g, b = rgb
    return r <= 3 and g <= 12 and b <= 35


def remove_outer_background(image: Image.Image) -> Image.Image:
    """Flood-fill transparent through the outer dark padding from image edges."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()
    visited = [[False] * width for _ in range(height)]
    queue: deque[tuple[int, int]] = deque()

    def try_seed(x: int, y: int) -> None:
        if _is_outer_background(pixels[x, y][:3]):
            visited[y][x] = True
            queue.append((x, y))

    for x in range(width):
        try_seed(x, 0)
        try_seed(x, height - 1)
    for y in range(height):
        try_seed(0, y)
        try_seed(width - 1, y)

    while queue:
        x, y = queue.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if (
                0 <= nx < width
                and 0 <= ny < height
                and not visited[ny][nx]
                and _is_outer_background(pixels[nx, ny][:3])
            ):
                visited[ny][nx] = True
                queue.append((nx, ny))

    result = rgba.copy()
    out = result.load()
    for y in range(height):
        for x in range(width):
            if visited[y][x]:
                out[x, y] = (0, 0, 0, 0)
    return result


def soften_alpha(image: Image.Image, radius: float = 2.0) -> Image.Image:
    """Feather cutout edges so they look smoother on the launcher background."""
    red, green, blue, alpha = image.split()
    alpha = alpha.filter(ImageFilter.GaussianBlur(radius))
    return Image.merge("RGBA", (red, green, blue, alpha))


def prepare_logo() -> Image.Image:
    source = Image.open(LOGO_PATH)
    cutout = soften_alpha(remove_outer_background(source))
    bounds = cutout.getbbox()
    if bounds:
        cutout = cutout.crop(bounds)
    return cutout


logo = prepare_logo()


def compose(size: int, padding_ratio: float = 0.12) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), BG)
    inner = int(size * (1 - 2 * padding_ratio))
    scaled = logo.resize((inner, inner), Image.Resampling.LANCZOS)
    offset = (size - inner) // 2
    canvas.paste(scaled, (offset, offset), scaled)
    return canvas.convert("RGB")


def foreground(size: int, padding_ratio: float = 0.12) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner = int(size * (1 - 2 * padding_ratio))
    scaled = logo.resize((inner, inner), Image.Resampling.LANCZOS)
    offset = (size - inner) // 2
    canvas.paste(scaled, (offset, offset), scaled)
    return canvas


def save_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")


android_launcher = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}
android_foreground = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}

res = ROOT / "android" / "app" / "src" / "main" / "res"
for folder, size in android_launcher.items():
    save_png(compose(size), res / folder / "ic_launcher.png")

for folder, size in android_foreground.items():
    save_png(foreground(size), res / folder / "ic_launcher_foreground.png")

save_png(compose(256), res / "drawable-nodpi" / "ic_logo.png")

ios_icons = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}
ios_dir = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
for name, size in ios_icons.items():
    save_png(compose(size), ios_dir / name)

# Website asset: cutout PNG on transparent background (site bg is also #081020).
docs_logo = ROOT / "docs" / "assets" / "logo.png"
save_png(logo, docs_logo)

print(
    "Generated",
    len(android_launcher) + len(android_foreground) + len(ios_icons) + 2,
    "icons/assets",
)
