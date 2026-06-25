"""One-off helper: logo on light grey for launcher icons."""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LOGO_PATH = ROOT / "lib" / "src" / "assets" / "logo.png"
BG = (232, 232, 232, 255)  # #E8E8E8

logo = Image.open(LOGO_PATH).convert("RGBA")


def compose(size: int, padding_ratio: float = 0.12) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), BG)
    inner = int(size * (1 - 2 * padding_ratio))
    scaled = logo.resize((inner, inner), Image.Resampling.LANCZOS)
    offset = (size - inner) // 2
    canvas.paste(scaled, (offset, offset), scaled)
    return canvas.convert("RGB")


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
    inner = int(size * 0.76)
    fg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    scaled = logo.resize((inner, inner), Image.Resampling.LANCZOS)
    offset = (size - inner) // 2
    fg.paste(scaled, (offset, offset), scaled)
    save_png(fg, res / folder / "ic_launcher_foreground.png")

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

print(
    "Generated",
    len(android_launcher) + len(android_foreground) + len(ios_icons) + 1,
    "icons",
)
